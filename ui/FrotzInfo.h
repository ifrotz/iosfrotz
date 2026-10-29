//
//  FrotzInfo.h
//  Frotz
//
//  Created by Craig Smith on 8/3/08.
//  Copyright 2008 Craig Smith. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "FrotzSettings.h"

NS_ASSUME_NONNULL_BEGIN

@protocol KeyboardOwner <NSObject>
-(nullable id)dismissKeyboard;
@end

@interface FrotzInfo : UIViewController <FrotzSettingsInfoDelegate> {
    UIBarButtonItem *m_infoBarItem;
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
/// The Frotz (i) settings button. Owners place it among their navigation item's trailing items; as a
/// bar button item with a symbol it can move to the iPhone Duo's vertical controls.
@property (nonatomic, readonly, strong) UIBarButtonItem *infoBarButtonItem;
-(void)updateAccessibility;
-(void)updateTitle;
@end

NS_ASSUME_NONNULL_END
