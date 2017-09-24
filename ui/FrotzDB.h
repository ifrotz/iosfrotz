
#import <UIKit/UIKit.h>

#define UseNewDropBoxSDKByDefault 0

#ifdef COCOAPODS
#define UseNewDropBoxSDK UseNewDropBoxSDKByDefault
#else
#define UseNewDropBoxSDK 0 // always off if build w/o CocoaPod installed
#endif

#if UseNewDropBoxSDK
#import <ObjectiveDropboxOfficial/ObjectiveDropboxOfficial.h>
#else
#import <DropboxSDK/DropboxSDK.h> // old SDK
#endif

@interface FrotzDBController : UITableViewController <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>
{
    UITableView	*m_tableView;
    UILabel	*m_headerLabel, *m_folderLabel;

    UITextField *m_textField;
    
    id __weak m_delegate;
    BOOL m_hasAppeared;
    BOOL m_isUnlinking;
}

- (instancetype)init;
- (void)donePressed;
- (BOOL)isLinked;
@property (nonatomic, weak) id delegate;
@end

