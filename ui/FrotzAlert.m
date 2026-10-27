//
//  FrotzAlert.m
//  Frotz
//
//  UIAlertController wrapper with UIAlertView-style button numbering, for the
//  scene-based lifecycle where UIAlertView is unavailable.
//

#import "FrotzAlert.h"

static const NSTimeInterval kFrotzAlertRetryInterval = 0.1;
static const int kFrotzAlertMaxRetries = 50; // ~5 seconds

static void FrotzPresentAlert(UIViewController *presenter, UIAlertController *alert, int retriesLeft) {
    // A presenter that is pushed under another controller (e.g. Settings while the File Transfer
    // screen is showing) has no view in the window; its navigation controller does. Present from
    // the nearest ancestor that is on screen so the alert lands above whatever is visible.
    UIViewController *vc = presenter;
    while (vc && !vc.viewIfLoaded.window)
        vc = vc.parentViewController;
    if (!vc) {
        // Not on screen yet (e.g. the story browser during launch, or a URL handled before the
        // window is key). UIAlertView used its own window so this never mattered; wait for one.
        if (retriesLeft > 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kFrotzAlertRetryInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                FrotzPresentAlert(presenter, alert, retriesLeft - 1);
            });
        } else {
            NSLog(@"FrotzShowAlert: no window to present '%@' from", alert.title);
        }
        return;
    }
    while (vc.presentedViewController && ![vc.presentedViewController isBeingDismissed])
        vc = vc.presentedViewController;
    [vc presentViewController:alert animated:YES completion:nil];
}

UIAlertController *FrotzShowAlert(UIViewController *presenter, NSString *title, NSString *message,
                                  NSString *cancelTitle, NSArray<NSString *> *otherTitles, FrotzAlertHandler handler) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            FrotzShowAlert(presenter, title, message, cancelTitle, otherTitles, handler);
        });
        return nil;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    if (cancelTitle) {
        [alert addAction:[UIAlertAction actionWithTitle:cancelTitle style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            if (handler)
                handler(0);
        }]];
    }
    NSInteger nextIndex = 1;
    for (NSString *otherTitle in otherTitles) {
        NSInteger buttonIndex = nextIndex++;
        [alert addAction:[UIAlertAction actionWithTitle:otherTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            if (handler)
                handler(buttonIndex);
        }]];
    }
    if (!presenter) {
        NSLog(@"FrotzShowAlert: no presenter for '%@'", title);
        return alert;
    }
    FrotzPresentAlert(presenter, alert, kFrotzAlertMaxRetries);
    return alert;
}
