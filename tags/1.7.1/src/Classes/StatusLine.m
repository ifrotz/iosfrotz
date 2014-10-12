//
//  StatusLine.m
//  Frotz
//
//  Created by Craig Smith on 2/9/10.
//  Copyright 2010 Craig Smith. All rights reserved.
//

#import "StatusLine.h"
#include "iphone_frotz.h"

@implementation StatusLine

- (BOOL)handleTouch: (UITouch*)touch withEvent: (UIEvent*)event {
    StoryMainViewController *delegate = (StoryMainViewController*)[self delegate];
    
    [delegate hideInputHelper];
    if (m_tapTimer) {
        [[m_tapTimer userInfo] release];
        [m_tapTimer invalidate];
        [m_tapTimer release];
        m_tapTimer = nil;
    }
    UITouchPhase phase = [touch phase];
    CGPoint superPt = [touch locationInView: [[self superview] superview]];
    if (phase == UITouchPhaseEnded && [touch tapCount]==1) {
        if (m_magnified) {
            SavedTouch *st =[[SavedTouch alloc] initWithPhase:phase point:superPt];
            m_tapTimer = [[NSTimer alloc] initWithFireDate: [NSDate dateWithTimeIntervalSinceNow: 0.1] interval:0.0
                                                    target:self selector:@selector(timerFireMethod:) userInfo:st repeats:NO];
            [[NSRunLoop currentRunLoop] addTimer: m_tapTimer forMode: NSDefaultRunLoopMode];
        } else {
            if (![delegate isKBShown])
                [delegate activateKeyboard];
        }
        return YES;
    }
    if ([touch tapCount] <= 1)
        return [self handleMagnifyTouchWithPhase: phase atPoint:superPt];
    return UseFullSizeStatusLineFont ? YES : NO;
}

- (void)timerFireMethod:(NSTimer*)theTimer {
    SavedTouch *savedTouch = (SavedTouch*)[theTimer userInfo];
    CGPoint pt = savedTouch.pt;
    UITouchPhase phase = savedTouch.phase;
	
    [self handleMagnifyTouchWithPhase: phase atPoint:pt];
    [savedTouch release];
    if (m_tapTimer) {
        [m_tapTimer invalidate];
        [m_tapTimer release];
        m_tapTimer = nil;
    }
}

- (void) touchesEnded:(NSSet*)touches withEvent:(UIEvent*)event
{
    [[self superview] setTransform: CGAffineTransformIdentity];
}

- (void) touchesCancelled:(NSSet*)touches withEvent:(UIEvent*)event
{
    [[self superview] setTransform: CGAffineTransformIdentity];
}
@end

