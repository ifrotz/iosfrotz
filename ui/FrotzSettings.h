
#import <UIKit/UIKit.h>
#import "GettingStarted.h"
#import "AboutFrotz.h"
#import "ReleaseNotes.h"
#import "ColorPicker.h"
#import "FontPicker.h"
#import "FrotzDB.h"

@class StoryBrowser;

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
@property (nonatomic, getter=isCompletionEnabled) BOOL completionEnabled;
@property (nonatomic) BOOL canEditStoryInfo;
-(void)savePrefs;
-(StoryBrowser*)storyBrowser;
@end

@class FileTransferInfo;

@interface FrotzSettingsController : UITableViewController <UITableViewDelegate, UITableViewDataSource, ColorPickerDelegate>
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
    UITableViewCell	    *m_storyFontSizeCell, *m_notesFontSizeCell;

    int m_origStoryFontSize, m_newStoryFontSize;
    int m_origNotesFontSize, m_newNotesFontSize;
}
- (instancetype)init;
@property (nonatomic, strong) id<FrotzSettingsInfoDelegate> infoDelegate;
@property (nonatomic, strong) id<FrotzSettingsStoryDelegate,FrotzFontDelegate> storyDelegate;
@property (nonatomic, strong) id<FrotzFontDelegate> notesDelegate;
@property (nonatomic, readonly, copy) NSString *rootPath;
- (void)donePressed;
- (void)colorPicker:(ColorPicker*)picker selectedColor:(UIColor*)color;
@property (nonatomic, readonly, copy) UIFont *fontForColorDemo;
- (void)updateAccessibility;

@end

