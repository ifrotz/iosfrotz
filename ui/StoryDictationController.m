//
//  StoryDictationController.m
//  Frotz
//
//  Created by Craig Smith on 6/19/23.
//

#import "StoryDictationController.h"

#if EnableStoryDictation

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

@implementation StoryDictationController

@synthesize delegate = m_delegate;
@synthesize stateDelegate = m_stateDelegate;

-(void)notifyStateChanged {
    [m_stateDelegate dictationListeningStateChanged: self];
}

-(instancetype)init {
    self = [super init];
    if (self) {
        m_sfrecog =  [[SFSpeechRecognizer alloc] initWithLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en-US"]];
        m_sfrecog.delegate = self;
        
        m_audioEngine = [[AVAudioEngine alloc] init];
        m_audioSession = [AVAudioSession sharedInstance];
    }
    return self;
}

-(void)stopListening {
    if (m_speechCommitTimer) {
        [m_speechCommitTimer invalidate];
        m_speechCommitTimer = nil;
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(listenForSpeech) object:nil];

    m_isPaused = NO;
    [m_audioEngine stop];
    AVAudioInputNode *audioInputNode = [m_audioEngine inputNode];
    [audioInputNode removeTapOnBus:0];
    if (m_recognitionTask) {
        [m_sfRecogRequest endAudio];
        [m_recognitionTask cancel];
        m_sfRecogRequest = nil;
        m_recognitionTask = nil;
    }
    [self notifyStateChanged];
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

// A pause is an interruption (the notes page or the file chooser came up), not the end of a
// command, so an utterance in progress is abandoned rather than committed: otherwise the silence
// that follows would commit "put the brass lantern" as a command while the player was elsewhere.
// The partial text already shown stays in the input line to be finished or cleared on return.
// The task is dropped before it is cancelled so its cancellation callback is ignored as stale.
-(void)pauseListening {
    [m_speechCommitTimer invalidate];
    m_speechCommitTimer = nil;
    SFSpeechRecognitionTask *task = m_recognitionTask;
    m_recognitionTask = nil;
    [m_sfRecogRequest endAudio];
    m_sfRecogRequest = nil;
    [task cancel];
    m_currentTranscription = nil;
    [m_delegate abandonDictation]; // so the words after the pause follow the ones before it
    if ([m_audioEngine isRunning])
        [m_audioEngine pause];
    m_isPaused = YES;
    DictationLog(@"pauseListening");
    [self notifyStateChanged];
}

// Starts (or, when paused, resumes) listening. Every way out reports the resulting state to the
// state delegate, since the audio engine may refuse to start and leave nothing listening.
-(void)listenForSpeech {
    [self startListening];
    [self notifyStateChanged];
}

-(void)startListening {
    NSError *error = nil;
    if (m_isPaused) {
        [m_audioEngine startAndReturnError: &error];
        m_isPaused = NO;
        if (!error && [m_audioEngine isRunning] && m_recognitionTask) {
            DictationLog(@"listenForSpeech unpaused");
            return;
        }
    }
    // Cancel the previous task if it's running.
    if (m_recognitionTask) {
        [m_recognitionTask finish];
        m_recognitionTask = nil;
        m_sfRecogRequest = nil;
    }
    // The session must be a recording session before the engine is touched.
    [m_audioSession setCategory: AVAudioSessionCategoryPlayAndRecord error: &error];
    if (error) {
        NSLog(@"Error AVAudioSession setCategory: %@", error);
        error = nil;
    }
    [m_audioSession setActive:YES withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error: &error];
    if (error) {
        NSLog(@"Error AVAudioSession setActive: %@", error);
        error = nil;
    }

    if (![m_audioEngine isRunning]) {
        AVAudioInputNode *audioInputNode = [m_audioEngine inputNode];
        AVAudioFormat *recordingFormat = [audioInputNode outputFormatForBus: 0];
        [audioInputNode removeTapOnBus:0];
        @try {
            [audioInputNode installTapOnBus:0 bufferSize:1024 format:recordingFormat block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
                if (m_sfRecogRequest)
                    [m_sfRecogRequest appendAudioPCMBuffer: buffer];
            }];
            [m_audioEngine prepare];
            [m_audioEngine startAndReturnError: &error];
        }
        @catch (NSException *exception) {
            return;
        }
        if (error) {
            NSLog(@"Error audioEngine:startAndReturnError: %@", error);
        }
    }

    m_sfRecogRequest = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
    m_sfRecogRequest.shouldReportPartialResults = YES;
    m_sfRecogRequest.requiresOnDeviceRecognition = YES;
    m_sfRecogRequest.contextualStrings = @[ @"look", @"grue", @"i", @"frotz", @"nitfol", @"aimfiz", @"filfre", @"gnusto", @"rezrov" ];
    m_recognitionTask = [m_sfrecog recognitionTaskWithRequest: m_sfRecogRequest delegate: self];
}

// An utterance ends when the recognizer has sent no hypothesis for this long. Each hypothesis
// restarts the timer, so it only ever fires once, after the speaker has stopped.
static const NSTimeInterval kDictationSilenceInterval = 0.8;

-(void)restartSilenceTimer {
    [m_speechCommitTimer invalidate];
    __weak StoryDictationController *weakSelf = self;
    m_speechCommitTimer = [NSTimer scheduledTimerWithTimeInterval: kDictationSilenceInterval repeats: NO block: ^(NSTimer *timer) {
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

#endif // EnableStoryDictation
