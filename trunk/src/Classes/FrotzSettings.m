#import "FrotzSettings.h"
#import "DisplayCell.h"
#import "FileTransferInfo.h"

#import "iphone_frotz.h"

#define kLeftMargin                     20.0
#define kTopMargin                      20.0
#define kRightMargin                    20.0
#define kBottomMargin                   20.0
#define kTweenMargin                    10.0

// standard control dimensions, copied from an example
#define kStdButtonWidth                 106.0
#define kStdButtonHeight                40.0
#define kSegmentedControlHeight         40.0
#define kSliderHeight                   7.0
#define kSwitchButtonWidth              94.0
#define kSwitchButtonHeight             27.0
#define kTextFieldHeight                30.0
#define kSearchBarHeight                40.0
#define kLabelHeight                    20.0
#define kProgressIndicatorSize          40.0
#define kToolbarHeight                  40.0
#define kUIProgressBarWidth             160.0
#define kUIProgressBarHeight            24.0

// specific font metrics used in text fields and text views
#define kFontName                       @"Arial"
#define kTextFieldFontSize              18.0
#define kTextViewFontSize               18.0

// UITableView row heights
#define kUIRowHeight                    50.0
#define kUIRowLabelHeight               22.0

#define kFontSizeStr "Font size (%d)"

@implementation FrotzSettingsController

enum ControlTableSections
{
    kFrotzInfoSection,
    kFrotzPrefsSection,
//  kFrotzColorsSection,
//  kFrotzFontSection,
    kFrotzResetSection,
    kFrotzNumSections
};

-(void)setupFade {
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:0.5];
	    
    [UIView setAnimationTransition:(UIViewAnimationTransitionFlipFromLeft)
								forView:[[[self view] superview] superview] cache:YES];
    [UIView commitAnimations];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if(m_resetting) {
	NSIndexPath *idx = [[self tableView] indexPathForSelectedRow];
	if (idx)
	    [[self tableView] deselectRowAtIndexPath: idx animated:YES];
	m_resetting = NO;
	if (buttonIndex == 1) {
	    [m_storyDelegate resetSettingsToDefault];
	    m_newFontSize = m_origFontSize = (int)[m_storyDelegate fontSize];
	    m_sliderCtl.value = (float)m_origFontSize;
	    [m_switchCtl setOn: [m_storyDelegate isCompletionEnabled]];
	    [[self tableView] reloadData];
	}
	return;
    }
    // else FTP Alert
    if (buttonIndex == 1) {
	[m_fileTransferInfo stopServer];
	[self donePressed];
    }
}

-(void)updateAccessibility {
    [m_colorPicker updateAccessibility];
}

-(void)donePressed {
    if (m_fileTransferInfo) {
        if ([m_fileTransferInfo serverIsRunning]) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"File server running"
                                                            message: @"The file server will be disabled when you exit settings"
                                                           delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles: @"OK", nil];
            [alert show];
            [alert release];
            return;
        }
    }
    if ([m_tableView superview]) {
        m_selectedSection = m_selectedRow = -1;
    }
    if (m_infoDelegate && [m_infoDelegate respondsToSelector:@selector(dismissInfo)]) {
        if (m_storyDelegate) {
            if (m_newFontSize != m_origFontSize)
                [m_storyDelegate setFont: [m_storyDelegate font] withSize: m_newFontSize];
            [m_storyDelegate savePrefs];
        }
        
        [m_infoDelegate dismissInfo];
    }
    else {
        [self setupFade];
        [[self navigationController] popViewControllerAnimated: NO];
        [UIView commitAnimations];
    }
    
    m_settingsShown = NO;
}

-(void)viewDidDisappear:(BOOL)animated {
    if (!m_subPagePushed)
        m_settingsShown = NO;
    m_subPagePushed = NO;
}

- (id)init
{
    if ((self = [super init]))
    {
        m_colorPicker = [[ColorPicker alloc] init];
        [m_colorPicker setDelegate: self];
        m_fontPicker = [[FontPicker alloc] init];
        m_frotzDB = [[FrotzDBController alloc] init];
        m_releaseNotes = [[ReleaseNotes alloc] init];
    }
    return self;
}

- (void)setInfoDelegate:(id<FrotzSettingsInfoDelegate>)delegate {
    m_infoDelegate = delegate;
}

- (id<FrotzSettingsInfoDelegate>)infoDelegate {
    return m_infoDelegate;
}

- (void)setStoryDelegate:(id<FrotzSettingsStoryDelegate,FrotzFontDelegate>)delegate {
    m_storyDelegate = delegate;
    [m_fontPicker setDelegate: m_storyDelegate];
    [m_frotzDB setDelegate: m_storyDelegate];
}

- (id<FrotzSettingsStoryDelegate, FrotzFontDelegate>)storyDelegate {
    return m_storyDelegate;
}

- (NSString*)rootPath {
    if (m_storyDelegate)
        return [m_storyDelegate rootPath];
    return nil;
}

- (void)dealloc
{
    [m_tableView setDelegate:nil];
    [m_tableView release];
    m_tableView = nil;
    
    [m_gettingStarted release];
    [m_aboutFrotz release];
    [m_releaseNotes release];
    m_gettingStarted = nil;
    m_aboutFrotz = nil;
    m_releaseNotes = nil;
    
    [m_colorPicker release];
    [m_fontPicker release];
    m_colorPicker = nil;
    m_fontPicker = nil;
    
    [m_frotzDB release];
    m_frotzDB = nil;
    
    [super dealloc];
}

- (void)create_UISwitch
{
    CGRect frame = CGRectMake(0.0, 0.0, kSwitchButtonWidth, kSwitchButtonHeight);
    m_switchCtl = [[UISwitch alloc] initWithFrame:frame];
    [m_switchCtl addTarget:self action:@selector(switchAction:) forControlEvents:UIControlEventValueChanged];
    
    // in case the parent view draws with a custom color or gradient, use a transparent color
    m_switchCtl.backgroundColor = [UIColor clearColor];
    [m_switchCtl setOn: [m_storyDelegate isCompletionEnabled]];

    m_switchCtl2 = [[UISwitch alloc] initWithFrame:frame];
    [m_switchCtl2 addTarget:self action:@selector(switchAction:) forControlEvents:UIControlEventValueChanged];
    
    // in case the parent view draws with a custom color or gradient, use a transparent color
    m_switchCtl2.backgroundColor = [UIColor clearColor];
    [m_switchCtl2 setOn: [m_storyDelegate canEditStoryInfo]];
}

- (void)switchAction:(id)sender
{
    if (sender == m_switchCtl)
	[m_storyDelegate setCompletionEnabled: [sender isOn]];
    else if (sender == m_switchCtl2)
	[m_storyDelegate setCanEditStoryInfo: [sender isOn]];
}

- (void)create_UISlider
{
    CGRect frame = CGRectMake(0.0, 0.0, 120.0, kSliderHeight);
    m_sliderCtl = [[UISlider alloc] initWithFrame:frame];
    [m_sliderCtl addTarget:self action:@selector(sliderAction:) forControlEvents:UIControlEventValueChanged];
    
    // in case the parent view draws with a custom color or gradient, use a transparent color
    m_sliderCtl.backgroundColor = [UIColor clearColor];
    
    m_sliderCtl.minimumValue = 8.0;
    m_sliderCtl.maximumValue = 24.0 + (gLargeScreenDevice ? 8.0 : 0.0);
    m_sliderCtl.continuous = YES;
    m_origFontSize = (int)[m_storyDelegate fontSize];
    m_sliderCtl.value = (float)m_origFontSize;
}

- (void)sliderAction:(UISlider*)sender
{
    static int lastValue;
    int value = [sender value];
    
    if (value != lastValue) {
        ((DisplayCell*)m_fontSizeCell).nameLabel.text = [NSString stringWithFormat: @kFontSizeStr, value];
        m_newFontSize = (int)value;
        if (gLargeScreenDevice)
            [m_storyDelegate setFont: [m_storyDelegate font] withSize: value];
    }
    lastValue = value;
}

- (BOOL)settingsActive {
    return m_settingsShown;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return gLargeScreenDevice ? YES : interfaceOrientation == UIInterfaceOrientationPortrait;
}

-(void)viewDidUnload {
    [m_gettingStarted release];
    [m_aboutFrotz release];
    [m_fileTransferInfo release];
    m_gettingStarted = nil;
    m_aboutFrotz = nil;
    m_fileTransferInfo = nil;
    [m_tableView release];
    m_tableView = nil;
}

- (void)loadView
{
    CGRect frame = CGRectMake(0, 0, 240, 200);
    //[[UIScreen mainScreen] applicationFrame];

    m_tableView = [[UITableView alloc] initWithFrame:frame style:UITableViewStyleGrouped];	
    m_tableView.delegate = self;
    m_tableView.dataSource = self;
    m_tableView.autoresizesSubviews = YES;
    self.view = m_tableView;

    m_selectedSection = m_selectedRow = -1;
    
    m_gettingStarted = [[GettingStarted alloc] init];
    m_aboutFrotz = [[AboutFrotz alloc] init];
    if (!m_releaseNotes)
        m_releaseNotes = [[ReleaseNotes alloc] init];
    m_fileTransferInfo = [[FileTransferInfo alloc] initWithController: m_storyDelegate];	
    
    [self create_UISwitch];
    [self create_UISlider];

}

-(void)colorPicker:(ColorPicker*)picker selectedColor:(UIColor*)color {
    if ([picker isTextColorMode])
        [m_storyDelegate setTextColor: color makeDefault:YES];
    else
        [m_storyDelegate setBackgroundColor: color makeDefault:YES];
}	

-(UIFont*)fontForColorDemo {
    return m_storyDelegate ? [UIFont fontWithName:[m_storyDelegate font] size:m_newFontSize] : nil;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    m_tableView.delegate = self;
    m_tableView.dataSource = self;
    m_settingsShown = YES;
    m_subPagePushed = NO;
    if ([self.navigationController.navigationBar respondsToSelector:@selector(setBarTintColor:)]) {
        [self.navigationController.navigationBar setBarStyle: UIBarStyleDefault];
        [self.navigationController.navigationBar  setBarTintColor: [UIColor whiteColor]];
        [self.navigationController.navigationBar  setTintColor:  [UIColor darkGrayColor]];
    }

    [[self.navigationItem backBarButtonItem] setEnabled: NO];
    [[self.navigationItem leftBarButtonItem] setEnabled: NO];
    [self.navigationItem setHidesBackButton: YES animated:YES];
	
    UIBarButtonItem *doneItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem: UIBarButtonSystemItemDone target:self action:@selector(donePressed)];
    self.navigationItem.rightBarButtonItem = doneItem;
    [doneItem release];    

    self.title = NSLocalizedString(@"Settings", @"");
    if (m_storyDelegate)
        m_newFontSize = m_origFontSize = (int)[m_storyDelegate fontSize];
    if (m_fontSizeCell)
        ((DisplayCell*)m_fontSizeCell).nameLabel.text = [NSString stringWithFormat: @kFontSizeStr, m_origFontSize];
    m_sliderCtl.value = (float)m_origFontSize;

//    [self tableView: nil didSelectRowAtIndexPath: [NSIndexPath indexPathForRow: m_selectedRow inSection: m_selectedSection]];
}

#pragma mark - UITableView delegates

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
	return UITableViewCellEditingStyleNone;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return kFrotzNumSections;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSString *title;
    switch (section)
    {
	case kFrotzInfoSection:
	{
	    title = @"Info";
	    break;
	}
	case kFrotzPrefsSection:
	{
	    title = @"Preferences ";
	    break;
	}
#if 0
	case kFrotzColorsSection:
	{
	    title = @"Colors";
	    break;
	}
	case kFrotzFontSection: 
	{
	    title = @"Fonts";
	    break;
	}
#endif
	default:
	{
	    title = @" ";
	    break;
	}
    }
    return title;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == kFrotzInfoSection) {
	return 4;
    } else if (section == kFrotzResetSection)
	return 1;
#ifdef FROTZ_DB_APP_KEY
    return 7;
#else
    return 6;
#endif
}

// to determine specific row height for each cell, override this.  In this example, each row is determined
// buy the its subviews that are embedded.
//
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    CGFloat result;
    
    switch ([indexPath row])
    {
	case 0:
	default:
	{
	    result = kUIRowHeight;
	    break;
	}
    }

    return result;
}

// utility routine leveraged by 'cellForRowAtIndexPath' to determine which UITableViewCell to be used on a given row
//
- (DisplayCell *)obtainTableCellForRow:(NSInteger)row
{
    DisplayCell *cell = nil;

    cell = (DisplayCell*)[m_tableView dequeueReusableCellWithIdentifier:kDisplayCell_ID];
	
    if (cell == nil) {
	cell = [[[DisplayCell alloc] initWithFrame:CGRectZero reuseIdentifier:kDisplayCell_ID] autorelease];
    }
    cell.textAlignment = UITextAlignmentLeft;
    cell.text = nil;
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
    if (indexPath.section == kFrotzPrefsSection && indexPath.row >= 3 && indexPath.row != 6 || indexPath.section == kFrotzResetSection)
	cell.accessoryType = UITableViewCellAccessoryNone;
    else
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    switch (indexPath.section)
    {
	case kFrotzInfoSection:
	{
	    switch (row) {
		case 0:
		    cell.text = @"About Frotz";
		    break;
		case 1:
		    cell.text = @"Getting Started";
		    break;
		case 2:
		    cell.text = @"What's New?";
		    break;
		case 3:
		    cell.text = @"File Transfer";
		    break;
	    }
	    break;
	}
	case kFrotzPrefsSection:
	{
	    switch (row) {
		case 0:
		    cell.text = @"Text Color";
		    break;
		case 1:
		    cell.text = @"Background Color";
		    break;
		case 2:
		    cell.text = @"Story Font";
		    break;
		case 3:
		    m_fontSizeCell = cell;
		    ((DisplayCell*)cell).nameLabel.text = [NSString stringWithFormat: @kFontSizeStr, (int)[m_sliderCtl value]];
		    ((DisplayCell*)cell).view = m_sliderCtl;
		    break;
		case 4:
		    ((DisplayCell*)cell).nameLabel.text = @"Word completion";
		    ((DisplayCell*)cell).view = m_switchCtl;
		    break;
		case 5:
		    ((DisplayCell*)cell).nameLabel.text = @"Story Info Editing";
		    ((DisplayCell*)cell).view = m_switchCtl2;
		    break;
#ifdef FROTZ_DB_APP_KEY
		case 6:
		    cell.text = @"Dropbox Settings";
		    break;
#endif
	    }
	    break;
	}
	case kFrotzResetSection:
	{
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		cell.text = @"Reset Preferences to Default";
		cell.textAlignment = UITextAlignmentCenter;
		break;
	}
#if 0
	case kFrotzFontSection:
	{
	    if (row == 0)
		cell.text = @"Main Story Font";
	    else
		cell.text = @"Fixed Width Font";
	    break;
	}
#endif
    }
    
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
//    NSInteger section = indexPath.section, row = indexPath.row;
    return NO;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{   
    NSInteger section = indexPath.section, row = indexPath.row;
    m_selectedSection = section;
    m_selectedRow = row;
    UIViewController *viewController = nil;
    switch (section)  {
	case kFrotzInfoSection: {
	    switch (row) {
		case 0:
		    viewController = m_aboutFrotz;
		    break;
		case 1:
		    viewController = m_gettingStarted;
		    break;
		case 2:
		    viewController = m_releaseNotes;
		    break;
		case 3:
		    viewController = m_fileTransferInfo;
		    break;
	    }
	    break;
	}
	case kFrotzPrefsSection: 
//	case kFrotzColorsSection: 
	    if (row==0) {
		[m_colorPicker setTextColor: [m_storyDelegate textColor] bgColor: [m_storyDelegate backgroundColor] changeText:YES];
	    	m_colorPicker.title = NSLocalizedString(@"Text Color", @"");
		viewController = m_colorPicker;
	    } else if (row==1) {
		[m_colorPicker setTextColor: [m_storyDelegate textColor] bgColor: [m_storyDelegate backgroundColor] changeText:NO];
	    	m_colorPicker.title = NSLocalizedString(@"Background Color", @"");
		viewController = m_colorPicker;
	    } else if (row==2) {
		[m_fontPicker setFixedFontsOnly: false];
		viewController = m_fontPicker;
#ifdef FROTZ_DB_APP_KEY
	    }
	     else if (row==6) {
		viewController = m_frotzDB;
#endif
	    }
	    break;
	case kFrotzResetSection: {
		m_resetting = YES;
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Reset Preferences"
			message: @"Do you want to reset all color and font settings to their defaults?"
			delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles: @"OK", nil];
		[alert show];
		[alert release];
	    }
	    break;

#if 0
	case kFrotzFontSection:
	    [m_fontPicker setFixedFontsOnly: (row==1)];
	    viewController = m_fontPicker;
	    break;
#endif
	default:
	    break;
    }
    if (viewController) {
	if (!viewController.navigationItem.rightBarButtonItem) {
	    UIBarButtonItem *doneItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem: UIBarButtonSystemItemDone target:self action:@selector(donePressed)];
	    viewController.navigationItem.rightBarButtonItem = doneItem;
	    [doneItem release];
	}
	m_subPagePushed = YES;
	[[self navigationController] pushViewController: viewController animated: YES];
	[tableView deselectRowAtIndexPath:indexPath animated:NO];
    }
}

@end

