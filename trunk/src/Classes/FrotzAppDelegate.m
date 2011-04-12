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
#import "StatusLine.h"
#import "StoryInputLine.h"
#import "StoryView.h"

#import "DBSession.h"

@interface FrotzWindow : UIWindow
{
}
- (void)sendEvent:(UIEvent *)event;                    // called by UIApplication to dispatch events to views inside the window
@end

@implementation FrotzWindow
- (void)sendEvent:(UIEvent *)event {
    static UIView *prevView;
    for (UITouch *touch in [event allTouches]) {
	UIView *view = [touch view];
	UITouchPhase phase = [touch phase];

	if (!view && phase != UITouchPhaseBegan)
	    view = prevView; // for some reason sometomes view is nil and we lose the phase ended event!
	if ([touch tapCount]>=1 || phase == UITouchPhaseEnded) {
	    if ([view isDescendantOfView: theInputLine]) {
		prevView = view;
		if (![theInputLine handleTouch: touch withEvent: event])
		    return;
	    } else if ([view isDescendantOfView: theStoryView]) {
		prevView = view;
		if (![theStoryView handleTouch: touch withEvent: event])
		    return;
	    } else if ([view isDescendantOfView: theStatusLine]) {
		prevView = view;
		if (![theStatusLine handleTouch: touch withEvent: event])
		    return;
	    }
	}
    }
    [super sendEvent: event];
}
@end

@implementation FrotzAppDelegate

- (id)init {
	if ((self = [super init])) {
		// 
	} 
	return self;
}

-(void)fadeSplashScreen {
    [m_transitionView replaceSubview: m_splash withSubview:nil transition:kCATransitionFade  direction:kCATransitionFromTop duration:0.25];
}

bool gLargeScreenDevice;
bool gUseSplitVC;

//CGImageRef UIGetScreenImage(void);

//- (void)applicationDidFinishLaunching:(UIApplication *)application
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOption {
    // Configure and show the window
    CGRect rect = [[UIScreen mainScreen] bounds];

    gLargeScreenDevice = ((UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad) || (rect.size.width > 480));
    gUseSplitVC = gLargeScreenDevice;
    //Create a full-screen window
    m_window = [[FrotzWindow alloc] initWithFrame:rect];

    rect = [[UIScreen mainScreen] applicationFrame];
    BOOL useSplashTransition = NO;

    if (useSplashTransition && !gLargeScreenDevice) { // Fade splash screen gradually to story browser, but not on iPad; see comment below
	m_transitionView = [[TransitionView alloc] initWithFrame: rect];
	m_transitionView.backgroundColor = [UIColor clearColor];
#if 1
	UIImage *splashImage = [UIImage imageNamed: @"Default"];
	if (!splashImage)
	    splashImage = [UIImage imageNamed: @"Default.png"];
	m_splash = [[UIImageView alloc] initWithImage: splashImage];	
#else // Device orientation isn't yet correctly set when launched in landscape; this doesn't work, so we don't even try on iPad
	if (!gLargeScreenDevice)
	    m_splash = [[UIImageView alloc] initWithImage: [UIImage imageNamed: @"Default.png"]];
	else if (UIDeviceOrientationIsLandscape([[UIDevice currentDevice] orientation]))
	    m_splash = [[UIImageView alloc] initWithImage: [UIImage imageNamed: @"Default-Landscpe.png"]];
	else
	    m_splash = [[UIImageView alloc] initWithImage: [UIImage imageNamed: @"Default-Portrait.png"]];
#endif
	[m_transitionView setDelegate: self];
	[m_transitionView addSubview: m_splash];
	[m_transitionView bringSubviewToFront: m_splash];
      
	m_activityView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];

	[m_activityView setFrame: CGRectMake(rect.size.width/2-10, rect.size.height - 80, 20, 20)];
	[m_transitionView addSubview: m_activityView];
	[m_transitionView bringSubviewToFront: m_activityView];
	[m_activityView startAnimating];
    }

    NSURL *launchURL = nil;

    m_browser = [[StoryBrowser alloc] init];
    if (launchOption) {
	NSURL *url = [launchOption objectForKey:UIApplicationLaunchOptionsURLKey];
	if (url) 
	    launchURL = url;
    }

    Class SplitVCClass = NSClassFromString(@"UISplitViewController");
    if (!SplitVCClass)
	gUseSplitVC = NO;

    if (gUseSplitVC) {
	UISplitViewController* splitVC = [[SplitVCClass alloc] init];

	m_navigationController = [[UINavigationController alloc] initWithRootViewController: m_browser];
	[m_navigationController.navigationBar setBarStyle: UIBarStyleBlackOpaque];   

	UINavigationController* navigationController = [[UINavigationController alloc] initWithRootViewController: [m_browser storyMainViewController]];
	[navigationController.navigationBar setBarStyle: UIBarStyleBlackOpaque];   

	splitVC.viewControllers = [NSArray arrayWithObjects: m_navigationController, [[m_browser detailsController] navigationController], nil];
	[splitVC setDelegate: m_browser];

	[m_window addSubview: splitVC.view];
    } else {
	m_navigationController = [[UINavigationController alloc] initWithRootViewController: m_browser];
	[m_navigationController.navigationBar setBarStyle: UIBarStyleBlackOpaque];
	[m_window addSubview:[m_navigationController view]];
	if (m_transitionView) {
	    [m_window addSubview: m_transitionView];
	    [m_window bringSubviewToFront: m_transitionView];
	}
    }

    [[m_browser storyMainViewController] initializeDropbox];

    [m_window makeKeyAndVisible];
    [self performSelector: @selector(fadeSplashScreen) withObject: nil afterDelay: 0.01];

    if (launchURL)
	[self application:application handleOpenURL: launchURL];
    return YES;
}

- (void)transitionViewDidFinish:(TransitionView *)view {
    [m_window addSubview: [m_navigationController view]];
    [m_splash removeFromSuperview];
    [m_splash release];
    [m_activityView stopAnimating];
    [m_activityView removeFromSuperview];
    [m_activityView release];
    [m_transitionView removeFromSuperview];    
    [m_transitionView release];
}

- (void)applicationWillTerminate:(UIApplication *)application {
    StoryMainViewController *storyMainViewController = [m_browser storyMainViewController];
    [storyMainViewController suspendStory];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    StoryMainViewController *storyMainViewController = [m_browser storyMainViewController];
    [storyMainViewController autoSaveStory];
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication*)app {
    NSLog(@"memory warning!");
}

- (BOOL)application: (UIApplication*)application handleOpenURL: (NSURL*)launchURL {
    NSLog(@"handleOpenURL %@", launchURL);
    if (launchURL && [launchURL isFileURL]) {
	NSString *launchPath = [launchURL path];

	[m_browser setLaunchPath: launchPath];
	if ((launchPath = [m_browser launchPath])) { // nil if file couldn't be accessed
	    [m_browser addRecentStory: launchPath];
	    [m_browser launchStory: launchPath];
	}
    } else {
	NSLog(@"Frotz launched w/unknown URL: %@", launchURL);
	UIAlertView *alert = [[UIAlertView alloc]  initWithTitle:@"Frotz cannot handle URL"
			message: [NSString stringWithFormat:@"%@", launchURL]
			delegate:self cancelButtonTitle:@"OK" otherButtonTitles: nil];
	[alert show];
	[alert release];
    }

    return NO;
}

- (void)dealloc {
    [m_browser release];
    [m_navigationController release];
    [m_window release];
    [super dealloc];
}

@end
