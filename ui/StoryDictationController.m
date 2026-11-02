//
//  StoryDictationController.m
//  Frotz
//
//  Created by Craig Smith on 6/19/23.
//

#import "StoryDictationController.h"

#if EnableStoryDictation

#import <AudioToolbox/AudioToolbox.h>

// Trace output (StoryDictationDebugLogging in iosfrotz.h); errors use NSLog directly.
#if StoryDictationDebugLogging
#define DictationLog(...) NSLog(__VA_ARGS__)
#else
#define DictationLog(...) ((void)0)
#endif

@interface NSString (IFDictation)
-(NSString*)stringWithSanitizeDictation;
@end

@implementation NSString (IFDictation)
-(NSString*)stringWithSanitizeDictation {
    // Counterfeit Monkey helper.  Convert en dashes and em dashes to hyphens, remove surrounding spaces, so
    // "Wave x-remover at ..." dictates better.
    NSString *str = [self stringByReplacingOccurrencesOfString:@"–" withString:@"-"];
    str = [str stringByReplacingOccurrencesOfString:@"—" withString:@"-"];
    str = [str stringByReplacingOccurrencesOfString:@" - " withString:@"-"];
    return str;
}
@end

// The recognizer reports its failures as error codes in the assistant domain, with no public
// constants; the table in the error property's comment in SFSpeechRecognitionTask.h lists them.
// 203, "failure occurred during speech recognition", is what a task ends with when the audio it
// was given held nothing it could recognize (a pause with no speech, say); 1110, "failed to
// recognize any speech", is the same outcome by its description. The task is over at that point,
// so the reference is dropped and the commit timer starts a fresh one.
static NSString *const kSpeechAssistantErrorDomain = @"kAFAssistantErrorDomain";
static const NSInteger kSpeechErrorRecognitionFailed = 203;
static const NSInteger kSpeechErrorNoSpeechRecognized = 1110;

static BOOL ErrorEndsRecognitionTask(NSError *error) {
    return (error.code == kSpeechErrorRecognitionFailed || error.code == kSpeechErrorNoSpeechRecognized)
        && [error.domain isEqualToString: kSpeechAssistantErrorDomain];
}

static const NSTimeInterval kDictationDefaultSilenceInterval = 0.8;

@implementation StoryDictationController

@synthesize delegate = m_delegate;
@synthesize stateDelegate = m_stateDelegate;
@synthesize silenceInterval = m_silenceInterval;

-(void)notifyStateChanged {
    [m_stateDelegate dictationListeningStateChanged: self];
}

-(StoryDictationAvailability)availability {
    if (!m_sfrecog.isAvailable)
        return kStoryDictationRecognizerUnavailable;
    if (!m_sfrecog.supportsOnDeviceRecognition) // requests here set requiresOnDeviceRecognition
        return kStoryDictationOnDeviceUnsupported;
    return kStoryDictationAvailable;
}

// SFSpeechRecognizerDelegate. The recognizer can go away mid-session (Siri and Dictation turned
// off in Settings, say); a task in flight would just fail, so stop cleanly and say why.
- (void)speechRecognizer:(SFSpeechRecognizer *)speechRecognizer availabilityDidChange:(BOOL)available {
    DictationLog(@"recognizer available: %d", available);
    if (available || !([self isListening] || m_isPaused))
        return;
    [self stopListening];
    [m_stateDelegate dictationBecameUnavailable: self];
}

-(instancetype)init {
    self = [super init];
    if (self) {
        m_sfrecog =  [[SFSpeechRecognizer alloc] initWithLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en-US"]];
        m_sfrecog.delegate = self;
        
        m_audioEngine = [[AVAudioEngine alloc] init];
        m_audioSession = [AVAudioSession sharedInstance];
        m_silenceInterval = kDictationDefaultSilenceInterval;

        // The system can take the audio away or reconfigure it under us; see the handlers below.
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver: self selector: @selector(audioSessionInterrupted:) name: AVAudioSessionInterruptionNotification object: m_audioSession];
        [center addObserver: self selector: @selector(mediaServicesWereReset:) name: AVAudioSessionMediaServicesWereResetNotification object: m_audioSession];
        [center addObserver: self selector: @selector(audioEngineConfigurationChanged:) name: AVAudioEngineConfigurationChangeNotification object: m_audioEngine];
        [center addObserver: self selector: @selector(applicationDidEnterBackground:) name: UIApplicationDidEnterBackgroundNotification object: nil];
        [center addObserver: self selector: @selector(voiceOverStatusChanged:) name: UIAccessibilityVoiceOverStatusDidChangeNotification object: nil];
    }
    return self;
}

// Leaving Frotz for another app ends dictation, like leaving the story for the Story List does:
// the mic shouldn't stay open behind another app, and listening comes back only when the player
// asks for it again. (Posted once every scene is in the background, so a second window on the
// iPad or the Duo keeps listening while it is still up.)
-(void)applicationDidEnterBackground:(NSNotification*)note {
    if ([self isListening] || m_isPaused) {
        DictationLog(@"app went to the background");
        [self stopListening];
    }
}

-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}

// The system took the audio away (Speak Screen, VoiceOver, a phone call, Siri) and stopped the
// engine, which nothing here would otherwise notice: no hypotheses arrive and the mic icon stays
// lit. Listening is over as far as the user can tell, so make it so: drop the utterance in flight
// and report "not listening", so the icon goes dark and a tap starts dictation again. If the
// system later says the interruption has ended and audio may resume, start again by ourselves,
// unless the user has restarted or stopped dictation meanwhile. That notice is not guaranteed
// (system speech in particular may never send it), which is why the state can't wait for it.
// A pause the UI already made (isListening false) is left to the UI to end.
-(void)audioSessionInterrupted:(NSNotification*)note {
    NSDictionary *info = note.userInfo;
    dispatch_async(dispatch_get_main_queue(), ^{
        AVAudioSessionInterruptionType type = [info[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
        if (type == AVAudioSessionInterruptionTypeBegan) {
            if (![self isListening])
                return;
            DictationLog(@"audio interrupted");
            [self abandonUtterance];
            [m_audioEngine stop];
            m_resumeAfterInterruption = YES;
            [self notifyStateChanged];
        } else if (m_resumeAfterInterruption) {
            m_resumeAfterInterruption = NO;
            AVAudioSessionInterruptionOptions options = [info[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue];
            BOOL resume = (options & AVAudioSessionInterruptionOptionShouldResume) != 0;
            DictationLog(@"audio interruption ended, resume %d", resume);
            if (resume)
                [self listenForSpeech];
        }
    });
}

// The engine stopped itself because the audio route or format changed (headphones in or out, a
// Bluetooth device, VoiceOver claiming the speaker). The tap was installed for the old input
// format and must be put back for the new one, so drop the utterance and restart from scratch;
// if listening was paused, stay paused and let the resume do the reinstalling.
-(void)audioEngineConfigurationChanged:(NSNotification*)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        DictationLog(@"audio engine configuration changed");
        [self restartAudioForChangedConfiguration];
    });
}

// VoiceOver decides whether voice processing is wanted (see startListening), so a change while
// dictation is on means tearing the engine down and setting it up again the other way.
-(void)voiceOverStatusChanged:(NSNotification*)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        DictationLog(@"VoiceOver running: %d", UIAccessibilityIsVoiceOverRunning());
        [self restartAudioForChangedConfiguration];
    });
}

// Drops the utterance and sets the engine up again from scratch (startListening reinstalls the
// tap, and decides voice processing afresh). Paused dictation stays paused; the resume does it.
-(void)restartAudioForChangedConfiguration {
    BOOL wasListening = m_sfRecogRequest != nil && !m_isPaused; // not isListening: the engine may already have stopped
    if (!wasListening && !m_isPaused)
        return;
    [self pauseListening];
    [m_audioEngine stop];
    [[m_audioEngine inputNode] removeTapOnBus: 0];
    m_tapInstalled = NO;
    if (wasListening)
        [self listenForSpeech];
}

-(void)stopListening {
    if (m_speechCommitTimer) {
        [m_speechCommitTimer invalidate];
        m_speechCommitTimer = nil;
    }
    [self cancelLongIdleTimer];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(listenForSpeech) object:nil];

    m_isPaused = NO;
    m_resumeAfterInterruption = NO;
    if (m_recognitionTask) {
        [m_sfRecogRequest endAudio];
        [m_recognitionTask cancel];
        m_sfRecogRequest = nil;
        m_recognitionTask = nil;
    }
    [self releaseAudio];
    [self notifyStateChanged];
}

// Stops the engine, removes the tap and gives the audio system back: the mic indicator goes off,
// and other apps are told they may resume anything the session's activation had interrupted.
// Shared by stopping and pausing, so that the two leave the audio in the same state and the next
// start, from either, is the same full setup (see startListening). An engine merely paused, or
// stopped with the session left active, was resumed with a bare restart, and after one such
// resume the stop cue came out loud and thunking on every pause until a full stop and start.
// Failure to deactivate is only worth a log.
-(void)releaseAudio {
    [m_audioEngine stop];
    [[m_audioEngine inputNode] removeTapOnBus: 0];
    m_tapInstalled = NO;
    NSError *error = nil;
    if (![m_audioSession setActive: NO withOptions: AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error: &error])
        NSLog(@"Error AVAudioSession setActive:NO: %@", error);
}

// Called when the task first detects speech in the source audio
- (void)speechRecognitionDidDetectSpeech:(SFSpeechRecognitionTask *)task {
    DictationLog(@"task detected speech");
}

// Called for all recognitions, including non-final hypothesis
- (void)speechRecognitionTask:(SFSpeechRecognitionTask *)task didHypothesizeTranscription:(SFTranscription *)transcription {
    if (task != m_recognitionTask)
        return; // a task listenForSpeech has already replaced; see didFinishSuccessfully
    NSString *text = [transcription formattedString];
    DictationLog(@"speechRecognitionTask:didHypothesizeTranscription: %@", text);
    if (![text isEqualToString: m_currentTranscription]) {
        m_currentTranscription = text;
        if (m_delegate && text.length > 0)
            [m_delegate acceptDictation: text final: NO];
    }
    // Every hypothesis, changed or not, means speech is still coming in.
    [self restartSilenceTimer];
    [self restartLongIdleTimer];
}

-(NSUInteger)dictationDictionaryScore:(NSString *)text {
    NSUInteger score = 0;
    NSMutableCharacterSet *separatorSet = [NSMutableCharacterSet whitespaceAndNewlineCharacterSet];
    [separatorSet formUnionWithCharacterSet: [NSCharacterSet punctuationCharacterSet]];
    [separatorSet removeCharactersInString: @"'"];
    NSArray *words = [text componentsSeparatedByCharactersInSet:separatorSet];
    int i = 0;
    NSUInteger count = [words count];
    NSUInteger wordCountScore = count >= 10 ? 0 : 10 - count;
    score += wordCountScore;
    for (NSString *word in words) {
        if ([word length] > 2) {
            if ([m_delegate validateWord:word]) {
                DictationLog(@"  validated: %@", word);
                score++;
            }
            i++;
        }
    }
    return score;
}

// Called only for final recognitions of utterances. No more about the utterance will be reported
- (void)speechRecognitionTask:(SFSpeechRecognitionTask *)task didFinishRecognition:(SFSpeechRecognitionResult *)result {
    if (task != m_recognitionTask)
        return; // a task listenForSpeech has already replaced; see didFinishSuccessfully
    BOOL isFinal = [result isFinal];
    DictationLog(@"speechRecognitionTask:didFinishRecognition final=%d", isFinal);
    NSArray<SFTranscription *> *transcriptions = [result transcriptions];
    int i = 0, bestIndex = -1;
    NSUInteger bestScore = 0;
    //SFTranscription *transcription = [result bestTranscription];
    for (SFTranscription *transcription in transcriptions) {
        NSString *text = [transcription formattedString];
        NSUInteger score = [self dictationDictionaryScore: text];
        DictationLog(@"  Count: %d Score: %lu Recog: %@", i, score, text);
        if (score > bestScore) {
            bestScore = score;
            bestIndex = i;
        }
        ++i;
    }
    SFTranscription *transcription;
    if (bestIndex >= 0)
        transcription = transcriptions[bestIndex];
    else
        transcription = [result bestTranscription];
    NSString *text = [transcription formattedString];
    DictationLog(@"Final: %d Recog: %@", isFinal, text);
    m_currentTranscription = [text stringWithSanitizeDictation];

    NSError *error = [task error];
    if (error)
        NSLog(@"recognitionTaskWithRequest error: %@", error);
    if (isFinal || ErrorEndsRecognitionTask(error))
        [self commitTranscription]; // the task is over; this is the utterance
    else
        [self restartSilenceTimer];
}

// Called when the task is no longer accepting new audio but may be finishing final processing
- (void)speechRecognitionTaskFinishedReadingAudio:(SFSpeechRecognitionTask *)task {
    DictationLog(@"Task finished audio");
}

// Called when the task has been cancelled, either by client app, the user, or the system
- (void)speechRecognitionTaskWasCancelled:(SFSpeechRecognitionTask *)task {
    DictationLog(@"Task canceled");
}

// Called when recognition of all requested utterances is finished.
// If successfully is false, the error property of the task will contain error information
- (void)speechRecognitionTask:(SFSpeechRecognitionTask *)task didFinishSuccessfully:(BOOL)successfully {
    // These callbacks arrive asynchronously, so one from a task that listenForSpeech has since
    // finished and replaced can land after the new task is running. Only the current task may
    // report results or clear m_recognitionTask; otherwise the new task's results were lost and
    // the commit timer took the cleared task as the signal to accept whatever text it had.
    if (task != m_recognitionTask)
        return;
    // Normally didFinishRecognition has already committed and cleared the task, and the guard
    // above skips this. It matters when the task ends without a final result: with nothing
    // heard, say, which commitTranscription treats as an empty utterance and listens again.
    BOOL taskEnded = successfully;
    if (!successfully) {
        NSError *error = [task error];
        if (error)
            NSLog(@"speechRecognitionTask:didFinishSuccessfully error: %@", error);
        taskEnded = ErrorEndsRecognitionTask(error);
    }
    if (taskEnded)
        [self commitTranscription];
    else if ([self isListening])
        [self restartSilenceTimer];
}

-(BOOL)isListening {
    return m_sfRecogRequest != nil && [m_audioEngine isRunning];
}

-(BOOL)isPaused {
    return m_isPaused;
}

-(BOOL)willResume {
    return m_isPaused || m_resumeAfterInterruption;
}

// Drops the utterance in progress without committing it: the silence timer, task, request and
// text all go, and the delegate is told so that the next words follow what is already shown
// rather than replacing it. The task is dropped before it is cancelled so its cancellation
// callback is ignored as stale.
-(void)abandonUtterance {
    [m_speechCommitTimer invalidate];
    m_speechCommitTimer = nil;
    SFSpeechRecognitionTask *task = m_recognitionTask;
    m_recognitionTask = nil;
    [m_sfRecogRequest endAudio];
    m_sfRecogRequest = nil;
    [task cancel];
    m_currentTranscription = nil;
    [m_delegate abandonDictation];
}

// A pause is an interruption (the notes page or the file chooser came up), not the end of a
// command, so an utterance in progress is abandoned rather than committed: otherwise the silence
// that follows would commit "put the brass lantern" as a command while the player was elsewhere.
// The partial text already shown stays in the input line to be finished or cleared on return.
-(void)pauseListening {
    [self abandonUtterance];
    [self cancelLongIdleTimer]; // nothing can be heard while paused; the clock restarts with the resume
    // The audio is released exactly as a stop releases it (see releaseAudio); only the dictation
    // state differs, so that the UI's resume brings listening back without the player asking.
    [self releaseAudio];
    m_isPaused = YES;
    DictationLog(@"pauseListening");
    [self notifyStateChanged];
}

// Starts (or, when paused, resumes) listening. Every way out reports the resulting state to the
// state delegate, since the audio engine may refuse to start and leave nothing listening.
-(void)listenForSpeech {
    [self startListening];
    if ([self isListening])
        [self restartLongIdleTimer];
    [self notifyStateChanged];
}

// The mic doesn't stay open indefinitely: with no speech heard for this long, dictation switches
// itself off (mic icon and all), as if the player had tapped it. Reading, or a break, shouldn't
// leave the recording indicator lit and the battery draining. Each hypothesis restarts the clock.
static const NSTimeInterval kDictationLongIdleTimeout = 90;

-(void)restartLongIdleTimer {
    [m_longIdleTimer invalidate];
    __weak StoryDictationController *weakSelf = self;
    m_longIdleTimer = [NSTimer scheduledTimerWithTimeInterval: kDictationLongIdleTimeout repeats: NO block: ^(NSTimer *timer) {
        [weakSelf longIdleTimerFired];
    }];
}

-(void)cancelLongIdleTimer {
    [m_longIdleTimer invalidate];
    m_longIdleTimer = nil;
}

-(void)longIdleTimerFired {
    m_longIdleTimer = nil;
    DictationLog(@"idle for %.0fs, stopping", kDictationLongIdleTimeout);
    [self stopListening];
}

// The system's audio daemon was restarted (it happens after a long idle, under memory pressure,
// or when it crashes). Every audio object from before is dead: the engine can't be started again,
// its input node reports no format, and installing a tap throws. Apple's instruction is to
// recreate them, so the engine is rebuilt here; listening, if it was on, is over, and the mic
// button shows it. Without this a tap on the mic failed silently from then until the app was
// relaunched.
-(void)mediaServicesWereReset:(NSNotification*)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL wasOn = [self isListening] || m_isPaused;
        NSLog(@"Media services were reset; rebuilding the dictation audio engine");
        [self stopListening];
        [self rebuildAudioEngine];
        if (wasOn)
            [m_stateDelegate dictationBecameUnavailable: self];
    });
}

// A fresh engine in place of one that can't be started. The configuration-change observer is
// bound to the engine object, so it moves to the new one.
-(void)rebuildAudioEngine {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver: self name: AVAudioEngineConfigurationChangeNotification object: m_audioEngine];
    [m_audioEngine stop];
    m_audioEngine = [[AVAudioEngine alloc] init];
    m_tapInstalled = NO;
    [center addObserver: self selector: @selector(audioEngineConfigurationChanged:) name: AVAudioEngineConfigurationChangeNotification object: m_audioEngine];
}

// Sets up the input node and starts the engine, with the tap installed for the node's current
// format. Returns whether the engine is running with the tap in place; every failure is logged
// and returns NO rather than leaving a half-started engine for a task to wait on in silence.
-(BOOL)startAudioEngineWithVoiceProcessing:(BOOL)wantVoiceProcessing {
    NSError *error = nil;
    AVAudioInputNode *audioInputNode = [m_audioEngine inputNode];
    // Voice processing: echo cancellation against the device's own speaker output, plus noise
    // suppression and gain control, the same treatment FaceTime's microphone gets. Without the
    // echo cancellation VoiceOver's speech is picked up and transcribed as if the player had said
    // it, "VoiceOver on" included, and feeds back on every announcement after; the suppression
    // helps anyone dictating somewhere noisy. But the voice-processing unit interrupts other
    // apps' audio when it starts, whatever the session's mixing options say (measured: the
    // options took, the music still paused when the engine started), so it is a choice between
    // it and the player's music. Taken when VoiceOver is on, which needs it, or when nothing
    // else is playing, where it costs nothing; a VoiceOver change restarts the engine to redo
    // it. It has to be set while the engine is stopped, it needs the output node in the graph,
    // and it changes the input format, so the tap's format is read after it. Dictation still
    // works without it if enabling fails.
    DictationLog(@"voice processing %s (VoiceOver %d, other audio now %d, was enabled %d)", wantVoiceProcessing ? "on" : "off",
                 UIAccessibilityIsVoiceOverRunning(), m_audioSession.isOtherAudioPlaying, audioInputNode.isVoiceProcessingEnabled);
    if (audioInputNode.isVoiceProcessingEnabled != wantVoiceProcessing) {
        (void)[m_audioEngine outputNode];
        if (![audioInputNode setVoiceProcessingEnabled: wantVoiceProcessing error: &error]) {
            NSLog(@"Error %s voice processing on the audio input: %@", wantVoiceProcessing ? "enabling" : "disabling", error);
            error = nil;
        }
    }
    // While voice processing runs it also ducks any other audio that does start; iOS 17 can
    // limit that to moments speech is detected, and to the shallowest level.
    if (wantVoiceProcessing) {
        if (@available(iOS 17.0, *)) {
            AVAudioVoiceProcessingOtherAudioDuckingConfiguration ducking = { .enableAdvancedDucking = YES, .duckingLevel = AVAudioVoiceProcessingOtherAudioDuckingLevelMin };
            audioInputNode.voiceProcessingOtherAudioDuckingConfiguration = ducking;
        }
    }
    AVAudioFormat *recordingFormat = [audioInputNode outputFormatForBus: 0];
    [audioInputNode removeTapOnBus:0];
    m_tapInstalled = NO;
    // A node with no usable format is the sign of a dead engine (see mediaServicesWereReset:);
    // installing a tap for it throws, so it is checked first and the @try is the backstop.
    if (recordingFormat.sampleRate <= 0 || recordingFormat.channelCount == 0) {
        NSLog(@"Audio input has no usable format (%@); the engine can't be started", recordingFormat);
        return NO;
    }
    @try {
        [audioInputNode installTapOnBus:0 bufferSize:1024 format:recordingFormat block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
            if (m_sfRecogRequest)
                [m_sfRecogRequest appendAudioPCMBuffer: buffer];
        }];
        m_tapInstalled = YES;
        [m_audioEngine prepare];
        if (![m_audioEngine startAndReturnError: &error]) {
            NSLog(@"Error audioEngine:startAndReturnError: %@", error);
            return NO;
        }
    }
    @catch (NSException *exception) {
        NSLog(@"Exception starting the audio engine: %@", exception);
        return NO;
    }
    return [m_audioEngine isRunning];
}

-(void)startListening {
    NSError *error = nil;
    // Read before the session is touched below: whether someone else is playing decides voice
    // processing, and the answer must not be coloured by our own activation.
    BOOL otherAudioPlaying = m_audioSession.isOtherAudioPlaying;
    m_resumeAfterInterruption = NO; // the user (or the UI) is starting it; the interruption's end needn't
    // A resume from a pause is a start like any other: the pause released the audio (releaseAudio),
    // so the full setup below runs. Nothing is restarted in place.
    if (m_isPaused) {
        DictationLog(@"listenForSpeech resuming from pause");
        m_isPaused = NO;
    }
    // Cancel the previous task if it's running.
    if (m_recognitionTask) {
        [m_recognitionTask finish];
        m_recognitionTask = nil;
        m_sfRecogRequest = nil;
    }
    // The tap must match the input node's current format, so it is (re)installed whenever the
    // engine is down or a configuration change has removed it, with the engine stopped meanwhile.
    // The session is configured here too, and only here: this method also runs after every
    // committed command to start the next task, and reconfiguring and reactivating a live session
    // each time is wasted work at best (and was a suspect for the player's music pausing).
    if (![m_audioEngine isRunning] || !m_tapInstalled) {
        if ([m_audioEngine isRunning])
            [m_audioEngine stop];

        // The session must be a recording session before the engine is touched. Voice processing
        // (below) routes output to the earpiece unless told otherwise, which would make VoiceOver
        // and the story's sounds go quiet, hence DefaultToSpeaker. Play-and-record ignores
        // Bluetooth headsets unless asked: the hands-free option admits a headset's own mic (and
        // sends output to it), the A2DP option lets output use the music profile while the phone's
        // mic records, and with both iOS picks what the headset supports. Wired headphones need
        // no asking. MixWithOthers keeps the player's music or podcast going: Frotz plays nothing
        // itself, so there is no reason to silence anyone. Record-only can't mix, nor host voice
        // processing, which is why the category is play-and-record at all.
        [m_audioSession setCategory: AVAudioSessionCategoryPlayAndRecord mode: AVAudioSessionModeDefault
                             options: AVAudioSessionCategoryOptionDefaultToSpeaker | AVAudioSessionCategoryOptionAllowBluetoothHFP
                                    | AVAudioSessionCategoryOptionAllowBluetoothA2DP | AVAudioSessionCategoryOptionMixWithOthers
                               error: &error];
        if (error) {
            NSLog(@"Error AVAudioSession setCategory: %@", error);
            error = nil;
        }
        // iOS mutes haptics and system sounds while the mic is live unless told otherwise, and the
        // started and resumed cues (StoryDictationCuePlayer) play once the engine is running.
        if (![m_audioSession setAllowHapticsAndSystemSoundsDuringRecording: YES error: &error]) {
            NSLog(@"Error AVAudioSession setAllowHapticsAndSystemSoundsDuringRecording: %@", error);
            error = nil;
        }
        [m_audioSession setActive:YES withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error: &error];
        if (error) {
            NSLog(@"Error AVAudioSession setActive: %@", error);
            error = nil;
        }
        DictationLog(@"audio session: category %@, mode %@, options 0x%lx, other audio playing %d, route %@",
                     m_audioSession.category, m_audioSession.mode, (unsigned long)m_audioSession.categoryOptions,
                     m_audioSession.isOtherAudioPlaying, m_audioSession.currentRoute);

        // If the engine won't start, it is most likely dead from a media services reset that
        // went unannounced (the notification isn't guaranteed), so it is rebuilt and tried once
        // more; the mic button shouldn't fail silently in any case, hence the delegate call. No
        // task is started against an engine that isn't running: it would wait forever for audio.
        BOOL wantVoiceProcessing = UIAccessibilityIsVoiceOverRunning() || !otherAudioPlaying;
        if (![self startAudioEngineWithVoiceProcessing: wantVoiceProcessing]) {
            NSLog(@"The dictation audio engine failed to start; rebuilding it and trying again");
            [self rebuildAudioEngine];
            if (![self startAudioEngineWithVoiceProcessing: wantVoiceProcessing]) {
                [self stopListening];
                [m_stateDelegate dictationFailedToStart: self];
                return;
            }
        }
    }

    m_sfRecogRequest = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
    m_sfRecogRequest.shouldReportPartialResults = YES;
    m_sfRecogRequest.requiresOnDeviceRecognition = YES;
    m_sfRecogRequest.contextualStrings = @[ @"look", @"grue", @"i", @"frotz", @"nitfol", @"aimfiz", @"filfre", @"gnusto", @"rezrov" ];
    m_recognitionTask = [m_sfrecog recognitionTaskWithRequest: m_sfRecogRequest delegate: self];
    DictationLog(@"recognition task started, other audio playing %d", m_audioSession.isOtherAudioPlaying);
}

// An utterance ends when the recognizer has sent no hypothesis for silenceInterval. Each
// hypothesis restarts the timer, so it only ever fires once, after the speaker has stopped.
-(void)deferCommit {
    if (m_speechCommitTimer) {
        DictationLog(@"commit deferred");
        [self restartSilenceTimer];
    }
}

-(void)restartSilenceTimer {
    [m_speechCommitTimer invalidate];
    __weak StoryDictationController *weakSelf = self;
    m_speechCommitTimer = [NSTimer scheduledTimerWithTimeInterval: m_silenceInterval repeats: NO block: ^(NSTimer *timer) {
        [weakSelf silenceTimerFired];
    }];
}

// The speaker has paused. Ask the task to finish; its final result comes back through
// didFinishRecognition, which commits. A task that is already winding down (or gone) has no
// final result coming, so commit what there is.
-(void)silenceTimerFired {
    m_speechCommitTimer = nil;
    DictationLog(@"silence: ct:%@", m_currentTranscription);
    if (m_recognitionTask && m_recognitionTask.state <= SFSpeechRecognitionTaskStateRunning) {
        DictationLog(@" calling recognitionTask finish");
        [m_recognitionTask finish];
        return;
    }
    [self commitTranscription];
}

// Hands the utterance to the delegate as a command (if there was one) and starts listening for
// the next; the current task, if any, is done with.
-(void)commitTranscription {
    [m_speechCommitTimer invalidate];
    m_speechCommitTimer = nil;
    m_recognitionTask = nil;
    DictationLog(@"Final transcript: %@", m_currentTranscription);
    if (m_delegate && [m_currentTranscription length] > 0)
        [m_delegate acceptDictation: m_currentTranscription final:YES];
    m_currentTranscription = nil;
    // Not while paused: the pause stops the hypotheses, so the silence timer fires soon after
    // and lands here, and listening again would undo the pause behind the UI's back. The
    // resume (listenForSpeech with m_isPaused set) finds no task and starts a fresh one.
    if (!m_isPaused)
        [self performSelector: @selector(listenForSpeech) withObject:nil afterDelay:0];
}

@end

#pragma mark - Cues

// The sounds are WAV files in the app bundle's Sounds folder (resources/Sounds, a folder
// reference; made by meta/make_dictation_cues.py): two quick strikes of A4 for a start, one for a
// resume, and the same an octave down, one strike of A3 for a pause and two for a stop. The second
// strike of a double cue begins this long in, and the second haptic tap goes with it.
static NSString *const kCueFileNames[kStoryDictationCueCount] = { @"DictationStarted", @"DictationResumed", @"DictationPaused", @"DictationStopped" };
static NSString *const kCueSoundsFolder = @"Sounds";
static const NSTimeInterval kCueSecondNoteOffset = 0.08; // SECOND_STRIKE in the script

@implementation StoryDictationCuePlayer
{
    SystemSoundID m_sounds[kStoryDictationCueCount]; // indexed by StoryDictationCue; 0 until first played
    UIImpactFeedbackGenerator *m_startHaptic;   // light taps for started and resumed
    UIImpactFeedbackGenerator *m_stopHaptic;    // firmer taps for paused and stopped
}

-(instancetype)init {
    self = [super init];
    if (self) {
        m_startHaptic = [[UIImpactFeedbackGenerator alloc] initWithStyle: UIImpactFeedbackStyleLight];
        m_stopHaptic = [[UIImpactFeedbackGenerator alloc] initWithStyle: UIImpactFeedbackStyleMedium];
    }
    return self;
}

-(void)dealloc {
    for (NSUInteger i = 0; i < kStoryDictationCueCount; i++)
        if (m_sounds[i])
            AudioServicesDisposeSystemSoundID(m_sounds[i]);
}

// Each cue's sound is registered with System Sound Services from its bundle file the first time
// it is needed.
-(SystemSoundID)soundForCue:(StoryDictationCue)cue {
    if (m_sounds[cue])
        return m_sounds[cue];
    NSString *name = kCueFileNames[cue];
    NSURL *url = [[NSBundle mainBundle] URLForResource: name withExtension: @"wav" subdirectory: kCueSoundsFolder];
    if (!url) {
        NSLog(@"Dictation cue sound %@/%@.wav is missing from the app bundle", kCueSoundsFolder, name);
        return 0;
    }
    OSStatus status = AudioServicesCreateSystemSoundID((__bridge CFURLRef)url, &m_sounds[cue]);
    if (status != noErr) {
        NSLog(@"Error creating dictation cue sound %@: %d", name, (int)status);
        m_sounds[cue] = 0;
    }
    return m_sounds[cue];
}

-(void)playCue:(StoryDictationCue)cue {
    SystemSoundID sound = [self soundForCue: cue];
    if (sound)
        AudioServicesPlaySystemSound(sound);

    // The haptic mirrors the tone: light for the high cues, firmer for the low ones, and two taps
    // timed with the double notes. Devices without a haptic engine (most iPads) ignore these.
    BOOL high = (cue == kStoryDictationCueStarted || cue == kStoryDictationCueResumed);
    BOOL doubled = (cue == kStoryDictationCueStarted || cue == kStoryDictationCueStopped);
    UIImpactFeedbackGenerator *haptic = high ? m_startHaptic : m_stopHaptic;
    [haptic impactOccurred];
    if (doubled) {
        [haptic prepare];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kCueSecondNoteOffset * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [haptic impactOccurred];
        });
    }
}

@end

#endif // EnableStoryDictation
