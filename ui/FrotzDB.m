#import "FrotzDB.h"
#import "DisplayCell.h"

#import "iosfrotz.h"
#import "StoryMainViewController.h"

#define kLeftMargin                     20.0
#define kTopMargin                      20.0
#define kRightMargin                    20.0
#define kBottomMargin                   20.0
#define kTweenMargin                    10.0

// standard control dimensions, copied from an example
#define kTextFieldHeight                22.0
#define kLabelHeight                    20.0

#define kUIRowHeight                    50.0
#define kUIRowLabelHeight               22.0

#define kFontSizeStr "Font size (%d)"

@implementation FrotzDBController

-(void)donePressed {

}

-(void)viewDidDisappear:(BOOL)animated {
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
    }
    return self;
}

- (void)setDelegate:(id)delegate {
    m_delegate = delegate;
}

- (id)delegate {
    return m_delegate;
}

-(void)viewDidUnload {
    [m_tableView setDelegate: nil];
    m_tableView = nil;
    m_headerLabel = nil;
    m_folderLabel = nil;
    m_textField = nil;
}

- (void)dealloc
{
    [m_tableView setDelegate:nil];
    m_tableView = nil;
    m_headerLabel = nil;
    m_folderLabel = nil;
    m_textField = nil;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return gLargeScreenDevice ? YES : interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (void)loadView
{
    CGRect frame = CGRectMake(0, 0, 240, 200);
    //[[UIScreen mainScreen] applicationFrame];

    m_tableView = [[UITableView alloc] initWithFrame:frame style:UITableViewStyleGrouped];	
    m_tableView.delegate = self;
    m_tableView.dataSource = self;
    m_tableView.autoresizesSubviews = YES;
    
    m_tableView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleBottomMargin |
            UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
//    m_tableView.backgroundColor = [UIColor darkGrayColor];
    m_tableView.scrollEnabled = YES;

    self.view = m_tableView;

    CGRect tframe = CGRectMake(0.0, 0.0, 140, kTextFieldHeight);
    m_textField = [[UITextField alloc] initWithFrame:tframe];
    [m_textField addTarget:self action:@selector(switchAction:) forControlEvents:UIControlEventValueChanged];
    m_textField.enablesReturnKeyAutomatically = YES;
    m_textField.autocorrectionType = UITextAutocorrectionTypeNo;
    m_textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    m_textField.text = [(StoryMainViewController*)m_delegate dbTopPath];
    m_textField.textAlignment = UITextAlignmentCenter;
    m_textField.placeholder = @"/Frotz";
    m_textField.delegate = self;
    
}

- (BOOL)textFieldShouldBeginEditing:(UITextField*)textField {
    if (!gLargeScreenDevice)
        [self.tableView setContentOffset:CGPointMake(0, 125) animated:YES];

    return YES;
}

-(BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField.text.length < 2)
	return NO;
    [m_textField resignFirstResponder];
    if (!gLargeScreenDevice)
        [self.tableView setContentOffset:CGPointZero animated:YES];
    return YES;
}

-(BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    if (range.location==0 && ![string hasPrefix: @"/"])
        return NO;
    
    if (range.location > 0 && [[textField.text substringWithRange:NSMakeRange(range.location-1, 1)] isEqualToString: @"/"] && [string hasPrefix: @"/"])
        return NO;
    return YES;
}

-(BOOL)textFieldShouldEndEditing:(UITextField *)textField {
    return YES;
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (m_isUnlinking) {
        m_isUnlinking = NO;

        if (buttonIndex == 1) {
            [[DBSession sharedSession] unlinkAll];
            [[self tableView] reloadData];
        }
        } else { // change DB folder
            StoryMainViewController *smvc = (StoryMainViewController*)m_delegate;
            if (buttonIndex == 1) {
                if (![[smvc dbTopPath] isEqualToString: m_textField.text]) {
                [smvc setDBTopPath: m_textField.text];		
                }
        } 
        m_textField.text = [smvc dbTopPath];
    }
}

-(void)textFieldDidEndEditing:(UITextField *)textField {
    NSString *newFolder = [textField text];
    StoryMainViewController *smvc = (StoryMainViewController*)m_delegate;
    if (![newFolder isEqualToString: [smvc dbTopPath]]) {
	if ([newFolder hasSuffix: @"/"])
	    m_textField.text = [newFolder substringToIndex: [newFolder length]-1];
	if ([smvc dbIsActive]) {
	    if (![[DBSession sharedSession] isLinked]) {
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Must link account to change Sync Folder"
					    message: @"You have previously synched with a different Dropbox folder. You must relink "
					    "your account before changing folders so the change can take effect."
					    delegate:self cancelButtonTitle:@"OK" otherButtonTitles:  nil];
		[alert show];
		textField.text = [smvc dbTopPath];
	    } else {
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Change Dropbox Sync Folder?"
					    message: @"Any Frotz files previously synched with Dropbox will be moved to the new location."
					    delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles: @"Change", nil];
		[alert show];
	    }
	} else{
	    [smvc setDBTopPath: m_textField.text];		
	    m_textField.text = [smvc dbTopPath];
	}
    }
    [m_textField resignFirstResponder];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    m_hasAppeared = YES;
}

-(void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [m_textField resignFirstResponder];
    m_hasAppeared = NO;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    m_tableView.delegate = self;
    m_tableView.dataSource = self;

    self.title = NSLocalizedString(@"Dropbox Settings", @"");
    
    [m_tableView reloadData];
}

#pragma mark - UITableView delegates

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
	return UITableViewCellEditingStyleNone;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (CGFloat)tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section {
    if (section == 0)
	return 130;
    return 32;
}

- (UIView*)tableView:(UITableView*)tableView viewForHeaderInSection:(NSInteger)section {
    if (section == 0) {

	if (!m_headerLabel) {
	    m_headerLabel = [UILabel new];
	    m_headerLabel.backgroundColor = [UIColor clearColor];
	    m_headerLabel.textColor = [UIColor darkGrayColor];
	    m_headerLabel.font = [UIFont boldSystemFontOfSize:15];
	    m_headerLabel.textAlignment = UITextAlignmentCenter;
	    m_headerLabel.lineBreakMode = UILineBreakModeWordWrap;
	    m_headerLabel.text = 
		[NSString stringWithFormat: @"%@  This will automatically\n"
		 "synchronize saved game files with your\n"
		 "Dropbox so you can easily share them \n"
		 "between multiple devices.",
         [[DBSession sharedSession] isLinked] ? 
         @"Frotz is currently linked to your Dropbox\naccount.":
         @"If you have a Dropbox account, you can\nlink it to Frotz."];
	    m_headerLabel.numberOfLines = 0;
	}
	return m_headerLabel;
    } else {
	if (!m_folderLabel) {
	    m_folderLabel = [UILabel new];
	    m_folderLabel.backgroundColor = [UIColor clearColor];
	    m_folderLabel.textColor = [UIColor darkGrayColor];
	    m_folderLabel.font = [UIFont boldSystemFontOfSize:15];
    	    m_folderLabel.textAlignment = UITextAlignmentCenter;
	    m_folderLabel.text = @"Dropbox folder for Frotz files";
	}
	return m_folderLabel;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSString *title = nil;;
    switch (section)
    {
	case 0:
	default:
	    break;
	case 1:
	    title = @"Dropbox folder for Frotz files";
	    break;
    }
    return title;
}


- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0)
	return 2;
    else
	return 1;
}

// to determine specific row height for each cell, override this.  In this example, each row is determined
// buy the its subviews that are embedded.
//
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return kUIRowHeight;
}

// utility routine leveraged by 'cellForRowAtIndexPath' to determine which UITableViewCell to be used on a given row
//
- (DisplayCell *)obtainTableCellForRow:(NSInteger)row
{
    DisplayCell *cell = nil;

    cell = (DisplayCell*)[m_tableView dequeueReusableCellWithIdentifier:kDisplayCell_ID];
	
    if (cell == nil) {
        cell = [[DisplayCell alloc] initWithFrame:CGRectZero reuseIdentifier:kDisplayCell_ID];
    }
    cell.textAlignment = UITextAlignmentLeft;
    cell.textLabel.text = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.nameLabel.text = nil;
    [cell setView: nil];

    return cell;
}

// to determine which UITableViewCell to be used on a given row.
//
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSInteger row = [indexPath row];
    DisplayCell *cell = [self obtainTableCellForRow:row];
    cell.accessoryType = UITableViewCellAccessoryNone;
    BOOL isLinked = [[DBSession sharedSession] isLinked];
    switch (indexPath.section)
    {
	case 0:
        {
            if (row == 0) {
                cell.textLabel.text = isLinked ? @"Relink to Dropbox Account..." : @"Link to Dropbox Account...";
            }
            else if (row == 1) {
            cell.textLabel.text = @"Unlink Account";
            cell.textLabel.enabled = isLinked;		
            }
            break;
        }
	case 1:
        {
            cell.nameLabel.text = @"Sync Folder";
            cell.view = m_textField;
            break;
        }
    }
    
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{   
    NSInteger section = indexPath.section, row = indexPath.row;

    switch (section)  {
	case 0: {
	    [m_textField resignFirstResponder];
	    switch (row) {
		case 0: {
            [[DBSession sharedSession] linkFromController:self];
#if 0
		    DBLoginController *dbController = [[DBLoginController new] autorelease];
		    dbController.delegate = m_delegate;
		    [dbController presentFromController:self];
		    dbController.navigationController.navigationBar.barStyle = UIBarStyleBlack;
#endif
		    break;
		    }
		case 1: {
		    if ([[DBSession sharedSession] isLinked]) {
                m_isUnlinking = YES;
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Unlink Account"
                        message: @"Do you want to unlink your Dropbox account from Frotz?  Game files will no longer be automatically synchronized."
                        delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles: @"Unlink", nil];
                [alert show];
		    }
		    break;
		}
	    break;
	    }
	}
    }
}

@end

