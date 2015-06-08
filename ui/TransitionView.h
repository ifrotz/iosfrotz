//
//  TransitionView.h
//  Frotz
//
//  Created by Craig Smith on 7/30/08.
//  Copyright 2008 Craig Smith. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@class TransitionView;

@protocol TransitionViewDelegate <NSObject>
@optional
- (void)transitionViewDidStart:(TransitionView *)view;
- (void)transitionViewDidFinish:(TransitionView *)view;
- (void)transitionViewDidCancel:(TransitionView *)view;
@end

@interface TransitionView: UIView
{
    BOOL transitioning;
    BOOL wasEnabled;
    id<TransitionViewDelegate> __weak delegate;
}
@property (weak) id<TransitionViewDelegate> delegate;
@property (readonly, getter=isTransitioning) BOOL transitioning;

-(void)replaceSubview:(UIView *)oldView withSubview:(UIView *)newView transition:(NSString *)transition direction:(NSString *)direction duration:(NSTimeInterval)duration;
- (void)cancelTransition;
@end

