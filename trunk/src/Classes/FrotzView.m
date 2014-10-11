//
//  FrotzView.m
//  Frotz
//
//  Created by Craig Smith on 2/9/10.
//  Copyright 2010 Craig Smith. All rights reserved.
//

#import "FrotzView.h"
#include "iphone_frotz.h"

@implementation SavedTouch
@synthesize phase;
@synthesize pt;
-(id)initWithPhase:(UITouchPhase)aPhase point:(CGPoint)aPt {
    if ((self = [super init])) {
	phase = aPhase;
	pt = aPt;
    }
    return self;
}
@end

@implementation FrotzView

- (RichTextView*)initWithFrame: (CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        NSString *osVersStr = [[UIDevice currentDevice] systemVersion];
        if (osVersStr && ([osVersStr characterAtIndex: 0] >= '4' || [osVersStr characterAtIndex: 0] == '1')) { // 1x
            UIPinchGestureRecognizer *pinch = [[[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(storyViewPinch:)] autorelease];
            [self addGestureRecognizer:pinch];
            
            UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(storyViewTwoFingerTap:)]
                                               autorelease];
            tap.numberOfTouchesRequired = 2;
            [self addGestureRecognizer:tap];
        }
    }
    return self;
}

-(void)storyViewTwoFingerTap:(UITapGestureRecognizer *) recognizer {
    if ((ipzAllowInput & kIPZNoEcho))
        iphone_feed_input(@"\x1b"); // press ESC
}

-(void)storyViewPinch:(UIPinchGestureRecognizer *) recognizer {
    if (self.autoresizingMask == 0)
        return;
    if (recognizer.state==UIGestureRecognizerStateBegan)
        m_origFontSize = m_fontSize;
    else if (recognizer.state==UIGestureRecognizerStateChanged || recognizer.state==UIGestureRecognizerStateEnded) {
        CGFloat scale = recognizer.scale;
        
        CGFloat newFontSize = m_origFontSize * scale;
        if (newFontSize < 8)
            newFontSize = 8;
        else if (newFontSize > 32)
            newFontSize = 32;
        if ((int)(m_fontSize) != (int)(newFontSize) || recognizer.state==UIGestureRecognizerStateEnded) {
            CGFloat duration = 0.12;
            CATransition *animation = [CATransition animation];
            [animation setType:kCATransitionFade];
            [animation setDuration: duration];
            [animation setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
            [[self.superview.superview layer] addAnimation:animation forKey:@"storyviewpinch"];
            
            StoryMainViewController *delegate = (StoryMainViewController*)[self delegate];
            [delegate setFont: nil withSize: (int)newFontSize];
            [self repositionAfterReflow];
            [delegate resizeStatusWindow];
        }
    }
}


-(BOOL)canBecomeFirstResponder { return NO; }

-(BOOL)handleMagnifyTouchWithPhase:(UITouchPhase)phase atPoint:(CGPoint) pt {
    UIView *view = [self superview];
    const float scale = 1.8;
    CGRect bounds = [view bounds];
    CGFloat width = bounds.size.width/2.0;
    CGFloat height = bounds.size.height/2.0;
    NSString *osVersStr = [[UIDevice currentDevice] systemVersion];
    if (osVersStr && [osVersStr characterAtIndex: 0] == '3' && [osVersStr characterAtIndex: 2] < '2')
        ;
    else if (UseFullSizeStatusLineFont || gLargeScreenDevice)
        return YES;
    CGFloat magThresY = height*2;
    if (magThresY > 140)
	magThresY = 140;
    if (phase == UITouchPhaseBegan || phase == UITouchPhaseMoved /*|| phase == UITouchPhaseStationary*/) {
	if (m_magnified || pt.y <= magThresY) {
	    const CGFloat maxGravity = 4.0, minGravity = 1.5;
	    CGFloat xBorderGravity = maxGravity; // (pt.y < 40) ? maxGravity : (pt.y > 100) ? minGravity : maxGravity - (maxGravity-minGravity) * (pt.y - 40)/60;
	    CGFloat x = (width-pt.x) * xBorderGravity;
	    CGFloat y = (height-pt.y) * minGravity;
	    if (x > width)
		x = width;
	    else if (x < -width)
		x = -width;
	    if (y > height)
		y = height;
	    else if (y < -height)
		y = -height;
	    CGAffineTransform scaled = CGAffineTransformTranslate(CGAffineTransformScale(CGAffineTransformMakeTranslation(0.0, 0.0),
		scale, scale), x*(scale-1.0)/scale, /*was height*/ y *(scale-1.0)/scale);
	    if (phase == UITouchPhaseBegan) {
	    
            UIImageView *img = [[UIImageView alloc] initWithImage:
                                [UIImage imageNamed:
                                 view.superview.frame.size.width >= 568 ? @"glarels5.png" :
                                 view.superview.frame.size.width > 320 ? @"glarels.png" : @"glare.png"]];
            if (img) {
                [img setTag: 1];
                [img setAlpha: 0.50];
                [view setAlpha: 1.0];
                [[view superview] addSubview: img];
                [img release];
            }
	    }
	    [view setTransform: scaled];

	    if ([self.superview respondsToSelector: @selector(setCanCancelContentTouches:)])
		[(UIScrollView*)self.superview setCanCancelContentTouches: NO];
	    
	    m_magnified = YES;
	    return NO;
	}
    } else if (phase == UITouchPhaseStationary)
	return NO;
    UIView *img = [[view superview] viewWithTag: 1];
    m_magnified = NO;

    if ([self.superview respondsToSelector: @selector(setCanCancelContentTouches:)])
	[(UIScrollView*)self.superview setCanCancelContentTouches: YES];

    if (img)
	[img removeFromSuperview];
	
    [view setAlpha: 1.0];
    [view setTransform: CGAffineTransformIdentity];
    return YES;
}


@end

