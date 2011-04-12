//
//  FrotzInfo.h
//  Frotz
//
//  Created by Craig Smith on 8/3/08.
//  Copyright 2008 Craig Smith. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "FrotzSettings.h"
//#import "ColorPicker.h"


@protocol KeyboardOwner
-(id)dismissKeyboard;
@end

@interface FrotzInfo : UIViewController <FrotzSettingsInfoDelegate> {
    UIButton *m_infoButton;
//    UIButton *m_titleTextView;
    UILabel *m_titleTextView;

    UINavigationController *m_navigationController;
    UIBarButtonItem *m_doneButton, *m_savedLeftButton, *m_savedRightButton;
    
    UIViewController *m_viewController;
    
    UITextView *m_pane1, *m_pane2;
    FrotzSettingsController *m_settings;
    UINavigationItem *m_navItem;
    id m_prevResponder;

    id <KeyboardOwner> m_kbdOwner;
}

-(id)initWithSettingsController:(FrotzSettingsController*)settings navController:(UINavigationController*)navController navItem: (UINavigationItem*) navItem;
-(void)dismissInfo;
-(void)frotzInfo;
-(void)setKeyboardOwner:(id<KeyboardOwner>)kbdOwner;
-(id<KeyboardOwner>)keyboardOwner;
-(UINavigationController*)navController;
-(UINavigationItem*)navItem;
-(void)updateAccessibility;
@end
