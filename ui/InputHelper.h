//
//  InputHelper.h
//  Frotz
//
//  Created by Craig Smith on 9/6/08.
//  Copyright 2008 Craig Smith. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "FrotzWordPicker.h"
#import "iosfrotz.h"

@protocol FrotzInputDelegate <NSObject>
-(void)inputHelperString:(NSString*)string;
#if EnableStoryDictation
-(void)acceptDictation:(NSString*)string final:(BOOL)isFinal;
// The utterance in progress ended without a final result (listening was paused). Whatever was
// shown for it stays; the next hypothesis begins a new utterance after it rather than revising it.
-(void)abandonDictation;
-(BOOL)validateWord:(NSString*)word;
// How many of the commands in a transcript begin as a command does: with a verb (per the game's
// dictionary, or an ordinary verb) or a direction. Several commands can be chained ("take lamp
// then look"). Weighs the recognizer's alternatives.
-(NSUInteger)dictationCommandsStartingWithVerb:(NSString*)text;
// Whether the story is waiting for a single key rather than a line, so the recognizer can be
// primed for letter names and the few words that stand for keys. Asked when a task starts.
-(BOOL)dictationExpectsSingleKey;
// How directly text names a key, for choosing among the recognizer's alternative transcriptions
// at a key prompt: 2 for a bare letter or digit ("Q"), 1 for a word that stands for a key or
// spells a letter's name ("yes", "space", "cue", "you"), 0 for anything else, which would only
// lend its first letter. Bare letters rank above names because a name can be a mishearing of a
// different letter ("you" for Q), while a bare letter is the recognizer's own reading of one.
-(NSUInteger)dictationKeyScore:(NSString*)text;
// Words and phrases the player is likely to say next, for the recognizer's contextual strings:
// the player's recent commands, the words of the story's recent output (the nouns on screen are
// what commands are about), and the ordinary verbs of the form. Most likely first. Asked when a
// task starts, so once per utterance.
-(NSArray<NSString*>*)dictationContextWords;
// A final transcript with words the game doesn't know replaced, where there is a near match, by
// words from the recent story output that it does know ("yemen" by "yomin", "drivers" by
// "driver's"). Words the game knows are left alone, as are words with no near match, words in
// all capitals (the player spelled them out), and words lying in confidentRanges: character
// ranges of the transcript the recognizer was sure of, which a correction would second-guess.
-(NSString*)dictationCorrectedText:(NSString*)text confidentRanges:(NSIndexSet*)confidentRanges;
#endif
-(BOOL)isFirstResponder;
@end

typedef NS_ENUM(unsigned int, FrotzInputHelperMode) {
    FrotzInputHelperModeNone = 0,
    FrotzInputHelperModeWords,
    FrotzInputHelperModeMoreWords,
    FrotzInputHelperModeHistory
    };

@interface FrotzInputHelper : UITableViewController {
    NSMutableArray<NSString*> *m_history;
    NSArray<NSString*> *m_commonCommands;
    id<FrotzInputDelegate> __weak m_delegate;
    FrotzWordPicker *m_wordPicker;
    FrotzInputHelperMode m_mode;
    NSInteger m_lastCommonWordPicked;
    NSUInteger m_currHistoryItem;
}
- (instancetype)init;
@property (nonatomic, weak) id<FrotzInputDelegate> delegate;
- (void)clearHistory;
@property (nonatomic, readonly) NSUInteger historyCount;
@property (nonatomic, readonly, copy) NSArray<NSString*> *historyItems; // oldest first, whatever the helper's mode
@property (nonatomic, readonly) NSUInteger menuCount;
- (NSString*)historyItem:(NSInteger)item;
- (NSUInteger)addHistoryItem:(NSString*)historyItem;
@property (nonatomic, getter=getNextHistoryItem, readonly, copy) NSString *nextHistoryItem;
@property (nonatomic, getter=getPrevHistoryItem, readonly, copy) NSString *prevHistoryItem;
@property (nonatomic, readonly, strong) UIView *helperView;
@property (nonatomic, readonly) FrotzInputHelperMode mode;
-(void)showInputHelperInView:(UIView*)parentView atPoint:(CGPoint)pt withMode:(FrotzInputHelperMode)mode;
-(void)hideInputHelper;

@end
