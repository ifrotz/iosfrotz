#import "FrotzSettings.h"
#import "FileTransferInfo.h"

#import "iosfrotz.h"

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

#define kFontSizeStr "Story Font Size (%d)"
#define kNotesSizeStr "Notes Font Size (%d)"
#if EnableStoryDictation
#define kDictationDelayStr "Dictation Delay (%.1fs)"
#endif

#import "FrotzAlert.h"

@implementation FrotzSettingsController
@synthesize storyDelegate = m_storyDelegate;
@synthesize infoDelegate = m_infoDelegate;
@synthesize notesDelegate = m_notesDelegate;

// The table's sections. Preferences used to be one long section mixing colors, fonts, notes,
// input behaviour and the library; grouping them (inset grouped style, so each is a card) is what
// separates them visually.
enum ControlTableSections
{
    kFrotzInfoSection,
    kFrotzStorySection,     // "Story Appearance": colors and the story font
    kFrotzNotesSection,
    kFrotzInputSection,
    kFrotzLibrarySection,
    kFrotzResetSection,
    kFrotzNumSections
};

// Every row, whichever section it is in; SettingsSectionRows() says which rows each section shows
// and in what order, so adding a row is one enum case, one entry there, and cases in
// cellForRowAtIndexPath: and didSelectRowAtIndexPath:.
typedef NS_ENUM(NSInteger, FrotzSettingsRow)
{
    kFrotzInfoAbout,
    kFrotzInfoGettingStarted,
    kFrotzInfoReleaseNotes,
    kFrotzInfoFileTransfer,
    kFrotzPrefsTextColor,
    kFrotzPrefsBGColor,
    kFrotzPrefsStoryFont,
    kFrotzPrefsStoryFontSize,
    kFrotzPrefsNotesFont,
    kFrotzPrefsNotesFontSize,
    kFrotzPrefsWordCompletion,
    kFrotzPrefsStoryInfoEditing,
#if EnableStoryDictation
    kFrotzPrefsStoryVoiceDictation,
    kFrotzPrefsDictationDelay,
    kFrotzPrefsDictationDuringVoiceOver, // only while VoiceOver runs; see SettingsSectionRows
#endif
#if UseDropBoxSDK && defined(FROTZ_DB_APP_KEY)
    kFrotzPrefsDropbox,
#endif
    kFrotzResetRow
};

// Built on each call: the Input section has a row that is there only while VoiceOver runs, and
// VoiceOver can be turned on or off while the settings page is open.
static NSArray<NSArray<NSNumber*>*> *SettingsSectionRows(void) {
    NSMutableArray<NSNumber*> *input = [NSMutableArray arrayWithObject: @(kFrotzPrefsWordCompletion)];
#if EnableStoryDictation
    [input addObjectsFromArray: @[ @(kFrotzPrefsStoryVoiceDictation), @(kFrotzPrefsDictationDelay) ]];
    if (UIAccessibilityIsVoiceOverRunning())
        [input addObject: @(kFrotzPrefsDictationDuringVoiceOver)];
#endif
    return @[
        @[ @(kFrotzInfoAbout), @(kFrotzInfoGettingStarted), @(kFrotzInfoReleaseNotes), @(kFrotzInfoFileTransfer) ],
        @[ @(kFrotzPrefsTextColor), @(kFrotzPrefsBGColor), @(kFrotzPrefsStoryFont), @(kFrotzPrefsStoryFontSize) ],
        @[ @(kFrotzPrefsNotesFont), @(kFrotzPrefsNotesFontSize) ],
        input,
        @[ @(kFrotzPrefsStoryInfoEditing),
#if UseDropBoxSDK && defined(FROTZ_DB_APP_KEY)
           @(kFrotzPrefsDropbox),
#endif
        ],
        @[ @(kFrotzResetRow) ],
    ];
}

-(FrotzSettingsRow)rowAtIndexPath:(NSIndexPath*)indexPath {
    return [SettingsSectionRows()[indexPath.section][indexPath.row] integerValue];
}

// Rows that open another screen show a disclosure chevron; the rest carry their own control.
-(BOOL)rowOpensScreen:(FrotzSettingsRow)row {
    switch (row) {
        case kFrotzInfoAbout:
        case kFrotzInfoGettingStarted:
        case kFrotzInfoReleaseNotes:
        case kFrotzInfoFileTransfer:
        case kFrotzPrefsTextColor:
        case kFrotzPrefsBGColor:
        case kFrotzPrefsStoryFont:
        case kFrotzPrefsNotesFont:
#if UseDropBoxSDK && defined(FROTZ_DB_APP_KEY)
        case kFrotzPrefsDropbox:
#endif
            return YES;
        default:
            return NO;
    }
}

-(void)setupFade {
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:0.5];

    [UIView setAnimationTransition:(UIViewAnimationTransitionFlipFromLeft)
                           forView:[[[self view] superview] superview] cache:YES];
    [UIView commitAnimations];
}

-(void)updateAccessibility {
    [m_colorPicker updateAccessibility];
}

-(void)donePressed {
    if (m_fileTransferInfo) {
        if ([m_fileTransferInfo serverIsRunning]) {
            FrotzShowAlert(self, @"File server running", @"The file server will be disabled when you exit settings",
                           @"Cancel", @[@"OK"], ^(NSInteger buttonIndex) {
                if (buttonIndex == 1) {
                    [m_fileTransferInfo stopServer];
                    [self donePressed];
                }
            });
            return;
        }
    }
    if ([m_tableView superview]) {
        m_selectedSection = m_selectedRow = -1;
    }
    if (m_infoDelegate && [m_infoDelegate respondsToSelector:@selector(dismissInfo)]) {
        if (m_storyDelegate) {
            if (m_newStoryFontSize != m_origStoryFontSize)
                [m_storyDelegate setFont: [m_storyDelegate fontName] withSize: m_newStoryFontSize];
            if (m_newNotesFontSize != m_origNotesFontSize)
                [m_notesDelegate setFont: [m_notesDelegate fontName] withSize: m_newNotesFontSize];
            [m_storyDelegate savePrefs];
        }

        [m_infoDelegate dismissInfo];
    }
    else {
        [self setupFade];
        [[self navigationController] popViewControllerAnimated: NO];
        [UIView commitAnimations];
    }
}

- (instancetype)init
{
    if ((self = [super init]))
    {
        m_colorPicker = [[ColorPicker alloc] init];
        [m_colorPicker setDelegate: self];
        m_storyFontPicker = [FontPicker frotzFontPickerWithTitle:@"Story Font" includingFaces:NO monospaceOnly:NO];
        m_notesFontPicker = [FontPicker frotzFontPickerWithTitle:@"Notes Font" includingFaces:YES monospaceOnly:NO];
        m_frotzDB = [[FrotzDBController alloc] init];
        m_releaseNotes = [[ReleaseNotes alloc] init];
    }
    return self;
}

- (void)setStoryDelegate:(id<FrotzSettingsStoryDelegate,FrotzFontDelegate>)delegate {
    m_storyDelegate = delegate;
    [m_storyFontPicker setDelegate: m_storyDelegate];
    [m_frotzDB setDelegate: m_storyDelegate];
}

- (void)setNotesDelegate:(id<FrotzFontDelegate>)delegate {
    m_notesDelegate = delegate;
    [m_notesFontPicker setDelegate: m_notesDelegate];
}

- (NSString*)rootPath {
    if (m_storyDelegate)
        return [m_storyDelegate rootPath];
    return nil;
}

- (void)dealloc
{
    [m_tableView setDelegate:nil];
    m_tableView = nil;

    m_gettingStarted = nil;
    m_aboutFrotz = nil;
    m_releaseNotes = nil;

    m_colorPicker = nil;
    m_storyFontPicker = nil;
    m_notesFontPicker = nil;

    m_frotzDB = nil;

}

- (void)create_UISwitches
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

#if EnableStoryDictation
    m_dictationSwitchCtl = [[UISwitch alloc] initWithFrame:frame];
    [m_dictationSwitchCtl addTarget:self action:@selector(switchAction:) forControlEvents:UIControlEventValueChanged];
    m_dictationSwitchCtl.backgroundColor = [UIColor clearColor];
    [m_dictationSwitchCtl setOn: [m_storyDelegate isDictationEnabled]];

    m_dictationVoiceOverSwitchCtl = [[UISwitch alloc] initWithFrame:frame];
    [m_dictationVoiceOverSwitchCtl addTarget:self action:@selector(switchAction:) forControlEvents:UIControlEventValueChanged];
    m_dictationVoiceOverSwitchCtl.backgroundColor = [UIColor clearColor];
    [m_dictationVoiceOverSwitchCtl setOn: [m_storyDelegate dictationListensDuringVoiceOver]];
#endif
}

- (void)switchAction:(id)sender
{
    if (sender == m_switchCtl)
        [m_storyDelegate setCompletionEnabled: [sender isOn]];
    else if (sender == m_switchCtl2)
        [m_storyDelegate setCanEditStoryInfo: [sender isOn]];
#if EnableStoryDictation
    else if (sender == m_dictationSwitchCtl)
        [m_storyDelegate setDictationEnabled: [sender isOn]];
    else if (sender == m_dictationVoiceOverSwitchCtl)
        [m_storyDelegate setDictationListensDuringVoiceOver: [sender isOn]];
#endif
}

#if EnableStoryDictation
// Applied as the slider moves; the label shows the value to a tenth of a second.
- (void)dictationDelaySliderAction:(UISlider*)sender
{
    NSTimeInterval value = round([sender value] * 10) / 10;
    if (value != [m_storyDelegate dictationCommitDelay]) {
        m_dictationDelayCell.textLabel.text = [NSString stringWithFormat: @kDictationDelayStr, value];
        [m_storyDelegate setDictationCommitDelay: value];
    }
}
#endif

- (void)storyFontSliderAction:(UISlider*)sender
{
    static int lastValue;
    int value = [sender value];

    if (value != lastValue) {
        m_storyFontSizeCell.textLabel.text = [NSString stringWithFormat: @kFontSizeStr, value];
        m_newStoryFontSize = (int)value;
        if (self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular)
            [m_storyDelegate setFont: [m_storyDelegate fontName] withSize: value];
    }
    lastValue = value;
}

- (void)notesFontSliderAction:(UISlider*)sender
{
    static int lastValue;
    int value = [sender value];

    if (value != lastValue) {
        m_notesFontSizeCell.textLabel.text = [NSString stringWithFormat: @kNotesSizeStr, value];
        m_newNotesFontSize = (int)value;
        if (self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular)
            [m_notesDelegate setFont: [m_notesDelegate fontName] withSize: value];
    }
    lastValue = value;
}

- (void)loadView
{
    CGRect frame = CGRectMake(0, 0, 240, 200);


    m_tableView = [[UITableView alloc] initWithFrame:frame style:UITableViewStyleInsetGrouped];
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

    [self create_UISwitches];

    CGRect sframe = CGRectMake(0.0, 0.0, 120.0, kSliderHeight);

    m_storyFontSliderCtl = [[UISlider alloc] initWithFrame:sframe];
    [m_storyFontSliderCtl addTarget:self action:@selector(storyFontSliderAction:) forControlEvents:UIControlEventValueChanged];
    // in case the parent view draws with a custom color or gradient, use a transparent color
    m_storyFontSliderCtl.backgroundColor = [UIColor clearColor];
    m_storyFontSliderCtl.minimumValue = 8.0;
    m_storyFontSliderCtl.maximumValue = 32.0;
    m_storyFontSliderCtl.continuous = YES;
    m_origStoryFontSize = (int)[m_storyDelegate fontSize];
    m_storyFontSliderCtl.value = (float)m_origStoryFontSize;

    m_notesFontSliderCtl = [[UISlider alloc] initWithFrame:sframe];
    [m_notesFontSliderCtl addTarget:self action:@selector(notesFontSliderAction:) forControlEvents:UIControlEventValueChanged];
    m_notesFontSliderCtl.backgroundColor = [UIColor clearColor];
    m_notesFontSliderCtl.minimumValue = 8.0;
    m_notesFontSliderCtl.maximumValue = 32.0;
    m_notesFontSliderCtl.continuous = YES;
    m_origNotesFontSize = (int)[m_notesDelegate fontSize];
    m_notesFontSliderCtl.value = (float)m_origNotesFontSize;

#if EnableStoryDictation
    m_dictationDelaySliderCtl = [[UISlider alloc] initWithFrame:sframe];
    [m_dictationDelaySliderCtl addTarget:self action:@selector(dictationDelaySliderAction:) forControlEvents:UIControlEventValueChanged];
    m_dictationDelaySliderCtl.backgroundColor = [UIColor clearColor];
    m_dictationDelaySliderCtl.minimumValue = kDictationDelayMin;
    m_dictationDelaySliderCtl.maximumValue = kDictationDelayMax;
    m_dictationDelaySliderCtl.continuous = YES;
    m_dictationDelaySliderCtl.value = (float)[m_storyDelegate dictationCommitDelay];
#endif
}

-(void)colorPicker:(ColorPicker*)picker selectedColor:(UIColor*)color {
    if ([picker isTextColorMode])
        [m_storyDelegate setTextColor: color makeDefault:YES];
    else
        [m_storyDelegate setBackgroundColor: color makeDefault:YES];
}

-(UIFont*)fontForColorDemo {
    return m_storyDelegate ? [UIFont fontWithName:[m_storyDelegate fontName] size:m_newStoryFontSize] : nil;
}

-(void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    [self donePressed];
}

-(BOOL)presentationControllerShouldDismiss:(UIPresentationController *)presentationController {
    if (m_fileTransferInfo && [m_fileTransferInfo serverIsRunning])
        return NO;
    return YES;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    m_tableView.delegate = self;
    m_tableView.dataSource = self;

    [self.navigationController.navigationBar setBarStyle: UIBarStyleDefault];
    [self.navigationController.navigationBar setBarTintColor: [UIColor systemBackgroundColor]];
    [self.navigationController.navigationBar setTintColor: [UIColor labelColor]];

    [[self.navigationItem backBarButtonItem] setEnabled: NO];
    [[self.navigationItem leftBarButtonItem] setEnabled: NO];
    [self.navigationItem setHidesBackButton: YES animated:YES];

    UIBarButtonItem *doneItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem: UIBarButtonSystemItemDone target:self action:@selector(donePressed)];
    self.navigationItem.rightBarButtonItem = doneItem;
    self.navigationController.presentationController.delegate = self;

    self.title = NSLocalizedString(@"Frotz Settings", @"");
    if (m_storyDelegate)
        m_newStoryFontSize = m_origStoryFontSize = (int)[m_storyDelegate fontSize];
    if (m_notesDelegate)
        m_newNotesFontSize = m_origNotesFontSize = (int)[m_notesDelegate fontSize];
    if (m_storyFontCell)
        m_storyFontCell.detailTextLabel.text = [[m_storyDelegate font] familyName];
    if (m_storyFontSizeCell)
        m_storyFontSizeCell.textLabel.text = [NSString stringWithFormat: @kFontSizeStr, m_origStoryFontSize];
    if (m_notesFontCell)
        m_notesFontCell.detailTextLabel.text = [[m_notesDelegate font] familyName];
    if (m_notesFontSizeCell)
        m_notesFontSizeCell.textLabel.text = [NSString stringWithFormat: @kNotesSizeStr, m_origNotesFontSize];

    m_storyFontSliderCtl.value = (float)m_origStoryFontSize;
    m_notesFontSliderCtl.value = (float)m_origNotesFontSize;
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
    switch (section)
    {
        case kFrotzInfoSection:     return NSLocalizedString(@"Info", @"");
        case kFrotzStorySection:    return NSLocalizedString(@"Story Appearance", @"");
        case kFrotzNotesSection:    return NSLocalizedString(@"Notes", @"");
        case kFrotzInputSection:    return NSLocalizedString(@"Input", @"");
        case kFrotzLibrarySection:  return NSLocalizedString(@"Library", @"");
        default:                    return nil; // the reset button stands alone
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
#if EnableStoryDictation
    if (section == kFrotzInputSection) {
        NSString *footer = NSLocalizedString(@"Dictation Delay is how long Frotz waits after you stop speaking before entering what you said as a command.", @"");
        if (UIAccessibilityIsVoiceOverRunning())
            footer = [footer stringByAppendingString: NSLocalizedString(@" Listen During VoiceOver keeps the microphone open while VoiceOver reads the story, so you can speak over it; VoiceOver's speech may crackle while this is on unless Audio Ducking is turned off in VoiceOver's settings. When it is off, pause the reading with a two-finger tap, then Magic Tap (a two-finger double tap) to speak.", @"")];
        return footer;
    }
#endif
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [SettingsSectionRows()[section] count];
}

// to determine specific row height for each cell, override this.  In this example, each row is determined
// by its embedded subviews
//
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    CGFloat result;

    switch ([indexPath row])
    {
        default:
            result = kUIRowHeight;
            break;
    }
    return result;
}

// utility routine leveraged by 'cellForRowAtIndexPath' to determine which UITableViewCell to be used on a given row
//
- (UITableViewCell *)obtainTableCellForRow:(NSInteger)row
{
    UITableViewCell *cell = nil;
    NSString *kReuseIdentifier = @"frotzSettings_ID";

    cell = [m_tableView dequeueReusableCellWithIdentifier: kReuseIdentifier];

    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle: UITableViewCellStyleValue1 reuseIdentifier: kReuseIdentifier];
    }
    cell.textAlignment = NSTextAlignmentLeft;
    cell.textLabel.text = nil;
    cell.detailTextLabel.text = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    return cell;
}

// to determine which UITableViewCell to be used on a given row.
//
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    FrotzSettingsRow row = [self rowAtIndexPath: indexPath];
    UITableViewCell *cell = [self obtainTableCellForRow: indexPath.row];
    cell.accessoryType = [self rowOpensScreen: row] ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    cell.accessoryView = nil;

    switch (row) {
        case kFrotzInfoAbout:
            cell.textLabel.text = @"About Frotz";
            break;
        case kFrotzInfoGettingStarted:
            cell.textLabel.text = @"Getting Started";
            break;
        case kFrotzInfoReleaseNotes:
            cell.textLabel.text = @"What's New?";
            break;
        case kFrotzInfoFileTransfer:
            cell.textLabel.text = @"File Transfer";
            break;
        case kFrotzPrefsTextColor:
            cell.textLabel.text = @"Text Color";
            break;
        case kFrotzPrefsBGColor:
            cell.textLabel.text = @"Background Color";
            break;
        case kFrotzPrefsStoryFont:
            m_storyFontCell = cell;
            cell.textLabel.text = @"Story Font";
            cell.detailTextLabel.text = [[m_storyDelegate font] familyName];
            break;
        case kFrotzPrefsNotesFont:
            m_notesFontCell = cell;
            cell.textLabel.text = @"Notes Font";
            cell.detailTextLabel.text = [[m_notesDelegate font] familyName];
            break;
        case kFrotzPrefsStoryFontSize:
            m_storyFontSizeCell = cell;
            cell.textLabel.text = [NSString stringWithFormat: @kFontSizeStr, (int)[m_storyFontSliderCtl value]];
            cell.accessoryView = m_storyFontSliderCtl;
            break;
        case kFrotzPrefsNotesFontSize:
            m_notesFontSizeCell = cell;
            cell.textLabel.text = [NSString stringWithFormat: @kNotesSizeStr, (int)[m_notesFontSliderCtl value]];
            cell.accessoryView = m_notesFontSliderCtl;
            break;
        case kFrotzPrefsWordCompletion:
            cell.textLabel.text = @"Word Completion";
            cell.accessoryView = m_switchCtl;
            break;
        case kFrotzPrefsStoryInfoEditing:
            cell.textLabel.text = @"Story Info Editing";
            cell.accessoryView = m_switchCtl2;
            break;
#if EnableStoryDictation
        case kFrotzPrefsStoryVoiceDictation:
            cell.textLabel.text = @"Story Voice Dictation";
            cell.accessoryView = m_dictationSwitchCtl;
            break;
        case kFrotzPrefsDictationDelay:
            m_dictationDelayCell = cell;
            cell.textLabel.text = [NSString stringWithFormat: @kDictationDelayStr, [m_storyDelegate dictationCommitDelay]];
            cell.accessoryView = m_dictationDelaySliderCtl;
            break;
        case kFrotzPrefsDictationDuringVoiceOver:
            cell.textLabel.text = @"Listen During VoiceOver";
            cell.accessoryView = m_dictationVoiceOverSwitchCtl;
            break;
#endif
#if UseDropBoxSDK && defined(FROTZ_DB_APP_KEY)
        case kFrotzPrefsDropbox:
            cell.textLabel.text = @"Dropbox Settings";
            break;
#endif
        case kFrotzResetRow:
            cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            cell.textLabel.text = @"Reset Preferences to Default";
            cell.textAlignment = NSTextAlignmentCenter;
            break;
    }

    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{   
    m_selectedSection = indexPath.section;
    m_selectedRow = indexPath.row;
    UIViewController *viewController = nil;
    switch ([self rowAtIndexPath: indexPath]) {
        case kFrotzInfoAbout:
            viewController = m_aboutFrotz;
            break;
        case kFrotzInfoGettingStarted:
            viewController = m_gettingStarted;
            break;
        case kFrotzInfoReleaseNotes:
            viewController = m_releaseNotes;
            break;
        case kFrotzInfoFileTransfer:
            viewController = m_fileTransferInfo;
            break;
        case kFrotzPrefsTextColor:
            [m_colorPicker setTextColor: [m_storyDelegate textColor] bgColor: [m_storyDelegate backgroundColor] changeText:YES];
            m_colorPicker.title = NSLocalizedString(@"Text Color \u29C9", @"");
            viewController = m_colorPicker;
            break;
        case kFrotzPrefsBGColor:
            [m_colorPicker setTextColor: [m_storyDelegate textColor] bgColor: [m_storyDelegate backgroundColor] changeText:NO];
            m_colorPicker.title = NSLocalizedString(@"Background Color \u29C9", @"");
            viewController = m_colorPicker;
            break;
        case kFrotzPrefsStoryFont:
            viewController = m_storyFontPicker;
            break;
        case kFrotzPrefsNotesFont:
            viewController = m_notesFontPicker;
            break;
#if UseDropBoxSDK && defined(FROTZ_DB_APP_KEY)
        case kFrotzPrefsDropbox:
            viewController = m_frotzDB;
            break;
#endif
        case kFrotzResetRow: {
            m_resetting = YES;
            FrotzShowAlert(self, @"Reset Preferences", @"Do you want to reset all color and font settings to their defaults?",
                           @"Cancel", @[@"OK"], ^(NSInteger buttonIndex) {
                NSIndexPath *idx = [[self tableView] indexPathForSelectedRow];
                if (idx)
                    [[self tableView] deselectRowAtIndexPath: idx animated:YES];
                m_resetting = NO;
                if (buttonIndex == 1) {
                    [m_storyDelegate resetSettingsToDefault];
                    m_newStoryFontSize = m_origStoryFontSize = (int)[m_storyDelegate fontSize];
                    m_newNotesFontSize = m_origNotesFontSize = (int)[m_notesDelegate fontSize];
                    m_storyFontSliderCtl.value = (float)m_origStoryFontSize;
                    m_notesFontSliderCtl.value = (float)m_origNotesFontSize;
                    [m_switchCtl setOn: [m_storyDelegate isCompletionEnabled]];
#if EnableStoryDictation
                    [m_dictationSwitchCtl setOn: [m_storyDelegate isDictationEnabled]];
                    m_dictationDelaySliderCtl.value = (float)[m_storyDelegate dictationCommitDelay];
                    [m_dictationVoiceOverSwitchCtl setOn: [m_storyDelegate dictationListensDuringVoiceOver]];
#endif
                    [[self tableView] reloadData];
                }
            });
        }
            break;

        default:
            break;
    }
    if (viewController) {
        if (!viewController.navigationItem.rightBarButtonItem) {
            UIBarButtonItem *doneItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem: UIBarButtonSystemItemDone target:self action:@selector(donePressed)];
            viewController.navigationItem.rightBarButtonItem = doneItem;
        }

        [[self navigationController] pushViewController: viewController animated: YES];
        [tableView deselectRowAtIndexPath:indexPath animated:NO];
    }
}

@end

