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

#import "FrotzAlert.h"
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
        self.title = @"Narration Voice";
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
        self.title = @"Input Language";
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

// Runtime availability is independent of the player's toolbar mode choices.
@interface FrotzVoiceSettingsController : FrotzSpeechSettingsController
@end
@implementation FrotzVoiceSettingsController
- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
        self.title = @"Voice";
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(accessibilityChanged:)
            name:UIAccessibilityVoiceOverStatusDidChangeNotification object:nil];
    }
    return self;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)accessibilityChanged:(NSNotification *)note { [self.tableView reloadData]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64;
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? (FROTZ_ENABLE_DICTATION ? 4 : 0) : section == 1 ? (FROTZ_ENABLE_NARRATION ? 3 : 0) : 0;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 && FROTZ_ENABLE_DICTATION ? @"Dictation" : section == 1 && FROTZ_ENABLE_NARRATION ? @"Voice Narration" : nil;
}
- (NSString *)helpTextForSection:(NSInteger)section {
    if (section == 0 && FROTZ_ENABLE_DICTATION)
        return @"Show the app's microphone control. Use it during play to enable dictation, then start or pause listening in the bar below the story. Story taps page or select words while dictation is enabled. The system keyboard's dictation button is separate and does not submit commands automatically. Re-enabling this setting does not start recording.";
    if (section == 1 && FROTZ_ENABLE_NARRATION)
        return @"Show the narration control. Use it during play to turn automatic reading on or off. Choose an installed voice and tap it for a preview. For clearer voices, download an Enhanced or Premium voice in iOS Settings → Accessibility → Read & Speak → Voices (Spoken Content on older iOS). Only voices exposed by iOS appear here.";
    if (section == 2) {
        if ([VoiceManager shared].isVoiceOverEnabled)
            return @"VoiceOver uses its own voice and rate. Moving VoiceOver focus pauses dictation so UI speech is not submitted as a command. Use a two-finger double-tap to start or stop listening. Replay last response is also in the controls' Actions menu. A rising tone means listening is ready; a falling pair means navigation paused it; three low tones indicate an error. VoiceOver still announces command review when spoken confirmations are off.";
        return @"VoiceOver uses its own voice settings. Additional VoiceOver instructions appear here when it is enabled. Keyboard input remains available in every mode.";
    }
    return nil;
}
- (UISwitch *)switchWithTag:(NSInteger)tag on:(BOOL)on label:(NSString *)label {
    UISwitch *control = [UISwitch new];
    control.tag = tag; control.on = on; control.accessibilityLabel = label;
    [control addTarget:self action:@selector(availabilityChanged:) forControlEvents:UIControlEventValueChanged];
    return control;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.numberOfLines = cell.detailTextLabel.numberOfLines = 0;
    VoiceManager *manager = [VoiceManager shared];
    if (path.section == 0) {
        cell.textLabel.text = @[@"Dictation Available", @"Input Language", @"Command Confirmation", @"Speak Command Confirmations"][path.row];
        if (path.row == 0) cell.accessoryView = [self switchWithTag:1 on:manager.dictationAvailable label:cell.textLabel.text];
        else if (path.row == 3) {
            cell.accessoryView = [self switchWithTag:3 on:manager.speakCommandConfirmations label:cell.textLabel.text];
            cell.detailTextLabel.text = @"Read review prompts aloud, independently of story narration. VoiceOver follows its own announcement path.";
        } else {
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.detailTextLabel.text = path.row == 1 ? (manager.speechRecognitionLanguage ? ([NSLocale.currentLocale localizedStringForLocaleIdentifier:manager.effectiveRecognitionLanguage] ?: manager.effectiveRecognitionLanguage) : @"Automatic — story language") : manager.commandConfirmationDescription;
        }
    } else {
        cell.textLabel.text = @[@"Narration Available", @"Narration Voice", @"Narration Rate"][path.row];
        if (path.row == 0) cell.accessoryView = [self switchWithTag:2 on:manager.narrationAvailable label:cell.textLabel.text];
        else if (path.row == 1) {
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.detailTextLabel.text = manager.speechVoiceDescription;
        } else {
            UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 130, 44)];
            slider.minimumValue = 0.5; slider.maximumValue = 3; slider.value = manager.speechRate;
            slider.accessibilityLabel = @"Narration Rate";
            slider.accessibilityValue = [NSString stringWithFormat:@"%.1f times", manager.speechRate];
            [slider addTarget:self action:@selector(rateChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = slider;
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.1f×", manager.speechRate];
        }
    }
    cell.selectionStyle = cell.accessoryView ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;
    return cell;
}
- (void)availabilityChanged:(UISwitch *)control {
    VoiceManager *manager = [VoiceManager shared];
    if (control.tag == 1) manager.dictationAvailable = control.on;
    else if (control.tag == 2) manager.narrationAvailable = control.on;
    else manager.speakCommandConfirmations = control.on;
    [manager savePreferences];
}
- (void)rateChanged:(UISlider *)slider {
    [VoiceManager shared].speechRate = slider.value;
    slider.accessibilityValue = [NSString stringWithFormat:@"%.1f times", slider.value];
    UITableViewCell *cell = (id)slider.superview;
    while (cell && ![cell isKindOfClass:UITableViewCell.class]) cell = (id)cell.superview;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%.1f×", slider.value];
    [[VoiceManager shared] savePreferences];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    UIViewController *next = nil;
    if (path.section == 0 && path.row == 1) next = [FrotzSpeechLanguageController new];
    else if (path.section == 0 && path.row == 2) next = [FrotzCommandConfirmationController new];
    else if (path.section == 1 && path.row == 1) next = [FrotzSpeechVoiceController new];
    if (next) [self.navigationController pushViewController:next animated:YES];
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
    // Retired root rows retain their original integer values.
    kFrotzPrefsTTS,
    kFrotzPrefsSTT,
    kFrotzPrefsCommandConfirmation,
    kFrotzPrefsSpeechVoice,
    kFrotzPrefsSpeechLanguage,
    kFrotzPrefsSpeechRate,
#if UseDropBoxSDK && defined(FROTZ_DB_APP_KEY)
    kFrotzPrefsDropbox,
#endif
    kFrotzPrefsVoice,
    kFrotzPrefsNumRows
};

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


}

- (void)switchAction:(id)sender
{
    if (sender == m_switchCtl)
        [m_storyDelegate setCompletionEnabled:[sender isOn]];
    else if (sender == m_switchCtl2)
        [m_storyDelegate setCanEditStoryInfo:[sender isOn]];
}

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
    return nil; // Detailed help is on the Voice page.
}

- (NSArray<NSNumber *> *)visiblePreferenceRows {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSInteger row = 0; row < kFrotzPrefsNumRows; ++row) {
        BOOL narrationRow = row == kFrotzPrefsTTS || row == kFrotzPrefsSpeechVoice || row == kFrotzPrefsSpeechRate;
        BOOL dictationRow = row == kFrotzPrefsSTT || row == kFrotzPrefsCommandConfirmation || row == kFrotzPrefsSpeechLanguage;
        if (narrationRow || dictationRow) continue;
        if (row == kFrotzPrefsVoice && !FROTZ_ENABLE_NARRATION && !FROTZ_ENABLE_DICTATION) continue;
        [rows addObject:@(row)];
    }
    return rows;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == kFrotzInfoSection) {
        return kFrotzInfoNumRows;
    } else if (section == kFrotzResetSection)
        return 1;
    return self.visiblePreferenceRows.count;
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
    if (indexPath.section == kFrotzPrefsSection) row = [self.visiblePreferenceRows[row] integerValue];
    UITableViewCell *cell = [self obtainTableCellForRow:row];
    if (indexPath.section == kFrotzPrefsSection && row >= kFrotzPrefsStoryFontSize
        && row != kFrotzPrefsNotesFont
        && row != kFrotzPrefsVoice
#if UseDropBoxSDK && defined(FROTZ_DB_APP_KEY)
        && row != kFrotzPrefsDropbox
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
                case kFrotzPrefsVoice:
                    cell.textLabel.text = @"Voice";
                    break;
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
    if (section == kFrotzPrefsSection) row = [self.visiblePreferenceRows[row] integerValue];
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
            if (row==kFrotzPrefsVoice) {
                viewController = [FrotzVoiceSettingsController new];
            } else if (row==kFrotzPrefsTextColor) {
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
#if UseDropBoxSDK && defined(FROTZ_DB_APP_KEY)
            else if (row==kFrotzPrefsDropbox) {
                viewController = m_frotzDB;
            }
#endif
            break;
        case kFrotzResetSection: {
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
                    [[self tableView] reloadData];
                }
            });
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

