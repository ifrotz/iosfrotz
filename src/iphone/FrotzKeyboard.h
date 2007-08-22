// FrotzKeyboard.h
#import "UITextTraitsClientProtocol.h"
#import "UIKeyboardInputProtocol.h"
#import <UIKit/UIKeyboardImpl.h>

@class UIFrotzWinView;

@interface FrotzKeyboard : UIKeyboardImpl
{
    BOOL m_visible;
    BOOL m_landscape;
}
-(int) keyboardHeight;
-(int) keyboardWidth;
-(BOOL) isVisible;
-(void) setVisible:(BOOL)visible;
-(BOOL) isLandscape;
-(void) setLandscape:(BOOL)landscape;
-(void) show:(UIFrotzWinView*)view;
-(void) hide:(UIFrotzWinView*)view;
-(void) toggle:(UIFrotzWinView*)view;

@end
