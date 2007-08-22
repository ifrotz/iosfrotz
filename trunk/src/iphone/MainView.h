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
#import "FileBrowser.h"
#import "StoryMainView.h"

@interface UIView (Fixup) 
-(CGRect) frame;
-(void) setFrame: (CGRect)frame;
@end

enum { kModeSelectStory, kModePlayStory, kModeSelectFont, kModeSelectFile };

@interface MainView : UIView  <StorySelected> {
    UINavigationBar *_navBar;
    UITransitionView *_transitionView;
    StoryBrowser *_storyBrowser;
    StoryMainView *_storyMainView;
    UIFontChooser *m_fontc;
    UIKeyboard *m_keyb;
    FileBrowser *m_fileBrowser;
    int m_orient;

    int _mode;
}

-(id) initWithFrame:(CGRect)frame;
-(void) updateNavBarButtons;
-(void) storyBrowser:browser storySelected:storyPath;
-(void) abortToBrowser;
-(void) suspendStory;
-(void) dealloc;
-(void) openFileBrowser;
-(void) fileBrowser: (FileBrowser *)browser fileSelected:(NSString *)file;
-(int) orientation;
-(void) updateOrientation: (int)orient;
@end
