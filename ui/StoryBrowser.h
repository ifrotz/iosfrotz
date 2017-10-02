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
@class StoryBrowser;

NS_ASSUME_NONNULL_BEGIN

@interface StoryInfo : NSObject {
    NSString *path;
}
-(instancetype)initWithPath:(NSString*)storyPath browser:(StoryBrowser*)browser NS_DESIGNATED_INITIALIZER;
-(instancetype)init NS_UNAVAILABLE;
-(BOOL)isEqual:(id)object;
@property (nonatomic, readonly, copy) NSString *title;

@property(nonatomic,copy) NSString *path;
@property(nonatomic,weak,nullable) StoryBrowser *browser;
@end

@interface StoryBrowser : UITableViewController <UIActionSheetDelegate, UISplitViewControllerDelegate, UIPopoverControllerDelegate,UISearchBarDelegate, UISearchDisplayDelegate, UITableViewDataSource, UITableViewDelegate> {
    NSMutableArray *m_paths;

    int m_numStories;
    NSMutableArray *m_storyNames;
    NSMutableArray *m_recents;
    NSMutableArray *m_unsupportedNames;
    
    NSArray *m_filteredNames;

    StoryMainViewController<FrotzFontDelegate> *m_storyMainViewController;
    StoryWebBrowserController *m_webBrowserController;
    StoryDetailsController *m_details;
    FrotzInfo *m_frotzInfoController;
    FrotzSettingsController *m_settings;

    UISearchDisplayController *m_searchDisplayController;

    UIView *m_navTitleView;

    UIView *m_background;
    UITableView *m_tableView;

    UIBarButtonItem *m_editButtonItem;
    UIBarButtonItem *m_nowPlayingButtonItem;

    NSMutableDictionary *m_metaDict;
    NSMutableDictionary *m_storyInfoDict;

    NSString *m_launchPath;
    UIImage *m_defaultThumb;
    BOOL m_isDeleting;
    BOOL m_lowMemory;
    BOOL m_postLaunch;
}
- (instancetype)init;
@property (nonatomic, copy) NSString *launchPath;
@property (nonatomic, readonly, strong) UIView *navTitleView;
@property (nonatomic, readonly, copy) NSArray *storyNames;
- (BOOL)storyIsInstalled:(NSString*)story;
- (nullable NSString*)canonicalStoryName:(NSString*)story;
@property (nonatomic, readonly, copy) NSArray *unsupportedStoryNames;
- (void)addRecentStoryInfo:(StoryInfo*)storyInfo;
- (void)addRecentStory:(NSString*)storyInfo;
- (void)addPath: (NSString *)path;
@property (nonatomic, readonly) BOOL lowMemory;
- (void)refresh;
- (void)reloadData;
- (void)updateNavButton;
@property (nonatomic, readonly, strong, nullable) UIBarButtonItem *nowPlayingNavItem;
@property (nonatomic, readonly, strong) StoryMainViewController *storyMainViewController;
@property (nonatomic, readonly, strong) FrotzInfo *frotzInfoController;
@property (nonatomic, readonly, strong) FrotzSettingsController *settings;
@property (nonatomic, readonly, strong) StoryDetailsController *detailsController;
- (void)setPostLaunch;
- (void)refreshDetails;
- (void)setStoryDetails:(StoryInfo*)storyInfo;
- (void)showStoryDetails:(StoryInfo*)storyInfo;
- (void)showMainStoryController;
- (void)autoRestoreAndShowMainStoryController;
- (void)didPressModalStoryListButton;
- (void)addTitle: (NSString*)fullName forStory:(NSString*)story;
- (void)addAuthors: (NSString*)authors forStory:(NSString*)story;
- (void)addTUID: (NSString*)tuid forStory:(NSString*)story;
- (void)addDescript: (NSString*)descript forStory:(NSString*)story;
@property (nonatomic, readonly) BOOL canEditStoryInfo;
- (NSString*)fullTitleForStory:(NSString*)story;
- (nullable NSString*)customTitleForStory:(NSString*)story storyKey:(NSString*__nonnull*__nullable)storyKey;
- (NSString*)tuidForStory:(NSString*)story;
- (NSString*)authorsForStory:(NSString*)story;
- (NSString*)descriptForStory:(NSString*)story;
- (NSData*)thumbDataForStory:(NSString*)story;
- (void)addThumbData: (NSData*)imageData forStory:(NSString*)story;
- (void)addSplashData: (NSData*)imageData forStory:(NSString*)story;
- (NSData*)splashDataForStory: (NSString*)story;
- (void)removeSplashDataForStory: (NSString*)story;
- (NSString*)splashPathForStory:(NSString*)story;
- (NSString*)cacheSplashPathForBuiltinStory:(NSString*)story;
- (NSString*)userSplashPathForStory:(NSString*)story;
@property (nonatomic, readonly, copy) NSArray *builtinSplashes;
- (void)hideStory: (NSString*)story withState:(BOOL)hide;
- (void)unHideAll;
- (BOOL)isHidden: (NSString*)story;
- (nullable NSString*)getNotesForStory:(NSString*)story;
- (void)saveNotes:(NSString*)notesText forStory:(NSString*)story;
- (void)saveRecents;
- (void)saveStoryInfoDict;
- (void)saveMetaData;
- (NSString*)mapInfocom83Filename:(NSString*)story;
- (void)launchStory: (NSString*)storyPath;
- (void)launchStoryInfo:(StoryInfo*)storyInfo;
- (void)resumeStory;
@property (nonatomic, readonly, copy) NSString *resourceGamePath;
@property (nonatomic, readonly, copy) NSString *currentStory;
- (void)launchBrowserWithURL:(NSString*)url;
- (void)launchBrowser;
- (NSUInteger)indexRowFromStoryInfo:(StoryInfo*)recentStory;
- (NSUInteger)recentRowFromStoryInfo:(StoryInfo*)storyInfo;
- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath;
- (nullable StoryInfo *)storyInfoForIndexPath:(NSIndexPath*)indexPath tableView:(UITableView*)tableView;
- (NSString *)storyForIndexPath:(NSIndexPath*)indexPath tableView:(UITableView*)tableView;
- (void)storyInfoChanged;
- (void)updateAccessibility;

@property(nonatomic,strong) UISearchDisplayController *searchDisplayController;
@end

extern NSString *storyGamePath;

@interface NSString (storyKey)
@property (nonatomic, readonly, copy) NSString *storyKey;
@end

NS_ASSUME_NONNULL_END
