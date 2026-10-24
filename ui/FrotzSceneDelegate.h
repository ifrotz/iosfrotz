//
//  FrotzSceneDelegate.h
//  Frotz
//
//  Scene lifecycle delegate. Owns the window and the per-scene setup that
//  previously lived in FrotzAppDelegate.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface FrotzSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nullable, nonatomic, strong) UIWindow *window;
@end

NS_ASSUME_NONNULL_END
