//
//  FrotzInfo.m
//  Frotz
//
//  Created by Craig Smith on 8/3/08.
//  Copyright 2008 Craig Smith. All rights reserved.
//

#include "iosfrotz.h"
#import "FrotzInfo.h"
#import <QuartzCore/QuartzCore.h>
#import "TextViewExt.h"

// UIKit may compress a custom navigation title beside the voice toolbar.
// Keep Settings inside its hit-test bounds; the decorative title yields first.
@interface FrotzInfoTitleView : UIView
@property UILabel *titleLabel;
@property UIButton *infoButton;
@end
@implementation FrotzInfoTitleView
- (CGSize)intrinsicContentSize { return CGSizeMake(106, 44); }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    CGFloat buttonWidth = MIN(44, width);
    self.infoButton.frame = CGRectMake(width - buttonWidth, 0, buttonWidth, self.bounds.size.height);
    CGFloat labelWidth = width - buttonWidth;
    self.titleLabel.hidden = labelWidth < 54;
    self.titleLabel.frame = CGRectMake(0, 0, labelWidth, self.bounds.size.height);
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
}
@end

@implementation FrotzInfo
@synthesize keyboardOwner = m_kbdOwner;

-(instancetype)initWithSettingsController:(FrotzSettingsController*)settings navController:(UINavigationController*)navController navItem: (UINavigationItem*) navItem {
	if ((self = [super initWithNibName:nil bundle:nil])) {
	    // Initialization code
        
	    m_navigationController = navController;
	    m_navItem = navItem;
        m_settings = settings;
        // don't set settings infoDelegate here; we could be loaded while settings is already up (e.g. StoryDetailsController because of rotation)
	}
	return self;
}

-(void)loadView {
    self.view = [[FrotzInfoTitleView alloc] initWithFrame:CGRectMake(0, 0, 106, 44)];
    
    CGRect frame = CGRectMake(0,0, 106, 44);
    
    m_titleTextView = [[UILabel alloc] initWithFrame: CGRectMake(20,0,54,44)];
    [m_titleTextView setText: @"Frotz"];
    
    m_titleTextView.backgroundColor = [UIColor clearColor];
    m_titleTextView.font = [UIFont boldSystemFontOfSize: 20];
    
    UIView *view = [self view];
    [view setAutoresizingMask: UIViewAutoresizingNone];
    [view setFrame: frame];
    view.backgroundColor = [UIColor clearColor];
    [view addSubview: m_titleTextView];
    m_infoButton = [UIButton buttonWithType: UIButtonTypeInfoLight];
    [m_infoButton setFrame: CGRectMake(62, 0, 44, 44)];
    ((FrotzInfoTitleView *)view).titleLabel = m_titleTextView;
    ((FrotzInfoTitleView *)view).infoButton = m_infoButton;
    m_infoButton.accessibilityIdentifier = @"frotzSettings";
    [self updateAccessibility];
    [view addSubview: m_infoButton];
    [m_infoButton addTarget:self action:@selector(frotzInfo) forControlEvents: UIControlEventTouchUpInside];
    
    m_doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem: UIBarButtonSystemItemDone target:self action:@selector(frotzInfo)];
    [self updateTitle];

}

-(void)updateTitle {
    UINavigationController *nc = m_navigationController;
    UIColor *color = [nc.navigationBar tintColor];
    [m_titleTextView setTextColor: color];
    [m_infoButton setTintColor: color];
}

-(void)updateAccessibility {
    if ([m_infoButton respondsToSelector: @selector(setAccessibilityLabel:)])
        [m_infoButton setAccessibilityLabel: @"Settings"];
}

-(UINavigationController*)navController {
    return m_navigationController;
}

-(UINavigationItem*)navItem {
    return m_navItem;
}


-(void)setupFade {
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:0.5];

    [UIView setAnimationTransition:
     ([m_settings.view superview] ? UIViewAnimationTransitionFlipFromLeft : UIViewAnimationTransitionFlipFromRight)
                           forView: m_navigationController.view
                             cache:NO];

    [UIView commitAnimations];
}

-(void)dismissInfoModal {
    [m_navigationController dismissViewControllerAnimated:YES completion:^{
        if ([self->m_kbdOwner respondsToSelector:@selector(resumeVoiceAfterSettings)])
            [self->m_kbdOwner resumeVoiceAfterSettings];
    }];
}

-(void)dismissInfo {
    if (m_navigationController) {
        UINavigationController *nc;
        if ((nc = (UINavigationController*)m_navigationController.modalViewController)) {
            if ([nc respondsToSelector:@selector(topViewController)]
                && [nc topViewController] != m_settings)
                [nc popToViewController: m_settings animated:YES];
            [self performSelector:@selector(dismissInfoModal) withObject: nil afterDelay: 0.2];
        }
    }
    if (m_prevResponder && [m_prevResponder respondsToSelector:@selector(becomeFirstResponder)])
        [m_prevResponder performSelector:@selector(becomeFirstResponder) withObject:nil afterDelay:0.3];
    if (!m_navigationController.presentedViewController
        && [m_kbdOwner respondsToSelector:@selector(resumeVoiceAfterSettings)])
        [m_kbdOwner resumeVoiceAfterSettings];
}

-(void)frotzInfo {
    UIView *view = [m_settings view]; // Preload view so animation is smoother
    if (![view superview]) { // already presented
        if ([m_kbdOwner respondsToSelector:@selector(pauseVoiceForSettings)])
            [m_kbdOwner pauseVoiceForSettings];
        if (m_kbdOwner)
            m_prevResponder = [m_kbdOwner dismissKeyboard];
        [m_settings setInfoDelegate: self];

        UINavigationController *settingsNavController = [m_settings navigationController];
        if (!settingsNavController) {
            settingsNavController = [[UINavigationController alloc] initWithRootViewController: m_settings];
        }
        if (!gLargeScreenDevice)
            [settingsNavController setModalTransitionStyle: UIModalTransitionStyleFlipHorizontal];
        [settingsNavController setModalPresentationStyle: UIModalPresentationFormSheet];
        [m_navigationController presentModalViewController: settingsNavController animated:YES];
    }
}
@end
