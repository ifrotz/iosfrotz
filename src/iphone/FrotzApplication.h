#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UIKit/UIApplication.h>
#import "MainView.h"

@interface FrotzApplication : UIApplication {
    MainView *m_mainView;
}
@end

extern FrotzApplication *theApp;
extern float kUIStatusBarHeight;

extern BOOL gShowStatusBarInLandscapeMode;