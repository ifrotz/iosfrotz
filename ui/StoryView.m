
#import <UIKit/UIKit.h>
#include <sys/time.h>

#import "StoryView.h"
#import "FrotzAppDelegate.h"
#import "FileBrowser.h"
#import "ui_utils.h"
#include <execinfo.h>

#include <stdlib.h>
@implementation StoryView

@synthesize tapInputEnabled = m_tapInputEnabled;

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
    NSUInteger tapCount = [touch tapCount];
    CGPoint pt = [touch locationInView: [self superview]];
    
    if (m_tapTimer) {
        [m_tapTimer userInfo];
        [m_tapTimer invalidate];
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
        if (m_tapInputEnabled && tapCount==1) {
            if ([delegate tapInView: self atPoint: [touch locationInView:self]])
                return YES;
        }
        
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
                   // Use self.layer.removeAllAnimations instead ???
                    removeAnim(self);
                    [self clearSelection];
                    //[[delegate inputLine] setText: @""];
#endif
                    [delegate setIgnoreWordSelection:YES];
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
            else if (tapCount == 3) {
                removeAnim(self);
                [self clearSelection];
                [delegate setIgnoreWordSelection:YES];
                [delegate forceToggleKeyboard];
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
    NotesViewController* notesController = [delegate notesController];
    if ([[delegate navigationController] presentedViewController] || // settings active
        notesController && [notesController isVisible])
        ;
    else if (!gLargeScreenDevice && pt.y < magnifyYThreshold) {
        m_isMagnifying = YES;
    	if ([self handleMagnifyTouchWithPhase: phase atPoint: pt])
            m_isMagnifying = NO;
    } else {
        if (![delegate scrollStoryViewOnePage:self fraction:1.0]) {
            if (!m_skipNextTap && ![delegate splashVisible]) {
                if ((ipzAllowInput & kIPZNoEcho) || cwin == 1) { // single key input
                    iosif_feed_input(@" "); // press 'space'
                } else if (![delegate isKBShown]) {
                    [delegate activateKeyboard];
                }
            }
        }
    }
    if (m_tapTimer) {
        [m_tapTimer invalidate];
        m_tapTimer = nil;
    }
    m_skipNextTap = NO;
}

- (NSString*)lookForTruncatedWord:(NSString*)word {
    for (NSString *text in m_textRuns) {
        NSUInteger len = [text length];
        NSRange r = [text rangeOfString:word options:NSCaseInsensitiveSearch];
        if (r.length) {
            NSUInteger index = r.location;
            if (index > 0 && isalnum([text characterAtIndex:index-1]))
                continue;
            index += r.length;
            while (index < len) {
                unichar c = [text characterAtIndex: index];
                if (!isalnum(c) && c!='\'')
                    break;
                ++index;
            }
            return [text substringWithRange:NSMakeRange(r.location, index - r.location)];
        }
    }

    return nil;
    
}


-(void)setFrame:(CGRect)frame {

    //NSLog(@"sv setFrame: (%f,%f,%f,%f)", frame.origin.x, frame.origin.y, frame.size.width, frame.size.height);
#if 0
    void* callstack[128];
    char outbuf[16384];
    *outbuf = 0;
    int i, frames = backtrace(callstack, 128);
    char** strs = backtrace_symbols(callstack, frames);
    for (i = 0; i < frames; ++i) {
        sprintf(outbuf,"%s%s\n", outbuf,strs[i]);
    }
    NSLog(@"%s", outbuf);
    free(strs);
#endif
    [super setFrame: frame];
}


@end // StoryView
