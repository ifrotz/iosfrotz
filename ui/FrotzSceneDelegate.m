//
//  FrotzSceneDelegate.m
//  Frotz
//
//  Scene lifecycle delegate. Owns the window and the per-scene setup that
//  previously lived in FrotzAppDelegate's application:didFinishLaunchingWithOptions:.
//

#import "FrotzSceneDelegate.h"
#import "StoryBrowser.h"
#import "StoryMainViewController.h"
#import "StatusLine.h"
#import "StoryInputLine.h"
#import "StoryView.h"
#import "StoryDetailsController.h"
#import "FrotzDB.h"

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
    if (@available(iOS 13.4, *)) {
        if ([event isKindOfClass: [UIPressesEvent class]]) {
            StoryMainViewController *smvc = [theStoryBrowser storyMainViewController];
            if ([[smvc view] window]
                && ![[smvc navigationController] presentedViewController]
                && ![[smvc notesController] isVisible]) {
                if (theInputLine.isFirstResponder == NO)
                    [theInputLine becomeFirstResponder];
            }
        }
    }
    [super sendEvent: event];
}
@end

@implementation FrotzSceneDelegate {
    StoryBrowser *m_browser;
}

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass: [UIWindowScene class]])
        return;
    UIWindowScene *windowScene = (UIWindowScene *)scene;

    // The storyboard is instantiated by hand rather than through UISceneStoryboardFile so that
    // the window can be a FrotzWindow, whose sendEvent: override routes touches to the story views.
    FrotzWindow *window = [[FrotzWindow alloc] initWithWindowScene: windowScene];
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName: @"StoryStoryboard" bundle: nil];
    window.rootViewController = [storyboard instantiateInitialViewController];
    self.window = window;

    m_browser = [window.rootViewController.childViewControllers[0] childViewControllers][0];

    if (connectionOptions.shortcutItem)
        [m_browser setPostLaunch];

    UINavigationController* navigationController = [[UINavigationController alloc] initWithRootViewController: [m_browser storyMainViewController]];
    [m_browser storyMainViewController].storyNavController = navigationController;
    //NSLog(@"smbc snc %@ nc %@", [m_browser storyMainViewController].storyNavController, [m_browser storyMainViewController].navigationController);

    if (@available(iOS 13.0, *)) {
        [[UINavigationBar appearance] setTintColor:[UIColor labelColor]];
        [[UIButton appearanceWhenContainedIn: [UITableViewCell class], nil] setTintColor: [UIColor systemIndigoColor]];
    } else {
        [[UINavigationBar appearance] setTintColor:[UIColor darkGrayColor]];
        [[UINavigationBar appearance] setBarTintColor: [UIColor whiteColor]];
        [[UIButton appearanceWhenContainedIn: [UITableViewCell class], nil] setTintColor: [UIColor purpleColor]];
    }

    // This is now done explicitly for buttons in the StoryDetailsController, and in the xib files
    // because of bugs/misfeatures in the iOS 11 SDK.
    // See: http://www.openradar.me/radar?id=5064333964869632
    //[[UIButton appearance] setTintColor: [UIColor whiteColor]];
    //[[UIButton appearance] setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    //[[UIButton appearanceWhenContainedIn: [UINavigationBar class], nil] setTintColor: textColor];
    
    [[UIButton appearanceWhenContainedIn: [StoryDetailsController class], nil] setTitleColor: [UIColor whiteColor] forState:UIControlStateNormal];
    
    [[m_browser storyMainViewController] initializeDropbox];

    [m_browser view];
    m_browser.splitViewController.preferredDisplayMode = UISplitViewControllerDisplayModeAutomatic;

    for (UIOpenURLContext *context in connectionOptions.URLContexts)
        [self handleOpenURL: context.URL];

    [window makeKeyAndVisible];
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
    StoryMainViewController *storyMainViewController = [m_browser storyMainViewController];
    [storyMainViewController autoSaveStory];
}

- (void)sceneWillEnterForeground:(UIScene *)scene {
    StoryMainViewController *storyMainViewController = [m_browser storyMainViewController];
    // Unlike applicationWillEnterForeground:, this is also sent on first launch, before the
    // story view has been loaded; avoid forcing the view to load just to resize it.
    if ([storyMainViewController isViewLoaded])
        [storyMainViewController autosize];
}

- (void)windowScene:(UIWindowScene *)windowScene performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem completionHandler:(void (^)(BOOL))completionHandler {
    if ([[shortcutItem type] isEqualToString: @"storylist"]) {
        [m_browser setPostLaunch];
        [[m_browser navigationController] popToViewController:m_browser animated:YES];
        completionHandler(YES);
    }
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts {
    for (UIOpenURLContext *context in URLContexts)
        [self handleOpenURL: context.URL];
}

- (BOOL)handleOpenURL:(NSURL *)launchURL {
    NSLog(@"openURL %@", launchURL);
#if UseDropBoxSDK
    DBOAuthCompletion completion = ^(DBOAuthResult *authResult) {
        if (authResult != nil) {
            if ([authResult isSuccess]) {
                NSLog(@"Success! User is logged into Dropbox.");
                [[m_browser navigationController] popViewControllerAnimated: YES];
                [[m_browser storyMainViewController] dropboxDidLinkAccount];
            } else if ([authResult isCancel]) {
                NSLog(@"Authorization flow was manually canceled by user!");
            } else if ([authResult isError]) {
                NSLog(@"Error: %@", authResult);
            }
        }
    };
    BOOL canHandle = [DBClientsManager handleRedirectURL:launchURL completion: completion];
    if (canHandle)
        return YES;
#endif
    if (launchURL && [launchURL isFileURL]) {
        NSString *launchPath = [launchURL path];

        [m_browser setLaunchPath: launchPath];
        if ((launchPath = [m_browser launchPath])) { // nil if file couldn't be accessed
            [m_browser addRecentStory: launchPath];
            StoryInfo *si = [[StoryInfo alloc] initWithPath: launchPath browser:m_browser];
            [m_browser setStoryDetails: si];
            [m_browser performSelector:@selector(launchStory:) withObject:launchPath afterDelay:0.05];
        }
    } else {
        NSLog(@"Frotz launched w/unknown URL: %@", launchURL);
        UIAlertView *alert = [[UIAlertView alloc]  initWithTitle:@"Frotz cannot handle URL"
                message: [NSString stringWithFormat:@"%@", launchURL]
                delegate:self cancelButtonTitle:@"OK" otherButtonTitles: nil];
        [alert show];
    }

    return NO;
}

@end
