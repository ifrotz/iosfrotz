//
//  StoryDictationController.h
//  Frotz
//
//  Created by Craig Smith on 6/19/23.
//

#import <UIKit/UIKit.h>
#import "iosfrotz.h"

#if EnableStoryDictation
#import <Speech/Speech.h>
#import "InputHelper.h"

NS_ASSUME_NONNULL_BEGIN
@class SFSpeechAudioBufferRecognitionRequest, SFSpeechRecognitionTask, StoryDictationController;

// Whether the recognizer can take a request right now; see availability.
typedef NS_ENUM(NSInteger, StoryDictationAvailability) {
    kStoryDictationAvailable,
    kStoryDictationRecognizerUnavailable,   // the system recognizer is off: Siri and Dictation disabled, assets missing
    kStoryDictationOnDeviceUnsupported,     // this device can't recognize the locale offline, which is all we ask for
};

// Told whenever listening starts, pauses, resumes or stops, whether asked to or on its own (the
// audio engine failing to start, say); read isListening and isPaused for the new state. Lets the
// mic button show what the recognizer is actually doing. Also told when the system recognizer
// goes away while dictation is on, after listening has been stopped, so the user can be told.
@protocol StoryDictationStateDelegate <NSObject>
-(void)dictationListeningStateChanged:(StoryDictationController*)controller;
-(void)dictationBecameUnavailable:(StoryDictationController*)controller;
@end

// Runs on-device speech recognition on the microphone and hands the transcriptions to its
// delegate (the input line). Not a view controller: it has no UI of its own.
@interface StoryDictationController : NSObject <SFSpeechRecognizerDelegate, SFSpeechRecognitionTaskDelegate>
{
    SFSpeechRecognizer *m_sfrecog;
    SFSpeechAudioBufferRecognitionRequest *m_sfRecogRequest;
    AVAudioEngine *m_audioEngine;
    AVAudioSession *m_audioSession;
    SFSpeechRecognitionTask *m_recognitionTask;
    
    NSString *m_currentTranscription;
    NSTimer *m_speechCommitTimer; // fires after a stretch of silence; see restartSilenceTimer
    NSTimer *m_longIdleTimer;     // stops listening after a long stretch with no speech at all; see restartLongIdleTimer
    BOOL m_isPaused;
    BOOL m_resumeAfterInterruption; // an audio interruption stopped listening; start again if told it has ended
    BOOL m_tapInstalled;   // the input node has our tap, in the format current when it was installed
    id<FrotzInputDelegate> __weak m_delegate;
    id<StoryDictationStateDelegate> __weak m_stateDelegate;
}

-(instancetype)init NS_DESIGNATED_INITIALIZER;

// Check before listenForSpeech; a request made while the recognizer is unavailable just fails.
-(StoryDictationAvailability)availability;
-(void)listenForSpeech;
-(void)pauseListening;
-(BOOL)isListening;
-(BOOL)isPaused;
-(void)stopListening;

@property (nonatomic, weak) id<FrotzInputDelegate> delegate;
@property (nonatomic, weak) id<StoryDictationStateDelegate> stateDelegate;
@end

NS_ASSUME_NONNULL_END
#endif // EnableStoryDictation
