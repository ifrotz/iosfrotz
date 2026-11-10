//
//  StoryInputLine.h
//  Frotz
//
//  Created by Craig Smith on 2/9/10.
//  Copyright 2010 Craig Smith. All rights reserved.
//

#import "StoryMainViewController.h"
#import "CompletionLabel.h"

NS_ASSUME_NONNULL_BEGIN

@interface StoryInputLine: UITextField <FrotzInputDelegate> {
    StoryView *m_storyView;
    StatusLine *m_statusLine;
    UIView *m_enterAndClearView;
    FrotzInputHelper *m_inputHelper;
    UITouchPhase m_lastTouchPhaseSeen;
    NSTimeInterval m_lastTouchTimestamp;
    CGPoint m_touchBeganPosition;
    CompletionLabel *m_completionLabel;
    BOOL m_firstKeyPressed, m_lastCharDeleted;
    BOOL m_justHidHelper;
    BOOL m_completionAmbiguous;
#if EnableStoryDictation
    NSString *m_textBeforeDictation; // what was typed before the current utterance began; nil between utterances
    NSString *m_lastDictationShown;  // typed part and transcript as acceptDictation:final: last set them
    NSString *m_dictationSuffix;     // what followed the transcript at the last hypothesis (tapped or typed words)
    NSString *m_lastDictationTranscript; // the recognizer's transcript as of the last result shown
    NSString *m_dictationTakeoverTranscript; // the transcript shown when the player edited inside it; only what the recognizer adds after it is shown
    BOOL m_dictationHold;            // the player opened the input helper since the last words: don't submit the final result
    BOOL m_lastInputRequestWasKey;   // the story's most recent input request was for a single key; see dictationExpectsSingleKey
#endif
}
-(StoryInputLine*)initWithFrame:(CGRect)frame NS_DESIGNATED_INITIALIZER;
-(instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
-(instancetype)initWithCoder:(NSCoder *)aDecoder NS_UNAVAILABLE;
@property (nonatomic, strong) StoryView *storyView;
@property (nonatomic, strong) StatusLine *statusLine;
-(void)resetState;
@property (nonatomic, readonly) BOOL updatePosition;
-(BOOL)handleTouch: (UITouch*)touch withEvent: (UIEvent*)event;
-(NSUInteger)addHistoryItem:(NSString*)historyItem;
-(void)inputHelperString:(NSString*)string;
-(void)hideInputHelper;
-(void)holdDictationCommit; // the player is composing by other means; a dictated utterance's final result won't submit until they speak again
#if EnableStoryDictation
-(void)acceptDictation:(NSString*)string final:(BOOL)isFinal;
#endif
@property (nonatomic, readonly, strong) UIView *inputHelperView;
-(void)setClearButtonMode;
-(void)maybeShowEnterKey;
-(void)hideEnterKey;
-(void)setTextKeepCompletion:(NSString*)text;
@end

NS_ASSUME_NONNULL_END
