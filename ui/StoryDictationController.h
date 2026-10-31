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

// Told whenever listening starts, pauses, resumes or stops, whether asked to or on its own (the
// audio engine failing to start, say); read isListening and isPaused for the new state. Lets the
// mic button show what the recognizer is actually doing.
@protocol StoryDictationStateDelegate <NSObject>
-(void)dictationListeningStateChanged:(StoryDictationController*)controller;
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
    BOOL m_isPaused;
    id<FrotzInputDelegate> __weak m_delegate;
    id<StoryDictationStateDelegate> __weak m_stateDelegate;
}

-(instancetype)init NS_DESIGNATED_INITIALIZER;

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
