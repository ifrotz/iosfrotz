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

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UIKit/UITransitionView.h>
#import <UIKit/UINavigationBar.h>
#import <UIKit/UIFontChooser.h>
#import <UIKit/UIKeyboard.h>

#import "StoryBrowser.h"
#import "ColorPicker.h"
#import "FileBrowser.h"
#import "StoryMainView.h"

@interface UIView (Fixup) 
-(CGRect) frame;
-(void) setFrame: (CGRect)frame;
@end

enum { kModeUninit, kModeSelectStory, kModePlayStory, kModeResumeStory, kModePrefs, kModeSelectColor, kModeSelectFont, kModeSelectFile };

@interface MainView : UIView  <StorySelected> {
    UINavigationBar *m_navBar;
    UIView *m_background;
    UITransitionView *m_transitionView;
    StoryBrowser *m_storyBrowser;
    StoryMainView *m_storyMainView;
    UIFontChooser *m_fontc;
    ColorPicker *m_colorPicker;
    UIKeyboard *m_keyb;
    FileBrowser *m_fileBrowser;
    int m_mode;
    int m_orient;
    UITable *m_prefTable;
    UIPreferencesTableCell *m_prefButton[4];
    
    CGColorRef m_selectedColor;
    int m_whichColor;
}

- (id) initWithFrame:(CGRect)frame;
- (void) updateNavBarButtons:(int)mode;
- (void) storyBrowser:browser storySelected:storyPath;
- (void) abortToBrowser;
- (void) suspendStory;
- (void) dealloc;
- (void) openFileBrowser;
- (void) fileBrowser: (FileBrowser *)browser fileSelected:(NSString *)file;
- (int) orientation;
- (void) updateOrientation: (int)orient;
- (NSString*) preferencesTable:(id)sender titleForGroup:(int)group;
- (void) tableRowSelected: (NSNotification*)notif;
- (int) numberOfGroupsInPreferencesTable: (id)sender;
- (int) preferencesTable:(id)sender numberOfRowsInGroup:(int)group;
- (id) preferencesTable:(id)sender cellForRow:(int)row inGroup:(int)group;

@end
