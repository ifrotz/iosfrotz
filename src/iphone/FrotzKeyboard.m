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
#import "FrotzApplication.h"
#import "StoryMainView.h"
#import "FrotzKeyboard.h"

static int matchWord(NSString *str, NSString *wordArray[]) {
    int i;
    for (i=0; wordArray[i]; ++i) {
	if ([wordArray[i] hasPrefix: str]) {
	    return i;
	}
    }
    return -1;
}

@implementation FrotzKeyboardImpl

- (BOOL)autoCapitalizationPreference {
  return NO;
}

-(void)updateSuggestionsForCurrentInput {
    
    UIKBInputManager *inputManager = [UIKBInputManager activeInstance];
    if (!inputManager) {
    	[super updateSuggestionsForCurrentInput];
	return;
    }
    
    NSString *str = [inputManager inputString];
    static NSString *wordArray[] = { @"look", @"read", @"restore", @"take", @"get",
	@"pick", @"quit", @"but", @"throw", @"tell", @"open", @"close", @"put",
	@"up", @"down", @"i", @"it", @"in", @"out", nil };
	// removed 'inventory' because some games choke on the full spelling (HHGTTG)
    static NSString *rareWordArray[] = { @"examine", @"diagnose", @"say", @"save", @"to", @"no", @"yes", @"all", @"but", @"from", @"with", @"about",
	@"north", @"east", @"south", @"west", @"se", @"sw", @"sb", @"port", @"drop", @"door", @"push", @"pull", @"show", @"stand", @"switch",
	@"turn", @"sit", @"kill", @"jump",  @"go", @"give", @"disrobe", nil };
    static NSString *veryRareWordArray[] = { @"diagnose", @"verbose", @"brief", @"superbrief", @"score", @"restart", @"script", @"unscript",
	@"listen", @"touch", @"smell", @"taste", @"feel", @"light", @"lantern", nil };
    int len = [str length], match;
    int i;
    if (len == 0)//
    	[super updateSuggestionsForCurrentInput];//
    else //
    if ([str isEqualToString: @"x"])  // 1-letter shortcuts
	[self setAutocorrection: @"examine"];
    else  if ([str isEqualToString: @"z"])
	[self setAutocorrection: @"wait."];
    else  if ([str isEqualToString: @"g"])
	[self setAutocorrection: @"again."];
    else {
	if ((match = matchWord(str, wordArray)) >= 0) {
	    [self setAutocorrection: wordArray[match]];
	    return;
	}
	if (len > 1 && (match = matchWord(str, rareWordArray)) >= 0) {
	    [self setAutocorrection: rareWordArray[match]];
	    return;
	}
	if (len > 2 && (match = matchWord(str, veryRareWordArray)) >= 0) {
	    [self setAutocorrection: veryRareWordArray[match]];
	    return;
	}
    }
    if (len > 2) // don't correct 1/2 letter words, or cardinal dirs will be messed up
	[super updateSuggestionsForCurrentInput];
}

@end

@implementation FrotzKeyboard

const float kKeyboardSize = 236.0f;
const float kAnimDuration = 0.40f;

+(void) initImplementationNow {
    [FrotzKeyboardImpl sharedInstance];
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
	if (gShowStatusBarInLandscapeMode && [self isLandscape])
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
	if (gShowStatusBarInLandscapeMode && [self isLandscape])
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
