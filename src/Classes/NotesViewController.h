//
//  NotesViewController.h
//  Frotz
//
//  Created by Craig Smith on 9/6/10.
//  Copyright 2010 Craig Smith. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "FileBrowser.h"

@protocol LockableKeyboard
-(void)showKeyboardLockState;
@end

@interface NotesViewController : UIViewController <UIScrollViewDelegate, UITextViewDelegate, FileSelected> {
    CGRect m_frame;
    
    UISegmentedControl *m_notesTitle;
    
    UIScrollView *m_scrollView;
    UITextView *m_notesView;
    UIImageView *m_notesBGView;
    UIResponder *m_chainResponder;
    
    UIViewController<TextFileBrowser,FileSelected, LockableKeyboard> *m_delegate;
}

-(NotesViewController*)initWithFrame:(CGRect)frame NS_DESIGNATED_INITIALIZER;
-(void)dealloc;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *text;
-(void)setFrame:(CGRect)frame;
-(void)setChainResponder:(UIResponder*)responder;
-(void)activateKeyboard;
-(void)dismissKeyboard;
-(void)toggleKeyboard;
@property (nonatomic, readonly, strong) UIScrollView *containerScrollView;
-(void) keyboardWillShow:(CGRect)kbBounds;
-(void) keyboardWillHide;
@property (nonatomic, getter=isVisible, readonly) BOOL visible;
-(void)show;
-(void)hide;
-(void)loadView;
-(void)autosize;
-(void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView;
- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration;
-(void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation;
-(void)viewWillAppear:(BOOL)animated;
-(void)viewWillDisappear:(BOOL)animated;
-(void)setDelegate:(UIViewController<TextFileBrowser,FileSelected,LockableKeyboard>*)delegate;
-(UIViewController<TextFileBrowser,FileSelected>*)delegate;
-(void)workaroundFirstResponderBug;
@end
