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

    // TTS state
    NSString *_currentUtteranceText;  // full text of current utterance for range mapping
    BOOL _isPaused;

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
    return _synthesizer.isSpeaking && !_isPaused;
}

- (BOOL)isListening {
    return _audioEngine.isRunning;
}

#pragma mark - TTS

- (void)speakText:(NSString *)text inView:(RichTextView *)view {
    NSLog(@"VoiceManager speakText: ttsEnabled=%d, textLen=%lu, text='%.80s...'",
          self.ttsEnabled, (unsigned long)text.length, text.UTF8String);
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

    [self configureAudioSessionForPlayback];
    [_synthesizer speakUtterance:utterance];
}

- (void)stopSpeaking {
    if (_synthesizer.isSpeaking) {
        [_synthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    }
    _isPaused = NO;
    _currentUtteranceText = nil;
    [self clearHighlight];
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
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate voiceManagerDidClearHighlight];
    });
}

#pragma mark - AVSpeechSynthesizerDelegate

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer willSpeakRangeOfSpeechString:(NSRange)characterRange utterance:(AVSpeechUtterance *)utterance {
    RichTextView *view = _activeView;
    if (view && self.delegate) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate voiceManagerHighlightRange:characterRange inView:view];
        });
    }
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didFinishSpeechUtterance:(AVSpeechUtterance *)utterance {
    _currentUtteranceText = nil;
    _isPaused = NO;
    [self clearHighlight];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate voiceManagerDidFinishSpeaking];
    });
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didCancelSpeechUtterance:(AVSpeechUtterance *)utterance {
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

- (void)startListening {
    if (!self.sttEnabled)
        return;

    if (_recognitionTask) {
        [_recognitionTask cancel];
        _recognitionTask = nil;
    }

    if (_audioEngine.isRunning) {
        [self stopListening];
        return;
    }

    // Stop TTS if it's speaking — can't do both simultaneously
    if (_synthesizer.isSpeaking) {
        [self stopSpeaking];
    }

    [self configureAudioSessionForRecording];

    _hasReceivedSpeech = NO;
    _recognitionRequest = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
    _recognitionRequest.shouldReportPartialResults = YES;

    if (@available(iOS 13.0, *)) {
        if (_speechRecognizer.supportsOnDeviceRecognition) {
            _recognitionRequest.requiresOnDeviceRecognition = YES;
        }
    }

    AVAudioInputNode *inputNode = _audioEngine.inputNode;

    __weak __typeof(self) weakSelf = self;
    _recognitionTask = [_speechRecognizer recognitionTaskWithRequest:_recognitionRequest resultHandler:^(SFSpeechRecognitionResult * _Nullable result, NSError * _Nullable error) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        if (result) {
            NSString *text = result.bestTranscription.formattedString;
            BOOL isFinal = result.isFinal;

            strongSelf->_hasReceivedSpeech = YES;

            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf.delegate voiceManagerDidRecognizeText:text isFinal:isFinal];
            });

            // Reset silence timer on each partial result (shorter now that speech started)
            [strongSelf resetSilenceTimer];

            if (isFinal) {
                [strongSelf stopListening];
            }
        }

        if (error) {
            // Ignore cancellation errors
            if ([error.domain isEqualToString:@"kAFAssistantErrorDomain"] && error.code == 216) {
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf.delegate voiceManagerSTTError:error];
            });
            [strongSelf stopListening];
        }
    }];

    AVAudioFormat *recordingFormat = [inputNode outputFormatForBus:0];
    [inputNode installTapOnBus:0 bufferSize:1024 format:recordingFormat block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
        [self->_recognitionRequest appendAudioPCMBuffer:buffer];
    }];

    [_audioEngine prepare];

    NSError *error = nil;
    if (![_audioEngine startAndReturnError:&error]) {
        NSLog(@"VoiceManager: Failed to start audio engine: %@", error);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate voiceManagerSTTError:error];
        });
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate voiceManagerDidStartListening];
    });
}

- (void)stopListening {
    [self stopListeningFinishGracefully:NO];
}

- (void)stopListeningFinishGracefully:(BOOL)graceful {
    [_silenceTimer invalidate];
    _silenceTimer = nil;

    if (_audioEngine.isRunning) {
        [_audioEngine stop];
        [_audioEngine.inputNode removeTapOnBus:0];
    }

    [_recognitionRequest endAudio];
    _recognitionRequest = nil;

    if (graceful) {
        // Don't cancel the task or notify delegate yet — let the recognizer
        // deliver a final result (isFinal=YES). The result handler calls
        // stopListening (non-graceful) which will clean up and notify.
        return;
    }

    [_recognitionTask cancel];
    _recognitionTask = nil;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate voiceManagerDidStopListening];
    });
}

- (void)resetSilenceTimer {
    [_silenceTimer invalidate];
    // Only start the silence timer once speech has been detected.
    // Before that, wait indefinitely — the user may be hands-free and
    // thinking or occupied before speaking their command.
    if (!_hasReceivedSpeech)
        return;
    _silenceTimer = [NSTimer scheduledTimerWithTimeInterval:1.2
                                                    target:self
                                                  selector:@selector(silenceTimerFired)
                                                  userInfo:nil
                                                   repeats:NO];
}

- (void)silenceTimerFired {
    if (_audioEngine.isRunning) {
        // End gracefully so the recognizer delivers a final result
        [self stopListeningFinishGracefully:YES];
    }
}

#pragma mark - Audio Session

- (void)configureAudioSessionForPlayback {
    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback
             withOptions:AVAudioSessionCategoryOptionDuckOthers
                   error:&error];
    [session setActive:YES error:&error];
}

- (void)configureAudioSessionForRecording {
    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayAndRecord
             withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker | AVAudioSessionCategoryOptionAllowBluetooth
                   error:&error];
    [session setActive:YES error:&error];
}

#pragma mark - Translation

- (NSString *)translateForCharInput:(NSString *)spokenText {
    NSString *lower = [spokenText lowercaseString];
    NSString *mapped = _charInputMap[lower];
    if (mapped)
        return mapped;

    // If it's a single character already, pass through
    if (spokenText.length == 1)
        return spokenText;

    // Try first character as fallback
    return [spokenText substringToIndex:1];
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
        _voiceMode = (VoiceMode)[defaults integerForKey:kVoiceModeKey];
    }
    if ([defaults objectForKey:kSpeechRateKey]) {
        _speechRate = [defaults floatForKey:kSpeechRateKey];
    }
    if (_speechRate < 0.5f) _speechRate = 0.5f;
    if (_speechRate > 3.0f) _speechRate = 3.0f;
}

@end
