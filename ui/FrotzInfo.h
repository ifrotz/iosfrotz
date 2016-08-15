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

NS_ASSUME_NONNULL_BEGIN

@protocol KeyboardOwner <NSObject>
-(nullable id)dismissKeyboard;
@end

@interface FrotzInfo : UIViewController <FrotzSettingsInfoDelegate> {
    UIButton *m_infoButton;
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

-(instancetype)initWithSettingsController:(FrotzSettingsController*)settings navController:(UINavigationController*)navController navItem: (UINavigationItem*) navItem NS_DESIGNATED_INITIALIZER;
-(instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
-(instancetype)initWithCoder:(NSCoder *)aDecoder NS_UNAVAILABLE;
-(void)dismissInfo;
-(void)frotzInfo;
@property (nonatomic, strong) id<KeyboardOwner> keyboardOwner;
@property (nonatomic, readonly, strong) UINavigationController *navController;
@property (nonatomic, readonly, strong) UINavigationItem *navItem;
-(void)updateAccessibility;
-(void)updateTitle;
@end

NS_ASSUME_NONNULL_END
