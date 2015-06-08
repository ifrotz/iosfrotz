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

typedef NS_ENUM(unsigned int, FrotzInputHelperMode) {
    FrotzInputHelperModeNone = 0,
    FrotzInputHelperModeWords,
    FrotzInputHelperModeMoreWords,
    FrotzInputHelperModeHistory
    };

@interface FrotzInputHelper : UITableViewController {
    NSMutableArray *m_history;
    NSArray *m_commonCommands;
    NSObject<FrotzInputDelegate> *m_delegate;
    FrotzWordPicker *m_wordPicker;
    FrotzInputHelperMode m_mode;
    int m_lastCommonWordPicked;
    int m_currHistoryItem;
}
- (instancetype)init;
@property (nonatomic, weak) NSObject<FrotzInputDelegate> *delegate;
- (void)clearHistory;
@property (nonatomic, readonly) int historyCount;
@property (nonatomic, readonly) int menuCount;
- (NSString*)historyItem:(int)item;
- (int)addHistoryItem:(NSString*)historyItem;
@property (nonatomic, getter=getNextHistoryItem, readonly, copy) NSString *nextHistoryItem;
@property (nonatomic, getter=getPrevHistoryItem, readonly, copy) NSString *prevHistoryItem;
@property (nonatomic, readonly, strong) UIView *helperView;
@property (nonatomic, readonly) FrotzInputHelperMode mode;
-(void)showInputHelperInView:(UIView*)parentView atPoint:(CGPoint)pt withMode:(FrotzInputHelperMode)mode;
-(void)hideInputHelper;

@end
