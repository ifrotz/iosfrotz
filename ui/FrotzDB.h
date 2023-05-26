
#import <UIKit/UIKit.h>

#ifdef COCOAPODS
#define UseDropBoxSDK 1
#else
#define UseDropBoxSDK 0 // always off in build w/o CocoaPod installed
#endif

#if UseDropBoxSDK
#import <ObjectiveDropboxOfficial/ObjectiveDropboxOfficial.h>
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

