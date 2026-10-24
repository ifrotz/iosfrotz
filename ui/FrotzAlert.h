//
//  FrotzAlert.h
//  Frotz
//
//  UIAlertController wrapper with UIAlertView-style button numbering, for the
//  scene-based lifecycle where UIAlertView is unavailable.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// buttonIndex follows UIAlertView's convention: 0 is the cancel button, the other buttons are
// numbered from 1 in the order given in otherTitles.
typedef void (^FrotzAlertHandler)(NSInteger buttonIndex);

// Builds and presents an alert from the topmost view controller above `presenter`. If the presenter
// is not in a window yet (e.g. during launch) presentation is retried for a few seconds. Safe to call
// from any thread; off the main thread the alert is presented asynchronously and nil is returned.
UIAlertController *_Nullable FrotzShowAlert(UIViewController *_Nullable presenter,
                                            NSString *_Nullable title,
                                            NSString *_Nullable message,
                                            NSString *_Nullable cancelTitle,
                                            NSArray<NSString *> *_Nullable otherTitles,
                                            FrotzAlertHandler _Nullable handler);

NS_ASSUME_NONNULL_END
