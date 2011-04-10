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

#import <UIKit/UIKit.h>
#import "StoryMainViewController.h"
#import "StoryWebBrowserController.h"
#import "FrotzSettings.h"

#define kBundledZIPFile  "bundle/bundled.zip"
#define kBundledFileList "bundle/bundled.txt"

@class StoryDetailsController;

@interface StoryInfo : NSObject {
    NSString *path;
}
-(id)initWithPath:(NSString*)storyPath;
-(BOOL)isEqual:(id)object;
-(void)dealloc;

@property(nonatomic,copy) NSString *path;
@end

@interface StoryBrowser : UITableViewController <UIActionSheetDelegate, UISplitViewControllerDelegate, UIPopoverControllerDelegate> {
    NSMutableArray *m_paths;

    int m_numStories;
    NSMutableArray *m_storyNames;
    NSMutableArray *m_recents;
    NSMutableArray *m_unsupportedNames;

    StoryMainViewController<FrotzFontDelegate> *m_storyMainViewController;
    StoryWebBrowserController *m_webBrowserController;
    StoryDetailsController *m_details;
    FrotzInfo *m_frotzInfoController;
    FrotzSettingsController *m_settings;

    UIView *m_navTitleView;

    UIView *m_background;
    UITableView *m_tableView;

    UIBarButtonItem *m_editButtonItem;
    UIBarButtonItem *m_nowPlayingButtonItem;
    UIButton *m_nowPlayingButtonView;

    NSMutableDictionary *m_metaDict;
    NSMutableDictionary *m_storyInfoDict;

    NSString *m_launchPath;
    UIImage *m_defaultThumb;
    BOOL m_isDeleting;
    BOOL m_lowMemory;
    BOOL m_postLaunch;
    
    UIPopoverController *m_popoverController;
    UIBarButtonItem *m_popoverBarButton;
}
- (id)init;
- (void)setLaunchPath:(NSString*)path;
- (NSString*)launchPath;
- (UIView *)navTitleView;
- (NSMutableArray*)storyNames;
- (BOOL)storyIsInstalled:(NSString*)story;
- (NSString*)canonicalStoryName:(NSString*)story;
- (NSMutableArray*)unsupportedStoryNames;
- (void)addRecentStoryInfo:(StoryInfo*)storyInfo;
- (void)addRecentStory:(NSString*)storyInfo;
- (void)addPath: (NSString *)path;
- (BOOL)lowMemory;
- (void)refresh;
- (void)reloadData;
- (void)updateNavButton;
- (UIBarButtonItem*)nowPlayingNavItem;
- (StoryMainViewController*)storyMainViewController;
- (FrotzInfo*)frotzInfoController;
- (FrotzSettingsController*)settings;
- (StoryDetailsController*)detailsController;
- (void)refreshDetails;
- (void)setStoryDetails:(StoryInfo*)storyInfo;
- (void)showStoryDetails:(StoryInfo*)storyInfo;
- (void)showMainStoryController;
- (void)autoRestoreAndShowMainStoryController;
- (void)didPressModalStoryListButton;
- (void)hidePopover;
- (void)addTitle: (NSString*)fullName forStory:(NSString*)story;
- (void)addAuthors: (NSString*)authors forStory:(NSString*)story;
- (void)addTUID: (NSString*)tuid forStory:(NSString*)story;
- (void)addDescript: (NSString*)descript forStory:(NSString*)story;
- (BOOL)canEditStoryInfo;
- (NSString*)fullTitleForStory:(NSString*)story;
- (NSString*)tuidForStory:(NSString*)story;
- (NSString*)authorsForStory:(NSString*)story;
- (NSString*)descriptForStory:(NSString*)story;
- (NSData*)thumbDataForStory:(NSString*)story;
- (void)addThumbData: (NSData*)imageData forStory:(NSString*)story;
- (void)addSplashData: (NSData*)imageData forStory:(NSString*)story;
- (NSData*)splashDataForStory: (NSString*)story;
-(void)removeSplashDataForStory: (NSString*)story;
- (NSString*)splashPathForStory:(NSString*)story;
- (void)hideStory: (NSString*)story withState:(BOOL)hide;
- (void)unHideAll;
- (BOOL)isHidden: (NSString*)story;
- (NSString*)getNotesForStory:(NSString*)story;
- (void)saveNotes:(NSString*)notesText forStory:(NSString*)story;
- (void)saveRecents;
- (void)saveStoryInfoDict;
- (void)saveMetaData;
- (NSString*)mapInfocom83Filename:(NSString*)story;
- (void)launchStory: (NSString*)storyPath;
- (void)launchStoryInfo:(StoryInfo*)storyInfo;
- (void)resumeStory;
- (NSString*)resourceGamePath;
- (NSString*)currentStory;
- (void)launchBrowserWithURL:(NSString*)url;
- (void)launchBrowser;
- (NSInteger)numberOfSectionsInTableView: (UITableView*)tableView;
- (int)indexRowFromStoryInfo:(StoryInfo*)recentStory;
- (int)recentRowFromStoryInfo:(StoryInfo*)storyInfo;
- (NSString*)tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section;
- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section;
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath;
- (StoryInfo *)storyInfoForIndexPath:(NSIndexPath*)indexPath;
- (NSString *)storyForIndexPath:(NSIndexPath*)indexPath;
- (void)storyInfoChanged;
- (void)updateAccessibility;

@property(nonatomic,retain) UIPopoverController *popoverController;
@property(nonatomic,retain) UIBarButtonItem *popoverBarButton;

@end

extern NSString *storyGamePath;
