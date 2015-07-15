
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
-(BOOL)isCompletionEnabled;
-(void)setCompletionEnabled:(BOOL)on;
-(BOOL)canEditStoryInfo;
-(void)setCanEditStoryInfo: (BOOL)on;
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
    FontPicker	*m_fontPicker;
    FrotzDBController *m_frotzDB;
    
    BOOL	m_settingsShown, m_subPagePushed;
    BOOL	m_resetting;

    NSObject<FrotzSettingsInfoDelegate> *m_infoDelegate;
    NSObject<FrotzSettingsStoryDelegate, FrotzFontDelegate>	*m_storyDelegate;
    
    NSInteger m_selectedRow, m_selectedSection;

    UISwitch		    *m_switchCtl, *m_switchCtl2;
    UISlider		    *m_sliderCtl;    
    UITableViewCell	    *m_fontSizeCell;
    
    int m_origFontSize, m_newFontSize;
}
- (instancetype)init;
@property (nonatomic, readonly) BOOL settingsActive;
@property (nonatomic, strong) id<FrotzSettingsInfoDelegate> infoDelegate;
@property (nonatomic, strong) id<FrotzSettingsStoryDelegate,FrotzFontDelegate> storyDelegate;
@property (nonatomic, readonly, copy) NSString *rootPath;
- (void)donePressed;
- (void)colorPicker:(ColorPicker*)picker selectedColor:(UIColor*)color;
@property (nonatomic, readonly, copy) UIFont *fontForColorDemo;
- (void)updateAccessibility;

@end

