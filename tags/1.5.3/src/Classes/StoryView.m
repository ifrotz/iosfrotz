
#import <UIKit/UIKit.h>
#include <sys/time.h>

#import "StoryView.h"
#import "FrotzAppDelegate.h"
#import "FileBrowser.h"
#import "ui_utils.h"

#include <stdlib.h>
@implementation StoryView

- (void)appendText:(NSString*)text
{
#if UseRichTextView
    [super appendText: text];
#endif
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    BOOL retValue = NO;
  
    if (action == @selector(paste:) || action == @selector(cut:))
        retValue = NO;
    else if (action == @selector(copy:) || action == @selector(select:) || action == @selector(selectAll:))
        retValue = NO;
    else
        retValue = [super canPerformAction:action withSender:sender];
    return retValue;
}

- (BOOL)handleTouch: (UITouch*)touch withEvent: (UIEvent*)event {
    static NSTimeInterval lastTimestamp;
    int tapCount = [touch tapCount];
    CGPoint pt = [touch locationInView: [self superview]];

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

    if (!gLargeScreenDevice) {
	int magnifyYThreshold = 50;
	if  ([delegate isLandscape])
	    magnifyYThreshold = 20;
	    
	if (m_isMagnifying || (pt.y < magnifyYThreshold && phase == UITouchPhaseBegan && tapCount==1)) {
	    CGPoint superPt = [touch locationInView: [[self superview] superview]];
	    if (!m_isMagnifying) {
		SavedTouch *st = [[SavedTouch alloc] initWithPhase:phase point:superPt];
		m_tapTimer = [[NSTimer alloc] initWithFireDate: [NSDate dateWithTimeIntervalSinceNow: 0.1] interval:0.0 
		    target:self selector:@selector(timerFireMethod:) userInfo:st repeats:NO];
		[[NSRunLoop currentRunLoop] addTimer: m_tapTimer forMode: NSDefaultRunLoopMode];	
		return YES;
	    }
	    m_isMagnifying = YES;
	    if (![self handleMagnifyTouchWithPhase: phase atPoint:superPt])
		return NO;
	}
    }
    m_isMagnifying = NO;
    if (phase == UITouchPhaseBegan) {
	return YES;
    } else if (phase == UITouchPhaseMoved) {
	return YES;
    } else if (phase != UITouchPhaseEnded)
	return YES;
    
    [[self superview] setTransform: CGAffineTransformIdentity];
    if (tapCount<=1 && [self isDecelerating])
	return YES;

    [delegate focusGlkView:self];

    if ([[delegate currentStory] length] == 0) {
	if (tapCount >= 2)
	    [delegate abortToBrowser];
    } else if (tapCount >= 1) {

	if ([delegate isKBShown]) {
	    [self setSelectionDisabled: NO];
	    if (tapCount == 1)  {
		SavedTouch *st = [[SavedTouch alloc] initWithPhase:phase point:pt] ;
		m_tapTimer = [[NSTimer alloc] initWithFireDate: [NSDate dateWithTimeIntervalSinceNow: 0.1] interval:0.0
		    target:self selector:@selector(timerFireMethod:) userInfo:st repeats:NO];
		[[NSRunLoop currentRunLoop] addTimer: m_tapTimer forMode: NSDefaultRunLoopMode];
	    }
	    else if (tapCount == 3) {
		if ([touch timestamp] > lastTimestamp + 0.5) {
#if UseRichTextView
		    removeAnim(self);
		    [self clearSelection];
		    [[delegate inputLine] setText: @""];
#endif
		    [delegate dismissKeyboard];
		}
	    }
	    m_skipNextTap = NO;
	}
	else {
//	    [self setSelectionDisabled: YES]; // commented out to support hardware keyboard
	    if (tapCount == 1) {
		SavedTouch *st = [[SavedTouch alloc] initWithPhase:phase point:pt] ;
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
    }
    return YES;
}

- (void)skipNextTap {
    m_skipNextTap = YES;
}

- (void)timerFireMethod:(NSTimer*)theTimer {
    SavedTouch *savedTouch = (SavedTouch*)[theTimer userInfo];

    StoryMainViewController *delegate = (StoryMainViewController*)[self delegate];

    CGPoint pt = savedTouch.pt;
    UITouchPhase phase = savedTouch.phase;
    int magnifyYThreshold = 50;
    if  ([delegate isLandscape])
	magnifyYThreshold = 20;
    [savedTouch release];
    NotesViewController* notesController = [delegate notesController];

    if (notesController && [notesController isVisible])
	;
    else if (!gLargeScreenDevice && pt.y < magnifyYThreshold) {
	m_isMagnifying = YES;
    	if ([self handleMagnifyTouchWithPhase: phase atPoint: pt])
	    m_isMagnifying = NO;
    } else {
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
    
    
@end // StoryView
