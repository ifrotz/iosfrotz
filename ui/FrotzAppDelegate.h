//
//  FrotzAppDelegate.h
//  Frotz
//
//  Created by Craig Smith on 6/17/08.
//  Copyright Craig Smith 2008. All rights reserved.
//

#import <UIKit/UIKit.h>
#include "iosfrotz.h"
#import "StoryBrowser.h"
#import "TransitionView.h"

@interface FrotzAppDelegate : NSObject <UIApplicationDelegate, TransitionViewDelegate> {
	
	UIWindow *m_window;
	UINavigationController *m_navigationController;
	StoryBrowser *m_browser;
	TransitionView *m_transitionView;
	UIActivityIndicatorView *m_activityView;
	UIView *m_splash;
}
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOption;
-(void)fadeSplashScreen;
@end

