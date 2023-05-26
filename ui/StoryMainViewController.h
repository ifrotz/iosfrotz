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
#import "TransitionView.h"
#import "FrotzInfo.h"
#import "InputHelper.h"
#import "FrotzWordPicker.h"
#import "FileBrowser.h"
#import "NotesViewController.h"

@class StoryBrowser;
@class FrotzView;

#import "RichTextView.h"
#import "TextViewExt.h"

NS_ASSUME_NONNULL_BEGIN

enum { kIPZDisableInput = 0, kIPZRequestInput = 1, kIPZNoEcho = 2, kIPZAllowInput = 4 };
/* !!! Move these to state variables in StoryMainViewController! */
extern int ipzAllowInput;
extern int lastVisibleYPos[];
extern BOOL cursorVisible;

void iosif_clear_input(NSString *__nullable initStr);
void iosif_feed_input(NSString *str);
void iosif_feed_input_line(NSString *str);

@protocol InputHelperDelegate <NSObject>
-(void)hideInputHelper;
-(BOOL)inputHelperShown;
-(UIView*) inputHelperView;
@end

@class StoryView, StatusLine, StoryInputLine;

extern StoryView *theStoryView;
extern StatusLine *theStatusLine;
extern StoryInputLine *theInputLine;
extern StoryBrowser *theStoryBrowser;

@interface StoryMainViewController : UIViewController <UITextViewDelegate, UITextFieldDelegate,
    UIActionSheetDelegate, TransitionViewDelegate, KeyboardOwner, FrotzSettingsStoryDelegate,
    InputHelperDelegate, UIScrollViewDelegate, RTSelected, FileSelected, TextFileBrowser,
    LockableKeyboard>
{
    StoryView *m_storyView;
    StatusLine *m_statusLine;
    StoryInputLine *m_inputLine;

    NSMutableArray *m_glkViews;

    UIView *m_background;
    UIBarButtonItem *m_kbdToggleItem;
    UIImageView *m_splashImageView;
    NotesViewController *m_notesController;
    
    StoryBrowser *m_storyBrowser;
    FrotzInfo *m_frotzInfoController;
   
    NSMutableString *m_currentStory;    
    NSString *m_fontname;
    NSInteger m_fontSize;
    CGFloat topWinSize;
    
    UIColor *m_defaultBGColor;
    UIColor *m_defaultFGColor;

    NSString *frotzPrefsPath;
    NSString *storyGamePath;
    NSString *docPath;
    NSString *resourceGamePath;
    NSString *storyTopSavePath;
    NSString *storySavePath;
    NSString *storySIPPathOld;
    NSString *storySIPPath;
    NSString *storySIPSavePath;
    NSString *activeStoryPath;

    NSDictionary *m_autoRestoreDict;
    pthread_t m_storyTID;
    BOOL m_kbShown;
    BOOL m_landscape;
    UIInterfaceOrientation m_lastOrientation;
    BOOL m_completionEnabled;
    BOOL m_canEditStoryInfo;
    BOOL m_autoRestoreEnabled;
    BOOL m_kbLocked;
    BOOL m_ignoreWordSelection;

    NSInteger m_statusFixedFontSize;
    CGFloat m_statusFixedFontWidth;
    NSInteger m_statusFixedFontPixelHeight;
    CGPoint m_cursorOffset;
    CGSize m_kbdSize;
    NSTimeInterval m_animDuration;
    NSString *m_launchMessage;

    NSMutableDictionary *m_dbCachedMetadata;
    NSString *m_dbTopPath;
    BOOL m_dbActive;
}

@property (nonatomic, strong) UINavigationController* storyNavController;
@property (nonatomic, strong) StoryBrowser *storyBrowser;
@property (nonatomic, readonly, copy) NSString *storyGamePath;
@property (nonatomic, readonly, copy) NSString *resourceGamePath;
@property (nonatomic, readonly, copy) NSString *rootPath;
-(NSString*)pathToAppRelativePath:(NSString*)path;
-(NSString*)relativePathToAppAbsolutePath:(NSString*)path;
@property (nonatomic, getter=isKBShown, readonly) BOOL KBShown;
@property (nonatomic, getter=isKBLocked, readonly) BOOL KBLocked;
-(void) showKeyboardLockStateInView:(UIView*)kbdToggleItemView;
-(void) showKeyboardLockState;
-(void) addKeyBoardLockGesture;
-(instancetype) init NS_DESIGNATED_INITIALIZER;
-(instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
-(instancetype)initWithCoder:(NSCoder *)aDecoder NS_UNAVAILABLE;
-(void) loadView;
@property (nonatomic, readonly, strong) StoryView *storyView;
@property (nullable, nonatomic, copy) NSString *currentStory;
-(void) hideNotes;
@property (nonatomic, getter=isCompletionEnabled) BOOL completionEnabled;
@property (nonatomic) BOOL canEditStoryInfo;
- (void) activateKeyboard;
- (void) toggleKeyboard;
- (void) forceToggleKeyboard;
@property (nonatomic, readonly, strong) id dismissKeyboard;
- (void) setIgnoreWordSelection:(BOOL)ignore;
- (void) abortToBrowser;
- (void)autosize;
-(void) resizeStatusWindow;
-(void) launchStory;
-(void) abandonStory:(BOOL)deleteAutoSave;
-(void) forceAbandonStory;
-(void) rememberActiveStory;
-(BOOL) willAutoRestoreSession:(BOOL)isFirstLaunch;
@property (nonatomic, readonly) BOOL autoRestoreSession;
-(void) suspendStory;
-(void) autoSaveStory;
@property (nonatomic, readonly) BOOL possibleUnsavedProgress;
-(void) savePrefs;
-(void) loadPrefs;
@property (nonatomic, getter=isLandscape) BOOL landscape;
-(void) setFont: (nullable NSString*)font withSize:(NSInteger)size;
//@property (nonatomic, readonly, copy) NSString *font;
-(void) setFixedFont: (NSString*)font;
-(NSMutableString*) fixedFont;
@property (nonatomic, readonly) NSInteger fontSize;
-(void) setBackgroundColor: (UIColor*)color makeDefault:(BOOL)makeDefault;
-(void) setTextColor: (UIColor*)color makeDefault:(BOOL)makeDefault;
@property (nonatomic, readonly, copy) UIColor *backgroundColor;
@property (nonatomic, readonly, copy) UIColor *textColor;
@property (nonatomic, readonly) CGRect storyViewFullFrame;
-(void) scrollStoryViewToEnd;
-(void) scrollStoryViewToEnd:(BOOL)animated;
-(BOOL) scrollStoryViewOnePage:(FrotzView*)view fraction:(float)fraction;
-(BOOL) scrollStoryViewUpOnePage:(FrotzView*)view fraction:(float)fraction;
-(void) updateStatusLine:(RichTextView*)sl;
-(void) printText: (nullable id)unused;

-(void)reloadImages;
-(void)clearGlkViews;
-(void)newGlkViewWithWin:(NSValue*)winVal;
-(void)resizeGlkView:(NSArray*)arg;
-(void)destroyGlkView:(NSNumber*)arg;
-(void)drawGlkImage:(NSValue*)argsVal;
-(void)drawGlkRect:(NSValue*)argsVal;
-(void)updateGlkWin:(NSNumber*)viewNum;
-(void)focusGlkView:(UIView*)view;
-(FrotzView*)glkView:(int)viewNum;
-(BOOL)glkViewTypeIsGrid:(int)viewNum;
-(BOOL)tapInView:(UIView*)view atPoint:(CGPoint)pt;
-(void)enableTaps:(NSNumber*)viewNum;
-(void)disableTaps:(NSNumber*)viewNum;

-(void) setupFadeWithDuration:(CFTimeInterval)duration;
@property (nonatomic, readonly, strong) StoryInputLine *inputLine;
-(void) resetSettingsToDefault;
-(void) hideInputHelper;
@property (nonatomic, readonly) BOOL inputHelperShown;
@property (nonatomic, readonly, strong) UIView *inputHelperView;
-(void) openFileBrowser:(FileBrowserState)dialogType;
-(void) openFileBrowserWrap:(NSNumber*)dialogType;
@property (nonatomic, readonly, copy) NSString *currentStorySavePath;
@property (nonatomic, readonly, copy) NSString *textFileBrowserPath;
-(void)checkAccessibility;
-(void) keyboardDidShow:(NSNotification*)notif;
-(void) keyboardDidHide:(NSNotification*)notif;
@property (nonatomic, readonly) CGSize keyboardSize;
@property (nonatomic, readonly, strong) NotesViewController<FrotzFontDelegate> *notesController;
@property (nonatomic, readonly) BOOL splashVisible;
-(void) textSelected:(NSString*)text animDuration:(CGFloat)duration hilightView:(UIView <WordSelection>*)view;
-(void) textFieldFakeDidEndEditing:(UITextField *)textField;
-(void) rememberLastContentOffsetAndAutoSave:(UIScrollView*)textView;
@property (nonatomic, readonly) NSInteger statusFixedFontPixelWidth;
@property (nonatomic, readonly) NSInteger statusFixedFontPixelHeight;
-(void) updateAutosavePaths;
-(BOOL) autoSaveExistsForStory:(NSString*)storyPath;
-(void) deleteAutoSaveForStory:(NSString*)storyPath;
-(NSString*) saveSubFolderForStory:(NSString*)storyPath;
-(void) setLaunchMessage:(NSString*)msg clear:(BOOL)clear;
-(void) displayLaunchMessageWithDelay: (CGFloat)delay duration:(CGFloat)duration alpha:(CGFloat)alpha;
@property (nonatomic, readonly) CGPoint cursorOffset;
-(NSString*) completeWord:(NSString*)word prevString:(NSString*)prevString isAmbiguous:(BOOL*)isAmbiguous;
-(NSMutableString*) convertHTML:(NSString*)htmlString;

// Dropbox API
-(void)initializeDropbox;
-(void)saveDBCacheDict;
@property (nonatomic, readonly, copy) NSString *dbTopPath;
@property (nonatomic, readonly, copy) NSString *dbTopPathT;
@property (nonatomic, readonly, copy) NSString *dbGamePath;
@property (nonatomic, readonly, copy) NSString *dbSavePath;
@property (nonatomic, readonly) BOOL dbIsActive;
-(void)setDBTopPath:(NSString*)path;
-(NSString*)metadataSubPath:(NSString*)path;
-(void)dropboxDidLinkAccount;

#if UseDropBoxSDK
-(NSDate*)getCachedTimestampForSaveFile:(NSString*)saveFile;
-(void)cacheTimestamp:(nullable NSDate*)timeStamp forSaveFile:(NSString*)saveFile;

-(void)dbUploadSaveGameFile:(NSString*)saveGameSubPath;
-(void)dbDownloadSaveGameFile:(NSString*)saveGameSubPath;
-(void)dbRefreshFolder:(NSString*)folder createIfNotExists:(BOOL)createIfNotExists;
-(void)dbSyncSingleSaveDir:(DBFILESMetadata*)folderResult withEntries:(NSArray<DBFILESMetadata *>*)metadata;
-(void)handleDropboxError:(NSObject*)routeError withRequestError:(DBRequestError*)error;
#endif
@end

#if UseDropBoxSDK
@interface DBFILESMetadata (MySort)
-(NSComparisonResult)caseInsensitiveCompare:(DBFILESMetadata*)other;
@end
#endif

NS_ASSUME_NONNULL_END
