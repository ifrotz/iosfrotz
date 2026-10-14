#import <XCTest/XCTest.h>
#import "VoiceManager.h"
#import "RichTextView.h"
#import "StoryMainViewController.h"
#import "StoryInputLine.h"
#import <objc/runtime.h>

@interface StoryMainViewController (VoiceTesting)
- (BOOL)canAcceptVoiceInput;
- (void)setupVoiceTapOverlay;
- (void)startVoiceListeningAnimation;
- (void)scheduleVoiceListening;
- (void)stopVoiceActivity;
- (void)finishStoryNarration:(BOOL)unreadableStory inView:(RichTextView *)view voiceManager:(VoiceManager *)manager;
@end

@interface TestStoryController : StoryMainViewController
@property NSMutableArray<NSString *> *submittedCommands;
@end
@implementation TestStoryController
- (BOOL)canAcceptVoiceInput { return YES; }
- (void)autosize {} // Keep keyboard-layout work outside these voice-state tests.
- (void)textFieldFakeDidEndEditing:(UITextField *)field {
    if (!self.submittedCommands) self.submittedCommands = [NSMutableArray array];
    [self.submittedCommands addObject:field.text ?: @""];
}
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
+ (AVSpeechSynthesisVoice *)automaticVoiceFromVoices:(NSArray<AVSpeechSynthesisVoice *> *)voices;
+ (AVSpeechSynthesisVoice *)automaticVoiceFromVoices:(NSArray<AVSpeechSynthesisVoice *> *)voices language:(NSString *)language;
+ (NSString *)languageFromBlorbAtPath:(NSString *)path;
+ (NSString *)recognitionLanguageForLanguage:(NSString *)language;
- (BOOL)recordingIsAuthorized;
- (BOOL)configureAudioSessionForRecording;
- (void)deactivateAudioSession;
- (void)silenceTimerFired;
- (void)recognitionTimedOut;
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
@property BOOL recordingAllowed;
@property NSString *confirmationPrompt;
@end
@implementation TestVoiceManager
- (BOOL)recordingIsAuthorized { return self.recordingAllowed; }
- (BOOL)configureAudioSessionForRecording { return YES; }
- (void)deactivateAudioSession {}
- (void)speakConfirmationPrompt:(NSString *)text { self.confirmationPrompt = text; }
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
@property SFSpeechRecognitionRequest *lastRequest;
@end
@implementation TestSpeechRecognizer
- (NSLocale *)locale { return [NSLocale localeWithLocaleIdentifier:@"en-US"]; }
- (BOOL)isAvailable { return YES; }
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
    NSArray *keys = @[@"FrotzVoiceMode", @"FrotzSpeechRate", @"FrotzSpeechVoiceIdentifier", @"FrotzSpeechRecognitionLanguage"];
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
