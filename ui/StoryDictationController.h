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
// goes away while dictation is on, after listening has been stopped, so the user can be told;
// and when the microphone couldn't be started at all, so a tap on the mic never fails silently.
@protocol StoryDictationStateDelegate <NSObject>
-(void)dictationListeningStateChanged:(StoryDictationController*)controller;
-(void)dictationBecameUnavailable:(StoryDictationController*)controller;
-(void)dictationFailedToStart:(StoryDictationController*)controller;
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
    NSTimeInterval m_silenceInterval;
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
// Listening is off but due back without the player asking: paused by the UI, or taken by an audio
// interruption that may hand it back. Distinguishes a pause from a stop for the cues.
-(BOOL)willResume;
-(void)stopListening;

@property (nonatomic, weak) id<FrotzInputDelegate> delegate;
@property (nonatomic, weak) id<StoryDictationStateDelegate> stateDelegate;
// How long the speaker must be quiet before what was said is accepted as a command. The settings
// page's "Dictation Delay"; 0.8s unless set. Takes effect from the next utterance.
@property (nonatomic) NSTimeInterval silenceInterval;
@end

// Audible and felt cues for the state changes the mic button shows; the main view controller
// decides which to play from the state delegate's callbacks.
typedef NS_ENUM(NSInteger, StoryDictationCue) {
    kStoryDictationCueStarted,  // the player started listening: two quick high notes
    kStoryDictationCueResumed,  // listening came back by itself (notes page closed, a call ended): one high note
    kStoryDictationCuePaused,   // listening is off but will come back by itself: one low note
    kStoryDictationCueStopped,  // listening is over until the player starts it again: two quick low notes
    kStoryDictationCueCount
};

// Plays each cue as a short tone and a haptic together. The tones are WAV files in the app bundle
// played through System Sound Services, so they need no audio session of ours and don't light the
// mic indicator when played after dictation has stopped; the haptic covers a phone in silent mode
// (iOS gives no way to ask about the ring/silent switch, and tones through the recording session
// ignore it anyway).
@interface StoryDictationCuePlayer : NSObject
-(void)playCue:(StoryDictationCue)cue;
@end

NS_ASSUME_NONNULL_END
#endif // EnableStoryDictation
