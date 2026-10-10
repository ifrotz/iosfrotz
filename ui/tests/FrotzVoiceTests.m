#import <XCTest/XCTest.h>
#import "VoiceManager.h"
#import "RichTextView.h"
#import "StoryMainViewController.h"

@interface StoryMainViewController (VoiceTesting)
- (BOOL)canAcceptVoiceInput;
- (void)setupVoiceTapOverlay;
- (void)startVoiceListeningAnimation;
- (void)finishStoryNarration:(BOOL)unreadableStory inView:(RichTextView *)view voiceManager:(VoiceManager *)manager;
@end

@interface TestStoryController : StoryMainViewController
@end
@implementation TestStoryController
- (BOOL)canAcceptVoiceInput { return YES; }
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
- (BOOL)recordingIsAuthorized;
- (BOOL)configureAudioSessionForRecording;
- (void)deactivateAudioSession;
- (void)silenceTimerFired;
- (void)recognitionTimedOut;
@end

@interface RichTextView (Testing)
- (UIColor *)getCurrentTextColor;
@end

// Keep the tests independent of microphone permission, hardware and Apple's speech service.
@interface TestVoiceManager : VoiceManager
@property BOOL recordingAllowed;
@end
@implementation TestVoiceManager
- (BOOL)recordingIsAuthorized { return self.recordingAllowed; }
- (BOOL)configureAudioSessionForRecording { return YES; }
- (void)deactivateAudioSession {}
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
@end
@implementation TestAudioInput
- (AVAudioFormat *)outputFormatForBus:(AVAudioNodeBus)bus {
    return [[AVAudioFormat alloc] initStandardFormatWithSampleRate:self.invalidFormat ? 0 : 16000 channels:1];
}
- (void)installTapOnBus:(AVAudioNodeBus)bus bufferSize:(AVAudioFrameCount)size format:(AVAudioFormat *)format block:(AVAudioNodeTapBlock)block {
    NSAssert(!self.tapInstalled, @"A previous recording tap was not cleaned up");
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
@end
@implementation TestSpeechRecognizer
- (BOOL)isAvailable { return YES; }
- (BOOL)supportsOnDeviceRecognition { return NO; }
- (id)recognitionTaskWithRequest:(SFSpeechRecognitionRequest *)request resultHandler:(RecognitionHandler)handler {
    [self.handlers addObject:[handler copy]];
    return [[TestRecognitionTask alloc] init];
}
@end

@interface TestTranscription : NSObject
@property NSString *formattedString;
@end
@implementation TestTranscription
@end
@interface TestRecognitionResult : NSObject
@property (getter=isFinal) BOOL final;
@property TestTranscription *bestTranscription;
@end
@implementation TestRecognitionResult
@end

@interface TestVoiceDelegate : NSObject <VoiceManagerDelegate>
@property NSUInteger starts;
@property NSUInteger stops;
@property NSUInteger errors;
@property NSUInteger results;
@property NSString *lastText;
@end
@implementation TestVoiceDelegate
- (void)voiceManagerDidStartSpeaking {}
- (void)voiceManagerDidFinishSpeaking {}
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

@interface FrotzVoiceTests : XCTestCase
@property TestVoiceManager *manager;
@property TestAudioEngine *engine;
@property TestSpeechRecognizer *recognizer;
@property TestVoiceDelegate *voiceDelegate;
@end

@implementation FrotzVoiceTests
- (void)setUp {
    [super setUp];
    self.manager = [[TestVoiceManager alloc] init];
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
    handler((id)result, nil);
    [self drainCallbacks];
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
    TestStoryController *controller = [[TestStoryController alloc] init];
    [controller setupVoiceTapOverlay];
    UIView *overlay = [controller valueForKey:@"m_voiceTapOverlay"];
    UIView *icon = [overlay viewWithTag:999];
    [controller voiceManagerDidStartListening];
    XCTAssertEqualObjects(overlay.accessibilityLabel, @"Stop listening");
    if (UIAccessibilityIsReduceMotionEnabled()) {
        XCTAssertNil([icon.layer animationForKey:@"voiceListeningPulse"]);
        XCTAssertNil([icon.layer animationForKey:@"voiceListeningGlow"]);
    } else {
        XCTAssertNotNil([icon.layer animationForKey:@"voiceListeningPulse"]);
        XCTAssertNotNil([icon.layer animationForKey:@"voiceListeningGlow"]);
    }
    [controller voiceManagerDidStopListening];
    XCTAssertEqualObjects(overlay.accessibilityLabel, @"Start listening");
    XCTAssertNil([icon.layer animationForKey:@"voiceListeningPulse"]);
    XCTAssertNil([icon.layer animationForKey:@"voiceListeningGlow"]);
    XCTAssertEqual(icon.layer.shadowOpacity, 0);
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
