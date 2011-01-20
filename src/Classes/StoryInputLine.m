//
//  StoryInputLine.m
//  Frotz
//
//  Created by Craig Smith on 2/9/10.
//  Copyright 2010 Craig Smith. All rights reserved.
//

#import "StoryInputLine.h"
#import "StoryView.h"
#import "StatusLine.h"

#include "iphone_frotz.h"

@implementation StoryInputLine

-(StoryInputLine*)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame: frame]) {
	m_inputHelper = [[FrotzInputHelper alloc] init];
	[m_inputHelper setDelegate: self];

//	UIImageView *img = [[UIImageView alloc] initWithImage: [UIImage imageNamed: @"hsv-crosshair.png"]];
//	[self setLeftView: img];
//	[self setBorderStyle: UITextBorderStyleNone];
//	[self setLeftViewMode: UITextFieldViewModeAlways];
//	[self setBackgroundColor: [UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:0.05]];
//	[self setOpaque: NO];
//	[img release];
    }
    return self;
}

- (CGRect)leftViewRectForBounds:(CGRect)bounds {
    CGRect rect = [super leftViewRectForBounds: bounds];
//    rect.size.width /= 2.0;
    return rect;
}

-(void)dealloc {
    if (m_inputHelper)
	[m_inputHelper release];
    if (m_completionLabel)
	[m_completionLabel release];
    m_completionLabel = nil;
    m_inputHelper = nil;
    [super dealloc];
}

-(UIView*) inputHelperView {
    return [m_inputHelper helperView];
}

-(void)hideInputHelper {
    if (m_completionLabel) {
	[m_completionLabel removeFromSuperview];
    }
    [m_inputHelper hideInputHelper];
}

-(BOOL)becomeFirstResponder {
    if (![self isFirstResponder])
	[m_inputHelper hideInputHelper];
    return [super becomeFirstResponder];
}

-(void)inputHelperString:(NSString*)string {
    [self hideInputHelper];
    [self setText: [self.text stringByAppendingString: string]];
}

-(void)launchInputHelper:(id)unused {
    UIView *parentView = [m_storyView superview];
    CGFloat ypos = [self convertPoint: CGPointZero toView: parentView].y;
    CGPoint ihpt = !gLargeScreenDevice && [(StoryMainViewController*)[m_storyView delegate] isLandscape]
		    ? CGPointMake(132, 142) : CGPointMake(2, ypos-8);
    if (ihpt.y < 140) ihpt.y = 140;

    if (m_completionLabel)
	[m_completionLabel removeFromSuperview];
    [m_inputHelper showInputHelperInView:parentView atPoint: ihpt withMode: FrotzInputHelperModeWords];
}

- (BOOL)handleTouch: (UITouch*)touch withEvent: (UIEvent*)event {
    UITouchPhase phase = [touch phase];
    int tapCount = [touch tapCount];
    FrotzInputHelperMode mode = [m_inputHelper mode];
//    NSLog(@"touch phase %d tapc %d mode %d\n", phase, tapCount, mode);
    if (phase == UITouchPhaseCancelled) {
	if (m_inputHelper)
	    [self hideInputHelper];
        m_lastTouchPhaseSeen = phase;
	return YES;
    }
    
    // long tap on history for single word??
    StoryMainViewController *storyController = (StoryMainViewController*)self.delegate;
    UIView *parentView = [m_storyView superview];
    BOOL isInputHelperTouch =  [touch locationInView:parentView].x < 280;
    if (![storyController isKBShown] || (ipzAllowInput & kIPZNoEcho) || cwin == 1)
	isInputHelperTouch = NO;

    CGPoint currentTouchPosition = [touch locationInView:self];
    CGFloat ypos = [self convertPoint: CGPointZero toView: parentView].y;
    CGPoint ihpt = !gLargeScreenDevice && [storyController isLandscape] ? CGPointMake(132, 142) : CGPointMake(2, ypos-8);
    if (ihpt.y < 140) ihpt.y = 140;
    
    if (phase == UITouchPhaseEnded) {
	float xdist = fabsf(m_touchBeganPosition.x - currentTouchPosition.x);
	float ydist = fabsf(m_touchBeganPosition.y - currentTouchPosition.y);
	if (tapCount == 0 &&  ydist >= 100 && xdist <= 40 && m_touchBeganPosition.y > currentTouchPosition.y) {// Check for upward swipe
	    if (self.text.length > 0)
		[storyController performSelector: @selector(textFieldFakeDidEndEditing:) withObject: self afterDelay: 0.02];
	}
	else if (tapCount == 1 && isInputHelperTouch && mode == FrotzInputHelperModeNone)
	    [self performSelector: @selector(launchInputHelper:) withObject:nil afterDelay:0.14];
	else if (tapCount == 2 && isInputHelperTouch &&  mode != FrotzInputHelperModeWords) {
	    ihpt.y -= 10;
	    ihpt.x += 20;
	    [m_inputHelper showInputHelperInView:parentView atPoint: ihpt withMode: FrotzInputHelperModeHistory];
	} else if (mode != FrotzInputHelperModeNone && tapCount) {
	    [self hideInputHelper];
	    m_justHidHelper = YES;
    	    m_lastTouchTimestamp = [touch timestamp];
	} else {
	    m_justHidHelper = NO;
	}
    } else if (phase == UITouchPhaseBegan) {
	if (tapCount == 1) {
	    m_touchBeganPosition = [touch locationInView: self];
	    m_lastTouchTimestamp = [touch timestamp];
	} else if (tapCount == 2)
	    [NSRunLoop cancelPreviousPerformRequestsWithTarget: self];
    } 
    m_lastTouchPhaseSeen = phase;
    return YES;
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    BOOL retValue = YES;
    FrotzInputHelperMode mode = [m_inputHelper mode];
    if (mode != FrotzInputHelperModeNone)
	return NO;
    if ((ipzAllowInput & kIPZNoEcho) || cwin == 1 || m_justHidHelper)
	return NO;
#if 1
    if (action == @selector(paste:) ) {
	// can only get paste menu by long touch when helper menu isn't showing
	if ([[m_inputHelper view] superview]) // m_lastTouchPhaseSeen == UITouchPhaseEnded || 
	    retValue = NO;
    } else
#endif
	retValue = [super canPerformAction: action withSender:sender];
    return retValue;
}

-(int)addHistoryItem:(NSString*)historyItem {
    return [m_inputHelper addHistoryItem:  historyItem];
}

-(StoryView*) storyView {
    return m_storyView;
}
-(void)setStoryView:(StoryView*)sv {
    m_storyView = sv;
}
-(StatusLine*) statusLine {
    return m_statusLine;
}
-(void)setStatusLine:(StatusLine*)sl {
    m_statusLine = sl;
}

-(void)resetState {
    m_firstKeyPressed = NO;
    [self setClearButtonMode: UITextFieldViewModeAlways];
}

BOOL cursorVisible = YES;

-(BOOL)updatePosition {
    CGRect myFrame = [self frame];
    FrotzView *curTextView = m_storyView;
    StoryMainViewController *controller = (StoryMainViewController*)[self delegate];
    BOOL isGrid = NO;
    if (cwin >= 1) {
	curTextView = m_statusLine;
	isGrid = YES;
	FrotzView *v = [controller glkView: cwin];
	if (v) {
	    curTextView = v;
	    isGrid = [controller glkViewTypeIsGrid: cwin];
	}
    }
    CGRect frame = [curTextView frame];
    cursorVisible = YES;
    if (!(ipzAllowInput & kIPZRequestInput)) {
	myFrame.origin.x = 0;
	myFrame.origin.y = frame.size.height;
    }
    else if (isGrid) {
    //  NSLog(@"udp bounds=%f %f %f %f", bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height);
#if UseRichTextView
	CGPoint cursorPt = [controller cursorOffset];
	myFrame.origin.x = frame.origin.x + cursorPt.x; // cursor_col * fixedFontWidth - bounds.origin.x;
	myFrame.origin.y = frame.origin.y + cursorPt.y; // cursor_row * (fixedFontHeight) - bounds.origin.y;
	if (cursorPt.y >= frame.size.height) {
	    myFrame.origin.y = [curTextView frame].size.height;
	    cursorVisible = NO;
	}
#else
	int fixedFontWidth = [controller statusFixedFontPixelWidth];
	int fixedFontHeight = [controller statusFixedFontPixelHeight];
	CGRect bounds = [curTextView bounds];
	myFrame.origin.x = frame.origin.x + cursor_col * fixedFontWidth - bounds.origin.x + 2;
	myFrame.origin.y = frame.origin.y + cursor_row * (fixedFontHeight-1) - bounds.origin.y + 8;
#endif
	if (frame.origin.x != myFrame.origin.x) {
	    NSString *text = [self text];
	    [self setText: @" "];
	    [self setText: text];
	}
    }
    else
    {
	CGRect bounds = [curTextView bounds];
    //  NSLog(@"udp bounds=%f %f %f %f", bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height);
	CGSize sz = [curTextView contentSize];
#if UseRichTextView
	CGPoint cursorPt = sz.height > 40 ? [curTextView cursorPoint] : CGPointMake(0,0);
#else
	NSRange range = [curTextView selectedRange];
	if (range.location == INT32_MAX)
	    range.location = 0;
	CGRect selRect = sz.height > 40 ? [curTextView rectForSelection: range] : CGRectMake(0,0,0,0);
	CGPoint cursorPt = selRect.origin;
#endif
	myFrame.origin.x = frame.origin.x + cursorPt.x - bounds.origin.x;
	myFrame.origin.y = frame.origin.y + cursorPt.y - bounds.origin.y;
	myFrame.size.width = frame.size.width - myFrame.origin.x - 2;
	if (myFrame.origin.y > frame.origin.y + frame.size.height - [controller fontSize] - 8)
	    cursorVisible = NO;
    }
    
//  NSLog(@"udp cwin %d myFrame=%f %f %f %f", cwin, myFrame.origin.x, myFrame.origin.y, myFrame.size.width, myFrame.size.height);
    myFrame.size.width = frame.size.width - myFrame.origin.x;
    myFrame.size.height = [[self font] leading];
    [self setFrame: myFrame];
    if (m_completionLabel) {
	CGRect labelFrame = [m_completionLabel frame];
	labelFrame.origin.y = myFrame.origin.y - myFrame.size.height-4;
	[m_completionLabel setOrigin: labelFrame.origin];
    }
    [[self superview] bringSubviewToFront: self];
    [self setClearButtonMode];

    return cursorVisible;    
}

-(void) setClearButtonMode {
    CGRect frame = self.frame;
    CGRect parentFrame = self.superview.frame;
    if (frame.origin.x > parentFrame.size.width - 60)
	[self setClearButtonMode: UITextFieldViewModeNever];
    else
	[self setClearButtonMode: UITextFieldViewModeWhileEditing];
}

const int kCompletionViewTag = 21;

-(void)setFont:(UIFont *)font {
    [super setFont: font];
    if (m_completionLabel)
	[m_completionLabel setFont: font];
}

-(void)setText:(NSString *)text {
    [super setText: text];
    if (m_completionLabel) {
	[m_completionLabel setText: nil];
	[m_completionLabel removeFromSuperview];
    }
}

-(BOOL)keyboardInput:(id)sender shouldInsertText:(NSString*)text isMarkedText:(BOOL)imt {

    if (!m_firstKeyPressed) {
	// the clearButtonMode set is done to work around a bug where the input line doesn't draw
	// properly right after an autorestore.  All it does it set the field and call setNeedsLayout,
	// but just calling that directly didn't work; it doesn't force a redraw if nothing's really changed
	m_firstKeyPressed = YES;
	[self setClearButtonMode];
    }

    StoryMainViewController *storyController = (StoryMainViewController*)[self delegate];

    [self hideInputHelper];
    [storyController hideNotes];

    if ((ipzAllowInput & kIPZAllowInput)) {
    
	if (![self updatePosition]) {
	    [storyController scrollStoryViewToEnd: YES];
	    [self updatePosition];
	}

	CGSize sz = [[self storyView] contentSize];
	lastVisibleYPos[cwin] = sz.height;

	if ((ipzAllowInput & kIPZNoEcho) || cwin == 1) {//qqq was below
	    iphone_feed_input(text);
	    return NO;
	}
    }
  
    if ((ipzAllowInput & kIPZNoEcho) || cwin == 1) //qqq
	return NO;
    BOOL result = (BOOL)[super keyboardInput:sender shouldInsertText:text isMarkedText:imt];
    if (![storyController isCompletionEnabled])
	return result;
    if (result) {
	UIView *parentView = [self superview];
	CGRect frame = [self frame];
	if (!m_completionLabel) {
	    m_completionLabel = [[CompletionLabel alloc] initWithFont:[self font]];
	}
	NSString *word = [self text];
	NSString *prevString = nil;
	int len = [word length];
	NSRange r = [word rangeOfString: @" " options:NSBackwardsSearch range:NSMakeRange(0, len)];
	if (r.length)
	    prevString = [word substringToIndex: r.location+1];
	if (r.length)
	    ++r.location;
	else r.location = 0;
	r.length = len-r.location;
	word = [word substringWithRange: r];
	if ([text isEqualToString: @" "] || [text isEqualToString:@"."] || [text isEqualToString: @"\n"]) {
	    if ([m_completionLabel text]) {
		NSString *completion = [m_completionLabel text];
		if ([text isEqualToString: @"\n"]) {
		    [self setText: prevString ? [prevString stringByAppendingString: completion] : completion];
		    [m_completionLabel removeFromSuperview];
		    [m_completionLabel setText: nil];
		} else {
		    [super setText: prevString];
		    [parentView addSubview: m_completionLabel];
		    if (![text isEqualToString: @"."] || ![completion hasSuffix: @". "])
			completion = [completion stringByAppendingString: text];
		    [storyController textSelected:completion animDuration:0.02 hilightView:m_completionLabel];
		    return NO;
		}
	    }
	    return result;
	} else {
	    word = [word stringByAppendingString: text];
	    NSString *completion = [storyController completeWord: word prevString:prevString];
	    if (completion) {
		[m_completionLabel setText: completion];
		CGFloat inputLineWidth = frame.size.width;
		CGSize textSize = [completion sizeWithFont:[self font]];
		CGFloat clearButtonWidth = [self clearButtonRectForBounds: [self bounds]].size.width+1;
		CGFloat textWidth = prevString ? [prevString sizeWithFont: [self font]].width : 0;
		if (textWidth + textSize.width < inputLineWidth - clearButtonWidth)
		    frame.origin.x = textWidth;
		else 
		    frame.origin.x = inputLineWidth - textSize.width - clearButtonWidth;
		frame.size = textSize;
		frame.origin.y = -frame.size.height-4;
		frame = [self convertRect:frame toView:parentView];
		[m_completionLabel setOrigin: frame.origin];
		[parentView addSubview: m_completionLabel];
	    } else {
		[m_completionLabel removeFromSuperview];
		[m_completionLabel setText: nil];
	    }
	}
    }

    return result;
}

-(BOOL)keyboardInputShouldDelete:(id)sender {
    if (m_completionLabel) {
	[m_completionLabel removeFromSuperview];
	[m_completionLabel setText: nil];
    }
    if ((ipzAllowInput & kIPZAllowInput)) {
	if ((ipzAllowInput & kIPZNoEcho) || cwin == 1) {
	    [self setText: @""];
	    iphone_feed_input([NSString stringWithFormat:@"%c", ZC_BACKSPACE]);
	}
    	[self updatePosition];
    }
    else
	return NO;

    return (BOOL)[super keyboardInputShouldDelete:sender];

}
@end
