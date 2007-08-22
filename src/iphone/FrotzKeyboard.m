/*

 This program is free software; you can redistribute it and/or
 modify it under the terms of the GNU General Public License
 as published by the Free Software Foundation; version 2
 of the License.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program; if not, write to the Free Software
 Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

*/
// Thanks to author of MobileTerminal for example UITransformAnimation code

#import <UIKit/UIKit.h>
#import <UIKit/UIAnimator.h>
#import <UIKit/UIHardware.h>
#import <UIKit/UIScroller.h>
#import <UIKit/UITransformAnimation.h>
#import <UIKit/UIView-Geometry.h>
#import "Cleanup.h"
#import "StoryMainView.h"
#import "FrotzKeyboard.h"

@implementation FrotzKeyboard

const float kKeyboardSize = 236.0f;
const float kAnimDuration = 0.40f;

- (BOOL)autoCapitalizationPreference {
  return NO;
}

// We want to prevent common single letter inputs (i,w,e,s,q) from correcting to the wrong thing ('a') using the
// default word correction, without turning it off altogether. 
-(void)setAutocorrection:(id)str {
    // This works only partially because it's only called if there is already an autocorrection
    // suggested; we merely replace it.  So 'z' aand 'i' don't work.
    // To-do: Investigate pre-populating the m_autocorrectionHistory instead.
    if (str && [str length] > 2)
	[super setAutocorrection: str];
    else if (str && [str isEqualToString: @"x"])
	m_autocorrection = @"examine";
    else if (str && [str isEqualToString: @"l"])
	m_autocorrection = @"look";
    else if (str && [str isEqualToString: @"i"])
	m_autocorrection = @"inventory";
    else if (str && [str isEqualToString: @"g"])
	m_autocorrection = @"again.";
    else if (str && [str isEqualToString: @"z"])
	m_autocorrection = @"wait.";
    else if (str && [str isEqualToString: @"ta"])
	m_autocorrection = @"take";
    else if (str && [str isEqualToString: @"ge"])
	m_autocorrection = @"get";
    else
	m_autocorrection = @"";
}


-(int) keyboardHeight {
    return m_landscape ? 180 : 236;
}

-(int) keyboardWidth {
    return m_landscape ? 480 : 320;
}

-(BOOL) isLandscape {
    return m_landscape;
}

-(void) setLandscape:(BOOL)landscape {
    m_landscape = landscape;
}

-(BOOL) isVisible {
    return m_visible;
}

-(void) setVisible:(BOOL)visible {
    m_visible = visible;
}

- (void) show:(UIFrotzWinView*)view
{
    CGRect origKBFrame = [self frame];
    CGRect origViewFrame = [view frame];
    if (!m_visible) { 
	float kbdWidth = [self keyboardWidth];
	float kbdHeight = [self keyboardHeight];
	origViewFrame.size.height -= kbdHeight;
	[view setFrame: origViewFrame];
	[view becomeFirstResponder];
	[[[view _webView] webView] moveToEndOfDocument:self];
	[view scrollToEnd];

	struct CGAffineTransform identity = CGAffineTransformMake(1,0,0,1,0,0);
	[self setTransform: identity];
	if ([self isLandscape])
	    [self setFrame: CGRectMake(0.0f, 140.0f, kbdWidth, kbdHeight)];
	else
	    [self setFrame: CGRectMake(0.0f, 440.0 - kbdHeight, kbdWidth, kbdHeight)];
	if ([self isLandscape])
	    identity = CGAffineTransformTranslate(identity, -10.0f, 0.0f);
	struct CGAffineTransform trans = CGAffineTransformTranslate(identity, 0.0f, kbdHeight);
	
	UITransformAnimation *translate = [[UITransformAnimation alloc] initWithTarget: self];
	[translate setStartTransform: trans];
	[translate setEndTransform: identity];
	[translate setDelegate: self];

	UIAnimator *anim = [[UIAnimator alloc] init];
	[anim addAnimation:translate withDuration:kAnimDuration start:YES];	
	
    }
    m_visible = YES;
}

- (void) hide:(UIFrotzWinView*)view {
    CGRect origKBFrame = [self frame];
    CGRect origViewFrame = [view frame];
    if (m_visible) { 
    	float kbdWidth = [self keyboardWidth];
	float kbdHeight = [self keyboardHeight];

	origViewFrame.size.height += kbdHeight;
	[view setFrame: origViewFrame];
	[view becomeFirstResponder];
	[[[view _webView] webView] moveToEndOfDocument:self];
	[view scrollToEnd];
	
	struct CGAffineTransform identity = CGAffineTransformMake(1,0,0,1,0,0);
	[self setTransform: identity];
	if ([self isLandscape])
	    [self setFrame: CGRectMake(0.0f, 320.0f, kbdWidth, kbdHeight)];
	else
	    [self setFrame: CGRectMake(0.0f, 480.0f, kbdWidth, kbdHeight)];
	if ([self isLandscape])
	    identity = CGAffineTransformTranslate(identity, -10.0f, 0.0f);
	struct CGAffineTransform trans = CGAffineTransformTranslate(identity, 0.0f, -kbdHeight);
	
	UITransformAnimation *translate = [[UITransformAnimation alloc] initWithTarget: self];
	[translate setStartTransform: trans];
	[translate setEndTransform: identity];
	[translate setDelegate: self];

	UIAnimator *anim = [[UIAnimator alloc] init];
	[anim addAnimation:translate withDuration:kAnimDuration start:YES];	
    }
    m_visible = NO;
}

- (void) toggle:(UIFrotzWinView*)view {
    if (m_visible)
        [self hide:view];
    else
        [self show:view];
}

@end
