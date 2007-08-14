// FrotzKeyboard.h
#include <UIKit/UIKeyboard.h>

@class UIFrotzWinView;

@interface FrotzKeyboard : UIKeyboard
{
    BOOL m_visible;
}

- (void)show:(UIFrotzWinView*)view;
- (void)hide:(UIFrotzWinView*)view;
- (void)toggle:(UIFrotzWinView*)view;

@end
