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
void SBSetAccelerometerRawEventsEnabled(BOOL);
void SBSetAccelerometerDeviceOrientationChangedEventsEnabled(BOOL);

@implementation FrotzApplication

- (void)deviceOrientationChanged:(GSEvent *)event {
    int screenOrientation = GSEventDeviceOrientation(event);    
    [self setUIOrientation: screenOrientation]; // ??? does this do anything?
    [m_mainView updateOrientation: screenOrientation];
}

#if 0
-(void)acceleratedInX:(float)x Y:(float)y Z:(float)z {
 //   FILE *f = fopen("/tmp/accel.txt", "a+");
    fprintf (stderr, "Accel %f %f %f\n", x, y, z);
   // fclose(f);
}
#endif

- (void) applicationDidFinishLaunching: (id) unused
{
    UIWindow *window;
    struct CGRect winRect = [UIHardware fullScreenApplicationContentRect];
    window = [[UIWindow alloc] initWithContentRect: winRect];
    winRect.origin.x = winRect.origin.y = 0.0f;
    m_mainView = [[MainView alloc] initWithFrame: winRect];

    [self setStatusBarMode: 1 duration: 0];

    [window orderFront: self];
    [window makeKey: self];
    [window _setHidden: NO];

    [window setContentView: m_mainView];     

// SB probably means SpringBoard.  Accelerometer events seem to only be
// availale if the app is launched from SpringBoard; if you run via a
// shell, you get no accel or orientation events.
// These calls do not help enable the events in that case.
//    SBSetAccelerometerRawEventsEnabled(YES);
//    SBSetAccelerometerDeviceOrientationChangedEventsEnabled(YES);
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
    [m_mainView suspendStory];
    [super applicationWillTerminate];
}



@end // FrotzApplication



