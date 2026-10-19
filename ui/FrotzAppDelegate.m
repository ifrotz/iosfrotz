//
//  FrotzAppDelegate.m
//  Frotz
//
//  Created by Craig Smith on 6/17/08.
//  Copyright Craig Smith 2008. All rights reserved.
//

#import "FrotzAppDelegate.h"
#import "StoryBrowser.h"
#import "StoryMainViewController.h"

@implementation FrotzAppDelegate

- (StoryMainViewController *)voiceGestureStoryController {
    StoryMainViewController *story = [theStoryBrowser storyMainViewController];
    return story.viewIfLoaded.window ? story : nil;
}

- (BOOL)accessibilityPerformMagicTap {
    // Navigation-bar controls can bypass the story controller's responder chain.
    return [[self voiceGestureStoryController] accessibilityPerformMagicTap];
}

- (instancetype)init {
	if ((self = [super init])) {
		// 
	} 
	return self;
}

-(void)fadeSplashScreen {
    [m_transitionView replaceSubview: m_splash withSubview:nil transition:kCATransitionFade  direction:kCATransitionFromTop duration:0.25];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOption {
    // Window creation, story browser setup, appearance configuration and launch URL/shortcut
    // handling are per-scene and live in FrotzSceneDelegate.
    return YES;
}

- (void)transitionViewDidFinish:(TransitionView *)view {
    [[[theStoryBrowser view] window] addSubview: [m_navigationController view]];
    [m_splash removeFromSuperview];
    [m_activityView stopAnimating];
    [m_activityView removeFromSuperview];
    [m_transitionView removeFromSuperview];    
}

- (void)applicationWillTerminate:(UIApplication *)application {
    StoryMainViewController *storyMainViewController = [theStoryBrowser storyMainViewController];
    [storyMainViewController suspendStory];
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication*)app {
    NSLog(@"memory warning!");
}

@end
