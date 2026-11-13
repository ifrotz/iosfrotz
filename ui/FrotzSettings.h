
#import <UIKit/UIKit.h>
#import "GettingStarted.h"
#import "AboutFrotz.h"
#import "ReleaseNotes.h"
#import "ColorPicker.h"
#import "FontPicker.h"
#import "FrotzDB.h"
#import "iosfrotz.h"

@class StoryBrowser;

#if EnableStoryDictation
// Range of the "Dictation Delay" setting, the quiet time before what was said is sent as a command:
// short enough to feel responsive at one end, long enough at the other for someone who pauses
// mid-command. The slider's bounds, and what a loaded preference is clamped to.
#define kDictationDelayMin 0.5
#define kDictationDelayMax 3.0
#endif

@protocol FrotzSettingsInfoDelegate <NSObject>
-(void)dismissInfo;
@end

@protocol FrotzSettingsStoryDelegate <NSObject,FrotzFontDelegate>
-(void)resetSettingsToDefault;
-(void)setBackgroundColor:(UIColor*)color makeDefault:(BOOL)makeDefault;
-(void)setTextColor:(UIColor*)color makeDefault:(BOOL)makeDefault;
-(UIColor*)backgroundColor;
-(UIColor*)textColor;
-(NSString*)rootPath;
@property (nonatomic, readwrite, getter=isCompletionEnabled) BOOL completionEnabled;
@property (nonatomic, readwrite) BOOL canEditStoryInfo;
#if EnableStoryDictation
@property (nonatomic, readwrite, getter=isDictationEnabled) BOOL dictationEnabled;
@property (nonatomic, readwrite) NSTimeInterval dictationCommitDelay; // seconds, within kDictationDelayMin...Max
@property (nonatomic, readwrite) BOOL dictationListensDuringVoiceOver; // "Listen During VoiceOver"; row shown only while VoiceOver runs
#endif
#if EnableCloudSaveSync
@property (nonatomic, readwrite) BOOL cloudSaveSyncEnabled; // "Sync Saves with iCloud"
#endif
#if UseDropBoxSDK
@property (nonatomic, readwrite) BOOL dropboxSyncEnabled; // "Sync Saves with Dropbox"
#endif
-(void)savePrefs;
-(StoryBrowser*)storyBrowser;
@end

@class FileTransferInfo;

@interface FrotzSettingsController : UITableViewController <UITableViewDelegate, UITableViewDataSource, ColorPickerDelegate, UIAdaptivePresentationControllerDelegate>
{
    UITableView	    *m_tableView;
    
    GettingStarted  *m_gettingStarted;
    AboutFrotz	*m_aboutFrotz;
    ReleaseNotes *m_releaseNotes;
    FileTransferInfo *m_fileTransferInfo;

    ColorPicker	*m_colorPicker;
    FrotzFontPickerController *m_storyFontPicker;
    FrotzFontPickerController *m_notesFontPicker;
    FrotzDBController *m_frotzDB;

    BOOL	m_resetting;

    NSObject<FrotzSettingsInfoDelegate> *m_infoDelegate;
    NSObject<FrotzSettingsStoryDelegate, FrotzFontDelegate>	*m_storyDelegate;
    NSObject<FrotzFontDelegate>    *m_notesDelegate;

    NSInteger m_selectedRow, m_selectedSection;

    UISwitch		    *m_switchCtl, *m_switchCtl2;
    UISlider		    *m_storyFontSliderCtl, *m_notesFontSliderCtl;
    UITableViewCell     *m_storyFontCell, *m_notesFontCell;
    UITableViewCell	    *m_storyFontSizeCell, *m_notesFontSizeCell;
#if EnableStoryDictation
    UISwitch            *m_dictationSwitchCtl, *m_dictationVoiceOverSwitchCtl;
    UISlider            *m_dictationDelaySliderCtl;
    UITableViewCell     *m_dictationDelayCell;
#endif
#if EnableCloudSaveSync
    UISwitch            *m_cloudSyncSwitchCtl;
#endif
#if UseDropBoxSDK
    UISwitch            *m_dropboxSyncSwitchCtl;
#endif

    int m_origStoryFontSize, m_newStoryFontSize;
    int m_origNotesFontSize, m_newNotesFontSize;
}
- (instancetype)init;
- (void)showGettingStarted; // pushes the Getting Started page; for links to it from the other info pages
@property (nonatomic, strong) id<FrotzSettingsInfoDelegate> infoDelegate;
@property (nonatomic, strong) id<FrotzSettingsStoryDelegate,FrotzFontDelegate> storyDelegate;
@property (nonatomic, strong) id<FrotzFontDelegate> notesDelegate;
@property (nonatomic, readonly, copy) NSString *rootPath;
- (void)donePressed;
- (void)colorPicker:(ColorPicker*)picker selectedColor:(UIColor*)color;
@property (nonatomic, readonly, copy) UIFont *fontForColorDemo;
- (void)updateAccessibility;

@end

