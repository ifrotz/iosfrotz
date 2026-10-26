#import <XCTest/XCTest.h>
#import "VoiceManager.h"
#import "RichTextView.h"
#import "StoryMainViewController.h"
#import "StoryInputLine.h"
#import "StoryView.h"
#import "GlkView.h"
#import "FrotzSettings.h"
#import "FrotzAppDelegate.h"
#import "FrotzInfo.h"
#import <objc/runtime.h>

// Each case owns these preferences, including when rerunning a previously used QA app.
@interface VoicePreferenceIsolatedTestCase : XCTestCase
@property (nonatomic, copy) NSDictionary<NSString *, id> *savedFeaturePreferences;
@end
@implementation VoicePreferenceIsolatedTestCase
- (void)setUp {
    [super setUp];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSMutableDictionary *saved = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"FrotzSpeakCommandConfirmations", @"FrotzNarrationAvailable", @"FrotzDictationAvailable"]) {
        saved[key] = [defaults objectForKey:key] ?: NSNull.null;
        [defaults removeObjectForKey:key];
    }
    self.savedFeaturePreferences = saved;
}
- (void)tearDown {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    for (NSString *key in self.savedFeaturePreferences) {
        id value = self.savedFeaturePreferences[key];
        if (value == NSNull.null) [defaults removeObjectForKey:key];
        else [defaults setObject:value forKey:key];
    }
    self.savedFeaturePreferences = nil;
    [super tearDown];
}
@end

@interface UITableViewController (VoiceHelpTesting)
- (NSString *)helpTextForSection:(NSInteger)section;
@end

@interface FrotzSettingsController (ConfirmationTesting)
- (void)create_UISwitches;
@end

@interface StoryInputLine (ReplayTesting)
- (void)delayedInput:(NSString *)text;
@end

@interface TestEditingInputLine : StoryInputLine
@end
@implementation TestEditingInputLine
- (BOOL)isFirstResponder { return YES; }
@end

@interface StoryMainViewController (VoiceTesting)
- (BOOL)shouldActivateKeyboardForStoryTap;
- (void)setupLegacyVoiceToolbar;
- (void)showVoiceControls:(id)sender;
- (void)performVoiceFallbackAction:(NSString *)action;
- (BOOL)activateVoiceInput;
- (void)setupVoiceToolbar;
- (void)updateVoiceButtonIcons;
- (void)toggleTTS;
- (void)keyboardDidShow:(NSNotification *)notification;
- (CGFloat)voiceControlBarHeightForWidth:(CGFloat)width;
- (BOOL)canAcceptVoiceInput;
- (RichTextView *)voiceInputView;
- (void)refreshVoicePresentationForInputWindow;
- (void)setupVoiceTapOverlay;
- (BOOL)replayLastVoiceResponse:(UIAccessibilityCustomAction *)action;
- (void)startVoiceListeningAnimation;
- (void)scheduleVoiceListening;
- (void)stopVoiceActivity;
- (void)finishStoryNarration:(BOOL)unreadableStory inView:(RichTextView *)view voiceManager:(VoiceManager *)manager;
@end

@interface TestStoryController : StoryMainViewController
@property NSMutableArray<NSString *> *submittedCommands;
@property RichTextView *voiceOwnerOverride;
@end
@implementation TestStoryController
- (BOOL)canAcceptVoiceInput { return YES; }
- (RichTextView *)voiceInputView { return self.voiceOwnerOverride ?: [super voiceInputView]; }
- (void)autosize {} // Keep keyboard-layout work outside these voice-state tests.
- (void)textFieldFakeDidEndEditing:(UITextField *)field {
    if (!self.submittedCommands) self.submittedCommands = [NSMutableArray array];
    [self.submittedCommands addObject:field.text ?: @""];
}
@end

// Exercise the real StoryView tap route without bringing up a system keyboard.
@interface TestStoryTouch : NSObject
@property NSUInteger tapCount;
@property UITouchPhase phase;
@property NSTimeInterval timestamp;
@property UIView *view;
- (CGPoint)locationInView:(UIView *)view;
@end
@implementation TestStoryTouch
- (CGPoint)locationInView:(UIView *)view { return CGPointMake(100, 100); }
@end
@interface TestTapPolicyController : TestStoryController
@property NSUInteger keyboardToggles;
@end
@implementation TestTapPolicyController
- (NSString *)currentStory { return @"fixture.z5"; }
- (BOOL)isKBShown { return NO; }
- (void)forceToggleKeyboard { ++self.keyboardToggles; }
@end

@interface TestReviewController : TestTapPolicyController
@property UIViewController *capturedPresentation;
@property NSUInteger keyboardActivations;
@property NSUInteger gameTapEvents;
@property BOOL handlesGameTap;
@end
@implementation TestReviewController
- (void)activateKeyboard { ++self.keyboardActivations; }
- (BOOL)scrollStoryViewOnePage:(UIScrollView *)view fraction:(CGFloat)fraction { return NO; }
- (BOOL)splashVisible { return NO; }
- (BOOL)tapInView:(UIView *)view atPoint:(CGPoint)point { ++self.gameTapEvents; return self.handlesGameTap; }
- (UIViewController *)presentedViewController { return self.capturedPresentation; }
- (void)presentViewController:(UIViewController *)viewController animated:(BOOL)animated completion:(void (^)(void))completion {
    self.capturedPresentation = viewController;
    if (completion) completion();
}
- (void)dismissViewControllerAnimated:(BOOL)animated completion:(void (^)(void))completion {
    self.capturedPresentation = nil;
    if (completion) completion();
}
@end
@interface TestReviewGlkView : GlkView
@end
@implementation TestReviewGlkView
- (BOOL)handleMagnifyTouchWithPhase:(UITouchPhase)phase atPoint:(CGPoint)point { return YES; }
@end

@interface TestEndingController : StoryMainViewController
@property BOOL abandoned;
@end
@implementation TestEndingController
- (void)abandonStory:(BOOL)deleteAutoSave {
    self.abandoned = YES;
    [m_voiceOutputBuffers removeAllObjects];
    m_voiceSessionActive = NO;
    m_storyTID = 0;
}
@end

@interface VoiceManager (Testing)
@property (nonatomic) BOOL speakCommandConfirmations, narrationAvailable, dictationAvailable, narrationSelected, dictationSelected;
+ (AVSpeechSynthesisVoice *)automaticVoiceFromVoices:(NSArray<AVSpeechSynthesisVoice *> *)voices;
+ (AVSpeechSynthesisVoice *)automaticVoiceFromVoices:(NSArray<AVSpeechSynthesisVoice *> *)voices language:(NSString *)language;
+ (NSString *)languageFromBlorbAtPath:(NSString *)path;
+ (NSString *)recognitionLanguageForLanguage:(NSString *)language;
- (BOOL)recordingIsAuthorized;
- (BOOL)configureAudioSessionForRecording;
- (BOOL)configureAudioSessionForPlayback;
- (AVAudioSession *)recordingAudioSession;
- (void)deactivateAudioSession;
- (void)silenceTimerFired;
- (void)recognitionTimedOut;
- (BOOL)isVoiceOverEnabled;
- (BOOL)voiceOverNavigationPaused;
- (void)resumeAfterVoiceOverNavigation;
- (void)postAccessibilityAnnouncement:(NSString *)text;
@property (nonatomic, readonly) NSString *lastStoryResponse;
- (void)rememberStoryResponse:(NSString *)text;
- (BOOL)replayLastStoryResponse;
- (void)playVoiceFeedback:(VoiceFeedback)feedback;
@end

// Synthetic voice metadata covers Premium ranking without depending on installed downloads.
@interface TestSpeechVoice : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *language;
@property AVSpeechSynthesisVoiceQuality quality;
@end
@implementation TestSpeechVoice
@end

@interface RichTextView (Testing)
- (UIColor *)getCurrentTextColor;
@end

// Keep the tests independent of microphone permission, hardware and Apple's speech service.
@interface TestVoiceManager : VoiceManager
@property (nonatomic, copy) void (^permissionCompletion)(BOOL);
@property BOOL recordingAllowed;
@property NSString *confirmationPrompt;
@property BOOL voiceOverRunning;
@property NSMutableArray<NSNumber *> *feedback;
@property NSMutableArray<NSString *> *announcements;
@property NSUInteger audioDeactivations;
@end
@implementation TestVoiceManager
- (void)requestSTTPermissionsWithCompletion:(void (^)(BOOL))completion { self.permissionCompletion = completion; }
- (BOOL)isVoiceOverEnabled { return self.voiceOverRunning; }
- (void)playVoiceFeedback:(VoiceFeedback)feedback {
    if (!self.feedback) self.feedback = [NSMutableArray array];
    [self.feedback addObject:@(feedback)];
}
- (void)postAccessibilityAnnouncement:(NSString *)text {
    if (!self.announcements) self.announcements = [NSMutableArray array];
    [self.announcements addObject:text];
}
- (BOOL)recordingIsAuthorized { return self.recordingAllowed; }
- (BOOL)configureAudioSessionForRecording { return YES; }
- (void)deactivateAudioSession { ++self.audioDeactivations; }
- (void)speakConfirmationPrompt:(NSString *)text {
    self.confirmationPrompt = text;
    if (self.voiceOverRunning) [super speakConfirmationPrompt:text];
}
@end

@interface TestSynthesizer : NSObject
@property (getter=isSpeaking) BOOL speaking;
@property NSUInteger utterances;
@property NSUInteger stops;
@property NSMutableArray<AVSpeechUtterance *> *queuedUtterances;
@end
@implementation TestSynthesizer
- (void)speakUtterance:(AVSpeechUtterance *)utterance {
    self.speaking = YES; ++self.utterances;
    if (!self.queuedUtterances) self.queuedUtterances = [NSMutableArray array];
    [self.queuedUtterances addObject:utterance];
}
- (BOOL)stopSpeakingAtBoundary:(AVSpeechBoundary)boundary { ++self.stops; self.speaking = NO; return YES; }
@end

@interface TestNarrationManager : TestVoiceManager
@property (nonatomic, copy) NSString *spokenText;
@end
@implementation TestNarrationManager
- (void)speakText:(NSString *)text inView:(RichTextView *)view { self.spokenText = text; }
@end

@interface TestAudioInput : NSObject
@property BOOL tapInstalled;
@property NSUInteger installs;
@property NSUInteger removals;
@property BOOL invalidFormat;
@property BOOL voiceProcessingEnabled;
@property BOOL failVoiceProcessing;
@property BOOL processingWasEnabledWhenTapped;
@property AVAudioVoiceProcessingOtherAudioDuckingConfiguration voiceProcessingOtherAudioDuckingConfiguration;
@end
@implementation TestAudioInput
- (BOOL)isVoiceProcessingEnabled { return self.voiceProcessingEnabled; }
- (BOOL)setVoiceProcessingEnabled:(BOOL)enabled error:(NSError **)error {
    if (self.failVoiceProcessing) return NO;
    self.voiceProcessingEnabled = enabled;
    return YES;
}
- (AVAudioFormat *)outputFormatForBus:(AVAudioNodeBus)bus {
    return [[AVAudioFormat alloc] initStandardFormatWithSampleRate:self.invalidFormat ? 0 : 16000 channels:1];
}
- (void)installTapOnBus:(AVAudioNodeBus)bus bufferSize:(AVAudioFrameCount)size format:(AVAudioFormat *)format block:(AVAudioNodeTapBlock)block {
    NSAssert(!self.tapInstalled, @"A previous recording tap was not cleaned up");
    self.processingWasEnabledWhenTapped = self.voiceProcessingEnabled;
    self.tapInstalled = YES;
    ++self.installs;
}
- (void)removeTapOnBus:(AVAudioNodeBus)bus {
    self.tapInstalled = NO;
    ++self.removals;
}
@end

@interface TestAudioEngine : NSObject
@property (getter=isRunning) BOOL running;
@property BOOL failStart;
@property NSUInteger starts;
@property TestAudioInput *inputNode;
@end
@implementation TestAudioEngine
- (void)prepare {}
- (BOOL)startAndReturnError:(NSError **)error {
    ++self.starts;
    if (self.failStart) {
        if (error) *error = [NSError errorWithDomain:@"TestAudio" code:1 userInfo:nil];
        return NO;
    }
    self.running = YES;
    return YES;
}
- (void)stop { self.running = NO; }
@end

@interface TestRecognitionTask : NSObject
@end
@implementation TestRecognitionTask
- (void)cancel {}
@end

typedef void (^RecognitionHandler)(SFSpeechRecognitionResult *, NSError *);
@interface TestSpeechRecognizer : NSObject
@property NSMutableArray<RecognitionHandler> *handlers;
@property SFSpeechRecognitionRequest *lastRequest;
@property BOOL unavailable;
@end
@implementation TestSpeechRecognizer
- (NSLocale *)locale { return [NSLocale localeWithLocaleIdentifier:@"en-US"]; }
- (BOOL)isAvailable { return !self.unavailable; }
- (BOOL)supportsOnDeviceRecognition { return NO; }
- (id)recognitionTaskWithRequest:(SFSpeechRecognitionRequest *)request resultHandler:(RecognitionHandler)handler {
    self.lastRequest = request;
    [self.handlers addObject:[handler copy]];
    return [[TestRecognitionTask alloc] init];
}
@end

@interface TestSpeechSegment : NSObject
@property float confidence;
@end
@implementation TestSpeechSegment
@end

@interface TestTranscription : NSObject
@property NSString *formattedString;
@property NSArray *segments;
@end
@implementation TestTranscription
@end
@interface TestRecognitionResult : NSObject
@property (getter=isFinal) BOOL final;
@property TestTranscription *bestTranscription;
@property NSArray *transcriptions;
@end
@implementation TestRecognitionResult
@end

@interface TestVoiceDelegate : NSObject <VoiceManagerDelegate>
@property NSUInteger starts;
@property NSUInteger stops;
@property NSUInteger errors;
@property NSUInteger results;
@property NSString *lastText;
@property NSUInteger speakingStarts;
@property NSUInteger speakingFinishes;
@property BOOL keepAudioForListening;
@end
@implementation TestVoiceDelegate
- (void)voiceManagerDidStartSpeaking { ++self.speakingStarts; }
- (void)voiceManagerDidFinishSpeaking { ++self.speakingFinishes; }
- (BOOL)voiceManagerWillResumeListening { return self.keepAudioForListening; }
- (void)voiceManagerHighlightRange:(NSRange)range inView:(RichTextView *)view {}
- (void)voiceManagerDidClearHighlight {}
- (void)voiceManagerDidRecognizeText:(NSString *)text isFinal:(BOOL)isFinal {
    ++self.results;
    self.lastText = text;
}
- (void)voiceManagerDidStartListening { ++self.starts; }
- (void)voiceManagerDidStopListening { ++self.stops; }
- (void)voiceManagerSTTError:(NSError *)error { ++self.errors; }
@end

@interface LiveSpeechDelegate : TestVoiceDelegate
@property (nonatomic, strong) XCTestExpectation *finished;
@end
@implementation LiveSpeechDelegate
- (void)voiceManagerDidFinishSpeaking { [self.finished fulfill]; }
@end

@interface FrotzAppDelegate (VoiceGestureTesting)
- (StoryMainViewController *)voiceGestureStoryController;
@end
@interface TestVoiceGestureAppDelegate : FrotzAppDelegate
@property StoryMainViewController *voiceController;
@end
@implementation TestVoiceGestureAppDelegate
- (StoryMainViewController *)voiceGestureStoryController { return self.voiceController; }
@end

@interface TestRecordingSession : NSObject
@property BOOL cuesAllowed;
@property BOOL active;
@property BOOL cuesEnabledBeforeActivation;
@property NSString *category;
@property NSString *mode;
@property AVAudioSessionCategoryOptions categoryOptions;
@property NSUInteger categoryChanges;
@end
@implementation TestRecordingSession
- (BOOL)setCategory:(NSString *)category mode:(NSString *)mode options:(AVAudioSessionCategoryOptions)options error:(NSError **)error {
    self.category = category; self.mode = mode; self.categoryOptions = options; ++self.categoryChanges; return YES;
}
- (BOOL)setAllowHapticsAndSystemSoundsDuringRecording:(BOOL)allowed error:(NSError **)error {
    self.cuesAllowed = allowed;
    self.cuesEnabledBeforeActivation = allowed && !self.active;
    return YES;
}
- (BOOL)setActive:(BOOL)active error:(NSError **)error { self.active = active; return YES; }
@end
@interface TestRecordingSessionManager : VoiceManager
@property TestRecordingSession *session;
@end
@implementation TestRecordingSessionManager
- (AVAudioSession *)recordingAudioSession { return (id)self.session; }
@end

@interface FrotzVoiceTests : VoicePreferenceIsolatedTestCase
@property TestVoiceManager *manager;
@property TestAudioEngine *engine;
@property TestSpeechRecognizer *recognizer;
@property TestVoiceDelegate *voiceDelegate;
@end

@implementation FrotzVoiceTests
- (void)withReviewController:(void (^)(TestReviewController *controller))test {
    [self withSavedVoiceDefaults:^(NSUserDefaults *defaults) {
        [self withAutomaticListeningController:^(TestStoryController *unused) {
            TestReviewController *controller = [TestReviewController new];
            StoryInputLine *input = [[StoryInputLine alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
            [controller setValue:input forKey:@"m_inputLine"];
            RichTextView *story = [[RichTextView alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
            [story appendText:@"A gown and a table are here."];
            [controller setValue:story forKey:@"m_storyView"];
            [controller setValue:@YES forKey:@"m_voiceSessionActive"];
            [controller setValue:@YES forKey:@"m_voiceAutoListenReady"];
            [controller setValue:@YES forKey:@"m_handsFreeAutoLoop"];
            [controller setupVoiceTapOverlay];
            [controller setupVoiceToolbar];
            self.manager.delegate = controller;
            self.manager.commandConfirmationMode = VoiceCommandConfirmationOff;
            int savedInput = ipzAllowInput, savedWindow = cwin;
            ipzAllowInput = kIPZRequestInput; cwin = 0;
            @try { test(controller); }
            @finally {
                [controller stopVoiceActivity];
                ipzAllowInput = savedInput; cwin = savedWindow;
            }
        }];
    }];
}
- (void)testTypingEditsSurviveFurtherSelectionsWithDictationModeEnabled {
    [self withReviewController:^(TestReviewController *controller) {
        TestEditingInputLine *input = [[TestEditingInputLine alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
        [controller setValue:input forKey:@"m_inputLine"];
        input.text = @"put";
        [controller textSelected:@"gown" animDuration:0 hilightView:nil];
        input.text = [input.text stringByAppendingString:@" on"];
        [controller textSelected:@"table" animDuration:0 hilightView:nil];
        XCTAssertEqualObjects(input.text, @"put gown on table");
        [controller textFieldFakeDidEndEditing:input];
        input.text = @"open";
        [controller textSelected:@"box" animDuration:0 hilightView:nil];
        XCTAssertEqualObjects(input.text, @"open box");
    }];
}
- (void)testManualReturnEndsSelectionCompositionBeforeNextTurn {
    [self withReviewController:^(TestReviewController *controller) {
        [controller textSelected:@"gown" animDuration:0 hilightView:nil];
        XCTAssertTrue([controller textFieldShouldReturn:controller.inputLine]);
        XCTestExpectation *submitted = [self expectationWithDescription:@"manual return delivered"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [submitted fulfill]; });
        [self waitForExpectations:@[submitted] timeout:2];
        XCTAssertNil([controller valueForKey:@"m_voiceSelectedText"]);
        XCTAssertNil([controller valueForKey:@"m_voicePartialText"]);
        XCTAssertEqualObjects(controller.submittedCommands, (@[@"gown"]));
    }];
}
- (void)testSelectedWordBeforeMicrophoneStartSurvivesTheSpokenTurn {
    [self withReviewController:^(TestReviewController *controller) {
        [controller textSelected:@"gown" animDuration:0 hilightView:nil];
        [controller scheduleVoiceListening]; [self drainCallbacks];
        [self sendAlternatives:@[@"take"] confidence:0.95];
        XCTAssertEqualObjects(controller.submittedCommands, (@[@"take gown"]));
    }];
}
- (void)testFinalTranscriptAlreadyContainingSelectedPhraseDoesNotDuplicateIt {
    [self withReviewController:^(TestReviewController *controller) {
        [controller scheduleVoiceListening]; [self drainCallbacks];
        [self sendText:@"take" final:NO handler:self.recognizer.handlers.lastObject];
        [controller textSelected:@"gown" animDuration:0 hilightView:nil];
        [self sendAlternatives:@[@"take gown from table"] confidence:0.95];
        XCTAssertEqualObjects(controller.submittedCommands, (@[@"take gown from table"]));
    }];
}
- (void)testGlkStoryTapsKeepDictationAndGameOwnedEventsSeparate {
    [self withReviewController:^(TestReviewController *controller) {
        TestReviewGlkView *story = [[TestReviewGlkView alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
        story.delegate = controller;
        TestStoryTouch *touch = [TestStoryTouch new];
        touch.phase = UITouchPhaseEnded; touch.timestamp = 20000;
        for (NSNumber *mode in @[@(VoiceModeSTTOnly), @(VoiceModeOff)]) {
            self.manager.voiceMode = mode.integerValue;
            NSUInteger before = controller.keyboardActivations;
            touch.tapCount = 2; [story handleTouch:(id)touch withEvent:nil];
            touch.tapCount = 1; [story handleTouch:(id)touch withEvent:nil];
            XCTestExpectation *single = [self expectationWithDescription:@"Glk single tap resolved"];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [single fulfill]; });
            [self waitForExpectations:@[single] timeout:2];
            XCTAssertEqual(controller.keyboardActivations - before, mode.integerValue == VoiceModeOff ? 2u : 0u);
        }
        self.manager.voiceMode = VoiceModeSTTOnly;
        story.tapInputEnabled = YES; controller.handlesGameTap = YES;
        NSUInteger before = controller.keyboardActivations;
        touch.tapCount = 1; [story handleTouch:(id)touch withEvent:nil];
        XCTAssertEqual(controller.gameTapEvents, 1u);
        XCTAssertEqual(controller.keyboardActivations, before);
    }];
}
- (void)testLegacyVoiceToolbarCanEnableBothModesWithoutSystemSymbols {
    [self withReviewController:^(TestReviewController *controller) {
        self.manager.voiceMode = VoiceModeOff;
        [controller setupLegacyVoiceToolbar];
        UIBarButtonItem *voice = nil;
        for (UIBarButtonItem *item in controller.navigationItem.rightBarButtonItems)
            if ([item.accessibilityIdentifier isEqualToString:@"voiceLegacyControls"]) voice = item;
        XCTAssertNotNil(voice); XCTAssertEqual(voice.action, @selector(showVoiceControls:));
        [controller showVoiceControls:voice];
        [controller performVoiceFallbackAction:@"narration"];
        XCTAssertTrue(self.manager.ttsEnabled);
        [controller showVoiceControls:voice];
        [controller performVoiceFallbackAction:@"dictation"];
        void (^reply)(BOOL) = self.manager.permissionCompletion;
        self.manager.permissionCompletion = nil;
        XCTAssertNotNil(reply); if (reply) reply(YES);
        XCTAssertTrue(self.manager.sttEnabled);
        XCTAssertFalse(self.manager.isListening, @"Mode configuration must not start capture");
    }];
}
- (void)testHiddenVoiceBarStillOffersTouchCaptureAndCommandReview {
    [self withReviewController:^(TestReviewController *controller) {
        UIView *background = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 240, 70)];
        [controller setValue:background forKey:@"m_background"];
        RichTextView *story = (id)controller.storyView; story.frame = background.bounds;
        [background addSubview:story];
        [controller setValue:@"take gown" forKey:@"m_pendingVoiceCommand"];
        [controller refreshVoicePresentationForInputWindow];
        XCTAssertNil(((UIView *)[controller valueForKey:@"m_voiceTapOverlay"]).superview);
        [controller toggleSTT];
        UIAlertController *menu = (id)controller.capturedPresentation;
        XCTAssertTrue([menu isKindOfClass:UIAlertController.class]);
        NSArray *titles = [menu.actions valueForKey:@"title"];
        XCTAssertTrue([titles containsObject:@"Confirm command"]);
        XCTAssertTrue([titles containsObject:@"Retry command"]);
        XCTAssertTrue([titles containsObject:@"Cancel command"]);
        XCTAssertTrue(self.manager.sttEnabled);
        [controller performVoiceFallbackAction:@"confirm"];
        [controller performVoiceFallbackAction:@"confirm"];
        XCTAssertEqualObjects(controller.submittedCommands, (@[@"take gown"]));
        [controller textSelected:@"gown" animDuration:0 hilightView:nil];
        [controller showVoiceControls:nil];
        XCTAssertEqualObjects([controller valueForKey:@"m_voiceSelectedText"], @"gown");
        [controller performVoiceFallbackAction:@"listen"];
        [self drainCallbacks]; XCTAssertTrue(self.manager.isListening);
        [controller performVoiceFallbackAction:@"listen"];
        [self.manager stopListening];
        [controller voiceManagerSTTError:[NSError errorWithDomain:@"test" code:1 userInfo:nil]];
        [controller showVoiceControls:nil];
        XCTAssertTrue([[(UIAlertController *)controller.capturedPresentation actions] valueForKey:@"title"] != nil);
        [controller performVoiceFallbackAction:@"listen"];
        [self drainCallbacks]; XCTAssertTrue(self.manager.isListening);
    }];
}
- (void)testFallbackMenuActionsCannotResumeAfterLeavingAndReturning {
    [self withReviewController:^(TestReviewController *controller) {
        [controller showVoiceControls:nil];
        [controller stopVoiceActivity];
        [controller setValue:@YES forKey:@"m_voiceSessionActive"];
        self.manager.delegate = controller;
        [controller performVoiceFallbackAction:@"listen"];
        [self drainCallbacks];
        XCTAssertFalse(self.manager.isListening);
        XCTAssertEqual(self.engine.starts, 0u);
        XCTAssertEqual(controller.submittedCommands.count, 0u);
    }];
}
- (void)testVoiceOverFallbackStartWaitsForItsOwnedAnnouncement {
    [self withReviewController:^(TestReviewController *controller) {
        self.manager.voiceOverRunning = YES;
        self.manager.speakCommandConfirmations = NO;
        [controller showVoiceControls:nil];
        [controller performVoiceFallbackAction:@"listen"];
        [self drainCallbacks];
        XCTAssertTrue(self.manager.isSpeaking);
        XCTAssertFalse(self.manager.isListening);
        NSString *announcement = self.manager.announcements.lastObject;
        XCTAssertNotNil(announcement);
        if (announcement) [NSNotificationCenter.defaultCenter postNotificationName:UIAccessibilityAnnouncementDidFinishNotification object:nil userInfo:@{UIAccessibilityAnnouncementKeyStringValue:announcement, UIAccessibilityAnnouncementKeyWasSuccessful:@YES}];
        [self drainCallbacks];
        XCTAssertTrue(self.manager.isListening);
    }];
}
- (void)testDictationTripleTapDoesNotSuppressTheNextWordSelection {
    [self withAutomaticListeningController:^(TestStoryController *unused) {
        TestTapPolicyController *controller = [TestTapPolicyController new];
        StoryView *story = [[StoryView alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
        story.delegate = controller;
        TestStoryTouch *touch = [TestStoryTouch new];
        touch.tapCount = 3; touch.phase = UITouchPhaseEnded; touch.timestamp = 10000;
        self.manager.voiceMode = VoiceModeSTTOnly;
        [story handleTouch:(id)touch withEvent:nil];
        XCTAssertFalse([[controller valueForKey:@"m_ignoreWordSelection"] boolValue]);
        XCTAssertEqual(controller.keyboardToggles, 0u);
        self.manager.voiceMode = VoiceModeOff;
        [story handleTouch:(id)touch withEvent:nil];
        XCTAssertTrue([[controller valueForKey:@"m_ignoreWordSelection"] boolValue]);
        XCTAssertEqual(controller.keyboardToggles, 1u, @"Classic triple-tap keeps its existing behavior");
    }];
}
- (void)testStoryTapKeepsDictationActiveButClassicTapStillTypes {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        self.manager.voiceMode = VoiceModeSTTOnly;
        XCTAssertFalse([controller shouldActivateKeyboardForStoryTap]);
        self.manager.voiceMode = VoiceModeTTSOnly;
        XCTAssertTrue([controller shouldActivateKeyboardForStoryTap]);
        self.manager.voiceMode = VoiceModeOff;
        XCTAssertTrue([controller shouldActivateKeyboardForStoryTap]);
    }];
}
- (void)testSelectedWordsSurviveChangingPartialAndFinalRecognition {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        self.manager.commandConfirmationMode = VoiceCommandConfirmationOff;
        [controller voiceManagerDidRecognizeText:@"take" isFinal:NO];
        int saved = ipzAllowInput;
        ipzAllowInput = kIPZRequestInput;
        [controller textSelected:@"gown" animDuration:0 hilightView:nil];
        XCTestExpectation *selection = [self expectationWithDescription:@"selection copied"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [selection fulfill]; });
        [self waitForExpectations:@[selection] timeout:1];
        [controller voiceManagerDidRecognizeText:@"take the" isFinal:NO];
        XCTAssertEqualObjects([controller inputLine].text, @"take the gown");
        [controller voiceManagerDidRecognizeText:@"take gown" isFinal:YES];
        XCTAssertEqualObjects(controller.submittedCommands, (@[@"take gown"]));
        ipzAllowInput = saved;
    }];
}
- (void)testRepeatedSelectionDoesNotSubmitAndCancellationClearsComposition {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        self.manager.commandConfirmationMode = VoiceCommandConfirmationOff;
        int saved = ipzAllowInput;
        @try {
            ipzAllowInput = kIPZRequestInput;
            [controller voiceManagerDidRecognizeText:@"put" isFinal:NO];
            [controller textSelected:@"gown" animDuration:0 hilightView:nil];
            [controller textSelected:@"on table" animDuration:0 hilightView:nil];
            XCTAssertEqualObjects([controller inputLine].text, @"put gown on table");
            XCTAssertEqual(controller.submittedCommands.count, 0u);
            [controller voiceManagerDidRecognizeText:@"put the" isFinal:NO];
            XCTAssertEqualObjects([controller inputLine].text, @"put the gown on table");
            [controller stopVoiceActivity];
            XCTAssertNil([controller valueForKey:@"m_voiceSelectedText"]);
            XCTAssertNil([controller valueForKey:@"m_voicePartialText"]);
        } @finally { ipzAllowInput = saved; }
    }];
}
- (void)testMissingConfidenceAloneDoesNotInterruptSmartConfirmation {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        [controller scheduleVoiceListening]; [self drainCallbacks];
        [self sendAlternatives:@[@"plugh"] confidence:0];
        XCTAssertEqualObjects(controller.submittedCommands, (@[@"plugh"]));
        XCTAssertNil([controller valueForKey:@"m_pendingVoiceCommand"]);
    }];
}
- (void)testSafeAmbiguityWithMissingScoresStillNeedsReview {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        [controller scheduleVoiceListening]; [self drainCallbacks];
        [self sendAlternatives:@[@"wet", @"west", @"wait"] confidence:0];
        XCTAssertTrue(self.manager.recognizedCommandNeedsConfirmation);
        XCTAssertEqual(controller.submittedCommands.count, 0u);
    }];
}
- (void)testChangedFinalCommandAfterEndAudioIsReviewedEvenWithHighConfidence {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        [controller scheduleVoiceListening]; [self drainCallbacks];
        [self sendText:@"take gown" final:NO handler:self.recognizer.handlers.lastObject];
        [self.manager silenceTimerFired];
        [self sendAlternatives:@[@"bake down"] confidence:0.95];
        XCTAssertEqual(controller.submittedCommands.count, 0u);
        XCTAssertEqualObjects([controller valueForKey:@"m_pendingVoiceCommand"], @"bake down");
    }];
}
- (void)testSpokenConfirmationPreferenceDefaultsOnAndPersistsOff {
    [self withSavedVoiceDefaults:^(NSUserDefaults *defaults) {
        [defaults removeObjectForKey:@"FrotzSpeakCommandConfirmations"];
        VoiceManager *fresh = [VoiceManager new];
        XCTAssertTrue(fresh.speakCommandConfirmations);
        fresh.speakCommandConfirmations = NO;
        [fresh savePreferences];
        XCTAssertFalse([VoiceManager new].speakCommandConfirmations);
    }];
}
- (void)testSilentConfirmationDoesNotSpeakButRemainsAvailableToVoiceOver {
    VoiceManager *manager = [VoiceManager new];
    manager.voiceMode = VoiceModeSTTOnly;
    manager.speakCommandConfirmations = NO;
    TestSynthesizer *synth = [TestSynthesizer new];
    [manager setValue:synth forKey:@"synthesizer"];
    [manager speakConfirmationPrompt:@"Say confirm, retry or cancel."];
    XCTAssertEqual(synth.utterances, 0u);
    self.manager.speakCommandConfirmations = NO;
    self.manager.voiceOverRunning = YES;
    [self.manager speakConfirmationPrompt:@"Say confirm, retry or cancel."];
    XCTAssertEqualObjects(self.manager.announcements.lastObject, @"Say confirm, retry or cancel.");
    [manager stopSpeaking];
}
- (void)testSilentPromptStartsConfirmationCaptureWithoutSubmittingTurn {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        self.manager.speakCommandConfirmations = NO;
        [controller scheduleVoiceListening]; [self drainCallbacks];
        [self sendAlternatives:@[@"bake down"] confidence:0.4];
        [self drainCallbacks];
        XCTAssertEqual(controller.submittedCommands.count, 0u);
        XCTAssertEqualObjects([controller valueForKey:@"m_pendingVoiceCommand"], @"bake down");
        XCTAssertTrue(self.manager.isListening);
    }];
}
- (void)testFailedConfirmationRecognitionKeepsTheCommandAndUsableButtons {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        [controller scheduleVoiceListening]; [self drainCallbacks];
        [self sendAlternatives:@[@"bake down"] confidence:0.4]; [self drainCallbacks];
        [self.manager stopListening];
        [controller voiceManagerSTTError:[NSError errorWithDomain:@"test" code:1 userInfo:nil]];
        XCTAssertEqualObjects([controller valueForKey:@"m_pendingVoiceCommand"], @"bake down");
        UIView *bar = [controller valueForKey:@"m_voiceTapOverlay"];
        UIButton *confirm = [bar viewWithTag:910];
        XCTAssertFalse(confirm.superview.hidden);
        XCTAssertNil(controller.presentedViewController);
        [confirm sendActionsForControlEvents:UIControlEventTouchUpInside];
        [confirm sendActionsForControlEvents:UIControlEventTouchUpInside];
        XCTAssertEqualObjects(controller.submittedCommands, (@[@"bake down"]));
    }];
}
- (void)testConfirmationPanelStaysOpaqueAndScrollableInAShortInputWindow {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        UIView *background = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 240, 150)];
        [controller setValue:background forKey:@"m_background"];
        RichTextView *story = (id)controller.storyView;
        story.frame = background.bounds;
        story.backgroundColor = UIColor.clearColor;
        [background addSubview:story];
        [controller setValue:UIColor.whiteColor forKey:@"m_defaultBGColor"];
        [controller scheduleVoiceListening]; [self drainCallbacks];
        [self sendAlternatives:@[@"bake down"] confidence:0.4]; [self drainCallbacks];
        [controller refreshVoicePresentationForInputWindow];
        UIView *bar = [controller valueForKey:@"m_voiceTapOverlay"];
        XCTAssertNotNil(bar.superview);
        XCTAssertEqual(CGColorGetAlpha(bar.backgroundColor.CGColor), 1);
        XCTAssertGreaterThanOrEqual(story.frame.size.height, 44);
        [bar layoutIfNeeded];
        UIScrollView *scroll = [bar viewWithTag:997];
        XCTAssertTrue([scroll isKindOfClass:UIScrollView.class]);
        XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.size.height);
        for (NSNumber *tag in @[@910, @911, @912]) {
            UIButton *button = [bar viewWithTag:tag.integerValue];
            XCTAssertGreaterThanOrEqual(button.bounds.size.width, 44);
            XCTAssertGreaterThanOrEqual(button.bounds.size.height, 44);
            XCTAssertTrue(button.isAccessibilityElement);
        }
    }];
}
- (void)testAvailabilityMigrationPreservesModeAndOtherPreferences {
    [self withSavedVoiceDefaults:^(NSUserDefaults *defaults) {
        [defaults removeObjectForKey:@"FrotzNarrationAvailable"];
        [defaults removeObjectForKey:@"FrotzDictationAvailable"];
        [defaults setInteger:VoiceModeBoth forKey:@"FrotzVoiceMode"];
        [defaults setFloat:1.4 forKey:@"FrotzSpeechRate"];
        VoiceManager *fresh = [TestVoiceManager new];
        XCTAssertTrue(fresh.narrationAvailable); XCTAssertTrue(fresh.dictationAvailable);
        fresh.dictationAvailable = NO;
        XCTAssertTrue(fresh.ttsEnabled); XCTAssertFalse(fresh.sttEnabled);
        [fresh savePreferences];
        XCTAssertEqual([defaults integerForKey:@"FrotzVoiceMode"], VoiceModeBoth);
        XCTAssertEqualWithAccuracy(fresh.speechRate, 1.4, 0.01);
        fresh.narrationSelected = NO;
        fresh.dictationAvailable = YES;
        XCTAssertFalse(fresh.ttsEnabled); XCTAssertTrue(fresh.sttEnabled);
        XCTAssertFalse(fresh.isListening);
        fresh.narrationAvailable = NO;
        [fresh rememberStoryResponse:@"The prior turn."];
        TestSynthesizer *synth = [TestSynthesizer new];
        [fresh setValue:synth forKey:@"synthesizer"];
        XCTAssertFalse([fresh replayLastStoryResponse]);
        XCTAssertEqual(synth.utterances, 0u);
    }];
}
- (void)testDisablingDictationCancelsCaptureAndPendingConfirmationOnly {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        [controller scheduleVoiceListening]; [self drainCallbacks];
        [self sendAlternatives:@[@"bake down"] confidence:0.4]; [self drainCallbacks];
        self.manager.dictationAvailable = NO;
        XCTAssertFalse(self.manager.isListening);
        XCTAssertNil([controller valueForKey:@"m_pendingVoiceCommand"]);
        self.manager.dictationAvailable = YES;
        [self drainCallbacks];
        XCTAssertFalse(self.manager.isListening);
        XCTAssertEqual(controller.submittedCommands.count, 0u);
    }];
}
- (void)testRootOffersOneVoicePageAndDetailsStayOnTheSubpage {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        FrotzSettingsController *settings = [FrotzSettingsController new];
        [settings loadViewIfNeeded];
        NSMutableArray *labels = [NSMutableArray array];
        for (NSInteger row = 0; row < [settings tableView:settings.tableView numberOfRowsInSection:1]; ++row)
            [labels addObject:[settings tableView:settings.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:1]].textLabel.text ?: @""];
        XCTAssertTrue([labels containsObject:@"Voice"]);
        XCTAssertFalse([labels containsObject:@"Text-to-Speech"]);
        XCTAssertFalse([labels containsObject:@"Voice Command Confirmation"]);
        UITableViewController *voice = [NSClassFromString(@"FrotzVoiceSettingsController") new];
        XCTAssertNotNil(voice);
        [voice loadViewIfNeeded];
        XCTAssertEqual([voice numberOfSectionsInTableView:voice.tableView], 3);
        self.manager.voiceOverRunning = NO;
        NSString *general = [(id)voice helpTextForSection:2];
        XCTAssertFalse([general containsString:@"two-finger"]);
        self.manager.voiceOverRunning = YES;
        XCTAssertTrue([[(id)voice helpTextForSection:2] containsString:@"two-finger"]);
    }];
}
- (void)testLateMicrophonePermissionCannotEnableAnInactiveStory {
    [self withSavedVoiceDefaults:^(NSUserDefaults *defaults) {
        [self withAutomaticListeningController:^(TestStoryController *controller) {
            self.manager.voiceMode = VoiceModeOff;
            [controller toggleSTT];
            void (^reply)(BOOL) = self.manager.permissionCompletion;
            self.manager.permissionCompletion = nil;
            XCTAssertNotNil(reply); if (!reply) return;
            [controller stopVoiceActivity];
            reply(YES);
            XCTAssertFalse(self.manager.sttEnabled);
        }];
    }];
}
- (void)testFailedRecordingPreflightReleasesAudioRetainedForHandoff {
    self.manager.voiceMode = VoiceModeBoth;
    self.voiceDelegate.keepAudioForListening = YES;
    for (NSUInteger failure = 0; failure < 3; ++failure) {
        self.manager.recordingAllowed = failure != 0;
        self.recognizer.unavailable = failure == 1;
        self.manager.speechRecognitionLanguage = failure == 2 ? @"zz-ZZ" : @"en-US";
        TestSynthesizer *synthesizer = [TestSynthesizer new];
        [self.manager setValue:synthesizer forKey:@"synthesizer"];
        AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:@"Post Office Hill."];
        [self.manager setValue:utterance forKey:@"activeUtterance"];
        [self.manager speechSynthesizer:(id)synthesizer didFinishSpeechUtterance:utterance];
        NSUInteger before = self.manager.audioDeactivations;
        [self.manager startListening];
        XCTAssertFalse(self.manager.isListening);
        XCTAssertGreaterThan(self.manager.audioDeactivations, before, @"Preflight failure %lu must release retained audio", (unsigned long)failure);
    }
}
- (void)testFinishedSpeechReleasesAudioWhenTheControllerWillNotRecord {
    self.manager.voiceMode = VoiceModeBoth;
    TestSynthesizer *synthesizer = [TestSynthesizer new];
    [self.manager setValue:synthesizer forKey:@"synthesizer"];
    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:@"You stand by an iron gate."];
    [self.manager setValue:utterance forKey:@"activeUtterance"];
    NSUInteger before = self.manager.audioDeactivations;
    [self.manager speechSynthesizer:(id)synthesizer didFinishSpeechUtterance:utterance];
    XCTAssertGreaterThan(self.manager.audioDeactivations, before, @"Typing or an inactive view must not hold a recording session indefinitely");
}
- (void)testConfirmationNarrationHasAStopControlWhenAutomaticNarrationIsOff {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        self.manager.voiceMode = VoiceModeSTTOnly;
        self.manager.voiceOverRunning = YES;
        [self.manager speakConfirmationPrompt:@"Say confirm, retry or cancel."];
        UIView *bar = [controller valueForKey:@"m_voiceTapOverlay"];
        UIButton *speech = [bar viewWithTag:905];
        XCTAssertFalse(speech.hidden);
        XCTAssertTrue(speech.enabled);
        XCTAssertEqualObjects(speech.accessibilityLabel, @"Stop reading");
    }];
}
- (void)testTypedCommandStaysInlineAndTransparentWithVoiceEnabled {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        UIView *bar = [controller valueForKey:@"m_voiceTapOverlay"];
        UIView *background = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 640)];
        [controller setValue:background forKey:@"m_background"];
        UIColor *paper = [UIColor colorWithWhite:0.95 alpha:1];
        [controller setValue:paper forKey:@"m_defaultBGColor"];
        [background addSubview:bar];
        bar.frame = CGRectMake(0, 500, 320, 60);
        TestEditingInputLine *input = [[TestEditingInputLine alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
        [input setStoryView:(id)controller.storyView];
        input.delegate = controller;
        [background addSubview:input];
        [controller setValue:input forKey:@"m_inputLine"];
        input.font = [UIFont systemFontOfSize:17];
        int savedInput = ipzAllowInput;
        ipzAllowInput = kIPZRequestInput;
        [input updatePosition];
        ipzAllowInput = savedInput;
        XCTAssertLessThan(CGRectGetMaxY(input.frame), 500);
        XCTAssertEqualWithAccuracy(input.bounds.size.height, input.font.lineHeight + 2, 0.1);
        XCTAssertFalse(CGRectIntersectsRect(input.frame, bar.frame));
        XCTAssertTrue(input.backgroundColor == nil || CGColorGetAlpha(input.backgroundColor.CGColor) == 0);
        XCTAssertNil(input.placeholder);
    }];
}
- (void)testListeningPreservesTransparentInputAndCurrentStoryColors {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        StoryInputLine *input = [controller valueForKey:@"m_inputLine"];
        input.backgroundColor = UIColor.clearColor;
        [controller voiceManagerDidStartListening];
        XCTAssertEqual(CGColorGetAlpha(input.backgroundColor.CGColor), 0);
        UIColor *paper = [UIColor colorWithRed:0.2 green:0.3 blue:0.4 alpha:1];
        [controller setBackgroundColor:paper makeDefault:NO];
        UIView *bar = [controller valueForKey:@"m_voiceTapOverlay"];
        XCTAssertEqualObjects(bar.backgroundColor, paper);
        [controller voiceManagerDidStopListening];
        XCTAssertEqual(CGColorGetAlpha(input.backgroundColor.CGColor), 0);
        XCTAssertEqualObjects(bar.backgroundColor, paper);
    }];
}
- (void)testVoiceAccessoryFollowsInputOwnerWithoutResizingSiblingWindows {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        UIView *background = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 640)];
        [controller setValue:background forKey:@"m_background"];
        RichTextView *first = (id)controller.storyView;
        first.frame = CGRectMake(0, 0, 160, 480);
        [background addSubview:first];
        UIView *map = [[UIView alloc] initWithFrame:CGRectMake(160, 0, 160, 480)];
        [background addSubview:map];
        RichTextView *second = [[RichTextView alloc] initWithFrame:CGRectMake(0, 100, 160, 380)];
        second.backgroundColor = UIColor.brownColor;
        [background addSubview:second];
        controller.voiceOwnerOverride = first;
        [controller refreshVoicePresentationForInputWindow];
        CGFloat reducedHeight = first.frame.size.height;
        XCTAssertLessThan(reducedHeight, 480);
        [controller refreshVoicePresentationForInputWindow];
        XCTAssertEqualWithAccuracy(first.frame.size.height, reducedHeight, 0.1);
        controller.voiceOwnerOverride = second;
        [controller refreshVoicePresentationForInputWindow];
        UIView *bar = [controller valueForKey:@"m_voiceTapOverlay"];
        XCTAssertEqualWithAccuracy(first.frame.size.height, 480, 0.1);
        XCTAssertEqualWithAccuracy(CGRectGetMaxY(bar.frame), 480, 0.1);
        XCTAssertEqualObjects(bar.backgroundColor, UIColor.brownColor);
        XCTAssertFalse(CGRectIntersectsRect(bar.frame, map.frame));
        XCTAssertTrue(CGRectEqualToRect(map.frame, CGRectMake(160, 0, 160, 480)));
        [second removeFromSuperview];
        [controller refreshVoicePresentationForInputWindow];
        XCTAssertNil(bar.superview);
    }];
}
- (void)testAccessoryRefreshPreservesTheGamesInputColorAndScrollPosition {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        UIView *background = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 640)];
        [controller setValue:background forKey:@"m_background"];
        RichTextView *story = (id)controller.storyView;
        story.frame = CGRectMake(0, 0, 320, 480);
        [background addSubview:story];
        [story setTextColor:UIColor.blackColor];
        [controller inputLine].textColor = UIColor.magentaColor; // e.g. a game-owned upper-window prompt
        [controller refreshVoicePresentationForInputWindow];
        XCTAssertEqualObjects([controller inputLine].textColor, UIColor.magentaColor);
        story.contentSize = CGSizeMake(320, 600);
        story.contentOffset = CGPointMake(0, 150);
        [controller refreshVoicePresentationForInputWindow];
        XCTAssertEqualWithAccuracy(story.contentOffset.y, 150, 0.1);
    }];
}
- (void)testAccessoryUsesTheActiveGamePaletteWithoutAnExtraTurn {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        UIView *background = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 640)];
        [controller setValue:background forKey:@"m_background"];
        RichTextView *story = (id)controller.storyView;
        [background addSubview:story];
        story.backgroundColor = UIColor.yellowColor;
        [story getOrAllocColorIndex:UIColor.orangeColor]; // index1 is the renderer's default sentinel
        story.bgColorIndex = [story getOrAllocColorIndex:UIColor.blackColor];
        story.textColorIndex = [story getOrAllocColorIndex:UIColor.whiteColor];
        [controller refreshVoicePresentationForInputWindow];
        UIView *bar = [controller valueForKey:@"m_voiceTapOverlay"];
        XCTAssertEqualObjects(bar.backgroundColor, UIColor.blackColor);
        XCTAssertEqualObjects(((UIButton *)[bar viewWithTag:904]).tintColor, UIColor.whiteColor);
    }];
}
- (void)testFloatingAndPhysicalKeyboardsDoNotReserveAFullKeyboardHeight {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        controller.view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 640)];
        NSArray *frames = @[[NSValue valueWithCGRect:CGRectMake(0, 440, 320, 200)],
                            [NSValue valueWithCGRect:CGRectMake(70, 250, 220, 200)],
                            [NSValue valueWithCGRect:CGRectMake(0, 640, 320, 200)]];
        NSArray *expectedHeights = @[@200, @0, @0];
        for (NSUInteger i = 0; i < frames.count; ++i) {
            NSNotification *notification = [NSNotification notificationWithName:UIKeyboardDidShowNotification object:nil
                userInfo:@{UIKeyboardFrameEndUserInfoKey:frames[i], UIKeyboardBoundsUserInfoKey:[NSValue valueWithCGRect:CGRectMake(0, 0, 320, 200)]}];
            [controller keyboardDidShow:notification];
            CGSize keyboard = [[controller valueForKey:@"m_kbdSize"] CGSizeValue];
            XCTAssertEqualWithAccuracy(keyboard.height, [expectedHeights[i] doubleValue], 0.1);
        }
    }];
}
- (void)testNarrationHasAnIndependentReplayButtonWithTheMicrophoneDisabled {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        [self.manager setValue:[TestSynthesizer new] forKey:@"synthesizer"];
        self.manager.voiceMode = VoiceModeTTSOnly;
        [self.manager rememberStoryResponse:@"You stand by an iron gate."];
        [controller updateVoiceButtonIcons];
        UIView *bar = [controller valueForKey:@"m_voiceTapOverlay"];
        UIButton *microphone = [bar viewWithTag:904];
        UIButton *speech = [bar viewWithTag:905];
        XCTAssertNotNil(microphone); XCTAssertNotNil(speech);
        XCTAssertFalse(bar.isAccessibilityElement, @"The two controls must be independently accessible");
        XCTAssertTrue(microphone.hidden);
        XCTAssertFalse(speech.hidden);
        XCTAssertEqualObjects(speech.accessibilityLabel, @"Replay last response");
        XCTAssertTrue(speech.enabled);
        [speech sendActionsForControlEvents:UIControlEventTouchUpInside];
        XCTAssertTrue(self.manager.isSpeaking);
        XCTAssertFalse(self.manager.isListening);
        XCTAssertEqual(controller.submittedCommands.count, 0u);
        XCTAssertEqualObjects(speech.accessibilityLabel, @"Stop reading");
    }];
}
- (void)testTopSpeakerConfiguresNarrationInsteadOfBecomingAStopButton {
    [self withSavedVoiceDefaults:^(NSUserDefaults *defaults) {
        [self withAutomaticListeningController:^(TestStoryController *controller) {
            self.manager.voiceMode = VoiceModeBoth;
            TestSynthesizer *synthesizer = [TestSynthesizer new];
            synthesizer.speaking = YES;
            [self.manager setValue:synthesizer forKey:@"synthesizer"];
            [self.manager setValue:[AVSpeechUtterance speechUtteranceWithString:@"Reading"] forKey:@"activeUtterance"];
            [controller setupVoiceToolbar];
            [controller updateVoiceButtonIcons];
            UIButton *config = [controller.navigationItem.rightBarButtonItem.customView viewWithTag:901];
            XCTAssertEqualObjects(config.accessibilityLabel, @"Disable narration");
            [controller toggleTTS];
            XCTAssertFalse(self.manager.ttsEnabled);
            XCTAssertTrue(self.manager.sttEnabled);
            XCTAssertFalse(self.manager.isSpeaking, @"Disabling narration must stop the current automatic reading");
        }];
    }];
}
- (void)testVoiceBarFitsCompactAndWideScreensWithoutOverlappingControls {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        self.manager.voiceMode = VoiceModeBoth;
        [controller updateVoiceButtonIcons];
        XCTAssertTrue([controller respondsToSelector:@selector(voiceControlBarHeightForWidth:)]);
        if (![controller respondsToSelector:@selector(voiceControlBarHeightForWidth:)]) return;
        UIView *bar = [controller valueForKey:@"m_voiceTapOverlay"];
        for (NSNumber *width in @[@240, @320, @834]) {
            CGFloat height = [controller voiceControlBarHeightForWidth:width.doubleValue];
            XCTAssertLessThanOrEqual(height, 80);
            bar.frame = CGRectMake(0, 0, width.doubleValue, height);
            [bar layoutIfNeeded];
            UIButton *mic = [bar viewWithTag:904], *speech = [bar viewWithTag:905];
            CGRect micRect = [mic convertRect:mic.bounds toView:bar];
            CGRect speechRect = [speech convertRect:speech.bounds toView:bar];
            XCTAssertFalse(CGRectIntersectsRect(micRect, speechRect));
            XCTAssertGreaterThanOrEqual(micRect.size.height, 44);
            XCTAssertGreaterThanOrEqual(speechRect.size.height, 44);
            XCTAssertTrue(CGRectContainsRect(bar.bounds, micRect));
            XCTAssertTrue(CGRectContainsRect(bar.bounds, speechRect));
        }
    }];
}
- (void)testRoomHeadingAndParagraphsHaveSpeechBreaksWithoutEndingTheTurnEarly {
    self.manager.voiceMode = VoiceModeBoth;
    TestSynthesizer *synthesizer = [TestSynthesizer new];
    [self.manager setValue:synthesizer forKey:@"synthesizer"];
    [self.manager speakText:@"Outside cemetery\nYou stand by an iron gate.\n\nA road runs east." inView:nil];
    XCTAssertEqual(synthesizer.queuedUtterances.count, 3u);
    if (synthesizer.queuedUtterances.count != 3) return;
    XCTAssertEqualObjects(synthesizer.queuedUtterances[0].speechString, @"Outside cemetery");
    XCTAssertGreaterThanOrEqual(synthesizer.queuedUtterances[0].postUtteranceDelay, 0.15);
    [self.manager speechSynthesizer:(id)synthesizer didFinishSpeechUtterance:synthesizer.queuedUtterances[0]];
    XCTAssertTrue(self.manager.isSpeaking);
    XCTAssertEqual(self.voiceDelegate.speakingFinishes, 0u);
    [self.manager speechSynthesizer:(id)synthesizer didFinishSpeechUtterance:synthesizer.queuedUtterances[1]];
    XCTAssertTrue(self.manager.isSpeaking);
    [self.manager speechSynthesizer:(id)synthesizer didFinishSpeechUtterance:synthesizer.queuedUtterances[2]];
    XCTAssertFalse(self.manager.isSpeaking);
    XCTAssertEqual(self.voiceDelegate.speakingFinishes, 1u);
    XCTAssertEqualObjects(self.manager.lastStoryResponse, @"Outside cemetery\nYou stand by an iron gate.\n\nA road runs east.");
}
- (void)testVoiceOverGetsHeadingPunctuationAndParagraphBoundaries {
    self.manager.voiceMode = VoiceModeBoth;
    self.manager.voiceOverRunning = YES;
    [self.manager speakText:@"Outside cemetery\nYou stand by an iron gate." inView:nil];
    XCTAssertEqualObjects(self.manager.announcements.lastObject, @"Outside cemetery.\n\nYou stand by an iron gate.");
    XCTAssertEqualObjects(self.manager.lastStoryResponse, @"Outside cemetery\nYou stand by an iron gate.");
}
- (void)testMicrophoneHandoffDoesNotStopOrDeactivateTheJustFinishedSpeech {
    self.manager.voiceMode = VoiceModeBoth;
    self.voiceDelegate.keepAudioForListening = YES;
    TestSynthesizer *synthesizer = [TestSynthesizer new];
    synthesizer.speaking = YES; // The audio object may still drain after its finish callback.
    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:@"A road runs east to the top of Post Office Hill."];
    [self.manager setValue:synthesizer forKey:@"synthesizer"];
    [self.manager setValue:utterance forKey:@"activeUtterance"];
    NSUInteger before = self.manager.audioDeactivations;
    [self.manager speechSynthesizer:(id)synthesizer didFinishSpeechUtterance:utterance];
    [self.manager startListening];
    XCTAssertTrue(self.manager.isListening);
    XCTAssertEqual(synthesizer.stops, 0u, @"Normal handoff must not issue stop-at-immediate to draining speech");
    XCTAssertEqual(self.manager.audioDeactivations, before, @"Keep the audio session intact through the handoff");
    [self.manager stopListening];
    [self.manager stopSpeaking];
    XCTAssertGreaterThan(self.manager.audioDeactivations, before, @"Explicit cancellation still releases audio");
}
- (void)testCombinedModeUsesTheSameAudioConfigurationForSpeechAndRecording {
    TestRecordingSessionManager *manager = [TestRecordingSessionManager new];
    manager.session = [TestRecordingSession new];
    manager.voiceMode = VoiceModeBoth;
    XCTAssertTrue([manager configureAudioSessionForPlayback]);
    XCTAssertEqualObjects(manager.session.category, AVAudioSessionCategoryPlayAndRecord);
    XCTAssertTrue([manager configureAudioSessionForRecording]);
    XCTAssertEqual(manager.session.categoryChanges, 1u, @"Do not switch audio routing between narration and capture");
}
- (void)testConfirmationUsesShortReplyRecognitionAndAcceptsExactUnknownConfidence {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        [controller scheduleVoiceListening]; [self drainCallbacks];
        [self sendAlternatives:@[@"take gown"] confidence:0.4];
        [self drainCallbacks];
        XCTAssertTrue(self.manager.recognizingConfirmation);
        XCTAssertEqual(self.recognizer.lastRequest.taskHint, SFSpeechRecognitionTaskHintConfirmation);
        XCTAssertEqualObjects(self.recognizer.lastRequest.contextualStrings, (@[@"confirm", @"retry", @"cancel"]));
        [self sendAlternatives:@[@"confirm"] confidence:0];
        XCTAssertEqualObjects(controller.submittedCommands, (@[@"take gown"]));
    }];
}
- (void)testConflictingConfirmationAlternativesCannotApproveACommand {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        [controller scheduleVoiceListening]; [self drainCallbacks];
        [self sendAlternatives:@[@"take gown"] confidence:0.4];
        [self drainCallbacks];
        [self sendAlternatives:@[@"confirm", @"cancel"] confidence:0.95];
        XCTAssertEqual(controller.submittedCommands.count, 0u);
        XCTAssertNotNil([controller valueForKey:@"m_pendingVoiceCommand"]);
        XCTAssertFalse([self.manager.confirmationPrompt containsString:@"take gown"], @"Retry only the short choice reminder");
    }];
}
- (void)testNoisyDirectionCanOutrankAnOrdinaryVisibleWordButIsNeverInvented {
    [self.manager updateCommandContextWithVisibleText:@"The grass is wet."];
    [self.manager startListening];
    [self sendAlternatives:@[@"wet", @"west"] confidence:0.4];
    XCTAssertEqualObjects(self.voiceDelegate.lastText, @"west");
    [self.manager startListening];
    XCTAssertTrue([self.recognizer.lastRequest.contextualStrings containsObject:@"go west"]);
    XCTAssertTrue([self.recognizer.lastRequest.contextualStrings containsObject:@"northeast"]);
    [self sendAlternatives:@[@"wet"] confidence:0.4];
    XCTAssertEqualObjects(self.voiceDelegate.lastText, @"wet");
    [self.manager startListening];
    [self sendAlternatives:@[@"wet", @"west"] confidence:0.95];
    XCTAssertEqualObjects(self.voiceDelegate.lastText, @"wet");
}
- (void)finishAccessibilityAnnouncement:(NSString *)text success:(BOOL)success {
    [NSNotificationCenter.defaultCenter postNotificationName:UIAccessibilityAnnouncementDidFinishNotification object:nil
        userInfo:@{UIAccessibilityAnnouncementKeyStringValue:text, UIAccessibilityAnnouncementKeyWasSuccessful:@(success)}];
}
- (void)focusVoiceOverElement {
    [NSNotificationCenter.defaultCenter postNotificationName:UIAccessibilityElementFocusedNotification object:nil
        userInfo:@{UIAccessibilityAssistiveTechnologyKey:UIAccessibilityNotificationVoiceOverIdentifier,
                   UIAccessibilityFocusedElementKey:[UIButton buttonWithType:UIButtonTypeSystem]}];
}
- (void)testSettingsButtonRemainsHittableWhenNavigationTitleIsCompressed {
    FrotzInfo *info = [[FrotzInfo alloc] initWithSettingsController:nil navController:nil navItem:nil];
    UIView *title = info.view;
    UIButton *settings = nil;
    for (UIView *view in title.subviews)
        if ([view isKindOfClass:UIButton.class] && [view.accessibilityLabel isEqual:@"Settings"])
            settings = (UIButton *)view;
    XCTAssertNotNil(settings);
    for (NSNumber *width in @[@106, @64, @44]) {
        title.frame = CGRectMake(0, 0, width.doubleValue, 44);
        [title setNeedsLayout];
        [title layoutIfNeeded];
        XCTAssertTrue(CGRectContainsRect(title.bounds, settings.frame), @"Settings must fit the actual title width %@", width);
        XCTAssertGreaterThanOrEqual(settings.bounds.size.width, 44);
        XCTAssertGreaterThanOrEqual(settings.bounds.size.height, 44);
        CGPoint center = CGPointMake(CGRectGetMidX(settings.frame), CGRectGetMidY(settings.frame));
        XCTAssertEqual([title hitTest:center withEvent:nil], settings);
    }
}
- (void)testVoiceToolbarUsesCompactNonoverlappingAccessibleHitTargets {
    TestStoryController *controller = [TestStoryController new];
    XCTAssertTrue([controller respondsToSelector:@selector(setupVoiceToolbar)]);
    if (![controller respondsToSelector:@selector(setupVoiceToolbar)]) return;
    [controller setupVoiceToolbar];
    UIStackView *toolbar = (id)controller.navigationItem.rightBarButtonItem.customView;
    CGSize size = [toolbar systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
    XCTAssertLessThanOrEqual(size.width, 132);
    toolbar.frame = CGRectMake(0, 0, size.width, size.height);
    [toolbar layoutIfNeeded];
    XCTAssertEqual(toolbar.arrangedSubviews.count, 3u);
    CGFloat previousEnd = 0;
    for (UIView *button in toolbar.arrangedSubviews) {
        XCTAssertGreaterThanOrEqual(button.bounds.size.width, 44);
        XCTAssertGreaterThanOrEqual(button.bounds.size.height, 44);
        XCTAssertGreaterThanOrEqual(CGRectGetMinX(button.frame), previousEnd);
        previousEnd = CGRectGetMaxX(button.frame);
    }
}
- (void)testRecordingSessionAllowsReadySoundsAndHapticsBeforeActivation {
    TestRecordingSessionManager *manager = [[TestRecordingSessionManager alloc] init];
    manager.session = [TestRecordingSession new];
    [manager configureAudioSessionForRecording];
    XCTAssertEqualObjects(manager.session.category, AVAudioSessionCategoryPlayAndRecord);
    XCTAssertTrue(manager.session.cuesAllowed);
    XCTAssertTrue(manager.session.cuesEnabledBeforeActivation);
    XCTAssertTrue(manager.session.active);
}
- (void)testMagicTapStartsStopsAndResumesDictationWithoutSubmittingCommands {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        self.manager.voiceOverRunning = YES;
        XCTAssertTrue([controller accessibilityPerformMagicTap]);
        XCTAssertTrue(self.manager.isListening);
        if (!self.manager.isListening) return;
        [self sendText:@"unsubmitted partial" final:NO handler:self.recognizer.handlers.lastObject];
        [self drainCallbacks];
        XCTAssertTrue([controller accessibilityPerformMagicTap]);
        XCTAssertFalse(self.manager.isListening);
        XCTAssertEqual(controller.submittedCommands.count, 0u);
        [self focusVoiceOverElement];
        XCTAssertTrue([controller accessibilityPerformMagicTap]);
        XCTAssertTrue(self.manager.isListening);
        XCTAssertFalse(self.manager.voiceOverNavigationPaused);
    }];
}
- (void)testAppDelegateHandlesMagicTapWhenNavigationBarBypassesStoryResponder {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        TestVoiceGestureAppDelegate *delegate = [TestVoiceGestureAppDelegate new];
        delegate.voiceController = controller;
        XCTAssertTrue([delegate accessibilityPerformMagicTap]);
        XCTAssertTrue(self.manager.isListening);
        XCTAssertTrue([delegate accessibilityPerformMagicTap]);
        XCTAssertFalse(self.manager.isListening);
    }];
}
- (void)testMagicTapDoesNotEnableVoiceOrBypassUnsupportedConfirmation {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        self.manager.voiceMode = VoiceModeOff;
        XCTAssertFalse([controller accessibilityPerformMagicTap]);
        XCTAssertFalse(self.manager.isListening);
        self.manager.voiceMode = VoiceModeSTTOnly;
        self.manager.speechRecognitionLanguage = @"ja-JP";
        [controller setValue:@"take gown" forKey:@"m_pendingVoiceCommand"];
        XCTAssertTrue([controller accessibilityPerformMagicTap]); // Consume unavailable game action; never toggle background media.
        XCTAssertFalse(self.manager.isListening);
    }];
}
- (void)testReplayRetainsWholeTurnExcludesPromptsAndResetsForNewStory {
    XCTAssertTrue([self.manager respondsToSelector:@selector(rememberStoryResponse:)]);
    if (![self.manager respondsToSelector:@selector(rememberStoryResponse:)]) return;
    self.manager.voiceOverRunning = YES;
    self.manager.voiceMode = VoiceModeBoth;
    [self.manager speakText:@"A brass lamp is here." inView:nil];
    [self finishAccessibilityAnnouncement:@"A brass lamp is here." success:YES];
    [self.manager speakText:@"It is dark outside." inView:nil];
    [self finishAccessibilityAnnouncement:@"It is dark outside." success:YES];
    NSString *response = self.manager.lastStoryResponse;
    XCTAssertTrue([response containsString:@"A brass lamp is here."]);
    XCTAssertTrue([response containsString:@"It is dark outside."]);
    [self.manager speakConfirmationPrompt:@"I heard take lamp. Confirm, retry or cancel."];
    XCTAssertEqualObjects(self.manager.lastStoryResponse, response);
    [self.manager rememberPlayerCommand:@"look"];
    [self.manager speakText:@"You see a doorway." inView:nil];
    XCTAssertEqualObjects(self.manager.lastStoryResponse, @"You see a doorway.");
    XCTAssertTrue([self.manager replayLastStoryResponse]);
    XCTAssertEqualObjects(self.manager.announcements.lastObject, @"You see a doorway.");
    [self.manager configureForStoryAtPath:nil];
    XCTAssertNil(self.manager.lastStoryResponse);
    XCTAssertFalse([self.manager replayLastStoryResponse]);
}
- (void)testReplayIsAccessibleCancelsCaptureAndDoesNotConsumeATurn {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        self.manager.voiceOverRunning = YES;
        XCTAssertTrue([self.manager respondsToSelector:@selector(rememberStoryResponse:)]);
        if (![self.manager respondsToSelector:@selector(rememberStoryResponse:)]) return;
        [self.manager rememberStoryResponse:@"A brass lamp is here."];
        [self.manager startListening];
        RecognitionHandler old = self.recognizer.handlers.lastObject;
        UIView *overlay = [controller valueForKey:@"m_voiceTapOverlay"];
        XCTAssertEqualObjects(overlay.accessibilityCustomActions.firstObject.name, @"Replay last response");
        XCTAssertTrue([controller replayLastVoiceResponse:nil]);
        XCTAssertFalse(self.manager.isListening);
        XCTAssertTrue(self.manager.isSpeaking);
        XCTAssertEqualObjects(overlay.accessibilityValue, @"Reading response");
        XCTAssertEqualObjects(self.manager.announcements.lastObject, @"A brass lamp is here.");
        [self sendText:@"stale game command" final:YES handler:old];
        [self drainCallbacks];
        XCTAssertEqual(controller.submittedCommands.count, 0u);
        [controller voiceManagerSTTError:[NSError errorWithDomain:@"test" code:1 userInfo:nil]];
        XCTAssertTrue([overlay.accessibilityValue containsString:@"failed"]);
        XCTAssertTrue([controller replayLastVoiceResponse:nil]);
        XCTAssertEqualObjects(overlay.accessibilityValue, @"Reading response");
        XCTAssertFalse([overlay.accessibilityHint containsString:@"retry"]);
        [controller setValue:@"take gown" forKey:@"m_pendingVoiceCommand"];
        XCTAssertFalse([controller replayLastVoiceResponse:nil]);
        XCTAssertEqualObjects([controller valueForKey:@"m_pendingVoiceCommand"], @"take gown");
    }];
}
- (void)testKeyboardCharacterAnswerBeginsANewReplayResponse {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        [self.manager rememberStoryResponse:@"Would you like to continue?"];
        [controller.inputLine delayedInput:@"y"];
        [self.manager rememberStoryResponse:@"You enter the hallway."];
        XCTAssertEqualObjects(self.manager.lastStoryResponse, @"You enter the hallway.");
    }];
}
- (void)testReplayAndMagicTapCannotRestartVoiceAfterLeavingGameplay {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        self.manager.voiceOverRunning = YES;
        [self.manager rememberStoryResponse:@"A brass lamp is here."];
        [controller stopVoiceActivity];
        XCTAssertFalse([controller accessibilityPerformMagicTap]);
        XCTAssertFalse([controller replayLastVoiceResponse:nil]);
        XCTAssertFalse(self.manager.isListening);
        XCTAssertFalse(self.manager.isSpeaking);
        XCTAssertEqual(controller.submittedCommands.count, 0u);
    }];
}
- (void)testNavigationPauseAndFailureExposeDistinctRecoveryStateAndCues {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        self.manager.voiceOverRunning = YES;
        [self.manager startListening];
        XCTAssertTrue([self.manager.feedback containsObject:@0]); // Ready only after actual recording starts.
        [self focusVoiceOverElement];
        UIView *overlay = [controller valueForKey:@"m_voiceTapOverlay"];
        XCTAssertTrue([overlay.accessibilityValue containsString:@"Paused"]);
        XCTAssertTrue([overlay.accessibilityHint containsString:@"two-finger double-tap"]);
        XCTAssertTrue([self.manager.feedback containsObject:@2]);
        NSUInteger feedbackCount = self.manager.feedback.count;
        [self focusVoiceOverElement];
        XCTAssertEqual(self.manager.feedback.count, feedbackCount); // No repeated pause cue for every swipe.
        [controller voiceManagerSTTError:[NSError errorWithDomain:@"test" code:1 userInfo:nil]];
        XCTAssertTrue([overlay.accessibilityValue containsString:@"failed"]);
        XCTAssertTrue([overlay.accessibilityHint containsString:@"retry"]);
        XCTAssertEqualObjects(self.manager.feedback.lastObject, @3);
        XCTAssertFalse(self.manager.isListening);
        XCTAssertTrue([controller accessibilityPerformMagicTap]);
        XCTAssertTrue(self.manager.isListening);
        XCTAssertEqualObjects(overlay.accessibilityValue, @"Listening");
    }];
}
- (void)testVoiceOverOwnsNarrationAndRecordingWaitsForItsCompletion {
    self.manager.voiceOverRunning = YES;
    self.manager.voiceMode = VoiceModeBoth;
    TestSynthesizer *synth = [TestSynthesizer new];
    [self.manager setValue:synth forKey:@"synthesizer"];
    [self.manager speakText:@"A brass lamp is here." inView:nil];
    XCTAssertEqualObjects(self.manager.announcements, (@[@"A brass lamp is here."]));
    XCTAssertEqual(synth.utterances, 0u); // One narrator: VoiceOver, not an additional synthesizer.
    XCTAssertTrue(self.manager.isSpeaking);
    [self.manager startListening];
    XCTAssertFalse(self.manager.isListening);
    XCTAssertEqual(self.engine.starts, 0u);
    [self finishAccessibilityAnnouncement:@"Unrelated system message" success:YES];
    XCTAssertTrue(self.manager.isSpeaking);
    [self finishAccessibilityAnnouncement:@"A brass lamp is here." success:YES];
    XCTAssertFalse(self.manager.isSpeaking);
    XCTAssertEqual(self.voiceDelegate.speakingFinishes, 1u);
    [self.manager startListening];
    XCTAssertTrue(self.manager.isListening);
}
- (void)testInterruptedVoiceOverAnnouncementDoesNotRestartDictation {
    self.manager.voiceOverRunning = YES;
    self.manager.voiceMode = VoiceModeBoth;
    [self.manager speakText:@"You are in a hallway." inView:nil];
    [self finishAccessibilityAnnouncement:@"You are in a hallway." success:NO];
    XCTAssertFalse(self.manager.isSpeaking);
    XCTAssertEqual(self.voiceDelegate.speakingFinishes, 0u);
    [self.manager startListening];
    XCTAssertFalse(self.manager.isListening);
}
- (void)testVoiceOverNavigationCancelsCapturedSpeechAndRejectsLateResults {
    self.manager.voiceOverRunning = YES;
    [self.manager startListening];
    RecognitionHandler callback = self.recognizer.handlers.lastObject;
    [self focusVoiceOverElement];
    XCTAssertFalse(self.manager.isListening);
    [self sendText:@"Settings button" final:YES handler:callback];
    XCTAssertEqual(self.voiceDelegate.results, 0u);
    [self.manager startListening];
    XCTAssertFalse(self.manager.isListening); // A stale automatic restart cannot capture navigation speech.
}
- (void)testVoiceOverFocusCancelsQueuedAutomaticMicrophoneStart {
    self.manager.voiceOverRunning = YES;
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        [controller scheduleVoiceListening];
        [self focusVoiceOverElement];
        [self drainCallbacks];
        XCTAssertFalse(self.manager.isListening);
        XCTAssertEqual(controller.submittedCommands.count, 0u);
    }];
}
- (void)testVoiceOverCanActivateTheMicrophoneAfterNavigation {
    self.manager.voiceOverRunning = YES;
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        [self focusVoiceOverElement];
        UIView *overlay = [controller valueForKey:@"m_voiceTapOverlay"];
        XCTAssertTrue([overlay accessibilityActivate]);
        XCTAssertTrue(self.manager.isListening);
        XCTAssertTrue(overlay.accessibilityTraits & UIAccessibilityTraitStartsMediaSession);
        XCTAssertTrue([overlay accessibilityActivate]);
        XCTAssertFalse(self.manager.isListening);
    }];
}
- (void)testEnablingVoiceOverCancelsExistingAppSpeechAndMicrophone {
    [self.manager startListening];
    self.manager.voiceOverRunning = YES;
    [NSNotificationCenter.defaultCenter postNotificationName:UIAccessibilityVoiceOverStatusDidChangeNotification object:nil];
    XCTAssertFalse(self.manager.isListening);
    [self.manager startListening];
    XCTAssertFalse(self.manager.isListening);
}
- (void)testVoiceOverNavigationAllowsNextTurnNarrationButKeepsDictationPaused {
    self.manager.voiceOverRunning = YES;
    self.manager.voiceMode = VoiceModeBoth;
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        controller.inputLine.text = @"look";
        [self focusVoiceOverElement];
        XCTAssertEqualObjects(controller.inputLine.text, @"look");
        [self.manager speakText:@"The door opens." inView:nil];
        XCTAssertEqualObjects(self.manager.announcements.lastObject, @"The door opens.");
        XCTAssertTrue(self.manager.isSpeaking);
        [self finishAccessibilityAnnouncement:@"The door opens." success:YES];
        [self drainCallbacks];
        XCTAssertFalse(self.manager.isListening);
        UIView *overlay = [controller valueForKey:@"m_voiceTapOverlay"];
        XCTAssertTrue([overlay accessibilityActivate]);
        XCTAssertTrue(self.manager.isListening);
    }];
}
- (void)testVoiceOverAccessibilityActivationKeepsUnsupportedConfirmationOnScreen {
    self.manager.voiceOverRunning = YES;
    self.manager.speechRecognitionLanguage = @"ja-JP";
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        [controller setValue:@"take gown" forKey:@"m_pendingVoiceCommand"];
        UIView *overlay = [controller valueForKey:@"m_voiceTapOverlay"];
        XCTAssertFalse([overlay accessibilityActivate]);
        XCTAssertFalse(self.manager.isListening);
        XCTAssertEqualObjects([controller valueForKey:@"m_pendingVoiceCommand"], @"take gown");
    }];
}
- (void)testVoiceOverConfirmationWaitsForItsAnnouncementAndIgnoresCancelledCompletion {
    self.manager.voiceOverRunning = YES;
    self.manager.voiceMode = VoiceModeSTTOnly;
    [self.manager speakConfirmationPrompt:@"Did you say take gown?"];
    XCTAssertTrue(self.manager.isSpeaking);
    [self.manager startListening];
    XCTAssertFalse(self.manager.isListening);
    [self focusVoiceOverElement];
    [self finishAccessibilityAnnouncement:@"Did you say take gown?" success:YES];
    XCTAssertEqual(self.voiceDelegate.speakingFinishes, 0u);
    XCTAssertFalse(self.manager.isListening);
}
- (void)testVoiceOverNavigationPreservesTypedKeyboardCommands {
    self.manager.voiceOverRunning = YES;
    self.manager.voiceMode = VoiceModeTTSOnly;
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        controller.inputLine.text = @"take brass";
        [self focusVoiceOverElement];
        XCTAssertEqualObjects(controller.inputLine.text, @"take brass");
    }];
}
- (void)testVoiceOverNarrationOnlyRecoversOnTheNextTurnAfterNavigation {
    self.manager.voiceOverRunning = YES;
    self.manager.voiceMode = VoiceModeTTSOnly;
    [self focusVoiceOverElement];
    [self.manager speakText:@"The door opens." inView:nil];
    XCTAssertTrue(self.manager.isSpeaking);
    XCTAssertEqualObjects(self.manager.announcements.lastObject, @"The door opens.");
}
- (void)testVoiceOverRecordingCancelsSpeakerEchoBeforeCapturingAudio {
    self.manager.voiceOverRunning = YES;
    [self.manager startListening];
    XCTAssertTrue(self.manager.isListening);
    XCTAssertTrue(self.engine.inputNode.voiceProcessingEnabled);
    XCTAssertTrue(self.engine.inputNode.processingWasEnabledWhenTapped);
}
- (void)testVoiceOverRecordingFailsSafelyWhenEchoCancellationCannotStartAndCanRetry {
    self.manager.voiceOverRunning = YES;
    self.engine.inputNode.failVoiceProcessing = YES;
    [self.manager startListening];
    XCTAssertFalse(self.manager.isListening);
    XCTAssertEqual(self.engine.starts, 0u);
    XCTAssertEqual(self.engine.inputNode.installs, 0u);
    XCTAssertEqual(self.recognizer.handlers.count, 0u);
    XCTAssertEqual(self.voiceDelegate.errors, 1u);
    self.engine.inputNode.failVoiceProcessing = NO;
    [self.manager startListening];
    XCTAssertTrue(self.manager.isListening);
}
- (void)testNonVoiceOverRecordingRestoresItsOriginalAudioProcessing {
    self.manager.voiceOverRunning = YES;
    [self.manager startListening];
    XCTAssertTrue(self.engine.inputNode.voiceProcessingEnabled);
    [self.manager stopListening];
    self.manager.voiceOverRunning = NO;
    [self.manager startListening];
    XCTAssertFalse(self.engine.inputNode.voiceProcessingEnabled);
    XCTAssertTrue(self.manager.isListening);
    XCTAssertEqual(self.engine.inputNode.installs, 2u);
}
- (void)withAutomaticListeningController:(void (^)(TestStoryController *controller))test {
    // Replace only the singleton lookup; recording, scheduling and UI state stay real.
    Method sharedMethod = class_getClassMethod(VoiceManager.class, @selector(shared));
    IMP original = method_getImplementation(sharedMethod);
    TestVoiceManager *manager = self.manager;
    IMP replacement = imp_implementationWithBlock(^id(id classObject) { return manager; });
    TestStoryController *controller = [[TestStoryController alloc] init];
    method_setImplementation(sharedMethod, replacement);
    @try {
        [controller setValue:[[StoryInputLine alloc] initWithFrame:CGRectMake(0, 0, 320, 44)] forKey:@"m_inputLine"];
        RichTextView *story = [[RichTextView alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
        [story appendText:@"You see a gown here."];
        [controller setValue:story forKey:@"m_storyView"];
        [controller setupVoiceTapOverlay];
        [controller setValue:@YES forKey:@"m_handsFreeAutoLoop"];
        [controller setValue:@YES forKey:@"m_voiceSessionActive"];
        [controller setValue:@YES forKey:@"m_voiceAutoListenReady"];
        manager.delegate = controller;
        test(controller);
    } @finally {
        [controller stopVoiceActivity];
        method_setImplementation(sharedMethod, original);
        imp_removeBlock(replacement);
    }
}
- (void)testAutomaticListeningStartsOnNextMainQueueTurn {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        [controller scheduleVoiceListening];
        // A ready silent turn must capture speech on the next queue turn, without a timer pause.
        XCTestExpectation *checked = [self expectationWithDescription:@"next-turn recording"];
        dispatch_async(dispatch_get_main_queue(), ^{
            XCTAssertTrue(self.manager.isListening);
            UIView *overlay = [controller valueForKey:@"m_voiceTapOverlay"];
            XCTAssertEqualObjects(overlay.accessibilityLabel, @"Stop listening");
            [checked fulfill];
        });
        [self waitForExpectations:@[checked] timeout:2];
    }];
}
- (void)testAutomaticListeningPreparesInsteadOfDisplayingIdleMic {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        [controller voiceManagerDidFinishSpeaking];
        UIView *overlay = [controller valueForKey:@"m_voiceTapOverlay"];
        XCTAssertEqualObjects(overlay.accessibilityLabel, @"Preparing microphone");
        UIImageView *icon = [overlay viewWithTag:999];
        if (@available(iOS 13.0, *)) XCTAssertEqualObjects(icon.tintColor, UIColor.secondaryLabelColor);
        XCTAssertFalse(self.manager.isListening); // Don't signal recording before the engine starts.
    }];
}
- (void)testBeginningTextEditingCancelsMicrophonePreparation {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        [controller scheduleVoiceListening];
        [controller textFieldDidBeginEditing:controller.inputLine];
        XCTestExpectation *checked = [self expectationWithDescription:@"editing cancels preparation"];
        dispatch_async(dispatch_get_main_queue(), ^{
            XCTAssertFalse(self.manager.isListening);
            UIView *overlay = [controller valueForKey:@"m_voiceTapOverlay"];
            XCTAssertEqualObjects(overlay.accessibilityLabel, @"Start listening");
            [checked fulfill];
        });
        [self waitForExpectations:@[checked] timeout:2];
    }];
}
- (void)testQueuedAutomaticListeningIsCanceledWhenVoiceActivityStops {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        [controller scheduleVoiceListening];
        [controller stopVoiceActivity];
        XCTestExpectation *checked = [self expectationWithDescription:@"canceled restart"];
        dispatch_async(dispatch_get_main_queue(), ^{
            XCTAssertFalse(self.manager.isListening);
            [checked fulfill];
        });
        [self waitForExpectations:@[checked] timeout:2];
    }];
}
- (void)testQueuedAutomaticListeningWaitsForNewNarration {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        self.manager.voiceMode = VoiceModeBoth;
        [controller scheduleVoiceListening];
        RichTextView *view = [[RichTextView alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
        NSMapTable *buffers = [NSMapTable weakToStrongObjectsMapTable];
        [buffers setObject:[NSMutableString stringWithString:@"Next story output"] forKey:view];
        [controller setValue:buffers forKey:@"m_voiceOutputBuffers"];
        XCTestExpectation *checked = [self expectationWithDescription:@"narration prevents recording"];
        dispatch_async(dispatch_get_main_queue(), ^{
            XCTAssertFalse(self.manager.isListening);
            XCTAssertTrue([[controller valueForKey:@"m_voiceAutoListenReady"] boolValue]);
            [checked fulfill];
        });
        [self waitForExpectations:@[checked] timeout:2];
    }];
}
- (void)testAutomaticVoicePrefersSystemDefaultWhenQualityAndRegionTie {
    AVSpeechSynthesisVoice *systemVoice = [AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"];
    NSMutableArray *candidates = [NSMutableArray array];
    for (AVSpeechSynthesisVoice *voice in [AVSpeechSynthesisVoice speechVoices]) {
        if ([voice.language isEqualToString:systemVoice.language] && voice.quality == systemVoice.quality)
            [candidates addObject:voice];
    }
    XCTAssertGreaterThan(candidates.count, 0u);
    XCTAssertEqualObjects([VoiceManager automaticVoiceFromVoices:candidates].identifier, systemVoice.identifier);
}
- (void)testAutomaticVoicePrefersHighestEnglishQualityThenUSRegion {
    TestSpeechVoice *standard = [TestSpeechVoice new];
    standard.identifier = @"standard"; standard.language = @"en-US"; standard.quality = AVSpeechSynthesisVoiceQualityDefault;
    TestSpeechVoice *enhanced = [TestSpeechVoice new];
    enhanced.identifier = @"enhanced"; enhanced.language = @"en-US"; enhanced.quality = AVSpeechSynthesisVoiceQualityEnhanced;
    TestSpeechVoice *premium = [TestSpeechVoice new];
    premium.identifier = @"premium"; premium.language = @"en-GB";
    if (@available(iOS 16.0, *)) {
        premium.quality = AVSpeechSynthesisVoiceQualityPremium;
        NSArray *voices = @[standard, enhanced, premium];
        XCTAssertEqual([VoiceManager automaticVoiceFromVoices:voices], (id)premium);
        enhanced.quality = AVSpeechSynthesisVoiceQualityPremium;
        XCTAssertEqual([VoiceManager automaticVoiceFromVoices:voices], (id)enhanced);
    }
    premium.language = @"fr-FR";
    XCTAssertEqual(([VoiceManager automaticVoiceFromVoices:@[premium, standard, enhanced]]), (id)enhanced);
    XCTAssertNil([VoiceManager automaticVoiceFromVoices:@[premium]]);
}
- (void)testSelectedVoicePersistsAndMissingVoiceFallsBack {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *keys = @[@"FrotzVoiceMode", @"FrotzSpeechRate", @"FrotzSpeechVoiceIdentifier", @"FrotzSpeechRecognitionLanguage", @"FrotzVoiceCommandConfirmationEnabled", @"FrotzVoiceCommandConfirmationMode", @"FrotzSpeakCommandConfirmations", @"FrotzNarrationAvailable", @"FrotzDictationAvailable"];
    NSMutableDictionary *saved = [NSMutableDictionary dictionary];
    for (NSString *key in keys) saved[key] = [defaults objectForKey:key] ?: [NSNull null];
    @try {
        AVSpeechSynthesisVoice *voice = [AVSpeechSynthesisVoice speechVoices].firstObject;
        XCTAssertNotNil(voice);
        self.manager.speechVoiceIdentifier = voice.identifier;
        [self.manager savePreferences];
        VoiceManager *reloaded = [[VoiceManager alloc] init];
        XCTAssertEqualObjects(reloaded.speechVoiceIdentifier, voice.identifier);
        XCTAssertEqualObjects(reloaded.speechVoice.identifier, voice.identifier);
        NSLocale *locale = [SFSpeechRecognizer supportedLocales].anyObject;
        XCTAssertNotNil(locale);
        reloaded.speechRecognitionLanguage = locale.localeIdentifier;
        [reloaded savePreferences];
        VoiceManager *languageReloaded = [[VoiceManager alloc] init];
        XCTAssertEqualObjects(languageReloaded.speechRecognitionLanguage, locale.localeIdentifier);
        XCTAssertEqualObjects(languageReloaded.effectiveRecognitionLanguage, locale.localeIdentifier);
        reloaded.speechVoiceIdentifier = @"unavailable-test-voice";
        XCTAssertNotNil(reloaded.speechVoice);
        XCTAssertEqualObjects(reloaded.speechVoiceDescription, @"Automatic (voice unavailable)");
        reloaded.speechVoiceIdentifier = nil;
        reloaded.speechRecognitionLanguage = nil;
        [reloaded savePreferences];
        XCTAssertNil([[VoiceManager alloc] init].speechVoiceIdentifier);
        XCTAssertNil([[VoiceManager alloc] init].speechRecognitionLanguage);
    } @finally {
        for (NSString *key in keys) {
            if (saved[key] == [NSNull null]) [defaults removeObjectForKey:key];
            else [defaults setObject:saved[key] forKey:key];
        }
    }
}
- (void)testAutomaticLanguagesFollowStoryMetadataAndManualOverrides {
    TestSpeechVoice *english = [TestSpeechVoice new];
    english.identifier = @"english"; english.language = @"en-US"; english.quality = AVSpeechSynthesisVoiceQualityEnhanced;
    TestSpeechVoice *french = [TestSpeechVoice new];
    french.identifier = @"french"; french.language = @"fr-FR"; french.quality = AVSpeechSynthesisVoiceQualityDefault;
    NSArray *voices = @[english, french];
    XCTAssertEqual([VoiceManager automaticVoiceFromVoices:voices language:@"fr"], (id)french);
    XCTAssertEqual([VoiceManager automaticVoiceFromVoices:voices language:@"fra"], (id)french);
    XCTAssertNil([VoiceManager automaticVoiceFromVoices:voices language:@"de"]);
    VoiceManager *manager = [[VoiceManager alloc] init];
    manager.speechRecognitionLanguage = nil;
    manager.storyLanguage = @"fr";
    XCTAssertTrue([manager.effectiveRecognitionLanguage hasPrefix:@"fr"]);
    manager.speechRecognitionLanguage = @"de-DE";
    XCTAssertTrue([manager.effectiveRecognitionLanguage hasPrefix:@"de"]);
    manager.storyLanguage = nil;
    manager.speechRecognitionLanguage = nil;
    XCTAssertTrue([manager.effectiveRecognitionLanguage hasPrefix:@"en"]);
    XCTAssertNil([VoiceManager recognitionLanguageForLanguage:@"zz"]);
}
- (void)testBlorbLanguageMetadataIsOptionalAndBounded {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".gblorb"]];
    NSString *xml = @"<ifindex xmlns='http://babel.ifarchive.org/protocol/iFiction/'><story><bibliographic><language> fr-FR </language></bibliographic></story></ifindex>";
    NSData *metadata = [xml dataUsingEncoding:NSUTF8StringEncoding];
    uint32_t chunkLength = CFSwapInt32HostToBig((uint32_t)metadata.length);
    uint32_t formLength = CFSwapInt32HostToBig((uint32_t)(12 + metadata.length + (metadata.length & 1)));
    NSMutableData *blorb = [NSMutableData dataWithBytes:"FORM" length:4];
    [blorb appendBytes:&formLength length:4];
    [blorb appendBytes:"IFRSIFmd" length:8];
    [blorb appendBytes:&chunkLength length:4];
    [blorb appendData:metadata];
    if (metadata.length & 1) [blorb appendBytes:"\0" length:1];
    @try {
        XCTAssertTrue([blorb writeToFile:path atomically:YES]);
        XCTAssertEqualObjects([VoiceManager languageFromBlorbAtPath:path], @"fr-FR");
        [blorb setLength:blorb.length - 2];
        XCTAssertTrue([blorb writeToFile:path atomically:YES]);
        XCTAssertNil([VoiceManager languageFromBlorbAtPath:path]);
        XCTAssertTrue([[@"A raw story without metadata" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES]);
        XCTAssertNil([VoiceManager languageFromBlorbAtPath:path]);
        XCTAssertNil([VoiceManager languageFromBlorbAtPath:nil]);
    } @finally {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
}
- (void)setUp {
    [super setUp];
    self.manager = [[TestVoiceManager alloc] init];
    self.manager.speechRecognitionLanguage = @"en-US";
    self.manager.storyLanguage = @"en-US";
    self.manager.commandConfirmationMode = VoiceCommandConfirmationAsNeeded; // Existing review-flow fixtures explicitly opt in.
    self.manager.recordingAllowed = YES;
    self.manager.voiceMode = VoiceModeSTTOnly;
    self.engine = [[TestAudioEngine alloc] init];
    self.engine.inputNode = [[TestAudioInput alloc] init];
    self.recognizer = [[TestSpeechRecognizer alloc] init];
    self.recognizer.handlers = [NSMutableArray array];
    self.voiceDelegate = [[TestVoiceDelegate alloc] init];
    self.manager.delegate = self.voiceDelegate;
    [self.manager setValue:self.engine forKey:@"audioEngine"];
    [self.manager setValue:self.recognizer forKey:@"speechRecognizer"];
}
- (void)tearDown {
    [self.manager stopListening];
    self.manager.delegate = nil;
    self.manager = nil;
    [super tearDown];
}
- (void)drainCallbacks {
    XCTestExpectation *drained = [self expectationWithDescription:@"recognition callbacks drained"];
    dispatch_async(dispatch_get_main_queue(), ^{ [drained fulfill]; });
    [self waitForExpectations:@[drained] timeout:2];
}
- (void)sendText:(NSString *)text final:(BOOL)final handler:(RecognitionHandler)handler {
    TestRecognitionResult *result = [[TestRecognitionResult alloc] init];
    result.final = final;
    result.bestTranscription = [[TestTranscription alloc] init];
    result.bestTranscription.formattedString = text;
    TestSpeechSegment *segment = [[TestSpeechSegment alloc] init];
    segment.confidence = 0.95;
    result.bestTranscription.segments = @[segment];
    result.transcriptions = @[result.bestTranscription];
    handler((id)result, nil);
    [self drainCallbacks];
}
// These exercise real recognition/controller decisions; only speech hardware and the
// interpreter submission boundary are replaced, so an accidental turn is observable.
- (void)sendAlternatives:(NSArray<NSString *> *)texts confidence:(float)confidence {
    TestRecognitionResult *result = [[TestRecognitionResult alloc] init];
    result.final = YES;
    NSMutableArray *alternatives = [NSMutableArray array];
    for (NSString *text in texts) {
        TestTranscription *transcription = [[TestTranscription alloc] init];
        transcription.formattedString = text;
        TestSpeechSegment *segment = [[TestSpeechSegment alloc] init];
        segment.confidence = confidence;
        transcription.segments = @[segment];
        [alternatives addObject:transcription];
    }
    result.transcriptions = alternatives;
    result.bestTranscription = alternatives.firstObject;
    self.recognizer.handlers.lastObject((id)result, nil);
    [self drainCallbacks];
}
- (void)withSavedVoiceDefaults:(void (^)(NSUserDefaults *defaults))test {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSArray *keys = @[@"FrotzVoiceMode", @"FrotzSpeechRate", @"FrotzSpeechVoiceIdentifier", @"FrotzSpeechRecognitionLanguage", @"FrotzVoiceCommandConfirmationEnabled", @"FrotzVoiceCommandConfirmationMode", @"FrotzSpeakCommandConfirmations", @"FrotzNarrationAvailable", @"FrotzDictationAvailable"];
    NSMutableDictionary *saved = [NSMutableDictionary dictionary];
    for (NSString *key in keys) saved[key] = [defaults objectForKey:key] ?: NSNull.null;
    @try { test(defaults); }
    @finally {
        for (NSString *key in keys) {
            if (saved[key] == NSNull.null) [defaults removeObjectForKey:key];
            else [defaults setObject:saved[key] forKey:key];
        }
    }
}
- (void)reloadVoicePreferencesForRecognitionTest {
    [self.manager loadPreferences];
    self.manager.speechRecognitionLanguage = @"en-US";
    self.manager.storyLanguage = @"en-US";
    self.manager.voiceMode = VoiceModeSTTOnly;
    [self.manager setValue:self.recognizer forKey:@"speechRecognizer"];
}
- (void)testDefaultModeImmediatelySubmitsMatchedCommandWithoutReadback {
    [self withSavedVoiceDefaults:^(NSUserDefaults *defaults) {
        [defaults removeObjectForKey:@"FrotzVoiceCommandConfirmationEnabled"]; // Includes upgrades from build3.
        [defaults removeObjectForKey:@"FrotzVoiceCommandConfirmationMode"];
        [self reloadVoicePreferencesForRecognitionTest];
        [self withAutomaticListeningController:^(TestStoryController *controller) {
            [controller scheduleVoiceListening];
            [self drainCallbacks];
            [self sendAlternatives:@[@"bake down", @"take gown"] confidence:0.4];
            XCTAssertEqualObjects(controller.submittedCommands, (@[@"take gown"]));
            XCTAssertNil(self.manager.confirmationPrompt);
            XCTAssertTrue(((UIView *)[controller valueForKey:@"m_voiceConfirmationButtons"]).hidden);
        }];
    }];
}
- (void)testExplicitlyDisabledConfirmationSubmitsOriginalWhenNoAlternativeExists {
    [self withSavedVoiceDefaults:^(NSUserDefaults *defaults) {
        [defaults setBool:NO forKey:@"FrotzVoiceCommandConfirmationEnabled"];
        [defaults removeObjectForKey:@"FrotzVoiceCommandConfirmationMode"];
        [self reloadVoicePreferencesForRecognitionTest];
        [self withAutomaticListeningController:^(TestStoryController *controller) {
            [controller scheduleVoiceListening];
            [self drainCallbacks];
            [self sendAlternatives:@[@"bake down"] confidence:0];
            XCTAssertEqualObjects(controller.submittedCommands, (@[@"bake down"]));
            XCTAssertNil(self.manager.confirmationPrompt);
        }];
    }];
}
// Removing the Always gate would submit a confidently wrong command before approval.
- (void)testAlwaysReviewsConfidentCommandAndConfirmSubmitsOnlyOnce {
    [self withSavedVoiceDefaults:^(NSUserDefaults *defaults) {
        [defaults setBool:NO forKey:@"FrotzVoiceCommandConfirmationEnabled"];
        [defaults setInteger:2 forKey:@"FrotzVoiceCommandConfirmationMode"];
        [self reloadVoicePreferencesForRecognitionTest];
        [self withAutomaticListeningController:^(TestStoryController *controller) {
            [controller scheduleVoiceListening];
            [self drainCallbacks];
            [self sendAlternatives:@[@"frobnicate Zaphod"] confidence:0.95];
            XCTAssertEqual(controller.submittedCommands.count, 0u);
            XCTAssertTrue([self.manager.confirmationPrompt containsString:@"frobnicate Zaphod"]);
            [controller voiceManagerDidFinishSpeaking];
            [self drainCallbacks];
            [self sendAlternatives:@[@"confirm"] confidence:0.95];
            XCTAssertEqualObjects(controller.submittedCommands, (@[@"frobnicate Zaphod"]));
            XCTAssertNil([controller valueForKey:@"m_pendingVoiceCommand"]);
        }];
    }];
}
// Ignoring the new Off preference would revive an obsolete enabled switch.
- (void)testExplicitOffOverridesLegacyEnabledPreference {
    [self withSavedVoiceDefaults:^(NSUserDefaults *defaults) {
        [defaults setBool:YES forKey:@"FrotzVoiceCommandConfirmationEnabled"];
        [defaults setInteger:0 forKey:@"FrotzVoiceCommandConfirmationMode"];
        [self reloadVoicePreferencesForRecognitionTest];
        [self withAutomaticListeningController:^(TestStoryController *controller) {
            [controller scheduleVoiceListening]; [self drainCallbacks];
            [self sendAlternatives:@[@"bake down", @"take gown"] confidence:0.4];
            XCTAssertEqualObjects(controller.submittedCommands, (@[@"take gown"]));
            XCTAssertNil(self.manager.confirmationPrompt);
        }];
    }];
}
- (void)testLegacyEnabledMigratesToAsNeededAndSurvivesRelaunch {
    [self withSavedVoiceDefaults:^(NSUserDefaults *defaults) {
        [defaults removeObjectForKey:@"FrotzVoiceCommandConfirmationMode"];
        [defaults setBool:YES forKey:@"FrotzVoiceCommandConfirmationEnabled"];
        [self reloadVoicePreferencesForRecognitionTest];
        [self.manager savePreferences];
        XCTAssertEqualObjects([defaults objectForKey:@"FrotzVoiceCommandConfirmationMode"], @1);
        [defaults removeObjectForKey:@"FrotzVoiceCommandConfirmationEnabled"];
        [self reloadVoicePreferencesForRecognitionTest];
        [self withAutomaticListeningController:^(TestStoryController *controller) {
            [controller scheduleVoiceListening]; [self drainCallbacks];
            [self sendAlternatives:@[@"bake down"] confidence:0.4];
            XCTAssertEqual(controller.submittedCommands.count, 0u);
            XCTAssertNotNil(self.manager.confirmationPrompt);
        }];
    }];
}
- (void)testInvalidStoredConfirmationModeFallsBackToOff {
    [self withSavedVoiceDefaults:^(NSUserDefaults *defaults) {
        [defaults setBool:YES forKey:@"FrotzVoiceCommandConfirmationEnabled"];
        [defaults setInteger:99 forKey:@"FrotzVoiceCommandConfirmationMode"];
        [self reloadVoicePreferencesForRecognitionTest];
        [self withAutomaticListeningController:^(TestStoryController *controller) {
            [controller scheduleVoiceListening]; [self drainCallbacks];
            [self sendAlternatives:@[@"bake down"] confidence:0.4];
            XCTAssertEqualObjects(controller.submittedCommands, (@[@"bake down"]));
        }];
    }];
}
- (void)testSettingsConfirmationPickerPersistsAllChoices {
    [self withSavedVoiceDefaults:^(NSUserDefaults *defaults) {
        [defaults removeObjectForKey:@"FrotzVoiceCommandConfirmationEnabled"];
        [defaults removeObjectForKey:@"FrotzVoiceCommandConfirmationMode"];
        [self reloadVoicePreferencesForRecognitionTest];
        [self withAutomaticListeningController:^(TestStoryController *controller) {
            FrotzSettingsController *settings = [[FrotzSettingsController alloc] init];
            [settings create_UISwitches];
            UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:settings];
            NSIndexPath *voicePath = nil;
            for (NSInteger row = 0; row < [settings tableView:nil numberOfRowsInSection:1]; ++row) {
                NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:1];
                if ([[settings tableView:nil cellForRowAtIndexPath:path].textLabel.text isEqualToString:@"Voice"]) voicePath = path;
            }
            XCTAssertNotNil(voicePath); if (!voicePath) return;
            BOOL rootAnimations = UIView.areAnimationsEnabled;
            [UIView setAnimationsEnabled:NO];
            [settings tableView:nil didSelectRowAtIndexPath:voicePath];
            [UIView setAnimationsEnabled:rootAnimations];
            UITableViewController *voiceSettings = (id)navigation.topViewController;
            XCTAssertNotEqual(voiceSettings, settings);
            NSIndexPath *choicePath = nil;
            for (NSInteger row = 0; row < [voiceSettings tableView:nil numberOfRowsInSection:0]; ++row) {
                NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:0];
                UITableViewCell *cell = [voiceSettings tableView:nil cellForRowAtIndexPath:path];
                if ([cell.textLabel.text isEqualToString:@"Command Confirmation"]) {
                    choicePath = path;
                    XCTAssertEqualObjects(cell.detailTextLabel.text, @"Off");
                    XCTAssertEqual(cell.accessoryType, UITableViewCellAccessoryDisclosureIndicator);
                }
            }
            XCTAssertNotNil(choicePath); if (!choicePath) return;
            BOOL animationsEnabled = UIView.areAnimationsEnabled;
            [UIView setAnimationsEnabled:NO];
            [voiceSettings tableView:nil didSelectRowAtIndexPath:choicePath];
            [UIView setAnimationsEnabled:animationsEnabled];
            UITableViewController *picker = (id)navigation.topViewController;
            XCTAssertNotEqual(picker, settings);
            XCTAssertEqual([picker tableView:picker.tableView numberOfRowsInSection:0], 3);
            NSArray *names = @[@"Off", @"As Needed", @"Always"];
            for (NSNumber *value in @[@2, @1, @0]) {
                NSIndexPath *path = [NSIndexPath indexPathForRow:value.integerValue inSection:0];
                UITableViewCell *cell = [picker tableView:picker.tableView cellForRowAtIndexPath:path];
                XCTAssertEqualObjects(((UILabel *)[cell.contentView viewWithTag:1]).text, names[value.integerValue]);
                [picker tableView:picker.tableView didSelectRowAtIndexPath:path];
                XCTAssertEqualObjects([defaults objectForKey:@"FrotzVoiceCommandConfirmationMode"], value);
                [self.manager loadPreferences];
                cell = [picker tableView:picker.tableView cellForRowAtIndexPath:path];
                XCTAssertEqual(cell.accessoryType, UITableViewCellAccessoryCheckmark);
                XCTAssertTrue(cell.accessibilityTraits & UIAccessibilityTraitSelected);
                XCTAssertEqualObjects([voiceSettings tableView:nil cellForRowAtIndexPath:choicePath].detailTextLabel.text, names[value.integerValue]);
            }
            picker.view.frame = CGRectMake(0, 0, UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad ? 768 : 320, 640);
            [picker.tableView reloadData]; [picker.view layoutIfNeeded];
            UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:picker.view.bounds.size];
            UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
                [[UIColor whiteColor] setFill]; UIRectFill(picker.view.bounds);
                if (![picker.view drawViewHierarchyInRect:picker.view.bounds afterScreenUpdates:YES])
                    [picker.view.layer renderInContext:context.CGContext];
            }];
            XCTAttachment *attachment = [XCTAttachment attachmentWithImage:image];
            attachment.name = @"Voice Command Confirmation picker";
            attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
            [self addAttachment:attachment];
        }];
    }];
}
- (void)testAlwaysDoesNotReviewPartialRecognition {
    self.manager.commandConfirmationMode = VoiceCommandConfirmationAlways;
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        [controller scheduleVoiceListening]; [self drainCallbacks];
        [self sendText:@"take" final:NO handler:self.recognizer.handlers.lastObject];
        XCTAssertEqualObjects(controller.inputLine.text, @"take");
        XCTAssertEqual(controller.submittedCommands.count, 0u);
        XCTAssertNil(self.manager.confirmationPrompt);
    }];
}
- (void)testAlwaysBypassesReviewForSingleKeyPrompt {
    self.manager.commandConfirmationMode = VoiceCommandConfirmationAlways;
    int previous = ipzAllowInput;
    @try {
        ipzAllowInput = kIPZRequestInput | kIPZNoEcho;
        [self withAutomaticListeningController:^(TestStoryController *controller) {
            // Set the input request at the synchronous controller boundary: the host
            // interpreter can change its global request while async callbacks drain.
            ipzAllowInput = kIPZRequestInput | kIPZNoEcho;
            [self.manager rememberStoryResponse:@"Press a key to continue."];
            [controller voiceManagerDidRecognizeText:@"space" isFinal:YES];
            [self.manager rememberStoryResponse:@"The menu is open."];
            XCTAssertEqualObjects(self.manager.lastStoryResponse, @"The menu is open.");
            XCTAssertNil(self.manager.confirmationPrompt);
            XCTAssertNil([controller valueForKey:@"m_pendingVoiceCommand"]);
            XCTAssertEqualObjects(controller.inputLine.text, @"");
            XCTAssertEqual(controller.submittedCommands.count, 0u);
        }];
    } @finally { ipzAllowInput = previous; }
}
- (void)testConfirmationPickerWrapsLargeTextOnCompactScreen {
    UITableViewController *picker = [[NSClassFromString(@"FrotzCommandConfirmationController") alloc] init];
    XCTAssertNotNil(picker); if (!picker) return;
    UITableViewCell *cell = [picker tableView:picker.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
    UILabel *title = [cell.contentView viewWithTag:1];
    // Stress the same title with the font UIKit supplies at the largest accessibility size.
    UITraitCollection *traits = [UITraitCollection traitCollectionWithPreferredContentSizeCategory:UIContentSizeCategoryAccessibilityExtraExtraExtraLarge];
    title.adjustsFontForContentSizeCategory = NO; // Hold the simulated accessibility font during layout.
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody compatibleWithTraitCollection:traits];
    cell.frame = CGRectMake(0, 0, 240, 300); // Stress a narrow choice area at the largest text size.
    [cell setNeedsLayout]; [cell layoutIfNeeded];
    CGRect required = [title.text boundingRectWithSize:CGSizeMake(title.bounds.size.width, CGFLOAT_MAX)
        options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName:title.font} context:nil];
    XCTAssertGreaterThanOrEqual(title.bounds.size.height + 1, ceil(required.size.height), @"content=%@ title=%@ font=%g textWidth=%g", NSStringFromCGRect(cell.contentView.bounds), NSStringFromCGRect(title.frame), title.font.pointSize, [title.text sizeWithAttributes:@{NSFontAttributeName:title.font}].width);
    CGFloat fittedHeight = [cell.contentView systemLayoutSizeFittingSize:CGSizeMake(cell.contentView.bounds.size.width, 0)
        withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    cell.frame = CGRectMake(0, 0, 240, fittedHeight + 1);
    [cell setNeedsLayout]; [cell layoutIfNeeded];
    XCTAssertGreaterThanOrEqual(title.bounds.size.height + 1, ceil(required.size.height), @"content=%@ title=%@ font=%g textWidth=%g", NSStringFromCGRect(cell.contentView.bounds), NSStringFromCGRect(title.frame), title.font.pointSize, [title.text sizeWithAttributes:@{NSFontAttributeName:title.font}].width);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:cell.bounds.size];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [[UIColor whiteColor] setFill]; UIRectFill(cell.bounds);
        [cell.layer renderInContext:context.CGContext];
    }];
    XCTAttachment *attachment = [XCTAttachment attachmentWithImage:image];
    attachment.name = @"Confirmation choice at largest accessibility title size";
    attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:attachment];
}
- (void)testNoisyWholeCommandWaitsForConfirmationWithoutConsumingTurn {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        [controller scheduleVoiceListening];
        [self drainCallbacks];
        [self sendAlternatives:@[@"bake down", @"take gown"] confidence:0.45];
        XCTAssertEqual(controller.submittedCommands.count, 0u);
        XCTAssertEqualObjects(controller.inputLine.text, @"take gown");
        XCTAssertTrue([self.manager.confirmationPrompt containsString:@"take gown"]);
        [controller voiceManagerDidFinishSpeaking];
        [self drainCallbacks];
        [self sendAlternatives:@[@"confirm"] confidence:0.95];
        XCTAssertEqualObjects(controller.submittedCommands, (@[@"take gown"]));
    }];
}
- (void)testHiddenAlternativeCannotBecomeASpokenSuggestion {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        [controller scheduleVoiceListening];
        [self drainCallbacks];
        [self sendAlternatives:@[@"take gown", @"take crown"] confidence:0.45];
        XCTAssertEqual(controller.submittedCommands.count, 0u);
        XCTAssertEqualObjects(controller.inputLine.text, @"take gown");
        XCTAssertFalse([self.manager.confirmationPrompt containsString:@"crown"]);
    }];
}
- (void)testConfidentUnusualCommandIsPreservedAndSubmittedImmediately {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        [controller scheduleVoiceListening];
        [self drainCallbacks];
        [self sendAlternatives:@[@"frobnicate Zaphod"] confidence:0.95];
        XCTAssertEqualObjects(controller.submittedCommands, (@[@"frobnicate Zaphod"]));
        XCTAssertNil(self.manager.confirmationPrompt);
    }];
}
- (void)testRetryAndCancelDoNotSubmitConfirmationWordsToStory {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        [controller scheduleVoiceListening];
        [self drainCallbacks];
        [self sendAlternatives:@[@"bake down"] confidence:0.4];
        XCTAssertEqual(controller.submittedCommands.count, 0u);
        [controller voiceManagerDidFinishSpeaking];
        [self drainCallbacks];
        [self sendAlternatives:@[@"retry"] confidence:0.95];
        XCTAssertEqual(controller.submittedCommands.count, 0u);
        XCTAssertEqualObjects(controller.inputLine.text, @"");
        [self drainCallbacks];
        [self sendAlternatives:@[@"bake down"] confidence:0.4];
        [controller voiceManagerDidFinishSpeaking];
        [self drainCallbacks];
        [self sendAlternatives:@[@"cancel"] confidence:0.95];
        XCTAssertEqual(controller.submittedCommands.count, 0u);
        XCTAssertFalse(self.manager.isListening);
    }];
}
- (void)testStoppingVoiceInvalidatesAnUnconfirmedCommand {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        [controller scheduleVoiceListening];
        [self drainCallbacks];
        [self sendAlternatives:@[@"bake down"] confidence:0.4];
        XCTAssertEqual(controller.submittedCommands.count, 0u);
        [controller stopVoiceActivity];
        [self.manager startListening];
        [self sendAlternatives:@[@"confirm"] confidence:0.95];
        XCTAssertEqual(controller.submittedCommands.count, 0u);
    }];
}
- (void)testConfirmationControlsDoNotOverlapReadbackInCompactOverlay {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        [controller scheduleVoiceListening];
        [self drainCallbacks];
        [self sendAlternatives:@[@"bake down"] confidence:0.4];
        UIView *overlay = [controller valueForKey:@"m_voiceTapOverlay"];
        overlay.backgroundColor = UIColor.whiteColor;
        for (NSValue *size in @[[NSValue valueWithCGSize:CGSizeMake(320, 120)], [NSValue valueWithCGSize:CGSizeMake(768, 300)]]) {
            overlay.frame = (CGRect){CGPointZero, size.CGSizeValue};
            [overlay layoutIfNeeded];
            UIView *hint = [overlay viewWithTag:998];
            UIView *buttons = [controller valueForKey:@"m_voiceConfirmationButtons"];
            XCTAssertFalse(CGRectIntersectsRect(hint.frame, buttons.frame));
            XCTAssertGreaterThanOrEqual(CGRectGetMinY(hint.frame), 0);
            XCTAssertLessThanOrEqual(CGRectGetMaxY(buttons.frame), size.CGSizeValue.height);
            XCTAssertFalse(overlay.isAccessibilityElement); // VoiceOver must reach the buttons.
            UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size.CGSizeValue];
            UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) { [overlay.layer renderInContext:context.CGContext]; }];
            XCTAttachment *snapshot = [XCTAttachment attachmentWithImage:image];
            snapshot.name = [NSString stringWithFormat:@"confirmation-%.0f", size.CGSizeValue.width];
            snapshot.lifetime = XCTAttachmentLifetimeKeepAlways;
            [self addAttachment:snapshot];
        }
    }];
}
- (void)testRecognitionHintsContainOnlyVisibleOrOrdinaryWords {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        [controller scheduleVoiceListening];
        [self drainCallbacks];
        NSArray *hints = self.recognizer.lastRequest.contextualStrings;
        XCTAssertTrue([hints containsObject:@"gown"]);
        XCTAssertTrue([hints containsObject:@"take"]);
        XCTAssertFalse([hints containsObject:@"crown"]);
        XCTAssertLessThanOrEqual(hints.count, 100u);
    }];
}
- (void)testAmbiguousSafeAlternativesPreserveOriginalForConfirmation {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        [controller scheduleVoiceListening];
        [self drainCallbacks];
        [self sendAlternatives:@[@"bake down", @"take gown", @"take down"] confidence:0.4];
        XCTAssertEqual(controller.submittedCommands.count, 0u);
        XCTAssertEqualObjects(controller.inputLine.text, @"bake down");
    }];
}
- (void)testLowConfidenceConfirmCannotApproveAnUncertainCommand {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        [controller scheduleVoiceListening];
        [self drainCallbacks];
        [self sendAlternatives:@[@"bake down"] confidence:0.4];
        [controller voiceManagerDidFinishSpeaking];
        [self drainCallbacks];
        [self sendAlternatives:@[@"confirm"] confidence:0.4];
        XCTAssertEqual(controller.submittedCommands.count, 0u);
        XCTAssertEqualObjects(controller.inputLine.text, @"bake down");
    }];
}
- (void)testFrenchConfirmationUsesFrenchControlsWithoutEnglishGuessing {
    XCTAssertEqualObjects([VoiceManager confirmationActionForText:@"confirmer" language:@"fr-FR"], @"confirm");
    XCTAssertNil([VoiceManager confirmationActionForText:@"confirm" language:@"fr-FR"]);
    XCTAssertNil([VoiceManager confirmationActionForText:@"confirm" language:@"ja-JP"]);
    XCTAssertNil([VoiceManager confirmationActionForText:@"yes, take gown" language:@"en-US"]);
}
- (void)testOldControllerCannotCancelAnotherControllersConfirmation {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        self.manager.delegate = self.voiceDelegate;
        self.manager.recognizingConfirmation = YES;
        [controller stopVoiceActivity];
        XCTAssertTrue(self.manager.recognizingConfirmation);
    }];
}
- (void)testCharacterRecognitionBypassesWholeCommandRanking {
    int originalMode = ipzAllowInput;
    @try {
        ipzAllowInput = kIPZRequestInput | kIPZNoEcho;
        [self withAutomaticListeningController:^(TestStoryController *controller) {
            [controller scheduleVoiceListening];
            [self drainCallbacks];
            self.manager.delegate = self.voiceDelegate; // Observe the real recognizer output without feeding a live VM.
            [self sendAlternatives:@[@"bake down", @"take gown"] confidence:0.4];
            XCTAssertEqualObjects(self.voiceDelegate.lastText, @"bake down");
        }];
    } @finally { ipzAllowInput = originalMode; }
}
- (void)testUnsupportedConfirmationLanguageKeepsReadbackAfterPromptFinishes {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        [controller scheduleVoiceListening];
        [self drainCallbacks];
        [self sendAlternatives:@[@"bake down"] confidence:0.4];
        self.manager.speechRecognitionLanguage = @"ja-JP";
        [controller voiceManagerDidFinishSpeaking];
        UIView *overlay = [controller valueForKey:@"m_voiceTapOverlay"];
        XCTAssertTrue([((UILabel *)[overlay viewWithTag:998]).text containsString:@"bake down"]);
        XCTAssertFalse(self.manager.isListening);
        XCTAssertFalse(((UIView *)[controller valueForKey:@"m_voiceConfirmationButtons"]).hidden);
    }];
}
- (void)testStoppingConfirmationListeningKeepsReadback {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        [controller scheduleVoiceListening];
        [self drainCallbacks];
        [self sendAlternatives:@[@"bake down"] confidence:0.4];
        [self drainCallbacks];
        [self.manager stopListening];
        UIView *overlay = [controller valueForKey:@"m_voiceTapOverlay"];
        XCTAssertTrue([((UILabel *)[overlay viewWithTag:998]).text containsString:@"bake down"]);
        XCTAssertEqual(controller.submittedCommands.count, 0u);
    }];
}
- (void)testQuotedSpeechIsNotRewritten {
    for (NSArray *quotes in @[@[@"'", @"'"], @[@"\"", @"\""], @[@"“", @"”"], @[@"‘", @"’"], @[@"«", @"»"]]) {
        [self withAutomaticListeningController:^(TestStoryController *controller) {
            [controller scheduleVoiceListening];
            [self drainCallbacks];
            NSString *original = [NSString stringWithFormat:@"say %@bake down%@", quotes[0], quotes[1]];
            NSString *alternative = [NSString stringWithFormat:@"say %@take gown%@", quotes[0], quotes[1]];
            [self sendAlternatives:@[original, alternative] confidence:0.4];
            XCTAssertEqualObjects(controller.inputLine.text, original);
            XCTAssertEqual(controller.submittedCommands.count, 0u);
        }];
    }
}
- (void)testCharacterCommandsPreserveSpaceAndHandleEmptyInput {
    XCTAssertEqualObjects([self.manager translateForCharInput:@"space"], @" ");
    XCTAssertEqualObjects([self.manager translateForCharInput:@" Yes \n"], @"y");
    XCTAssertEqualObjects([self.manager translateForCharInput:@"no"], @"n");
    XCTAssertEqualObjects([self.manager translateForCharInput:@"enter"], @"\n");
    XCTAssertEqualObjects([self.manager translateForCharInput:@"escape"], @"\x1b");
    XCTAssertEqualObjects([self.manager translateForCharInput:@""], @"");
    XCTAssertEqualObjects([self.manager translateForCharInput:@" \n"], @"");
}
- (void)testDuplicateStartLeavesExistingRecordingRunning {
    [self.manager startListening];
    [self.manager startListening];
    XCTAssertTrue(self.manager.isListening);
    XCTAssertEqual(self.engine.starts, 1u);
    XCTAssertEqual(self.engine.inputNode.installs, 1u);
    XCTAssertEqual(self.voiceDelegate.starts, 1u);
}
- (void)testFailedStartupRemovesTapAndAllowsRetry {
    self.engine.failStart = YES;
    [self.manager startListening];
    XCTAssertFalse(self.manager.isListening);
    XCTAssertFalse(self.engine.inputNode.tapInstalled);
    XCTAssertEqual(self.voiceDelegate.errors, 1u);
    self.engine.failStart = NO;
    [self.manager startListening];
    XCTAssertTrue(self.manager.isListening);
    XCTAssertEqual(self.engine.inputNode.installs, 2u);
    XCTAssertEqual(self.engine.inputNode.removals, 1u);
}
- (void)testCanceledRecognitionCannotSubmitIntoNewSession {
    [self.manager startListening];
    RecognitionHandler old = self.recognizer.handlers.lastObject;
    [self.manager stopListening];
    [self.manager startListening];
    [self sendText:@"quit" final:YES handler:old];
    XCTAssertEqual(self.voiceDelegate.results, 0u);
    XCTAssertTrue(self.manager.isListening);
}
- (void)testCanceledRecognitionErrorCannotStopNewSession {
    [self.manager startListening];
    RecognitionHandler old = self.recognizer.handlers.lastObject;
    [self.manager stopListening];
    [self.manager startListening];
    old(nil, [NSError errorWithDomain:@"TestSpeech" code:300 userInfo:nil]);
    [self drainCallbacks];
    XCTAssertTrue(self.manager.isListening);
    XCTAssertEqual(self.voiceDelegate.errors, 0u);
}
- (void)testFinalRecognitionStopsRecordingAndDeliversOriginalCommand {
    [self.manager startListening];
    [self sendText:@"open mailbox" final:YES handler:self.recognizer.handlers.lastObject];
    XCTAssertFalse(self.manager.isListening);
    XCTAssertFalse(self.engine.inputNode.tapInstalled);
    XCTAssertEqual(self.voiceDelegate.stops, 1u);
    XCTAssertEqual(self.voiceDelegate.results, 1u);
    XCTAssertEqualObjects(self.voiceDelegate.lastText, @"open mailbox");
}
- (void)testSilenceFinalizationAcceptsFinalResultWithoutStartingAnotherRecording {
    [self.manager startListening];
    RecognitionHandler handler = self.recognizer.handlers.lastObject;
    [self sendText:@"look" final:NO handler:handler];
    [self.manager silenceTimerFired];
    XCTAssertTrue(self.manager.isListening);
    XCTAssertFalse(self.engine.isRunning);
    XCTAssertFalse(self.engine.inputNode.tapInstalled);
    [self.manager startListening];
    XCTAssertEqual(self.engine.starts, 1u);
    [self sendText:@"look" final:YES handler:handler];
    XCTAssertFalse(self.manager.isListening);
    XCTAssertEqualObjects(self.voiceDelegate.lastText, @"look");
}
- (void)testFinalizationTimeoutStopsAndReportsAnError {
    [self.manager startListening];
    [self.manager silenceTimerFired];
    [self.manager recognitionTimedOut];
    XCTAssertFalse(self.manager.isListening);
    XCTAssertFalse(self.engine.inputNode.tapInstalled);
    XCTAssertEqual(self.voiceDelegate.errors, 1u);
    XCTAssertEqual(self.voiceDelegate.stops, 1u);
}
- (void)testDeniedPermissionDoesNotStartMicrophone {
    self.manager.recordingAllowed = NO;
    [self.manager startListening];
    XCTAssertEqual(self.engine.starts, 0u);
    XCTAssertEqual(self.engine.inputNode.installs, 0u);
    XCTAssertEqual(self.voiceDelegate.errors, 1u);
}
- (void)testInvalidInputFormatDoesNotInstallTap {
    self.engine.inputNode.invalidFormat = YES;
    [self.manager startListening];
    XCTAssertEqual(self.engine.starts, 0u);
    XCTAssertEqual(self.engine.inputNode.installs, 0u);
    XCTAssertEqual(self.voiceDelegate.errors, 1u);
}
- (void)testAccessibilityContainerRejectsForeignElementsAndUsesContainerIndex {
    RichTextView *view = [[RichTextView alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
    UIAccessibilityElement *first = [[UIAccessibilityElement alloc] initWithAccessibilityContainer:view];
    UIAccessibilityElement *second = [[UIAccessibilityElement alloc] initWithAccessibilityContainer:view];
    [view setValue:[NSMutableArray arrayWithObjects:first, second, nil] forKey:@"m_accessibilityElements"];
    XCTAssertEqual([view indexOfAccessibilityElement:first], 0);
    XCTAssertEqual([view indexOfAccessibilityElement:second], 1);
    XCTAssertEqual([view indexOfAccessibilityElement:[[NSObject alloc] init]], NSNotFound);
    XCTAssertNil([view accessibilityElementAtIndex:-1]);
}
- (void)testCurrentColorKeepsValidPaletteIndexAndBoundsInvalidFallback {
    RichTextView *view = [[RichTextView alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
    view.textColor = [UIColor blackColor];
    [view setValue:[NSMutableArray arrayWithObjects:[UIColor redColor], [UIColor blueColor], nil] forKey:@"m_colorArray"];
    [view setValue:[NSMutableArray arrayWithObject:@1] forKey:@"m_colorIndex"];
    view.textColorIndex = 2;
    XCTAssertEqualObjects([view getCurrentTextColor], [UIColor blueColor]);
    [view setValue:@999 forKey:@"m_currentTextColorIndex"];
    [view setValue:[NSMutableArray arrayWithObject:@999] forKey:@"m_colorIndex"];
    XCTAssertEqualObjects([view getCurrentTextColor], [UIColor blackColor]);
}
- (void)testListeningFeedbackProvidesAccessibleStateAndStopsAnimations {
    [self withAutomaticListeningController:^(TestStoryController *controller) {
        UIView *bar = [controller valueForKey:@"m_voiceTapOverlay"];
        UIButton *microphone = [bar viewWithTag:904];
        UIView *icon = [bar viewWithTag:999];
        [self.manager startListening];
        XCTAssertEqualObjects(microphone.accessibilityLabel, @"Stop listening");
        if (UIAccessibilityIsReduceMotionEnabled()) {
            XCTAssertNil([icon.layer animationForKey:@"voiceListeningPulse"]);
        } else {
            XCTAssertNotNil([icon.layer animationForKey:@"voiceListeningPulse"]);
            XCTAssertNotNil([icon.layer animationForKey:@"voiceListeningGlow"]);
        }
        [self.manager stopListening];
        XCTAssertEqualObjects(microphone.accessibilityLabel, @"Start listening");
        XCTAssertNil([icon.layer animationForKey:@"voiceListeningPulse"]);
        XCTAssertNil([icon.layer animationForKey:@"voiceListeningGlow"]);
        XCTAssertEqual(icon.layer.shadowOpacity, 0);
    }];
}
- (void)testNormalEndingPreservesPendingNarrationAcrossTeardown {
    TestEndingController *controller = [[TestEndingController alloc] init];
    RichTextView *view = [[RichTextView alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
    NSMapTable *buffers = [NSMapTable weakToStrongObjectsMapTable];
    [buffers setObject:[NSMutableString stringWithString:@"You have won.\n"] forKey:view];
    [controller setValue:buffers forKey:@"m_voiceOutputBuffers"];
    [controller setValue:@YES forKey:@"m_voiceSessionActive"];
    TestNarrationManager *manager = [[TestNarrationManager alloc] init];
    manager.voiceMode = VoiceModeTTSOnly;
    [controller finishStoryNarration:NO inView:view voiceManager:manager];
    XCTAssertTrue(controller.abandoned);
    XCTAssertEqual(buffers.count, 0u);
    XCTAssertTrue([manager.spokenText containsString:@"You have won."]);
    XCTAssertTrue([manager.spokenText hasSuffix:@"End of story."]);
    XCTAssertFalse([controller canAcceptVoiceInput]);
}
- (void)testUnreadableStoryDoesNotNarrateAnEnding {
    TestEndingController *controller = [[TestEndingController alloc] init];
    [controller setValue:@YES forKey:@"m_voiceSessionActive"];
    TestNarrationManager *manager = [[TestNarrationManager alloc] init];
    manager.voiceMode = VoiceModeTTSOnly;
    [controller finishStoryNarration:YES inView:nil voiceManager:manager];
    XCTAssertTrue(controller.abandoned);
    XCTAssertNil(manager.spokenText);
}
- (void)testLiveSpeechSynthesis {
    XCTSkipIf(![[NSProcessInfo.processInfo.environment objectForKey:@"FROTZ_TEST_LIVE_SPEECH"] isEqualToString:@"1"],
              @"Set FROTZ_TEST_LIVE_SPEECH=1 for the optional live speech-service smoke test.");
    VoiceManager *manager = [[VoiceManager alloc] init];
    manager.voiceMode = VoiceModeTTSOnly;
    LiveSpeechDelegate *delegate = [[LiveSpeechDelegate alloc] init];
    delegate.finished = [self expectationWithDescription:@"live narration finished"];
    manager.delegate = delegate;
    RichTextView *view = [[RichTextView alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
    [manager speakText:@"This is a voice mode simulator test." inView:view];
    [self waitForExpectations:@[delegate.finished] timeout:20];
    XCTAssertFalse(manager.isSpeaking);
    [manager stopSpeaking];
    manager.delegate = nil;
}
- (void)testLiveConfirmationWithNarrationDisabled {
    XCTSkipIf(![[NSProcessInfo.processInfo.environment objectForKey:@"FROTZ_TEST_LIVE_SPEECH"] isEqualToString:@"1"],
              @"Set FROTZ_TEST_LIVE_SPEECH=1 for the optional live confirmation smoke test.");
    VoiceManager *manager = [[VoiceManager alloc] init];
    manager.voiceMode = VoiceModeSTTOnly;
    LiveSpeechDelegate *delegate = [[LiveSpeechDelegate alloc] init];
    delegate.finished = [self expectationWithDescription:@"live confirmation finished without narration"];
    manager.delegate = delegate;
    @try {
        [manager speakConfirmationPrompt:@"I heard take gown. Say confirm, retry or cancel."];
        XCTAssertTrue(manager.isSpeaking);
        XCTAssertNil(manager.activeView); // UI readback must not highlight story text.
        [self waitForExpectations:@[delegate.finished] timeout:20];
        XCTAssertFalse(manager.isSpeaking);
        XCTAssertFalse(manager.ttsEnabled);
    } @finally {
        [manager stopSpeaking];
        manager.delegate = nil;
    }
}
- (void)testSettingsPresentationStopsRecordingAndPendingRestarts {
    StoryMainViewController *controller = [[StoryMainViewController alloc] init];
    [controller setupVoiceTapOverlay];
    [controller startVoiceListeningAnimation];
    [controller setValue:@YES forKey:@"m_voiceSessionActive"];
    [controller setValue:@YES forKey:@"m_voiceAutoListenReady"];
    [controller setValue:@YES forKey:@"m_voiceListenPending"];
    VoiceManager *shared = [VoiceManager shared];
    id originalEngine = [shared valueForKey:@"audioEngine"];
    id originalDelegate = shared.delegate;
    self.engine.running = YES;
    self.engine.inputNode.tapInstalled = YES;
    [shared setValue:self.engine forKey:@"audioEngine"];
    [shared setValue:@YES forKey:@"inputTapInstalled"];
    shared.delegate = controller;
    @try {
        [controller pauseVoiceForSettings];
        XCTAssertFalse(shared.isListening);
        XCTAssertFalse(self.engine.inputNode.tapInstalled);
        XCTAssertNil(shared.delegate);
        XCTAssertFalse([[controller valueForKey:@"m_voiceSessionActive"] boolValue]);
        XCTAssertFalse([[controller valueForKey:@"m_voiceListenPending"] boolValue]);
        XCTAssertFalse([[controller valueForKey:@"m_voiceAutoListenReady"] boolValue]);
        UIView *overlay = [controller valueForKey:@"m_voiceTapOverlay"];
        XCTAssertNil([[overlay viewWithTag:999].layer animationForKey:@"voiceListeningPulse"]);
    } @finally {
        [shared setValue:originalEngine forKey:@"audioEngine"];
        shared.delegate = originalDelegate;
    }
}
@end

// These tests run under every compile-time combination, including both features off.
#ifndef FROTZ_ENABLE_NARRATION
#define FROTZ_ENABLE_NARRATION 1
#endif
#ifndef FROTZ_ENABLE_DICTATION
#define FROTZ_ENABLE_DICTATION 1
#endif
@interface VoiceFeatureGateTests : VoicePreferenceIsolatedTestCase
@end
@implementation VoiceFeatureGateTests
- (void)testDisabledFeaturesCannotBecomeEffectiveOrOverwriteSavedMode {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id previous = [defaults objectForKey:@"FrotzVoiceMode"];
    VoiceManager *manager = [VoiceManager new];
    manager.voiceMode = VoiceModeBoth;
    XCTAssertEqual(manager.ttsEnabled, (BOOL)FROTZ_ENABLE_NARRATION);
    XCTAssertEqual(manager.sttEnabled, (BOOL)FROTZ_ENABLE_DICTATION);
    XCTAssertEqual(manager.voiceMode, (VoiceMode)((FROTZ_ENABLE_NARRATION ? 1 : 0) | (FROTZ_ENABLE_DICTATION ? 2 : 0)));
    [manager savePreferences];
    XCTAssertEqual([defaults integerForKey:@"FrotzVoiceMode"], 3, @"An unavailable feature must not erase the user's saved mode");
    if (previous) [defaults setObject:previous forKey:@"FrotzVoiceMode"];
    else [defaults removeObjectForKey:@"FrotzVoiceMode"];
}
- (void)testDisabledCaptureDoesNotInitializeRecordingServices {
    VoiceManager *resources = [VoiceManager new];
    if (FROTZ_ENABLE_DICTATION) XCTAssertNotNil([resources valueForKey:@"audioEngine"]);
    if (FROTZ_ENABLE_NARRATION || FROTZ_ENABLE_DICTATION) XCTAssertNotNil([resources valueForKey:@"synthesizer"]);
#if !FROTZ_ENABLE_DICTATION
    VoiceManager *manager = [VoiceManager new];
    XCTAssertNil([manager valueForKey:@"audioEngine"]);
    XCTAssertNil([manager valueForKey:@"speechRecognizer"]);
#endif
#if !FROTZ_ENABLE_DICTATION && !FROTZ_ENABLE_NARRATION
    VoiceManager *silent = [VoiceManager new];
    XCTAssertNil([silent valueForKey:@"synthesizer"]);
#endif
}
- (void)testCompiledOutControlsAreNotOfferedInTheToolbar {
    StoryMainViewController *controller = [StoryMainViewController new];
    [controller setupVoiceToolbar];
    UIView *toolbar = controller.navigationItem.rightBarButtonItem.customView;
    XCTAssertNotNil(controller.navigationItem.rightBarButtonItem, @"Keyboard access remains available in every build");
    UIView *narration = [toolbar viewWithTag:901];
    UIView *dictation = [toolbar viewWithTag:902];
    if (!FROTZ_ENABLE_NARRATION) XCTAssertTrue(narration == nil || narration.hidden);
    if (!FROTZ_ENABLE_DICTATION) XCTAssertTrue(dictation == nil || dictation.hidden);
}
- (void)testCompiledOutSettingsAreNotOffered {
    FrotzSettingsController *settings = [FrotzSettingsController new];
    [settings create_UISwitches];
    NSMutableArray *labels = [NSMutableArray array];
    for (NSInteger row = 0; row < [settings tableView:nil numberOfRowsInSection:1]; ++row) {
        UITableViewCell *cell = [settings tableView:nil cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:1]];
        if (cell.textLabel.text) [labels addObject:cell.textLabel.text];
    }
    XCTAssertTrue([labels containsObject:@"Text Color"]);
    if (!FROTZ_ENABLE_NARRATION) {
        XCTAssertFalse([labels containsObject:@"Text-to-Speech"]);
        XCTAssertFalse([labels containsObject:@"Speech Voice"]);
    }
    if (!FROTZ_ENABLE_DICTATION) {
        XCTAssertFalse([labels containsObject:@"Speech-to-Text"]);
        XCTAssertFalse([labels containsObject:@"Speech Input Language"]);
        XCTAssertFalse([labels containsObject:@"Voice Command Confirmation"]);
    }
}
- (void)testInactiveVoiceDoesNotReportOtherAudioInterruptions {
    VoiceManager *manager = [VoiceManager new];
    manager.voiceMode = VoiceModeOff;
    TestVoiceDelegate *delegate = [TestVoiceDelegate new];
    manager.delegate = delegate;
    [NSNotificationCenter.defaultCenter postNotificationName:AVAudioSessionInterruptionNotification object:nil
        userInfo:@{AVAudioSessionInterruptionTypeKey:@(AVAudioSessionInterruptionTypeBegan)}];
    XCTestExpectation *drained = [self expectationWithDescription:@"interruption callback drained"];
    dispatch_async(dispatch_get_main_queue(), ^{
        XCTAssertEqual(delegate.errors, 0u, @"Classic play must not display a microphone error for unrelated audio");
        [drained fulfill];
    });
    [self waitForExpectations:@[drained] timeout:2];
}
@end
