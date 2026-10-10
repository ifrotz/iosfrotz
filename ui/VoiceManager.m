//
//  VoiceManager.m
//  Frotz
//
//  Voice mode manager: TTS (text-to-speech) and STT (speech-to-text)
//  for hands-free interactive fiction gameplay.
//

#import "VoiceManager.h"
#import "RichTextView.h"

static NSString *const kVoiceModeKey = @"FrotzVoiceMode";
static NSString *const kSpeechRateKey = @"FrotzSpeechRate";

// Map AVSpeechUtterance rate: Apple's default is 0.5, range 0.0-1.0
// We expose a multiplier (0.5x-3.0x) and convert internally
static float rateMultiplierToAVRate(float multiplier) {
    // AVSpeechUtteranceDefaultSpeechRate is 0.5
    // Map our 1.0x to that, scale linearly
    float rate = AVSpeechUtteranceDefaultSpeechRate * multiplier;
    if (rate < AVSpeechUtteranceMinimumSpeechRate)
        rate = AVSpeechUtteranceMinimumSpeechRate;
    if (rate > AVSpeechUtteranceMaximumSpeechRate)
        rate = AVSpeechUtteranceMaximumSpeechRate;
    return rate;
}

@implementation VoiceManager {
    AVSpeechSynthesizer *_synthesizer;

    // STT
    SFSpeechRecognizer *_speechRecognizer;
    SFSpeechAudioBufferRecognitionRequest *_recognitionRequest;
    SFSpeechRecognitionTask *_recognitionTask;
    AVAudioEngine *_audioEngine;
    NSTimer *_silenceTimer;
    BOOL _hasReceivedSpeech;  // whether any speech detected this listen session
    BOOL _inputTapInstalled;
    BOOL _finishingRecognition;
    NSUInteger _recognitionGeneration;

    // TTS state
    NSString *_currentUtteranceText;  // full text of current utterance for range mapping
    BOOL _isPaused;
    AVSpeechUtterance *_activeUtterance;

    // Char input translation dictionary
    NSDictionary<NSString *, NSString *> *_charInputMap;
}

+ (instancetype)shared {
    static VoiceManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VoiceManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _synthesizer = [[AVSpeechSynthesizer alloc] init];
        _synthesizer.delegate = self;

        _audioEngine = [[AVAudioEngine alloc] init];
        _speechRecognizer = [[SFSpeechRecognizer alloc] initWithLocale:[NSLocale localeWithLocaleIdentifier:@"en-US"]];
        _speechRecognizer.queue = [NSOperationQueue mainQueue];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioSessionInterrupted:)
                                                    name:AVAudioSessionInterruptionNotification object:nil];

        _speechRate = 1.0f;
        _voiceMode = VoiceModeOff;
        _isPaused = NO;

        _charInputMap = @{
            @"yes": @"y",
            @"yeah": @"y",
            @"yep": @"y",
            @"no": @"n",
            @"nope": @"n",
            @"space": @" ",
            @"enter": @"\n",
            @"return": @"\n",
            @"escape": @"\x1b",
        };

        [self loadPreferences];
    }
    return self;
}

#pragma mark - Properties

- (BOOL)ttsEnabled {
    return _voiceMode == VoiceModeTTSOnly || _voiceMode == VoiceModeBoth;
}

- (BOOL)sttEnabled {
    return _voiceMode == VoiceModeSTTOnly || _voiceMode == VoiceModeBoth;
}

- (BOOL)isSpeaking {
    return _activeUtterance != nil && !_isPaused;
}

- (BOOL)isListening {
    return _audioEngine.isRunning || _finishingRecognition;
}

#pragma mark - TTS

- (void)speakText:(NSString *)text inView:(RichTextView *)view {
    if (!self.ttsEnabled || text.length == 0)
        return;

    // Strip leading/trailing whitespace but preserve internal structure
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0)
        return;

    _activeView = view;
    _currentUtteranceText = trimmed;

    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:trimmed];
    utterance.rate = rateMultiplierToAVRate(_speechRate);
    utterance.pitchMultiplier = 1.0f;
    utterance.preUtteranceDelay = 0.0f;
    utterance.postUtteranceDelay = 0.05f;

    // Prefer premium/enhanced voice when available
    AVSpeechSynthesisVoice *voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"];
    NSArray<AVSpeechSynthesisVoice *> *voices = [AVSpeechSynthesisVoice speechVoices];
    for (AVSpeechSynthesisVoice *v in voices) {
        if ([v.language hasPrefix:@"en"] && v.quality == AVSpeechSynthesisVoiceQualityEnhanced) {
            voice = v;
            break;
        }
    }
    utterance.voice = voice;

    [self stopListening];
    if (![self configureAudioSessionForPlayback])
        return;
    _activeUtterance = utterance;
    [_synthesizer speakUtterance:utterance];
    NSLog(@"Voice speech started");
    [self.delegate voiceManagerDidStartSpeaking];
}

- (void)stopSpeaking {
    _activeUtterance = nil;
    if (_synthesizer.isSpeaking) {
        [_synthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    }
    _isPaused = NO;
    _currentUtteranceText = nil;
    [self clearHighlight];
    // Deactivate playback audio session so a subsequent recording session can start cleanly
    if (!self.isListening)
        [self deactivateAudioSession];
}

- (void)pauseSpeaking {
    if (_synthesizer.isSpeaking && !_isPaused) {
        [_synthesizer pauseSpeakingAtBoundary:AVSpeechBoundaryImmediate];
        _isPaused = YES;
    }
}

- (void)resumeSpeaking {
    if (_isPaused) {
        [_synthesizer continueSpeaking];
        _isPaused = NO;
    }
}

- (void)clearHighlight {
    [self.delegate voiceManagerDidClearHighlight];
}

#pragma mark - AVSpeechSynthesizerDelegate

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer willSpeakRangeOfSpeechString:(NSRange)characterRange utterance:(AVSpeechUtterance *)utterance {
    if (utterance != _activeUtterance)
        return;
    RichTextView *view = _activeView;
    if (view && self.delegate) {
        [self.delegate voiceManagerHighlightRange:characterRange inView:view];
    }
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didFinishSpeechUtterance:(AVSpeechUtterance *)utterance {
    if (utterance != _activeUtterance)
        return;
    _activeUtterance = nil;
    _currentUtteranceText = nil;
    _isPaused = NO;
    [self clearHighlight];
    [self deactivateAudioSession];
    NSLog(@"Voice speech finished");
    [self.delegate voiceManagerDidFinishSpeaking];
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didCancelSpeechUtterance:(AVSpeechUtterance *)utterance {
    if (utterance != _activeUtterance)
        return;
    _activeUtterance = nil;
    _currentUtteranceText = nil;
    _isPaused = NO;
    [self clearHighlight];
}

#pragma mark - STT

- (void)requestSTTPermissionsWithCompletion:(void (^)(BOOL granted))completion {
    [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
        if (status != SFSpeechRecognizerAuthorizationStatusAuthorized) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO);
            });
            return;
        }

        [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(granted);
            });
        }];
    }];
}

- (BOOL)recordingIsAuthorized {
    return [SFSpeechRecognizer authorizationStatus] == SFSpeechRecognizerAuthorizationStatusAuthorized
        && [AVAudioSession sharedInstance].recordPermission == AVAudioSessionRecordPermissionGranted;
}

- (void)startListening {
    // Delayed auto-starts must never toggle an existing recording off.
    if (!self.sttEnabled || self.isListening)
        return;
    if (![self recordingIsAuthorized] || !_speechRecognizer.isAvailable) {
        [self reportRecordingError:[NSError errorWithDomain:@"FrotzVoice" code:1
                                                  userInfo:@{NSLocalizedDescriptionKey: @"Speech recognition is unavailable. Check microphone and speech permissions in Settings."}]];
        return;
    }

    [self stopListening];
    [self stopSpeaking];
    if (![self configureAudioSessionForRecording])
        return;

    _hasReceivedSpeech = NO;
    _recognitionRequest = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
    _recognitionRequest.shouldReportPartialResults = YES;
    if (@available(iOS 13.0, *)) {
        if (_speechRecognizer.supportsOnDeviceRecognition)
            _recognitionRequest.requiresOnDeviceRecognition = YES;
    }

    AVAudioInputNode *inputNode = _audioEngine.inputNode;
    AVAudioFormat *recordingFormat = [inputNode outputFormatForBus:0];
    if (recordingFormat.sampleRate <= 0 || recordingFormat.channelCount == 0) {
        [self stopListening];
        [self reportRecordingError:[NSError errorWithDomain:@"FrotzVoice" code:2
                                                  userInfo:@{NSLocalizedDescriptionKey: @"No microphone input is available."}]];
        return;
    }

    NSUInteger generation = _recognitionGeneration;
    SFSpeechAudioBufferRecognitionRequest *request = _recognitionRequest;
    __weak __typeof(self) weakSelf = self;
    _recognitionTask = [_speechRecognizer recognitionTaskWithRequest:request resultHandler:^(SFSpeechRecognitionResult *result, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong __typeof(weakSelf) self = weakSelf;
            if (!self || generation != self->_recognitionGeneration)
                return;
            if (result) {
                NSString *text = result.bestTranscription.formattedString;
                if (result.isFinal) {
                    [self stopListening];
                    [self.delegate voiceManagerDidRecognizeText:text isFinal:YES];
                    return;
                }
                if (text.length > 0) {
                    self->_hasReceivedSpeech = YES;
                    [self.delegate voiceManagerDidRecognizeText:text isFinal:NO];
                    if (!self->_finishingRecognition)
                        [self resetSilenceTimer];
                }
            }
            if (error) {
                [self stopListening];
                [self reportRecordingError:error];
            }
        });
    }];

    // Capture this request rather than the mutable request for a later session.
    [inputNode installTapOnBus:0 bufferSize:1024 format:recordingFormat block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
        [request appendAudioPCMBuffer:buffer];
    }];
    _inputTapInstalled = YES;
    [_audioEngine prepare];
    NSError *error = nil;
    if (![_audioEngine startAndReturnError:&error]) {
        [self stopListening];
        [self reportRecordingError:error];
        return;
    }
    NSLog(@"Voice recording started");
    [self.delegate voiceManagerDidStartListening];
}

- (void)stopListening {
    BOOL wasListening = self.isListening;
    ++_recognitionGeneration; // Invalidate queued results before canceling the task.
    [_silenceTimer invalidate];
    _silenceTimer = nil;
    [_audioEngine stop];
    if (_inputTapInstalled) {
        [_audioEngine.inputNode removeTapOnBus:0];
        _inputTapInstalled = NO;
    }
    [_recognitionRequest endAudio];
    _recognitionRequest = nil;
    [_recognitionTask cancel];
    _recognitionTask = nil;
    _finishingRecognition = NO;
    if (!_synthesizer.isSpeaking)
        [self deactivateAudioSession];
    if (wasListening) {
        NSLog(@"Voice recording stopped");
        [self.delegate voiceManagerDidStopListening];
    }
}

- (void)resetSilenceTimer {
    [_silenceTimer invalidate];
    if (!_hasReceivedSpeech)
        return;
    _silenceTimer = [NSTimer scheduledTimerWithTimeInterval:1.2 target:self
                                                  selector:@selector(silenceTimerFired) userInfo:nil repeats:NO];
}

- (void)silenceTimerFired {
    if (!_audioEngine.isRunning || _finishingRecognition)
        return;
    [_audioEngine stop];
    if (_inputTapInstalled) {
        [_audioEngine.inputNode removeTapOnBus:0];
        _inputTapInstalled = NO;
    }
    _finishingRecognition = YES;
    [_recognitionRequest endAudio];
    // Bound the wait for a final result if the speech service never responds.
    _silenceTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self
                                                  selector:@selector(recognitionTimedOut) userInfo:nil repeats:NO];
}

- (void)recognitionTimedOut {
    [self stopListening];
    [self reportRecordingError:[NSError errorWithDomain:@"FrotzVoice" code:3
                                              userInfo:@{NSLocalizedDescriptionKey: @"Speech recognition timed out. Tap to try again."}]];
}

- (void)reportRecordingError:(NSError *)error {
    [self.delegate voiceManagerSTTError:error];
}

#pragma mark - Audio Session

- (BOOL)configureAudioSessionForPlayback {
    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    return [session setCategory:AVAudioSessionCategoryPlayback
                   withOptions:AVAudioSessionCategoryOptionDuckOthers error:&error]
        && [session setActive:YES error:&error];
}

- (BOOL)configureAudioSessionForRecording {
    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    BOOL configured = [session setCategory:AVAudioSessionCategoryPlayAndRecord
                              withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker | AVAudioSessionCategoryOptionAllowBluetooth error:&error]
        && [session setActive:YES error:&error];
    if (!configured)
        [self reportRecordingError:error];
    return configured;
}

- (void)deactivateAudioSession {
    [[AVAudioSession sharedInstance] setActive:NO
                                  withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
}

- (void)audioSessionInterrupted:(NSNotification *)notification {
    if ([notification.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue] != AVAudioSessionInterruptionTypeBegan)
        return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self stopListening];
        [self stopSpeaking];
        [self reportRecordingError:[NSError errorWithDomain:@"FrotzVoice" code:4
                                                  userInfo:@{NSLocalizedDescriptionKey: @"Audio was interrupted. Tap to try again."}]];
    });
}

#pragma mark - Translation

- (NSString *)translateForCharInput:(NSString *)spokenText {
    NSString *lower = [[spokenText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if (lower.length == 0)
        return @"";
    NSString *mapped = _charInputMap[lower];
    if (mapped)
        return mapped;

    // If it's a single character already, pass through
    if (lower.length == 1)
        return lower;

    // Try first character as fallback
    return [lower substringWithRange:[lower rangeOfComposedCharacterSequenceAtIndex:0]];
}

#pragma mark - Persistence

- (void)savePreferences {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:_voiceMode forKey:kVoiceModeKey];
    [defaults setFloat:_speechRate forKey:kSpeechRateKey];
    [defaults synchronize];
}

- (void)loadPreferences {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kVoiceModeKey]) {
        NSInteger storedMode = [defaults integerForKey:kVoiceModeKey];
        _voiceMode = storedMode >= VoiceModeOff && storedMode <= VoiceModeBoth ? (VoiceMode)storedMode : VoiceModeOff;
    }
    if ([defaults objectForKey:kSpeechRateKey]) {
        _speechRate = [defaults floatForKey:kSpeechRateKey];
    }
    if (_speechRate < 0.5f) _speechRate = 0.5f;
    if (_speechRate > 3.0f) _speechRate = 3.0f;
}

@end
