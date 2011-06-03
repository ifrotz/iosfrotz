
#import <UIKit/UIKit.h>
#include <sys/time.h>

#import "GlkView.h"
#import "FrotzAppDelegate.h"
#import "FileBrowser.h"
#import "ui_utils.h"

#include <stdlib.h>
@implementation GlkView

@synthesize tapInputEnabled;

-(void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    [self handleTouch:touch withEvent:event];
}
-(void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    [self handleTouch:touch withEvent:event];
}
-(void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    [self handleTouch:touch withEvent:event];
}
-(void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    [self handleTouch:touch withEvent:event];
}

- (BOOL)handleTouch: (UITouch*)touch withEvent: (UIEvent*)event {
    static NSTimeInterval lastTimestamp;
    int tapCount = [touch tapCount];
    //    CGPoint pt = [touch locationInView: [self superview]];
    
    if (m_tapTimer) {
        [[m_tapTimer userInfo] release];
        [m_tapTimer invalidate];
        [m_tapTimer release];
        m_tapTimer = nil;
    }
    
    StoryMainViewController *delegate = (StoryMainViewController*)[self delegate];
    UITouchPhase phase = [touch phase];
    if ([ delegate inputHelperShown] && ![[touch view] isDescendantOfView: [delegate inputHelperView]])
        [delegate hideInputHelper];
    
    CGPoint superPt = [touch locationInView: [[self superview] superview]];
    
    if (tapCount==1 && [self isDecelerating])
        return YES;
    
    if (phase == UITouchPhaseBegan || phase == UITouchPhaseMoved || phase == UITouchPhaseCancelled) {
        if ([touch tapCount] <= 1) {
            if (self.autoresizingMask != 0) // only graphics windows have no resizing mask
                return [self handleMagnifyTouchWithPhase: phase atPoint:superPt];
        }
        return YES;
    } else if (phase != UITouchPhaseEnded)
        return YES;
    
    if (!m_magnified)
        [delegate focusGlkView:self];
    
    if ([[delegate currentStory] length] == 0) {
        if (tapCount >= 2)
            [delegate abortToBrowser];
    } else if (tapCount >= 1) {
        if (tapInputEnabled && tapCount==1) {
            [delegate tapInView: self atPoint: [touch locationInView:self]];
            return YES;
        }
        if ([delegate isKBShown]) {
            [self setSelectionDisabled: NO];
            if (tapCount == 1)  {
                SavedTouch *st = [[SavedTouch alloc] initWithPhase:phase point:superPt];
                m_tapTimer = [[NSTimer alloc] initWithFireDate: [NSDate dateWithTimeIntervalSinceNow: 0.1] interval:0.0
                                                        target:self selector:@selector(timerFireMethod:) userInfo:st repeats:NO];
                [[NSRunLoop currentRunLoop] addTimer: m_tapTimer forMode: NSDefaultRunLoopMode];
            }
            else if (tapCount == 3) {
                if ([touch timestamp] > lastTimestamp + 0.5) {
#if UseRichTextView
                    removeAnim(self);
                    //		    [[UIAnimator sharedAnimator] removeAnimationsForTarget:self];
                    [self clearSelection];
                    [[delegate inputLine] setText: @""];
#endif
                    [delegate dismissKeyboard];
                }
            }
            m_skipNextTap = NO;
        }
        else {
            if (tapCount == 1) {
                SavedTouch *st = [[SavedTouch alloc] initWithPhase:phase point:superPt];
                m_tapTimer = [[NSTimer alloc] initWithFireDate: [NSDate dateWithTimeIntervalSinceNow: 0.1] interval:0.0
                                                        target:self selector:@selector(timerFireMethod:) userInfo:st repeats:NO];
                [[NSRunLoop currentRunLoop] addTimer: m_tapTimer forMode: NSDefaultRunLoopMode];
                lastTimestamp = [touch timestamp];
            } else if (tapCount == 2) {
                [delegate activateKeyboard];
                lastTimestamp = [touch timestamp];
                m_skipNextTap = NO;
            }
        }
    } else
        return [self handleMagnifyTouchWithPhase: phase atPoint:superPt];
    
    return YES;
}

- (void)skipNextTap {
    m_skipNextTap = YES;
}

-(void)setContentSize:(CGSize)size {
    [super setContentSize: size];
}

- (void)timerFireMethod:(NSTimer*)theTimer {
    SavedTouch *savedTouch = (SavedTouch*)[theTimer userInfo];
    
    StoryMainViewController *delegate = (StoryMainViewController*)[self delegate];
    
    CGPoint pt = savedTouch.pt;
    UITouchPhase phase = savedTouch.phase;
    
    BOOL r = [self handleMagnifyTouchWithPhase: phase atPoint:pt];
    [savedTouch release];
    if (r) {
        
        NotesViewController* notesController = [delegate notesController];
        
        if (notesController && [notesController isVisible])
            ;
        else {
            if (![delegate scrollStoryViewOnePage:self fraction:1.0]) {
                if (!m_skipNextTap && ![delegate splashVisible]) {
                    if ((ipzAllowInput & kIPZNoEcho) || cwin == 1) { // single key input
                        iphone_feed_input(@" "); // press 'space'
                    } else if (![delegate isKBShown]) {
                        [delegate activateKeyboard];
                    }
                }
            }
        }
    }
    
    if (m_tapTimer) {
        [m_tapTimer invalidate];
        [m_tapTimer release];
        m_tapTimer = nil;
    }
    m_skipNextTap = NO;
}

-(void)setFrame:(CGRect)frame {
    //    NSLog(@"sv setFrame: (%f,%f,%f,%f)", frame.origin.x, frame.origin.y, frame.size.width, frame.size.height);
    [super setFrame: frame];
}

@end // GlkView
