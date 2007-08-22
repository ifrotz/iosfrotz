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

#import "FrotzApplication.h"
#import "MainView.h"

struct GSEvent;
typedef struct GSEvent GSEvent;
int GSEventDeviceOrientation(GSEvent *);

@implementation FrotzApplication


- (void)deviceOrientationChanged:(GSEvent *)event {
    int screenOrientation = GSEventDeviceOrientation(event);    
    [self setUIOrientation: screenOrientation]; // ??? does this do anything?
    [_mainView updateOrientation: screenOrientation];
}

- (void) applicationDidFinishLaunching: (id) unused
{
    UIWindow *window;
    struct CGRect winRect = [UIHardware fullScreenApplicationContentRect];
    window = [[UIWindow alloc] initWithContentRect: winRect];
    winRect.origin.x = winRect.origin.y = 0.0f;
    _mainView = [[MainView alloc] initWithFrame: winRect];

    [self setStatusBarMode: 1 duration: 0];

    [window orderFront: self];
    [window makeKey: self];
    [window _setHidden: NO];

    [window setContentView: _mainView];     
}

#if 0
- (BOOL)respondsToSelector:(SEL)aSelector
{
  NSLog(@"Request for selector: %@\n", NSStringFromSelector(aSelector));
  return [super respondsToSelector:aSelector];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
  NSLog(@"Callapp %@\n", NSStringFromSelector([anInvocation selector]));
  [super forwardInvocation:anInvocation];
  return;
}
#endif

- (void)applicationWillTerminate {
    [_mainView suspendStory];
    [super applicationWillTerminate];
}



@end // FrotzApplication



