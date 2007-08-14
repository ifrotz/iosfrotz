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
#import "FrotzKeyboard.h"

#import <UIKit/UIKit.h>
#import <UIKit/UIAnimator.h>
#import <UIKit/UIHardware.h>
#import <UIKit/UIScroller.h>
#import <UIKit/UITransformAnimation.h>
#import <UIKit/UIView-Geometry.h>
#import "UIKeyboardInputProtocol.h"
#import "UIKit/UIKeyboardImpl.h"
#import "Cleanup.h"
#import "StoryMainView.h"

@implementation UIKeyboardImpl (NoCaps) 
- (BOOL)autoCapitalizationPreference {
  return NO;
}

// We want to prevent common single letter inputs (i,w,e,s,q) from correcting to the wrong thing ('a') using the
// default word correction, without turning it off altogether.  This is surely not the 'correct' way to do it,
// but it was the easiest way I could figure out. 
-(void)setAutocorrection:(id)str {
    if (str && [str length] > 2)
	m_autocorrection = [str retain];
    else
	m_autocorrection = @"";
}
@end

@implementation FrotzKeyboard

const float kKeyboardSize = 236.0f;
const float kAnimDuration = 0.40f;

- (void) show:(UIFrotzWinView*)view
{
    CGRect origKBFrame = [self frame];
    CGRect origViewFrame = [view frame];
    if (!m_visible) { 
	[view setBottomBufferHeight: 25];
	origViewFrame.size.height -= kKeyboardSize;
	[view setFrame: origViewFrame];
	[view scrollToEnd];
	struct CGAffineTransform identity = CGAffineTransformMake(1,0,0,1,0,0);
	struct CGAffineTransform trans = CGAffineTransformMakeTranslation(0, kKeyboardSize);
	[self setTransform: identity];
	[self setFrame:CGRectMake(0.0f, 480.0 - 40.0 -kKeyboardSize, 320.0f, kKeyboardSize)];
	
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
	[view setBottomBufferHeight:(70.0f)];
	origViewFrame.size.height += kKeyboardSize;
	[view setFrame: origViewFrame];
//	[view scrollToEnd];
	
	struct CGAffineTransform identity = CGAffineTransformMake(1,0,0,1,0,0);
	struct CGAffineTransform trans = CGAffineTransformMakeTranslation(0, -kKeyboardSize);
	[self setTransform: identity];
	[self setFrame: CGRectMake(0.0f, 480.0f, 320.0f, kKeyboardSize)];
	
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
