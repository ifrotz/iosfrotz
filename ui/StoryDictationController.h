//
//  StoryDictationController.h
//  Frotz
//
//  Created by Craig Smith on 6/19/23.
//

#import <UIKit/UIKit.h>
#import <Speech/Speech.h>
#import "InputHelper.h"

NS_ASSUME_NONNULL_BEGIN
@class SFSpeechAudioBufferRecognitionRequest, SFSpeechRecognitionTask;

@interface StoryDictationController : UIViewController <SFSpeechRecognizerDelegate, SFSpeechRecognitionTaskDelegate>
{
    SFSpeechRecognizer *m_sfrecog;
    SFSpeechAudioBufferRecognitionRequest *m_sfRecogRequest;
    AVAudioEngine *m_audioEngine;
    AVAudioSession *m_audioSession;
    SFSpeechRecognitionTask *m_recognitionTask;
    
    NSString *m_currentTranscription;
    NSDate *m_lastRecogDate;
    NSTimer *m_speechCommitTimer;
    BOOL m_isPaused;
    id<FrotzInputDelegate> __weak m_delegate;
}

-(instancetype)init NS_DESIGNATED_INITIALIZER;
-(instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
-(instancetype)initWithCoder:(NSCoder *)aDecoder NS_UNAVAILABLE;

-(void)listenForSpeech;
-(void)setupTimer;
-(void)pauseListening;
-(BOOL)isListening;
-(BOOL)isPaused;
-(void)stopListening;

@property (nonatomic, weak) id<FrotzInputDelegate> delegate;
@end

NS_ASSUME_NONNULL_END
