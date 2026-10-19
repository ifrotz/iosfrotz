#import "FrotzSettings.h"
#import "FileTransferInfo.h"
#import "VoiceManager.h"

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

// Kept with the settings UI so voice choices need no new project files.
@interface FrotzSpeechSettingsController : UITableViewController
- (NSString *)helpTextForSection:(NSInteger)section;
@end
@implementation FrotzSpeechSettingsController
- (NSString *)helpTextForSection:(NSInteger)section { return nil; }
- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    NSString *text = [self helpTextForSection:section];
    if (!text.length) return nil;
    UITableViewHeaderFooterView *footer = [tableView dequeueReusableHeaderFooterViewWithIdentifier:@"speechHelp"];
    if (!footer) {
        footer = [[UITableViewHeaderFooterView alloc] initWithReuseIdentifier:@"speechHelp"];
        UILabel *label = [[UILabel alloc] init];
        label.tag = 1;
        label.numberOfLines = 0;
        label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        label.adjustsFontForContentSizeCategory = YES;
        label.textColor = [UIColor grayColor];
        if (@available(iOS 13.0, *)) label.textColor = [UIColor secondaryLabelColor];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [footer.contentView addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor constraintEqualToAnchor:footer.contentView.layoutMarginsGuide.leadingAnchor],
            [label.trailingAnchor constraintEqualToAnchor:footer.contentView.layoutMarginsGuide.trailingAnchor],
            [label.topAnchor constraintEqualToAnchor:footer.contentView.topAnchor constant:12],
            [label.bottomAnchor constraintEqualToAnchor:footer.contentView.bottomAnchor constant:-12]
        ]];
    }
    ((UILabel *)[footer.contentView viewWithTag:1]).text = text;
    return footer;
}
- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return [self helpTextForSection:section].length ? UITableViewAutomaticDimension : 0;
}
- (CGFloat)tableView:(UITableView *)tableView estimatedHeightForFooterInSection:(NSInteger)section {
    return [self helpTextForSection:section].length ? 100 : 0;
}
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        // Re-measure multiline section footers for the new width.
        [self.tableView reloadData];
    }];
}
@end

@interface FrotzSpeechVoiceController : FrotzSpeechSettingsController <AVSpeechSynthesizerDelegate>
@property (nonatomic, copy) NSArray<NSString *> *languages;
@property (nonatomic, copy) NSDictionary<NSString *, NSArray<AVSpeechSynthesisVoice *> *> *voicesByLanguage;
@property (nonatomic, strong) AVSpeechSynthesizer *previewSynthesizer;
@property (nonatomic, strong) AVSpeechUtterance *previewUtterance;
@property (nonatomic) BOOL previewSessionActive;
@end

@implementation FrotzSpeechVoiceController
- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
        self.title = @"Speech Voice";
        _previewSynthesizer = [[AVSpeechSynthesizer alloc] init];
        _previewSynthesizer.delegate = self;
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(refreshVoices) name:UIApplicationWillEnterForegroundNotification object:nil];
        [center addObserver:self selector:@selector(stopPreview) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [center addObserver:self selector:@selector(stopPreview) name:AVAudioSessionInterruptionNotification object:nil];
        if (@available(iOS 17.0, *))
            [center addObserver:self selector:@selector(refreshVoices) name:AVSpeechSynthesisAvailableVoicesDidChangeNotification object:nil];
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64;
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshVoices];
}
- (void)viewWillDisappear:(BOOL)animated {
    [self stopPreview];
    [super viewWillDisappear:animated];
}
- (void)refreshVoices {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self refreshVoices]; });
        return;
    }
    NSMutableDictionary *groups = [NSMutableDictionary dictionary];
    NSArray *voices = [[AVSpeechSynthesisVoice speechVoices] sortedArrayUsingComparator:^NSComparisonResult(AVSpeechSynthesisVoice *a, AVSpeechSynthesisVoice *b) {
        NSComparisonResult nameOrder = [a.name localizedStandardCompare:b.name];
        if (nameOrder != NSOrderedSame) return nameOrder;
        if (a.quality != b.quality) return a.quality > b.quality ? NSOrderedAscending : NSOrderedDescending;
        return [a.identifier compare:b.identifier];
    }];
    for (AVSpeechSynthesisVoice *voice in voices) {
        if (!groups[voice.language]) groups[voice.language] = [NSMutableArray array];
        [groups[voice.language] addObject:voice];
    }
    self.voicesByLanguage = groups;
    self.languages = [[groups allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        BOOL aEnglish = [a hasPrefix:@"en-"];
        BOOL bEnglish = [b hasPrefix:@"en-"];
        if (aEnglish != bEnglish) return aEnglish ? NSOrderedAscending : NSOrderedDescending;
        NSLocale *locale = [NSLocale currentLocale];
        return [[locale localizedStringForLocaleIdentifier:a] ?: a localizedStandardCompare:[locale localizedStringForLocaleIdentifier:b] ?: b];
    }];
    [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.languages.count + 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 1 : self.voicesByLanguage[self.languages[section - 1]].count;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Narration Voice";
    NSString *language = self.languages[section - 1];
    return [[NSLocale currentLocale] localizedStringForLocaleIdentifier:language] ?: language;
}
- (NSString *)helpTextForSection:(NSInteger)section {
    if (section != 0) return nil;
    return @"VoiceOver uses its own voice and rate for game narration. These settings apply when VoiceOver is off. Tap to select a voice and hear a preview. Automatic follows the story language, defaulting to English, and prefers Premium or Enhanced voices. Download more in iOS Settings → Accessibility → Read & Speak → Voices (Spoken Content on older iOS).";
}
- (AVSpeechSynthesisVoice *)voiceAtIndexPath:(NSIndexPath *)path {
    return path.section == 0 ? nil : self.voicesByLanguage[self.languages[path.section - 1]][path.row];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"speechVoice"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"speechVoice"];
    AVSpeechSynthesisVoice *voice = [self voiceAtIndexPath:path];
    VoiceManager *manager = [VoiceManager shared];
    cell.textLabel.text = voice ? voice.name : @"Automatic";
    cell.detailTextLabel.text = voice ? [VoiceManager qualityDescriptionForVoice:voice]
        : manager.automaticSpeechVoice.name;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    cell.textLabel.numberOfLines = cell.detailTextLabel.numberOfLines = 0;
    if (@available(iOS 10.0, *)) {
        cell.textLabel.adjustsFontForContentSizeCategory = YES;
        cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    }
    BOOL selected = voice ? [voice.identifier isEqualToString:manager.speechVoiceIdentifier]
        : !manager.speechVoiceIdentifier.length || ![AVSpeechSynthesisVoice voiceWithIdentifier:manager.speechVoiceIdentifier];
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
    cell.accessibilityHint = @"Selects this voice and plays a preview.";
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    VoiceManager *manager = [VoiceManager shared];
    manager.speechVoiceIdentifier = [self voiceAtIndexPath:path].identifier;
    [manager savePreferences];
    [tableView reloadData];
    [self stopPreview];
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error = nil;
    if (![session setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionDuckOthers error:&error]
        || ![session setActive:YES error:&error]) {
        [session setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Preview Unavailable" message:@"Your voice choice has been saved. Audio playback is currently unavailable." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    self.previewSessionActive = YES;
    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:@"Welcome to Frotz. This is the voice that will read your story."];
    utterance.voice = manager.speechVoice;
    utterance.rate = MIN(AVSpeechUtteranceMaximumSpeechRate, MAX(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * manager.speechRate));
    self.previewUtterance = utterance;
    [self.previewSynthesizer speakUtterance:utterance];
}
- (void)stopPreview {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self stopPreview]; });
        return;
    }
    self.previewUtterance = nil;
    [self.previewSynthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    if (self.previewSessionActive) {
        self.previewSessionActive = NO;
        [[AVAudioSession sharedInstance] setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
    }
}
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didFinishSpeechUtterance:(AVSpeechUtterance *)utterance {
    if (utterance == self.previewUtterance) [self stopPreview];
}
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didCancelSpeechUtterance:(AVSpeechUtterance *)utterance {
    if (utterance == self.previewUtterance) [self stopPreview];
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _previewSynthesizer.delegate = nil;
    [_previewSynthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
}
@end

@interface FrotzSpeechLanguageController : FrotzSpeechSettingsController
@property (nonatomic, copy) NSArray<NSLocale *> *locales;
@end
@implementation FrotzSpeechLanguageController
- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
        self.title = @"Speech Input Language";
        _locales = [[[SFSpeechRecognizer supportedLocales] allObjects] sortedArrayUsingComparator:^NSComparisonResult(NSLocale *a, NSLocale *b) {
            NSLocale *display = NSLocale.currentLocale;
            NSString *aName = [display localizedStringForLocaleIdentifier:a.localeIdentifier] ?: a.localeIdentifier;
            NSString *bName = [display localizedStringForLocaleIdentifier:b.localeIdentifier] ?: b.localeIdentifier;
            return [aName localizedStandardCompare:bName];
        }];
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 50;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? 1 : self.locales.count; }
- (NSString *)helpTextForSection:(NSInteger)section {
    return section == 0 ? @"Automatic uses the story's declared language, or English when none is available. Choose the language the story understands; Frotz does not translate commands. Speech recognition availability and on-device support vary by language and device." : nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"speechLanguage"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"speechLanguage"];
    NSString *language = path.section == 0 ? nil : self.locales[path.row].localeIdentifier;
    cell.textLabel.text = language ? ([NSLocale.currentLocale localizedStringForLocaleIdentifier:language] ?: language) : @"Automatic";
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    NSString *chosen = [VoiceManager shared].speechRecognitionLanguage;
    BOOL selected = language ? [language isEqualToString:chosen] : !chosen.length;
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    [VoiceManager shared].speechRecognitionLanguage = path.section == 0 ? nil : self.locales[path.row].localeIdentifier;
    [[VoiceManager shared] savePreferences];
    [tableView reloadData];
}
@end

// Explicit constraints let both choice labels wrap at accessibility text sizes.
@interface FrotzCommandConfirmationCell : UITableViewCell
@property (nonatomic, strong) UILabel *choiceLabel;
@property (nonatomic, strong) UILabel *explanationLabel;
@end
@implementation FrotzCommandConfirmationCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier])) {
        _choiceLabel = [[UILabel alloc] init];
        _choiceLabel.tag = 1;
        _choiceLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        _explanationLabel = [[UILabel alloc] init];
        _explanationLabel.tag = 2;
        _explanationLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        _explanationLabel.textColor = [UIColor grayColor];
        if (@available(iOS 13.0, *)) _explanationLabel.textColor = [UIColor secondaryLabelColor];
        for (UILabel *label in @[_choiceLabel, _explanationLabel]) {
            label.numberOfLines = 0;
            label.adjustsFontForContentSizeCategory = YES;
        }
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_choiceLabel, _explanationLabel]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 4;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
            [stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12],
            [stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12]
        ]];
        self.isAccessibilityElement = YES;
    }
    return self;
}
@end

// A separate choice screen keeps the mode names and explanations readable on iPhone.
@interface FrotzCommandConfirmationController : FrotzSpeechSettingsController
@end
@implementation FrotzCommandConfirmationController
- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) self.title = @"Voice Command Confirmation";
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 80;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 3; }
- (NSString *)helpTextForSection:(NSInteger)section {
    return @"Confirmation applies to command lines. Confirmation replies and single-key game prompts keep their usual behavior. Matching stays active in every mode; recognition confidence does not guarantee your intent.";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    FrotzCommandConfirmationCell *cell = [tableView dequeueReusableCellWithIdentifier:@"commandConfirmation"];
    if (!cell) cell = [[FrotzCommandConfirmationCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"commandConfirmation"];
    cell.choiceLabel.text = @[@"Off", @"As Needed", @"Always"][path.row];
    cell.explanationLabel.text = @[@"Submit the best guess immediately. Default.",
        @"Review uncertain recognition or corrected commands before submitting.",
        @"Review every command before submitting, even when recognition is confident."][path.row];
    cell.accessibilityLabel = [NSString stringWithFormat:@"%@. %@", cell.choiceLabel.text, cell.explanationLabel.text];
    BOOL selected = path.row == [VoiceManager shared].commandConfirmationMode;
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    [VoiceManager shared].commandConfirmationMode = (VoiceCommandConfirmationMode)path.row;
    [[VoiceManager shared] savePreferences];
    [tableView reloadData];
}
@end

@implementation FrotzSettingsController
@synthesize storyDelegate = m_storyDelegate;
@synthesize infoDelegate = m_infoDelegate;
@synthesize notesDelegate = m_notesDelegate;

enum ControlTableSections
{
    kFrotzInfoSection,
    kFrotzPrefsSection,
    kFrotzResetSection,
    kFrotzNumSections
};

enum FrotzInfoRows
{
    kFrotzInfoAbout,
    kFrotzInfoGettingStarted,
    kFrotzInfoReleaseNotes,
    kFrotzInfoFileTransfer,
    kFrotzInfoNumRows
};

enum FrotzPrefsRows
{
    kFrotzPrefsTextColor,
    kFrotzPrefsBGColor,
    kFrotzPrefsStoryFont,
    kFrotzPrefsStoryFontSize,
    kFrotzPrefsNotesFont,
    kFrotzPrefsNotesFontSize,
    kFrotzPrefsWordCompletion,
    kFrotzPrefsStoryInfoEditing,
    kFrotzPrefsTTS,
    kFrotzPrefsSTT,
    kFrotzPrefsCommandConfirmation,
    kFrotzPrefsSpeechVoice,
    kFrotzPrefsSpeechLanguage,
    kFrotzPrefsSpeechRate,
#if UseDropBoxSDK && defined(FROTZ_DB_APP_KEY)
    kFrotzPrefsDropbox,
#endif
    kFrotzPrefsNumRows
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
            m_newStoryFontSize = m_origStoryFontSize = (int)[m_storyDelegate fontSize];
            m_newNotesFontSize = m_origNotesFontSize = (int)[m_notesDelegate fontSize];
            m_storyFontSliderCtl.value = (float)m_origStoryFontSize;
            m_notesFontSliderCtl.value = (float)m_origNotesFontSize;
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

    m_switchCtl3 = [[UISwitch alloc] initWithFrame:frame];
    m_switchCtl3.accessibilityLabel = @"Text-to-Speech";
    [m_switchCtl3 addTarget:self action:@selector(switchAction:) forControlEvents:UIControlEventValueChanged];
    m_switchCtl3.backgroundColor = [UIColor clearColor];
    [m_switchCtl3 setOn: [VoiceManager shared].ttsEnabled];

    m_switchCtl4 = [[UISwitch alloc] initWithFrame:frame];
    m_switchCtl4.accessibilityLabel = @"Speech-to-Text";
    [m_switchCtl4 addTarget:self action:@selector(switchAction:) forControlEvents:UIControlEventValueChanged];
    m_switchCtl4.backgroundColor = [UIColor clearColor];
    [m_switchCtl4 setOn: [VoiceManager shared].sttEnabled];

}

- (void)switchAction:(id)sender
{
    if (sender == m_switchCtl)
        [m_storyDelegate setCompletionEnabled: [sender isOn]];
    else if (sender == m_switchCtl2)
        [m_storyDelegate setCanEditStoryInfo: [sender isOn]];
    else if (sender == m_switchCtl3) {
        // TTS toggle
        VoiceManager *vm = [VoiceManager shared];
        if ([sender isOn]) {
            vm.voiceMode = vm.sttEnabled ? VoiceModeBoth : VoiceModeTTSOnly;
        } else {
            [vm stopSpeaking];
            vm.voiceMode = vm.sttEnabled ? VoiceModeSTTOnly : VoiceModeOff;
        }
        [vm savePreferences];
    } else if (sender == m_switchCtl4) {
        // STT toggle
        NSUInteger generation = ++m_sttPermissionGeneration;
        VoiceManager *vm = [VoiceManager shared];
        if ([sender isOn]) {
            [vm requestSTTPermissionsWithCompletion:^(BOOL granted) {
                if (generation != self->m_sttPermissionGeneration || !self->m_switchCtl4.isOn)
                    return;
                if (granted) {
                    vm.voiceMode = vm.ttsEnabled ? VoiceModeBoth : VoiceModeSTTOnly;
                } else {
                    [self->m_switchCtl4 setOn:NO animated:YES];
                }
                [vm savePreferences];
            }];
        } else {
            [vm stopListening];
            vm.voiceMode = vm.ttsEnabled ? VoiceModeTTSOnly : VoiceModeOff;
            [vm savePreferences];
        }
    }
}

- (void)storyFontSliderAction:(UISlider*)sender
{
    static int lastValue;
    int value = [sender value];

    if (value != lastValue) {
        m_storyFontSizeCell.textLabel.text = [NSString stringWithFormat: @kFontSizeStr, value];
        m_newStoryFontSize = (int)value;
        if (gLargeScreenDevice)
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
        if (gLargeScreenDevice)
            [m_notesDelegate setFont: [m_notesDelegate fontName] withSize: value];
    }
    lastValue = value;
}

#define kSpeechRateStr "Speech Rate (%.1fx)"

- (void)speechRateSliderAction:(UISlider*)sender
{
    float value = roundf([sender value] * 4.0f) / 4.0f; // snap to 0.25 increments
    m_speechRateCell.textLabel.text = [NSString stringWithFormat: @kSpeechRateStr, value];
    [VoiceManager shared].speechRate = value;
    [[VoiceManager shared] savePreferences];
}

- (void)loadView
{
    CGRect frame = CGRectMake(0, 0, 240, 200);


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

    m_speechRateSliderCtl = [[UISlider alloc] initWithFrame:sframe];
    [m_speechRateSliderCtl addTarget:self action:@selector(speechRateSliderAction:) forControlEvents:UIControlEventValueChanged];
    m_speechRateSliderCtl.backgroundColor = [UIColor clearColor];
    m_speechRateSliderCtl.minimumValue = 0.5;
    m_speechRateSliderCtl.maximumValue = 3.0;
    m_speechRateSliderCtl.continuous = YES;
    m_speechRateSliderCtl.value = [VoiceManager shared].speechRate;
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

    // Sync voice switches with current state (may have been toggled from toolbar)
    [m_switchCtl3 setOn:[VoiceManager shared].ttsEnabled animated:NO];
    [m_switchCtl4 setOn:[VoiceManager shared].sttEnabled animated:NO];
    m_speechRateSliderCtl.value = [VoiceManager shared].speechRate;

    if (@available(iOS 13.0, *)) {
        [self.navigationController.navigationBar setBarStyle: UIBarStyleDefault];
        [self.navigationController.navigationBar setBarTintColor: [UIColor systemBackgroundColor]];
        [self.navigationController.navigationBar setTintColor: [UIColor labelColor]];
    } else {
        [self.navigationController.navigationBar setBarStyle: UIBarStyleDefault];
        [self.navigationController.navigationBar setBarTintColor: [UIColor whiteColor]];
        [self.navigationController.navigationBar setTintColor:  [UIColor darkGrayColor]];
    }

    [[self.navigationItem backBarButtonItem] setEnabled: NO];
    [[self.navigationItem leftBarButtonItem] setEnabled: NO];
    [self.navigationItem setHidesBackButton: YES animated:YES];

    UIBarButtonItem *doneItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem: UIBarButtonSystemItemDone target:self action:@selector(donePressed)];
    self.navigationItem.rightBarButtonItem = doneItem;
    self.navigationController.presentationController.delegate = self;

    self.title = NSLocalizedString(@"Settings", @"");
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
    [m_tableView reloadData];
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

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == kFrotzPrefsSection)
        return @"With VoiceOver, narration uses VoiceOver’s voice and rate. Moving focus pauses dictation. Use a two-finger double-tap to start or stop listening. The speech controls’ Actions menu offers Replay last response without taking a turn. A rising tone means the microphone is ready; a falling pair means navigation paused it; three low tones indicate an error.";
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == kFrotzInfoSection) {
        return kFrotzInfoNumRows;
    } else if (section == kFrotzResetSection)
        return 1;
    return kFrotzPrefsNumRows;
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
    cell.textAlignment = UITextAlignmentLeft;
    cell.textLabel.text = nil;
    cell.detailTextLabel.text = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    return cell;
}

// to determine which UITableViewCell to be used on a given row.
//
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSInteger row = [indexPath row];
    UITableViewCell *cell = [self obtainTableCellForRow:row];
    if (indexPath.section == kFrotzPrefsSection && indexPath.row >= kFrotzPrefsStoryFontSize
        && indexPath.row != kFrotzPrefsNotesFont
        && indexPath.row != kFrotzPrefsSpeechVoice
        && indexPath.row != kFrotzPrefsSpeechLanguage
        && indexPath.row != kFrotzPrefsCommandConfirmation
#if UseDropBoxSDK && defined(FROTZ_DB_APP_KEY)
        && indexPath.row != kFrotzPrefsDropbox
#endif
        || indexPath.section == kFrotzResetSection)
        cell.accessoryType = UITableViewCellAccessoryNone;
    else
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.accessoryView = nil;

    switch (indexPath.section)
    {
        case kFrotzInfoSection:
        {
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
            }
            break;
        }
        case kFrotzPrefsSection:
        {
            switch (row) {
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
                case kFrotzPrefsTTS:
                    cell.textLabel.text = @"Text-to-Speech";
                    cell.accessoryView = m_switchCtl3;
                    break;
                case kFrotzPrefsSTT:
                    cell.textLabel.text = @"Speech-to-Text";
                    cell.accessoryView = m_switchCtl4;
                    break;
                case kFrotzPrefsCommandConfirmation:
                    cell.textLabel.text = @"Voice Command Confirmation";
                    cell.textLabel.numberOfLines = 0;
                    cell.detailTextLabel.text = [VoiceManager shared].commandConfirmationDescription;
                    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                    break;
                case kFrotzPrefsSpeechRate:
                    m_speechRateCell = cell;
                    cell.textLabel.text = [NSString stringWithFormat: @kSpeechRateStr, [m_speechRateSliderCtl value]];
                    cell.accessoryView = m_speechRateSliderCtl;
                    break;
                case kFrotzPrefsSpeechVoice:
                    cell.textLabel.text = @"Speech Voice";
                    cell.detailTextLabel.text = [VoiceManager shared].speechVoiceDescription;
                    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                    break;
                case kFrotzPrefsSpeechLanguage: {
                    VoiceManager *manager = [VoiceManager shared];
                    cell.textLabel.text = @"Speech Input Language";
                    cell.detailTextLabel.text = manager.speechRecognitionLanguage
                        ? ([NSLocale.currentLocale localizedStringForLocaleIdentifier:manager.effectiveRecognitionLanguage] ?: manager.effectiveRecognitionLanguage) : @"Automatic";
                    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                    break;
                }
#if UseDropBoxSDK && defined(FROTZ_DB_APP_KEY)
                case kFrotzPrefsDropbox:
                    cell.textLabel.text = @"Dropbox Settings";
                    break;
#endif
            }
            break;
        }
        case kFrotzResetSection:
        {
            cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            cell.textLabel.text = @"Reset Preferences to Default";
            cell.textAlignment = UITextAlignmentCenter;
            break;
        }
#if 0
        case kFrotzFontSection:
        {
            if (row == 0)
                cell.textLabel.text = @"Main Story Font";
            else
                cell.textLabel.text = @"Fixed Width Font";
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
            }
            break;
        }
        case kFrotzPrefsSection:
            //	case kFrotzColorsSection:
            if (row==kFrotzPrefsTextColor) {
                [m_colorPicker setTextColor: [m_storyDelegate textColor] bgColor: [m_storyDelegate backgroundColor] changeText:YES];
                m_colorPicker.title = NSLocalizedString(@"Text Color \u29C9", @"");
                viewController = m_colorPicker;
            } else if (row==kFrotzPrefsBGColor) {
                [m_colorPicker setTextColor: [m_storyDelegate textColor] bgColor: [m_storyDelegate backgroundColor] changeText:NO];
                m_colorPicker.title = NSLocalizedString(@"Background Color \u29C9", @"");
                viewController = m_colorPicker;
            } else if (row==kFrotzPrefsStoryFont) {
                viewController = m_storyFontPicker;
            } else if (row==kFrotzPrefsNotesFont)
                viewController = m_notesFontPicker;
            else if (row==kFrotzPrefsCommandConfirmation)
                viewController = [[FrotzCommandConfirmationController alloc] init];
            else if (row==kFrotzPrefsSpeechVoice)
                viewController = [[FrotzSpeechVoiceController alloc] init];
            else if (row==kFrotzPrefsSpeechLanguage)
                viewController = [[FrotzSpeechLanguageController alloc] init];
#if UseDropBoxSDK && defined(FROTZ_DB_APP_KEY)
            else if (row==kFrotzPrefsDropbox) {
                viewController = m_frotzDB;
            }
#endif
            break;
        case kFrotzResetSection: {
            m_resetting = YES;
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Reset Preferences"
                message: @"Do you want to reset all color and font settings to their defaults?"
                delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles: @"OK", nil];
            [alert show];
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
        }

        [[self navigationController] pushViewController: viewController animated: YES];
        [tableView deselectRowAtIndexPath:indexPath animated:NO];
    }
}

@end

