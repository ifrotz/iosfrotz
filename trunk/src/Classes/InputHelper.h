//
//  InputHelper.h
//  Frotz
//
//  Created by Craig Smith on 9/6/08.
//  Copyright 2008 Craig Smith. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "FrotzWordPicker.h"

@protocol FrotzInputDelegate
-(void)inputHelperString:(NSString*)string;
-(BOOL)isFirstResponder;
@end

typedef enum {
    FrotzInputHelperModeNone = 0,
    FrotzInputHelperModeWords,
    FrotzInputHelperModeMoreWords,
    FrotzInputHelperModeHistory
    } FrotzInputHelperMode;

@interface FrotzInputHelper : UITableViewController {
    NSMutableArray *m_history;
    NSArray *m_commonCommands;
    NSObject<FrotzInputDelegate> *m_delegate;
    FrotzWordPicker *m_wordPicker;
    FrotzInputHelperMode m_mode;
    int m_lastCommonWordPicked;    
}
- (id)init;
- (void)setDelegate:(NSObject<FrotzInputDelegate>*)delegate;
- (NSObject<FrotzInputDelegate>*)delegate;
- (void)clearHistory;
- (int)historyCount;
- (int)menuCount;
- (NSString*)historyItem:(int)item;
- (int)addHistoryItem:(NSString*)historyItem;
- (UIView*)helperView;
- (FrotzInputHelperMode)mode;
-(void)showInputHelperInView:(UIView*)parentView atPoint:(CGPoint)pt withMode:(FrotzInputHelperMode)mode;
-(void)hideInputHelper;

@end
