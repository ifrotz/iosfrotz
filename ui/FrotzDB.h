
#import <UIKit/UIKit.h>
#import <DropboxSDK/DropboxSDK.h> // old SDK

#ifdef COCOAPODS
#define UseNewDropBoxSDK 1
#import <ObjectiveDropboxOfficial/ObjectiveDropboxOfficial.h> // new SDK
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
@property (nonatomic, weak) id delegate;
@end

