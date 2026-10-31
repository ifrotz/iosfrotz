//
//  StoryDictationController.m
//  Frotz
//
//  Created by Craig Smith on 6/19/23.
//

#import "StoryDictationController.h"

#if EnableStoryDictation

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

@implementation StoryDictationController

@synthesize delegate = m_delegate;

-(instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
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
}

// Called when the task first detects speech in the source audio
- (void)speechRecognitionDidDetectSpeech:(SFSpeechRecognitionTask *)task {
    NSLog(@"task detected speech");
}

// Called for all recognitions, including non-final hypothesis
- (void)speechRecognitionTask:(SFSpeechRecognitionTask *)task didHypothesizeTranscription:(SFTranscription *)transcription {
    NSString *text = [transcription formattedString];
    NSLog(@"speechRecognitionTask:didHypothesizeTranscription: %@", text);
    if (![text isEqualToString: m_currentTranscription]) {
        m_currentTranscription = text;
        [self setupTimer];
    }
    m_lastRecogDate = [NSDate date];
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
                NSLog(@"  validated: %@", word);
                score++;
            }
            i++;
        }
    }
    return score;
}

// Called only for final recognitions of utterances. No more about the utterance will be reported
- (void)speechRecognitionTask:(SFSpeechRecognitionTask *)task didFinishRecognition:(SFSpeechRecognitionResult *)result {
    BOOL isFinal = [result isFinal];
    NSLog(@"speechRecognitionTask:didFinishRecognition final=%d", isFinal);
    NSArray<SFTranscription *> *transcriptions = [result transcriptions];
    int i = 0, bestIndex = -1;
    NSUInteger bestScore = 0;
    for (SFTranscription *transcription in transcriptions) {
        //SFTranscription *transcription = [result bestTranscription];
        NSString *text = [transcription formattedString];
        NSUInteger score = [self dictationDictionaryScore: text];
        NSLog(@"  Count: %d Score: %lu Recog: %@", i, score, text);
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
    m_lastRecogDate = [NSDate date];
    NSLog(@"Final: %d Recog: %@", isFinal, text);
    m_currentTranscription = [text stringWithSanitizeDictation];

    NSError *error = [task error];
    if (error || isFinal) {
        if (error)
            NSLog(@"recognitionTaskWithRequest error: %@", error);
        if (isFinal || [error code] == 203)
            m_recognitionTask = nil;
    }
    if ([self isListening])
        [self setupTimer];
}

// Called when the task is no longer accepting new audio but may be finishing final processing
- (void)speechRecognitionTaskFinishedReadingAudio:(SFSpeechRecognitionTask *)task {
    NSLog(@"Task finished audio");
}

// Called when the task has been cancelled, either by client app, the user, or the system
- (void)speechRecognitionTaskWasCancelled:(SFSpeechRecognitionTask *)task {
    NSLog(@"Task canceled");
}

// Called when recognition of all requested utterances is finished.
// If successfully is false, the error property of the task will contain error information
- (void)speechRecognitionTask:(SFSpeechRecognitionTask *)task didFinishSuccessfully:(BOOL)successfully {
    if (!successfully) {
        NSError *error = [task error];
        if (error)
            NSLog(@"speechRecognitionTask:didFinishSuccessfully error: %@", error);
        if ([error code] == 203)
            m_recognitionTask = nil;
    } else
        m_recognitionTask = nil;
    if ([self isListening])
        [self setupTimer];
}

-(BOOL)isListening {
    return m_sfRecogRequest != nil && [m_audioEngine isRunning];
}

-(BOOL)isPaused {
    return m_isPaused;
}

-(void)pauseListening {
    if ([m_audioEngine isRunning])
        [m_audioEngine pause];
    m_isPaused = YES;
    NSLog(@"pauseListening");
}

-(void)listenForSpeech {
    NSError *error = nil;
    if (m_isPaused) {
        [m_audioEngine startAndReturnError: &error];
        m_isPaused = NO;
        if (!error && [m_audioEngine isRunning] && m_recognitionTask) {
            NSLog(@"listenForSpeech unpaused");
            return;
        }
    }
    // Cancel the previous task if it's running.
    if (m_recognitionTask) {
        [m_recognitionTask finish];
        m_recognitionTask = nil;
        m_sfRecogRequest = nil;
    }
    if (![m_audioEngine isRunning]) {
        AVAudioInputNode *audioInputNode = [m_audioEngine inputNode];
        AVAudioFormat *recordingFormat = [audioInputNode outputFormatForBus: 0];
        [audioInputNode removeTapOnBus:0];
        @try {
            [audioInputNode installTapOnBus:0 bufferSize:1024 format:recordingFormat block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
                if (m_sfRecogRequest)
                    [m_sfRecogRequest appendAudioPCMBuffer: buffer];
                //NSLog(@" append audio %@", m_sfRecogRequest);
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
    
    [m_audioSession setCategory: AVAudioSessionCategoryPlayAndRecord // AVAudioSessionCategoryRecord // AVAudioSessionCategoryPlayAndRecord
//                           mode: AVAudioSessionModeDefault // AVAudioSessionModeSpokenAudio
//                        options: //AVAudioSessionCategoryOptionDuckOthers|
//                                AVAudioSessionCategoryOptionMixWithOthers|
//                                AVAudioSessionCategoryOptionAllowBluetooth
                          error: &error];
    if (error) {
        NSLog(@"Error AVAudioSession setCategory: %@", error);
    }
    [m_audioSession setActive:YES withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error: &error];
    if (error) {
        NSLog(@"Error AVAudioSession setActive: %@", error);
    }
    m_sfRecogRequest = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
    m_sfRecogRequest.shouldReportPartialResults = YES;
    m_sfRecogRequest.requiresOnDeviceRecognition = YES;
    m_sfRecogRequest.contextualStrings = @[ @"look", @"grue", @"i", @"frotz", @"nitfol", @"aimfiz", @"filfre", @"gnusto", @"rezrov" ];
    m_recognitionTask = [m_sfrecog recognitionTaskWithRequest: m_sfRecogRequest delegate: self];
}

-(void)setupTimer {
    if (m_speechCommitTimer) {
        [m_speechCommitTimer invalidate];
        m_speechCommitTimer = nil;
    }
    typedef void (^ATimerBlock)(NSTimer * _Nonnull timer);
    __block ATimerBlock block = ^(NSTimer * _Nonnull timer) {
        //if (m_currentTranscription)
            NSLog(@"timer: ct:%@", m_currentTranscription);
        if (!m_recognitionTask || m_currentTranscription.length > 0) {
            NSTimeInterval interval = [[timer fireDate] timeIntervalSinceDate: m_lastRecogDate];
            if (m_recognitionTask) {
                if (interval < 0.8) {
                    if (m_delegate && [m_currentTranscription length] > 0)
                        [m_delegate acceptDictation: m_currentTranscription final:NO];
                    [self setupTimer];
                    return;
                }
                // If the user has stopped speaking for 1 second, commit recognition.
                if (m_recognitionTask.state <= SFSpeechRecognitionTaskStateRunning) {
                    NSLog(@" calling finish");
                    [m_recognitionTask finish];
                    return;
                }
            }
            m_recognitionTask = nil;
            // Print the final transcription.
            [m_speechCommitTimer invalidate];
            m_speechCommitTimer = nil;
            NSLog(@"Final xscipt: %@", m_currentTranscription);
            if (m_delegate && [m_currentTranscription length] > 0)
                [m_delegate acceptDictation: m_currentTranscription final:YES];
            m_currentTranscription = nil;
            [self performSelector: @selector(listenForSpeech) withObject:nil afterDelay:0];
        }
    };
    m_speechCommitTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:NO block: block];
}

-(void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}


@end

#endif // EnableStoryDictation
