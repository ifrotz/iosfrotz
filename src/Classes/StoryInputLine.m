
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

-(void)enterButtonPressed:(id)sender {
    StoryMainViewController *storyController = (StoryMainViewController*)self.delegate;
    if (self.text.length > 0) {
        [self handleCompletion: @"\n"];
        [storyController performSelector: @selector(textFieldFakeDidEndEditing:) withObject: self afterDelay: 0.02];
    }
}

-(void)clearButtonPressed:(id)sender {
    NSString *text = [self text];
    int len = [text length];
    NSRange r = [text rangeOfString: @" " options:NSBackwardsSearch range:NSMakeRange(0, len)];
    if (r.length)
        [self setText: [text substringToIndex: r.location]];
    else
        [self setText: @""];
}

-(StoryInputLine*)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame: frame])) {
        m_inputHelper = [[FrotzInputHelper alloc] init];
        [m_inputHelper setDelegate: self];
        UIButton *enterButton = [UIButton buttonWithType: UIButtonTypeCustom];

        [enterButton setTitle:@"  \u23CE   " forState: UIControlStateNormal];
        [enterButton setTitleColor: [UIColor grayColor] forState: UIControlStateNormal];
        [enterButton sizeToFit];

        //UIImage *enterButtonImage = [UIImage imageNamed: @"glyph-enter"];
        UIImage *clearButtonImage = [UIImage imageNamed: @"glyph-input-clear.png"];
        CGFloat ecHeight = [clearButtonImage size].height+4;
        //[enterButton setImage: enterButtonImage forState: UIControlStateNormal];
        [enterButton setFrame: CGRectMake(0,1, enterButton.frame.size.width, ecHeight)];
//        [enterButton setFrame: CGRectMake(0,0,[enterButtonImage size].width, ecHeight)];
        enterButton.backgroundColor = [UIColor clearColor];
        [enterButton addTarget:self action:@selector(enterButtonPressed:) forControlEvents: UIControlEventTouchDown];

        const CGFloat spacingBetweenButtons = 8;
        UIButton *clearButton = [UIButton buttonWithType: UIButtonTypeCustom];
        [clearButton setImage: clearButtonImage forState: UIControlStateNormal];
        [clearButton setFrame: CGRectMake(enterButton.frame.size.width+spacingBetweenButtons,0,[clearButtonImage size].width+8, ecHeight)];
        clearButton.backgroundColor = [UIColor clearColor];
        [clearButton addTarget:self action:@selector(clearButtonPressed:) forControlEvents: UIControlEventTouchDown];

        m_enterAndClearView = [[UIView alloc] initWithFrame: CGRectMake(0,0,enterButton.frame.size.width+spacingBetweenButtons+clearButton.frame.size.width,ecHeight)];
        [m_enterAndClearView addSubview: enterButton];
        [m_enterAndClearView addSubview: clearButton];
        
        self.rightView = m_enterAndClearView;
        self.rightViewMode = UITextFieldViewModeWhileEditing;
        
        UIButton *inputHelperButton = [UIButton buttonWithType: UIButtonTypeCustom];
        UIImage *inputMenuImage = [UIImage imageNamed: @"glyph-input-helper.png"];
        [inputHelperButton setImage: inputMenuImage forState: UIControlStateNormal];
        [inputHelperButton setFrame: CGRectMake(0,0,[inputMenuImage size].width, [inputMenuImage size].height)];
        [inputHelperButton addTarget:self action:@selector(toggleInputHelper) forControlEvents: UIControlEventTouchUpInside];
        inputHelperButton.backgroundColor = [UIColor clearColor];

        self.leftView = inputHelperButton;
        self.leftViewMode = UITextFieldViewModeUnlessEditing;
        [self setInputMenuButtonAlpha];
    }
    return self;
}

- (CGRect)leftViewRectForBounds:(CGRect)bounds {
    CGRect rect = [super leftViewRectForBounds:bounds];
    return rect;
}

- (CGRect)editingRectForBounds:(CGRect)bounds {
    CGRect rect = [super editingRectForBounds: bounds];
    CGRect lrRect = [self leftViewRectForBounds: bounds];
    if (rect.origin.x >= lrRect.size.width) {
        rect.origin.x -= lrRect.size.width;
        rect.size.width += lrRect.size.width;
    }
    StoryMainViewController *storyController = (StoryMainViewController*)[m_storyView delegate];
    if ([storyController isKBLocked])
        rect.size.width -= m_enterAndClearView.frame.size.width;
    return rect;
}

-(void)dealloc {
    if (m_inputHelper)
        [m_inputHelper release];
    if (m_completionLabel)
        [m_completionLabel release];
    self.rightView = nil;
    self.leftView = nil;
    if (m_enterAndClearView)
        [m_enterAndClearView release];
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
    if (![self isFirstResponder] && [self canBecomeFirstResponder])
        [m_inputHelper hideInputHelper];
    return [super becomeFirstResponder];
}

-(void)inputHelperString:(NSString*)string {
    [self hideInputHelper];
    int len = [self.text length];
    if (len > 0) {
        if ([self.text characterAtIndex:len-1]!=' ' && !ispunct([self.text characterAtIndex:len-1]))
            string = [@" " stringByAppendingString: string];
        string = [self.text stringByAppendingString: string];
    }
    [self setText: string];
}

-(CGPoint)helperLaunchPosition {
    UIView *parentView = [m_storyView superview];
    CGFloat ypos = [self convertPoint: CGPointZero toView: parentView].y;
    StoryMainViewController *storyController = (StoryMainViewController*)[m_storyView delegate];
    CGPoint ihpt = CGPointMake(2, ypos-8);
    if (gLargeScreenDevice)
        ihpt.x += self.frame.origin.x;
    else if (!gLargeScreenDevice && ![storyController isKBLocked] && [self isFirstResponder]
                && [storyController isLandscape])
        ihpt = CGPointMake(120, 148);
    // point is bottom-LEFT of helper view; 140 is height of helper
    if (ihpt.y < 140) ihpt.y = 140;
    return ihpt;
}

-(void)launchInputHelper:(id)unused {
    UIView *parentView = [m_storyView superview];
    CGPoint ihpt = [self helperLaunchPosition];
    if (m_completionLabel)
        [m_completionLabel removeFromSuperview];
    [m_inputHelper showInputHelperInView:parentView atPoint: ihpt withMode: FrotzInputHelperModeWords];
}

-(void)setInputMenuButtonAlpha {
    UIButton *ivButton = (UIButton*)self.leftView;
    FrotzInputHelperMode mode = [m_inputHelper mode];
    if ((ipzAllowInput & kIPZNoEcho) || cwin == 1)
        ivButton.imageView.alpha = 0.0;
    else if (mode == FrotzInputHelperModeNone)
        ivButton.imageView.alpha = 0.25;
    else
        ivButton.imageView.alpha = 0.70;
}

-(void)toggleInputHelper {
    // we don't actually need to do anything special here since the general touuch handler handles this for anywhere on the input line
    FrotzInputHelperMode mode = [m_inputHelper mode];
    if (mode == FrotzInputHelperModeNone) {
        [self performSelector:@selector(setInputMenuButtonAlpha) withObject:nil afterDelay:0.2];
    }
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
    BOOL isInputHelperTouch =  [touch locationInView:self].x < self.frame.size.width * 0.8;
    CGPoint currentTouchPosition = [touch locationInView:self];

    //CGRect rtRect = [self rightViewRectForBounds:self.bounds];
    //NSLog(@"sit ht (%f,%f) (x %f- wid %f)",currentTouchPosition.x, currentTouchPosition.y, rtRect.origin.x, rtRect.size.width);

    BOOL kbLocked = [storyController isKBLocked];
    if (![storyController isKBShown] && !kbLocked
        && !CGRectContainsPoint([self leftViewRectForBounds:self.bounds], currentTouchPosition)
        || (ipzAllowInput & kIPZNoEcho) || cwin == 1)
        isInputHelperTouch = NO;

    if (CGRectContainsPoint([self rightViewRectForBounds:self.bounds], currentTouchPosition))
        return YES;
    
    CGPoint ihpt = [self helperLaunchPosition];
    
    if (phase == UITouchPhaseEnded) {
        float xdist = fabsf(m_touchBeganPosition.x - currentTouchPosition.x);
        float ydist = fabsf(m_touchBeganPosition.y - currentTouchPosition.y);
        if (tapCount == 0 &&  ydist >= 70 && xdist <= 40 && m_touchBeganPosition.y > currentTouchPosition.y) {// Check for upward swipe
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
    if ((ipzAllowInput & kIPZNoEcho) || cwin == 1 || m_justHidHelper) {
        if (action == @selector(upArrow:) || action == @selector(downArrow:)
            || action == @selector(leftArrow:) || action == @selector(rightArrow:) || action == @selector(escapeKey:))
            return YES;
        return NO;
    }
    if (action == @selector(paste:) ) {
        // can only get paste menu by long touch when helper menu isn't showing
        if ([[m_inputHelper view] superview]) // m_lastTouchPhaseSeen == UITouchPhaseEnded || 
            retValue = NO;
    } else
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

-(BOOL)canBecomeFirstResponder {
    StoryMainViewController *controller = (StoryMainViewController*)[self delegate];
    if ([controller isKBLocked])
        return NO;
    return [super canBecomeFirstResponder];
}

-(BOOL)updatePosition {
    static BOOL insideUpdatePosition;
    if (insideUpdatePosition) // prevent recursive update (setText: can cause htis)
        return NO;
    insideUpdatePosition = YES;
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
        myFrame.origin.y = frame.size.height + 1024; // make sure offscreen, not under kb
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
        if (myFrame.origin.y > frame.origin.y + frame.size.height - [controller fontSize])
            cursorVisible = NO;
    }
    
    //NSLog(@"udp cwin %d myFrame=%f %f %f %f vis=%d", cwin, myFrame.origin.x, myFrame.origin.y, myFrame.size.width, myFrame.size.height, cursorVisible);
    myFrame.size.width = frame.size.width - (myFrame.origin.x - frame.origin.x) - [curTextView rightMargin];
    int pad = 2;
    myFrame.size.height = [[self font] leading]+pad;

    [self setFrame: myFrame];
    if (m_completionLabel) {
        CGRect labelFrame = [m_completionLabel frame];
        labelFrame.origin.y = myFrame.origin.y - myFrame.size.height-pad-4;
        [m_completionLabel setOrigin: labelFrame.origin];
    }


    if (cursorVisible)
        [[self superview] bringSubviewToFront: self];
    else
        [[self superview] sendSubviewToBack: self];
    [self setClearButtonMode];
    insideUpdatePosition = NO;
   
    return cursorVisible;
}

-(void) setClearButtonMode {
    CGRect frame = self.frame;
    CGRect parentFrame = self.superview.frame;
    if (frame.origin.x > parentFrame.size.width - 60)
        [self setClearButtonMode: UITextFieldViewModeNever];
    else
        [self setClearButtonMode: UITextFieldViewModeWhileEditing];
    [self maybeShowEnterKey];
}

-(void)maybeShowEnterKey {
    StoryMainViewController *storyController = (StoryMainViewController*)[self delegate];
    
    [self setInputMenuButtonAlpha];
    
    if ([storyController isKBLocked] && (self.text.length > 0 && !m_lastCharDeleted || m_firstKeyPressed)) {
        m_firstKeyPressed = NO;
        self.rightViewMode = UITextFieldViewModeAlways;
        [self setClearButtonMode: UITextFieldViewModeNever];
        self.leftViewMode = UITextFieldViewModeNever;
    }
    else {
        self.rightViewMode = UITextFieldViewModeNever;
        if (self.text.length == 0)
            self.leftViewMode = UITextFieldViewModeUnlessEditing;
        else
            self.leftViewMode = UITextFieldViewModeNever;
        m_lastCharDeleted = NO;
    }
}

-(void)hideEnterKey {
    m_lastCharDeleted = YES;
    [self setClearButtonMode];
}

const int kCompletionViewTag = 21;

-(void)setFont:(UIFont *)font {
    if (font == self.font)
        return;
    [super setFont: font];
    if (m_completionLabel)
        [m_completionLabel setFont: font];
}

-(void)setText:(NSString *)text {
    [super setText: text];
    iphone_feed_input_line(text);

    if (m_completionLabel) {
        [m_completionLabel setText: nil];
        [m_completionLabel removeFromSuperview];
    }
    [self maybeShowEnterKey];
//    NSLog(@"set text %@", text);
}

-(void)setTextKeepCompletion:(NSString*)text {
    [super setText: text];
}


-(BOOL)keyboardInput:(id)sender shouldInsertText:(NSString*)text isMarkedText:(BOOL)imt {
    
    if (!m_firstKeyPressed && self.text.length==0) {
        // the clearButtonMode set is done to work around a bug where the input line doesn't draw
        // properly right after an autorestore.  All it does it set the field and call setNeedsLayout,
        // but just calling that directly didn't work; it doesn't force a redraw if nothing's really changed
        m_firstKeyPressed = YES;
        if (!(ipzAllowInput & kIPZAllowInput))
            [self setClearButtonMode]; // else updatePosition below will do it
    }

    StoryMainViewController *storyController = (StoryMainViewController*)[self delegate];
    
    [self hideInputHelper];
    [storyController hideNotes];
    
    if ((ipzAllowInput & kIPZAllowInput)) {
        // some love for users of bluetooth keyboards
        if ([text isEqualToString: @" "]) { // option-space = scroll up one page
            [storyController scrollStoryViewUpOnePage:[self storyView] fraction: 1.0];
            return NO;
        }
        if (![self updatePosition]) {
            if ([text isEqualToString:@" "]) { // space = scroll down one page
                [storyController scrollStoryViewOnePage:[self storyView] fraction:1.0];
                return NO;
            }
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
    if (result)
        result = [self handleCompletion:text];
    
    return result;
}


-(BOOL)handleCompletion:(NSString*)text {
    StoryMainViewController *storyController = (StoryMainViewController*)[self delegate];
    BOOL result = YES;
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
        if ([m_completionLabel text] && [[m_completionLabel text] length] > 0) {
            NSString *completion = [m_completionLabel text];
            if ([text isEqualToString: @"\n"]) {
                [self setText: prevString ? [prevString stringByAppendingString: completion] : completion];
                [m_completionLabel removeFromSuperview];
                [m_completionLabel setText: nil];
            } else {
                [super setText: prevString];
                [parentView addSubview: m_completionLabel];
                if ((![text isEqualToString: @"."] || ![completion hasSuffix: @". "]) && !m_completionAmbiguous)
                    completion = [completion stringByAppendingString: text];
                [storyController textSelected:completion animDuration:0.02 hilightView:m_completionLabel];
                return NO;
            }
        }
        return result;
    } else {
        word = [word stringByAppendingString: text];
        NSString *completion = [storyController completeWord: word prevString:prevString isAmbiguous:&m_completionAmbiguous];
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
        if (self.text.length == 1)
            m_lastCharDeleted = YES;
    	[self updatePosition];
    }
  
    return (BOOL)[super keyboardInputShouldDelete:sender];
    
}

#if __IPHONE_5_1 < __IPHONE_OS_VERSION_MAX_ALLOWED
- (NSArray *) keyCommands
{
    if ((ipzAllowInput & kIPZNoEcho)) {
        UIKeyCommand *upArrow = [UIKeyCommand keyCommandWithInput: UIKeyInputUpArrow modifierFlags: 0 action: @selector(upArrow:)];
        UIKeyCommand *downArrow = [UIKeyCommand keyCommandWithInput: UIKeyInputDownArrow modifierFlags: 0 action: @selector(downArrow:)];
        UIKeyCommand *leftArrow = [UIKeyCommand keyCommandWithInput: UIKeyInputLeftArrow modifierFlags: 0 action: @selector(leftArrow:)];
        UIKeyCommand *rightArrow = [UIKeyCommand keyCommandWithInput: UIKeyInputRightArrow modifierFlags: 0 action: @selector(rightArrow:)];
        UIKeyCommand *escapeKey = [UIKeyCommand keyCommandWithInput: UIKeyInputEscape modifierFlags: 0 action: @selector(escapeKey:)];
        UIKeyCommand *ctrlP = [UIKeyCommand keyCommandWithInput: @"p" modifierFlags: UIKeyModifierControl action: @selector(upArrow:)];
        UIKeyCommand *ctrlN = [UIKeyCommand keyCommandWithInput: @"n" modifierFlags: UIKeyModifierControl action: @selector(downArrow:)];
        UIKeyCommand *ctrlB = [UIKeyCommand keyCommandWithInput: @"b" modifierFlags: UIKeyModifierControl action: @selector(leftArrow:)];
        UIKeyCommand *ctrlF = [UIKeyCommand keyCommandWithInput: @"f" modifierFlags: UIKeyModifierControl action: @selector(rightArrow:)];
        return [[NSArray alloc] initWithObjects: upArrow, downArrow, leftArrow, rightArrow, escapeKey, ctrlP, ctrlN, ctrlB, ctrlF, nil];
    } else {
        UIKeyCommand *upArrow = [UIKeyCommand keyCommandWithInput: UIKeyInputUpArrow modifierFlags: 0 action: @selector(upArrow:)];
        UIKeyCommand *downArrow = [UIKeyCommand keyCommandWithInput: UIKeyInputDownArrow modifierFlags: 0 action: @selector(downArrow:)];
        UIKeyCommand *ctrlP = [UIKeyCommand keyCommandWithInput: @"p" modifierFlags: UIKeyModifierControl action: @selector(upArrow:)];
        UIKeyCommand *ctrlN = [UIKeyCommand keyCommandWithInput: @"n" modifierFlags: UIKeyModifierControl action: @selector(downArrow:)];
        return [[NSArray alloc] initWithObjects: upArrow, downArrow, ctrlP, ctrlN, nil];
    }
    return nil;
}

- (void) upArrow: (UIKeyCommand *) keyCommand
{
    if ((ipzAllowInput & kIPZNoEcho))
        iphone_feed_input(@ZC_IPS_ARROW_UP);
    else
        self.text = [m_inputHelper getPrevHistoryItem];
}

- (void) downArrow: (UIKeyCommand *) keyCommand
{
    if ((ipzAllowInput & kIPZNoEcho))
        iphone_feed_input(@ZC_IPS_ARROW_DOWN);
    else
        self.text = [m_inputHelper getNextHistoryItem];
}

- (void) leftArrow: (UIKeyCommand *) keyCommand
{
    iphone_feed_input(@ZC_IPS_ARROW_LEFT);
}

- (void) rightArrow: (UIKeyCommand *) keyCommand
{
    iphone_feed_input(@ZC_IPS_ARROW_RIGHT);
}
- (void) escapeKey: (UIKeyCommand *) keyCommand
{
    iphone_feed_input(@"\x1b");
}
#endif

@end
