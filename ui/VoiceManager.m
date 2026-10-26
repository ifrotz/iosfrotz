//
//  VoiceManager.m
//  Frotz
//
//  Voice mode manager: TTS (text-to-speech) and STT (speech-to-text)
//  for hands-free interactive fiction gameplay.
//

#import "VoiceManager.h"
#import "RichTextView.h"
#include <math.h>

static NSString *const kVoiceModeKey = @"FrotzVoiceMode";
static NSString *const kSpeechRateKey = @"FrotzSpeechRate";
static NSString *const kSpeechVoiceKey = @"FrotzSpeechVoiceIdentifier";
static NSString *const kRecognitionLanguageKey = @"FrotzSpeechRecognitionLanguage";
static NSString *const kLegacyCommandConfirmationKey = @"FrotzVoiceCommandConfirmationEnabled";
static NSString *const kCommandConfirmationModeKey = @"FrotzVoiceCommandConfirmationMode";

// Only bibliographic language is used; story text is never inspected or sent for detection.
@interface FrotzStoryLanguageParser : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) NSMutableArray<NSString *> *elements;
@property (nonatomic, strong) NSMutableString *text;
@property (nonatomic, copy) NSString *language;
@end
@implementation FrotzStoryLanguageParser
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)element namespaceURI:(NSString *)uri qualifiedName:(NSString *)name attributes:(NSDictionary *)attributes {
    [self.elements addObject:element];
    if ([self.elements isEqualToArray:@[@"ifindex", @"story", @"bibliographic", @"language"]])
        self.text = [NSMutableString string];
}
- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    if (self.text) [self.text appendString:string];
}
- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)element namespaceURI:(NSString *)uri qualifiedName:(NSString *)name {
    if ([element isEqualToString:@"language"] && self.text) {
        if (!self.language) self.language = [self.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        self.text = nil;
    }
    [self.elements removeLastObject];
}
@end

static uint32_t blorbWord(const unsigned char *bytes) {
    return ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) | ((uint32_t)bytes[2] << 8) | bytes[3];
}

// Map AVSpeechUtterance rate: Apple's default is 0.5, range 0.0-1.0
// We expose a multiplier (0.5x-3.0x) and convert internally
static float rateMultiplierToAVRate(float multiplier) {
    // AVSpeechUtteranceDefaultSpeechRate is 0.5
    // Map our 1.0x to that, scale linearly
    float rate = AVSpeechUtteranceDefaultSpeechRate * multiplier;
    if (rate < AVSpeechUtteranceMinimumSpeechRate)
        rate = AVSpeechUtteranceMinimumSpeechRate;
    if (rate > AVSpeechUtteranceMaximumSpeechRate)
        rate = AVSpeechUtteranceMaximumSpeechRate;
    return rate;
}

@implementation VoiceManager {
    AVSpeechSynthesizer *_synthesizer;

    // STT
    SFSpeechRecognizer *_speechRecognizer;
    SFSpeechAudioBufferRecognitionRequest *_recognitionRequest;
    SFSpeechRecognitionTask *_recognitionTask;
    AVAudioEngine *_audioEngine;
    NSTimer *_silenceTimer;
    NSSet<NSString *> *_commandWords;
    NSArray<NSString *> *_commandHints;
    NSMutableOrderedSet<NSString *> *_playerWords;
    BOOL _hasReceivedSpeech;  // whether any speech detected this listen session
    BOOL _inputTapInstalled;
    BOOL _finishingRecognition;
    NSUInteger _recognitionGeneration;
    BOOL _changingVoiceDirection; // Keep audio active while switching between narration and capture.

    // TTS state
    NSString *_currentUtteranceText;  // full text of current utterance for range mapping
    BOOL _isPaused;
    AVSpeechUtterance *_activeUtterance;
    NSMutableArray<AVSpeechUtterance *> *_speechParagraphs;
    NSMapTable<AVSpeechUtterance *, NSNumber *> *_speechOffsets;
    NSString *_accessibilityAnnouncement;
    BOOL _voiceOverNavigationPaused;
    NSString *_lastStoryResponse;
    BOOL _beginsStoryResponse;
    SystemSoundID _feedbackSounds[4];

    // Char input translation dictionary
    NSDictionary<NSString *, NSString *> *_charInputMap;
}

@synthesize voiceMode = _voiceMode;

+ (instancetype)shared {
    static VoiceManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VoiceManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
#if FROTZ_ENABLE_NARRATION || FROTZ_ENABLE_DICTATION
        // Dictation-only builds still support optional spoken confirmations.
        _synthesizer = [[AVSpeechSynthesizer alloc] init];
        _synthesizer.delegate = self;
#endif
#if FROTZ_ENABLE_DICTATION
        _audioEngine = [[AVAudioEngine alloc] init];
        _speechRecognizer = [[SFSpeechRecognizer alloc] initWithLocale:[NSLocale localeWithLocaleIdentifier:@"en-US"]];
        _speechRecognizer.queue = [NSOperationQueue mainQueue];
#endif
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioSessionInterrupted:)
                                                    name:AVAudioSessionInterruptionNotification object:nil];
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserver:self selector:@selector(accessibilityAnnouncementFinished:)
                       name:UIAccessibilityAnnouncementDidFinishNotification object:nil];
        [center addObserver:self selector:@selector(accessibilityFocusChanged:)
                       name:UIAccessibilityElementFocusedNotification object:nil];
        [center addObserver:self selector:@selector(voiceOverStatusChanged:)
                       name:UIAccessibilityVoiceOverStatusDidChangeNotification object:nil];

        _playerWords = [NSMutableOrderedSet orderedSet];
        _speechRate = 1.0f;
        _voiceMode = VoiceModeOff;
        _isPaused = NO;
        _beginsStoryResponse = YES;

        _charInputMap = @{
            @"yes": @"y",
            @"yeah": @"y",
            @"yep": @"y",
            @"no": @"n",
            @"nope": @"n",
            @"space": @" ",
            @"enter": @"\n",
            @"return": @"\n",
            @"escape": @"\x1b",
        };

        [self loadPreferences];
    }
    return self;
}

#pragma mark - Properties

+ (NSString *)languageFromBlorbAtPath:(NSString *)path {
    NSData *data = path.length ? [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil] : nil;
    if (data.length < 12) return nil;
    const unsigned char *bytes = data.bytes;
    if (memcmp(bytes, "FORM", 4) || memcmp(bytes + 8, "IFRS", 4)) return nil;
    uint64_t end = (uint64_t)blorbWord(bytes + 4) + 8;
    if (end > data.length || end < 12) return nil;
    for (uint64_t offset = 12; offset + 8 <= end;) {
        uint32_t size = blorbWord(bytes + offset + 4);
        uint64_t next = offset + 8 + size + (size & 1);
        if (next > end) return nil;
        if (!memcmp(bytes + offset, "IFmd", 4)) {
            if (size > 1024 * 1024) return nil;
            NSXMLParser *parser = [[NSXMLParser alloc] initWithData:[data subdataWithRange:NSMakeRange((NSUInteger)offset + 8, size)]];
            FrotzStoryLanguageParser *reader = [FrotzStoryLanguageParser new];
            reader.elements = [NSMutableArray array];
            parser.delegate = reader;
            parser.shouldProcessNamespaces = YES;
            parser.shouldResolveExternalEntities = NO;
            if (![parser parse]) return nil;
            NSString *language = reader.language;
            NSRange valid = [language rangeOfString:@"^[A-Za-z]{2,3}(-[A-Za-z]{2})?$" options:NSRegularExpressionSearch];
            return language.length && valid.location != NSNotFound ? language : nil;
        }
        offset = next;
    }
    return nil;
}

- (void)configureForStoryAtPath:(NSString *)path {
    _lastStoryResponse = nil;
    _beginsStoryResponse = YES;
    [_playerWords removeAllObjects];
    _commandWords = nil;
    _commandHints = nil;
    _recognizingConfirmation = NO;
    _recognizingCharacterInput = NO;
    _recognizedCommandNeedsConfirmation = NO;
    self.storyLanguage = [[self class] languageFromBlorbAtPath:path];
}

+ (NSString *)recognitionLanguageForLanguage:(NSString *)language {
    NSString *normalized = [[[NSLocale canonicalLanguageIdentifierFromString:language] stringByReplacingOccurrencesOfString:@"_" withString:@"-"] lowercaseString];
    NSString *base = [normalized componentsSeparatedByString:@"-"].firstObject;
    NSArray *locales = [[[SFSpeechRecognizer supportedLocales] allObjects] sortedArrayUsingComparator:^NSComparisonResult(NSLocale *a, NSLocale *b) {
        return [a.localeIdentifier compare:b.localeIdentifier];
    }];
    NSString *matching = nil;
    NSString *deviceLanguage = [[AVSpeechSynthesisVoice currentLanguageCode] stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
    for (NSLocale *locale in locales) {
        NSString *candidate = [locale.localeIdentifier stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
        if ([candidate.lowercaseString isEqualToString:normalized]) return locale.localeIdentifier;
        if ([[candidate.lowercaseString componentsSeparatedByString:@"-"].firstObject isEqualToString:base]) {
            if (!matching || [candidate isEqualToString:deviceLanguage]) matching = locale.localeIdentifier;
        }
    }
    return matching;
}

- (NSString *)effectiveRecognitionLanguage {
    return [[self class] recognitionLanguageForLanguage:self.speechRecognitionLanguage ?: self.storyLanguage ?: @"en-US"] ?: @"en-US";
}

- (void)updateSpeechRecognizer {
    if (!FROTZ_ENABLE_DICTATION) return;
    NSString *language = self.effectiveRecognitionLanguage;
    if ([_speechRecognizer.locale.localeIdentifier isEqualToString:language]) return;
    if (_speechRecognizer) [self stopListening];
    _speechRecognizer = [[SFSpeechRecognizer alloc] initWithLocale:[NSLocale localeWithLocaleIdentifier:language]];
    _speechRecognizer.queue = [NSOperationQueue mainQueue];
}

- (void)setStoryLanguage:(NSString *)language {
    _storyLanguage = [language copy];
    [self updateSpeechRecognizer];
}

- (void)setSpeechRecognitionLanguage:(NSString *)language {
    _speechRecognitionLanguage = [language copy];
    [self updateSpeechRecognizer];
}

- (BOOL)ttsEnabled {
    return FROTZ_ENABLE_NARRATION && (_voiceMode == VoiceModeTTSOnly || _voiceMode == VoiceModeBoth);
}

- (BOOL)sttEnabled {
    return FROTZ_ENABLE_DICTATION && (_voiceMode == VoiceModeSTTOnly || _voiceMode == VoiceModeBoth);
}

- (VoiceMode)voiceMode {
    return (VoiceMode)((self.ttsEnabled ? VoiceModeTTSOnly : 0) | (self.sttEnabled ? VoiceModeSTTOnly : 0));
}

- (BOOL)isSpeaking {
    return (_activeUtterance != nil || _accessibilityAnnouncement != nil) && !_isPaused;
}

- (BOOL)isVoiceOverEnabled { return UIAccessibilityIsVoiceOverRunning(); }
- (BOOL)voiceOverNavigationPaused { return _voiceOverNavigationPaused; }

- (void)resumeAfterVoiceOverNavigation { _voiceOverNavigationPaused = NO; }

- (void)pauseForVoiceOverNavigation {
    BOOL discardInput = self.isListening;
    _voiceOverNavigationPaused = self.isVoiceOverEnabled && self.sttEnabled;
    [self stopListening];
    [self stopSpeaking];
    if ([self.delegate respondsToSelector:@selector(voiceManagerDidPauseForVoiceOverDiscardingInput:)])
        [self.delegate voiceManagerDidPauseForVoiceOverDiscardingInput:discardInput];
}

- (void)accessibilityFocusChanged:(NSNotification *)notification {
    NSString *technology = notification.userInfo[UIAccessibilityAssistiveTechnologyKey];
    if (self.isVoiceOverEnabled && self.delegate && self.voiceMode != VoiceModeOff
        && (!technology || [technology isEqualToString:UIAccessibilityNotificationVoiceOverIdentifier]))
        [self pauseForVoiceOverNavigation];
}

- (void)voiceOverStatusChanged:(NSNotification *)notification {
    // Discard callbacks and partial commands from the previous audio arrangement.
    [self pauseForVoiceOverNavigation];
}

- (void)postAccessibilityAnnouncement:(NSString *)text {
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, text);
}

- (void)speakAccessibilityText:(NSString *)text {
    if (!FROTZ_ENABLE_NARRATION && !FROTZ_ENABLE_DICTATION) return;
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!self.isVoiceOverEnabled || trimmed.length == 0) return;
    [self stopListening];
    [self stopSpeaking];
    NSMutableArray *paragraphs = [NSMutableArray array];
    for (NSValue *value in [[self class] narrationRanges:trimmed]) {
        NSString *paragraph = [trimmed substringWithRange:value.rangeValue];
        // VoiceOver controls its own timing. Sentence punctuation and paragraph
        // boundaries supply the structure that raw heading newlines lack.
        if (![[@".!?…:;" stringByAppendingString:@"。！？"] containsString:[paragraph substringFromIndex:paragraph.length - 1]]
            && paragraphs.count == 0 && [trimmed rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound)
            paragraph = [paragraph stringByAppendingString:@"."];
        [paragraphs addObject:paragraph];
    }
    _accessibilityAnnouncement = [paragraphs componentsJoinedByString:@"\n\n"];
    [self.delegate voiceManagerDidStartSpeaking];
    [self postAccessibilityAnnouncement:_accessibilityAnnouncement];
}

- (void)accessibilityAnnouncementFinished:(NSNotification *)notification {
    if (!_accessibilityAnnouncement || ![notification.userInfo[UIAccessibilityAnnouncementKeyStringValue] isEqual:_accessibilityAnnouncement])
        return;
    _accessibilityAnnouncement = nil;
    if ([notification.userInfo[UIAccessibilityAnnouncementKeyWasSuccessful] boolValue]) {
        [self.delegate voiceManagerDidFinishSpeaking];
    } else {
        [self pauseForVoiceOverNavigation];
    }
}

- (BOOL)isListening {
    return _audioEngine.isRunning || _finishingRecognition;
}

#pragma mark - Spoiler-safe command recognition

+ (NSArray<NSString *> *)commandTokens:(NSString *)text {
    static NSRegularExpression *words;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ words = [NSRegularExpression regularExpressionWithPattern:@"[\\p{L}\\p{N}]+(?:['’][\\p{L}]+)*" options:0 error:nil]; });
    NSMutableArray *tokens = [NSMutableArray array];
    // Bound work for malformed or unexpectedly large transcripts/context.
    NSString *bounded = text.length > 32768 ? [text substringFromIndex:text.length - 32768] : text;
    for (NSTextCheckingResult *match in [words matchesInString:bounded ?: @"" options:0 range:NSMakeRange(0, bounded.length)])
        [tokens addObject:[[bounded substringWithRange:match.range] lowercaseString]];
    return tokens;
}

+ (NSArray<NSString *> *)ordinaryEnglishCommands {
    return @[@"take", @"get", @"drop", @"put", @"look", @"examine", @"open", @"close", @"read", @"wear", @"remove", @"go", @"give", @"ask", @"tell", @"wait", @"inventory", @"save", @"restore", @"quit", @"north", @"south", @"east", @"west", @"northeast", @"northwest", @"southeast", @"southwest", @"up", @"down", @"in", @"out", @"at", @"to", @"with", @"from", @"the", @"a", @"an", @"on", @"off", @"all", @"it", @"me"];
}

+ (NSArray<NSString *> *)ordinaryEnglishDirections {
    return @[@"north", @"south", @"east", @"west", @"northeast", @"northwest", @"southeast", @"southwest", @"up", @"down", @"in", @"out"];
}

- (void)rememberPlayerCommand:(NSString *)text {
    _beginsStoryResponse = YES;
    for (NSString *word in [[self class] commandTokens:text]) {
        [_playerWords removeObject:word];
        [_playerWords addObject:word];
    }
    while (_playerWords.count > 256) [_playerWords removeObjectAtIndex:0];
}

- (void)updateCommandContextWithVisibleText:(NSString *)text {
    NSMutableOrderedSet *words = [NSMutableOrderedSet orderedSet];
    if ([self.effectiveRecognitionLanguage.lowercaseString hasPrefix:@"en"])
        [words addObjectsFromArray:[[self class] ordinaryEnglishCommands]];
    NSArray *visible = [[self class] commandTokens:text];
    if (visible.count > 2000) visible = [visible subarrayWithRange:NSMakeRange(visible.count - 2000, 2000)];
    [words addObjectsFromArray:visible];
    [words addObjectsFromArray:_playerWords.array];
    _commandWords = [NSSet setWithArray:words.array];
    NSMutableOrderedSet *recent = [NSMutableOrderedSet orderedSet];
    for (NSString *word in [visible arrayByAddingObjectsFromArray:_playerWords.array]) {
        [recent removeObject:word];
        [recent addObject:word];
    }
    NSMutableOrderedSet *hints = [NSMutableOrderedSet orderedSet];
    if ([self.effectiveRecognitionLanguage.lowercaseString hasPrefix:@"en"]) {
        [hints addObjectsFromArray:[[self class] ordinaryEnglishCommands]];
        for (NSString *direction in [[self class] ordinaryEnglishDirections])
            [hints addObject:[@"go " stringByAppendingString:direction]];
    }
    for (NSString *word in recent.reverseObjectEnumerator) {
        if (hints.count >= 100) break;
        [hints addObject:word];
    }
    _commandHints = hints.array;
}

+ (NSArray<NSString *> *)confirmationWordsForLanguage:(NSString *)language {
    NSString *base = [[language.lowercaseString stringByReplacingOccurrencesOfString:@"_" withString:@"-"] componentsSeparatedByString:@"-"].firstObject;
    // First three are the UI's confirm/retry/cancel labels; no English guesses in
    // other locales. Unsupported control languages still have on-screen buttons.
    NSDictionary *controls = @{@"en": @[@"confirm", @"retry", @"cancel"],
        @"fr": @[@"confirmer", @"réessayer", @"annuler"],
        @"es": @[@"confirmar", @"reintentar", @"cancelar"],
        @"de": @[@"bestätigen", @"wiederholen", @"abbrechen"],
        @"it": @[@"conferma", @"riprova", @"annulla"],
        @"pt": @[@"confirmar", @"repetir", @"cancelar"]};
    return controls[base] ?: @[];
}

+ (NSString *)confirmationActionForText:(NSString *)text language:(NSString *)language {
    NSString *normalized = [[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    normalized = [normalized stringByTrimmingCharactersInSet:NSCharacterSet.punctuationCharacterSet];
    NSArray *words = [self confirmationWordsForLanguage:language];
    NSUInteger index = [words indexOfObject:normalized];
    return index < 3 ? @[@"confirm", @"retry", @"cancel"][index] : nil;
}

// A bounded edit distance of at most one; used only to rank actual recognizer
// alternatives, never to manufacture a new command from a story dictionary.
+ (BOOL)word:(NSString *)a isNearWord:(NSString *)b {
    if (a.length > 32 || b.length > 32 || labs((long)a.length - (long)b.length) > 1) return NO;
    NSUInteger i = 0, j = 0, edits = 0;
    while (i < a.length && j < b.length) {
        if ([a characterAtIndex:i] == [b characterAtIndex:j]) { ++i; ++j; continue; }
        if (++edits > 1) return NO;
        if (a.length >= b.length) ++i;
        if (b.length >= a.length) ++j;
    }
    return edits + (i < a.length || j < b.length) <= 1;
}

+ (float)minimumConfidence:(SFTranscription *)transcription {
    float confidence = 1;
    if (transcription.segments.count == 0) return 0;
    for (SFTranscriptionSegment *segment in transcription.segments) {
        if (!isfinite(segment.confidence) || segment.confidence <= 0) return 0;
        confidence = MIN(confidence, segment.confidence);
    }
    return confidence;
}

- (NSString *)commandFromResult:(SFSpeechRecognitionResult *)result {
    NSString *original = result.bestTranscription.formattedString;
    if (self.recognizingConfirmation) {
        // These are UI controls, not arbitrary game commands. Missing scores
        // are common for short replies and do not mean measured low confidence.
        NSString *choice = nil;
        NSString *reply = nil;
        BOOL reliable = NO;
        NSUInteger count = 0;
        for (SFTranscription *transcription in result.transcriptions) {
            if (++count > 8) break;
            NSString *action = [[self class] confirmationActionForText:transcription.formattedString language:self.effectiveRecognitionLanguage];
            if (!action) continue;
            if (choice && ![choice isEqual:action]) {
                _recognizedCommandNeedsConfirmation = YES;
                return original; // Conflicting controls must never approve a turn.
            }
            choice = action;
            float confidence = [[self class] minimumConfidence:transcription];
            if (confidence >= 0.8 || (transcription == result.bestTranscription && confidence == 0)) {
                reply = transcription.formattedString;
                reliable = YES;
            }
        }
        _recognizedCommandNeedsConfirmation = !reliable;
        return reply ?: original;
    }
    // Confidence is a heuristic, not a guarantee of intent. Zero/absent scores
    // are unknown. A confidently spoken unusual command must survive unchanged.
    _recognizedCommandNeedsConfirmation = [[self class] minimumConfidence:result.bestTranscription] < 0.8;
    if (!_recognizedCommandNeedsConfirmation || self.recognizingConfirmation || self.recognizingCharacterInput
        || ![self.effectiveRecognitionLanguage.lowercaseString hasPrefix:@"en"]
        || [original rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\"'“”‘’«»‹›„‟「」『』＂＇;\n."]].location != NSNotFound)
        return original;
    NSArray *source = [[self class] commandTokens:original];
    if (source.count == 0 || source.count > 12) return original;
    NSInteger bestScore = 0;
    for (NSString *word in source) if ([_commandWords containsObject:word]) ++bestScore;
    // A low-confidence single-word direction is a complete conventional command.
    // Visible prose alone ("the grass is wet") is not evidence that "wet" is a verb.
    BOOL shortCommand = source.count == 1 && ![_playerWords containsObject:source.firstObject];
    if (shortCommand && [[[self class] ordinaryEnglishDirections] containsObject:source.firstObject]) ++bestScore;
    NSInteger originalScore = bestScore;
    NSString *best = original;
    BOOL tied = NO;
    NSUInteger count = 0;
    for (SFTranscription *alternative in result.transcriptions) {
        if (++count > 8) break;
        NSArray *tokens = [[self class] commandTokens:alternative.formattedString];
        if (tokens.count != source.count || [tokens isEqualToArray:source]) continue;
        if ([alternative.formattedString rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\"'“”‘’«»‹›„‟「」『』＂＇;\n."]].location != NSNotFound) continue;
        NSInteger score = 0;
        NSUInteger changes = 0;
        BOOL safe = YES;
        for (NSUInteger i = 0; i < tokens.count; ++i) {
            NSString *word = tokens[i];
            if ([_commandWords containsObject:word]) ++score;
            if (![word isEqualToString:source[i]]) {
                ++changes;
                // Changed words must already be player-visible or ordinary.
                if (![_commandWords containsObject:word] || ![[self class] word:word isNearWord:source[i]]) safe = NO;
            }
        }
        if (shortCommand && [[[self class] ordinaryEnglishDirections] containsObject:tokens.firstObject]) ++score;
        if (!safe || changes > 2 || score <= originalScore) continue;
        if (score > bestScore) { bestScore = score; best = alternative.formattedString; tied = NO; }
        else if (score == bestScore && ![best.lowercaseString isEqualToString:alternative.formattedString.lowercaseString]) tied = YES;
    }
    return tied ? original : best;
}

#pragma mark - TTS

+ (NSArray<NSValue *> *)narrationRanges:(NSString *)text {
    NSMutableArray *ranges = [NSMutableArray array];
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length) options:NSStringEnumerationByParagraphs
        usingBlock:^(NSString *part, NSRange range, NSRange enclosing, BOOL *stop) {
        NSCharacterSet *whitespace = NSCharacterSet.whitespaceAndNewlineCharacterSet;
        while (range.length && [whitespace characterIsMember:[text characterAtIndex:range.location]]) { ++range.location; --range.length; }
        while (range.length && [whitespace characterIsMember:[text characterAtIndex:NSMaxRange(range) - 1]]) --range.length;
        if (range.length) [ranges addObject:[NSValue valueWithRange:range]];
    }];
    return ranges;
}

+ (NSString *)qualityDescriptionForVoice:(AVSpeechSynthesisVoice *)voice {
    if (@available(iOS 16.0, *)) {
        if (voice.quality == AVSpeechSynthesisVoiceQualityPremium)
            return @"Premium";
    }
    return voice.quality == AVSpeechSynthesisVoiceQualityEnhanced ? @"Enhanced" : @"Standard";
}

+ (AVSpeechSynthesisVoice *)automaticVoiceFromVoices:(NSArray<AVSpeechSynthesisVoice *> *)voices {
    return [self automaticVoiceFromVoices:voices language:@"en-US"];
}

+ (AVSpeechSynthesisVoice *)automaticVoiceFromVoices:(NSArray<AVSpeechSynthesisVoice *> *)voices language:(NSString *)language {
    NSString *normalized = [[[NSLocale canonicalLanguageIdentifierFromString:language] stringByReplacingOccurrencesOfString:@"_" withString:@"-"] lowercaseString];
    NSString *base = [normalized componentsSeparatedByString:@"-"].firstObject;
    NSString *systemVoiceIdentifier = [AVSpeechSynthesisVoice voiceWithLanguage:language].identifier;
    AVSpeechSynthesisVoice *best = nil;
    for (AVSpeechSynthesisVoice *voice in voices) {
        if (![[voice.language.lowercaseString componentsSeparatedByString:@"-"].firstObject isEqualToString:base])
            continue;
        BOOL sameQuality = voice.quality == best.quality;
        BOOL preferredRegion = [voice.language.lowercaseString isEqualToString:normalized];
        BOOL bestRegion = [best.language.lowercaseString isEqualToString:normalized];
        BOOL systemVoice = [voice.identifier isEqualToString:systemVoiceIdentifier];
        BOOL bestSystemVoice = [best.identifier isEqualToString:systemVoiceIdentifier];
        if (!best || voice.quality > best.quality
            || (sameQuality && preferredRegion && !bestRegion)
            || (sameQuality && preferredRegion == bestRegion
                && systemVoice && !bestSystemVoice)
            || (sameQuality && preferredRegion == bestRegion && systemVoice == bestSystemVoice
                && [voice.identifier compare:best.identifier] == NSOrderedAscending))
            best = voice;
    }
    return best;
}

- (AVSpeechSynthesisVoice *)speechVoice {
    AVSpeechSynthesisVoice *selected = self.speechVoiceIdentifier.length
        ? [AVSpeechSynthesisVoice voiceWithIdentifier:self.speechVoiceIdentifier] : nil;
    return selected ?: self.automaticSpeechVoice;
}

- (AVSpeechSynthesisVoice *)automaticSpeechVoice {
    NSString *language = self.storyLanguage ?: @"en-US";
    return [[self class] automaticVoiceFromVoices:[AVSpeechSynthesisVoice speechVoices] language:language]
        ?: [AVSpeechSynthesisVoice voiceWithLanguage:language]
        ?: [AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"];
}

- (NSString *)speechVoiceDescription {
    AVSpeechSynthesisVoice *selected = self.speechVoiceIdentifier.length
        ? [AVSpeechSynthesisVoice voiceWithIdentifier:self.speechVoiceIdentifier] : nil;
    if (selected)
        return [NSString stringWithFormat:@"%@ (%@)", selected.name, [[self class] qualityDescriptionForVoice:selected]];
    return self.speechVoiceIdentifier.length ? @"Automatic (voice unavailable)" : @"Automatic";
}

- (void)speakText:(NSString *)text inView:(RichTextView *)view {
    if (!self.ttsEnabled) return;
    [self rememberStoryResponse:text];
    [self speakVoiceText:text inView:view];
}

- (NSString *)lastStoryResponse { return _lastStoryResponse; }

- (void)rememberStoryResponse:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length) return;
    NSString *response = _beginsStoryResponse || !_lastStoryResponse.length
        ? trimmed : [_lastStoryResponse stringByAppendingFormat:@"\n%@", trimmed];
    // Bound retained output, including stories that print indefinitely without input.
    if (response.length > 65536) {
        NSRange tail = [response rangeOfComposedCharacterSequencesForRange:NSMakeRange(response.length - 65536, 65536)];
        response = [response substringWithRange:tail];
    }
    _lastStoryResponse = [response copy];
    _beginsStoryResponse = NO;
}

- (BOOL)replayLastStoryResponse {
    if (!_lastStoryResponse.length || self.voiceMode == VoiceModeOff) return NO;
    [self stopListening];
    [self stopSpeaking];
    [self speakVoiceText:_lastStoryResponse inView:nil];
    return self.isSpeaking;
}

- (void)playVoiceFeedback:(VoiceFeedback)feedback {
    if (feedback < VoiceFeedbackReady || feedback > VoiceFeedbackError) return;
    if (!_feedbackSounds[feedback]) {
        // Short, nonverbal PCM cues use system-sound mixing without reconfiguring
        // the recording session or interrupting VoiceOver to speak a status.
        const double notes[4][3] = {{550, 880, 0}, {330, 0, 0}, {440, 260, 0}, {220, 220, 220}};
        NSUInteger count = feedback == VoiceFeedbackError ? 3 : (feedback == VoiceFeedbackStopped ? 1 : 2);
        const double rate = 22050;
        AVAudioFrameCount noteFrames = (AVAudioFrameCount)(rate * 0.06);
        AVAudioFrameCount gapFrames = (AVAudioFrameCount)(rate * 0.025);
        AVAudioFrameCount frames = (noteFrames + gapFrames) * (AVAudioFrameCount)count;
        AVAudioFormat *format = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16 sampleRate:rate channels:1 interleaved:YES];
        AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:frames];
        buffer.frameLength = frames;
        int16_t *samples = buffer.int16ChannelData[0];
        memset(samples, 0, frames * sizeof(int16_t));
        for (NSUInteger note = 0; note < count; ++note) {
            for (AVAudioFrameCount i = 0; i < noteFrames; ++i) {
                double envelope = sin(M_PI * i / noteFrames);
                samples[note * (noteFrames + gapFrames) + i] = (int16_t)(8000 * envelope * sin(2 * M_PI * notes[feedback][note] * i / rate));
            }
        }
        NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"frotz-voice-cue-%ld.wav", (long)feedback]]];
        AVAudioFile *file = [[AVAudioFile alloc] initForWriting:url settings:format.settings commonFormat:AVAudioPCMFormatInt16 interleaved:YES error:nil];
        BOOL written = [file writeFromBuffer:buffer error:nil];
        file = nil; // Close the WAV before the system sound service opens it.
        if (written) AudioServicesCreateSystemSoundID((__bridge CFURLRef)url, &_feedbackSounds[feedback]);
    }
    if (_feedbackSounds[feedback]) AudioServicesPlaySystemSound(_feedbackSounds[feedback]);
    if (feedback == VoiceFeedbackReady) {
        [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    } else if (feedback == VoiceFeedbackNavigationPaused || feedback == VoiceFeedbackError) {
        [[[UINotificationFeedbackGenerator alloc] init] notificationOccurred:feedback == VoiceFeedbackError ? UINotificationFeedbackTypeError : UINotificationFeedbackTypeWarning];
    }
}

- (void)dealloc {
    for (NSUInteger i = 0; i < 4; ++i) if (_feedbackSounds[i]) AudioServicesDisposeSystemSoundID(_feedbackSounds[i]);
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)speakConfirmationPrompt:(NSString *)text {
    [self stopSpeaking];
    [self speakVoiceText:text inView:nil];
}

- (void)speakVoiceText:(NSString *)text inView:(RichTextView *)view {
    if (!FROTZ_ENABLE_NARRATION && !FROTZ_ENABLE_DICTATION) return;
    if (text.length == 0) return;
    if (self.isVoiceOverEnabled) {
        [self speakAccessibilityText:text];
        return;
    }

    // Strip leading/trailing whitespace but preserve internal structure
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0)
        return;

    _activeView = view;
    _currentUtteranceText = trimmed;

    _changingVoiceDirection = YES;
    [self stopListening];
    BOOL playbackReady = [self configureAudioSessionForPlayback];
    _changingVoiceDirection = NO;
    if (!playbackReady) {
        [self deactivateAudioSession];
        return;
    }
    _speechParagraphs = [NSMutableArray array];
    _speechOffsets = [NSMapTable strongToStrongObjectsMapTable];
    NSArray<NSValue *> *ranges = [[self class] narrationRanges:trimmed];
    for (NSValue *value in ranges) {
        NSRange range = value.rangeValue;
        AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:[trimmed substringWithRange:range]];
        utterance.rate = rateMultiplierToAVRate(_speechRate);
        utterance.voice = self.speechVoice;
        utterance.postUtteranceDelay = value == ranges.lastObject ? 0 : 0.20;
        [_speechParagraphs addObject:utterance];
        [_speechOffsets setObject:@(range.location) forKey:utterance];
    }
    _activeUtterance = _speechParagraphs.firstObject;
    for (AVSpeechUtterance *utterance in _speechParagraphs) [_synthesizer speakUtterance:utterance];
    NSLog(@"Voice speech started");
    [self.delegate voiceManagerDidStartSpeaking];
}

- (void)stopSpeaking {
    _accessibilityAnnouncement = nil;
    _activeUtterance = nil;
    _speechParagraphs = nil;
    _speechOffsets = nil;
    if (_synthesizer.isSpeaking) {
        [_synthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    }
    _isPaused = NO;
    _currentUtteranceText = nil;
    [self clearHighlight];
    // Deactivate playback audio session so a subsequent recording session can start cleanly
    if (!self.isListening)
        [self deactivateAudioSession];
}

- (void)pauseSpeaking {
    if (_synthesizer.isSpeaking && !_isPaused) {
        [_synthesizer pauseSpeakingAtBoundary:AVSpeechBoundaryImmediate];
        _isPaused = YES;
    }
}

- (void)resumeSpeaking {
    if (_isPaused) {
        [_synthesizer continueSpeaking];
        _isPaused = NO;
    }
}

- (void)clearHighlight {
    [self.delegate voiceManagerDidClearHighlight];
}

#pragma mark - AVSpeechSynthesizerDelegate

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer willSpeakRangeOfSpeechString:(NSRange)characterRange utterance:(AVSpeechUtterance *)utterance {
    if (utterance != _activeUtterance)
        return;
    RichTextView *view = _activeView;
    if (view && self.delegate) {
        characterRange.location += [[_speechOffsets objectForKey:utterance] unsignedIntegerValue];
        [self.delegate voiceManagerHighlightRange:characterRange inView:view];
    }
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didFinishSpeechUtterance:(AVSpeechUtterance *)utterance {
    if (utterance != _activeUtterance)
        return;
    if (_speechParagraphs.count) [_speechParagraphs removeObjectAtIndex:0];
    [_speechOffsets removeObjectForKey:utterance];
    if (_speechParagraphs.count) {
        _activeUtterance = _speechParagraphs.firstObject;
        return; // The whole response must finish before listening can resume.
    }
    _activeUtterance = nil;
    _currentUtteranceText = nil;
    _isPaused = NO;
    [self clearHighlight];
    NSLog(@"Voice speech finished");
    [self.delegate voiceManagerDidFinishSpeaking];
    // Keep audio intact only when the controller actually scheduled capture (or
    // another narration). Typing and inactive views must release it normally.
    BOOL handoff = self.sttEnabled && [self.delegate respondsToSelector:@selector(voiceManagerWillResumeListening)]
        && [self.delegate voiceManagerWillResumeListening];
    if (!handoff && !self.isListening && !self.isSpeaking) [self deactivateAudioSession];
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didCancelSpeechUtterance:(AVSpeechUtterance *)utterance {
    if (utterance != _activeUtterance)
        return;
    _activeUtterance = nil;
    _speechParagraphs = nil;
    _speechOffsets = nil;
    _currentUtteranceText = nil;
    _isPaused = NO;
    [self clearHighlight];
}

#pragma mark - STT

- (void)requestSTTPermissionsWithCompletion:(void (^)(BOOL granted))completion {
    if (!FROTZ_ENABLE_DICTATION) { completion(NO); return; }
    [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
        if (status != SFSpeechRecognizerAuthorizationStatusAuthorized) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO);
            });
            return;
        }

        [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(granted);
            });
        }];
    }];
}

- (BOOL)recordingIsAuthorized {
    return [SFSpeechRecognizer authorizationStatus] == SFSpeechRecognizerAuthorizationStatusAuthorized
        && [AVAudioSession sharedInstance].recordPermission == AVAudioSessionRecordPermissionGranted;
}

- (void)startListening {
    NSTimeInterval startupTime = NSProcessInfo.processInfo.systemUptime;
    // Delayed auto-starts must never toggle an existing recording off.
    if (!self.sttEnabled || self.isListening || self.isSpeaking || (self.isVoiceOverEnabled && _voiceOverNavigationPaused))
        return;
    if (![[self class] recognitionLanguageForLanguage:self.speechRecognitionLanguage ?: self.storyLanguage ?: @"en-US"]) {
        [self deactivateAudioSession];
        [self reportRecordingError:[NSError errorWithDomain:@"FrotzVoice" code:3
                                                  userInfo:@{NSLocalizedDescriptionKey: @"The story language is not supported for speech recognition. Choose a Speech Input Language in Settings."}]];
        return;
    }
    if (![self recordingIsAuthorized] || !_speechRecognizer.isAvailable) {
        [self deactivateAudioSession];
        [self reportRecordingError:[NSError errorWithDomain:@"FrotzVoice" code:1
                                                  userInfo:@{NSLocalizedDescriptionKey: @"Speech recognition is unavailable. Check microphone and speech permissions in Settings."}]];
        return;
    }

    _changingVoiceDirection = YES;
    [self stopListening];
    // No active narration remains here. In particular, do not stop the speech
    // audio object merely because it is still draining after didFinish.
    BOOL recordingReady = [self configureAudioSessionForRecording];
    _changingVoiceDirection = NO;
    if (!recordingReady) {
        [self deactivateAudioSession];
        return;
    }

    // VoiceOver can speak without moving focus (for example, rereading a
    // focused button). Cancel speaker echo before feeding microphone audio to STT.
    AVAudioInputNode *inputNode = _audioEngine.inputNode;
    BOOL needsVoiceProcessing = self.isVoiceOverEnabled;
    BOOL processingReady = !needsVoiceProcessing;
    if (@available(iOS 13.0, *)) {
        NSError *processingError = nil;
        processingReady = inputNode.isVoiceProcessingEnabled == needsVoiceProcessing
            || [inputNode setVoiceProcessingEnabled:needsVoiceProcessing error:&processingError];
        processingReady = processingReady && inputNode.isVoiceProcessingEnabled == needsVoiceProcessing;
        if (processingReady && needsVoiceProcessing) {
            if (@available(iOS 17.0, *)) {
                AVAudioVoiceProcessingOtherAudioDuckingConfiguration ducking = { NO, AVAudioVoiceProcessingOtherAudioDuckingLevelMin };
                inputNode.voiceProcessingOtherAudioDuckingConfiguration = ducking;
            }
        }
    }
    if (!processingReady) {
        [self stopListening];
        [self reportRecordingError:[NSError errorWithDomain:@"FrotzVoice" code:5
            userInfo:@{NSLocalizedDescriptionKey: @"Voice input with VoiceOver is unavailable. Retry or use the keyboard."}]];
        return;
    }

    _hasReceivedSpeech = NO;
    _recognitionRequest = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
    _recognitionRequest.shouldReportPartialResults = YES;
    NSArray *controls = [[self class] confirmationWordsForLanguage:self.effectiveRecognitionLanguage];
    if (self.recognizingCharacterInput) {
        _recognitionRequest.contextualStrings = @[];
    } else if (self.recognizingConfirmation) {
        _recognitionRequest.contextualStrings = controls;
        _recognitionRequest.taskHint = SFSpeechRecognitionTaskHintConfirmation;
    } else {
        _recognitionRequest.contextualStrings = _commandHints ?: @[];
        _recognitionRequest.taskHint = SFSpeechRecognitionTaskHintSearch;
    }
    if (@available(iOS 13.0, *)) {
        if (_speechRecognizer.supportsOnDeviceRecognition)
            _recognitionRequest.requiresOnDeviceRecognition = YES;
    }

    AVAudioFormat *recordingFormat = [inputNode outputFormatForBus:0];
    if (recordingFormat.sampleRate <= 0 || recordingFormat.channelCount == 0) {
        [self stopListening];
        [self reportRecordingError:[NSError errorWithDomain:@"FrotzVoice" code:2
                                                  userInfo:@{NSLocalizedDescriptionKey: @"No microphone input is available."}]];
        return;
    }

    NSUInteger generation = _recognitionGeneration;
    SFSpeechAudioBufferRecognitionRequest *request = _recognitionRequest;
    __weak __typeof(self) weakSelf = self;
    _recognitionTask = [_speechRecognizer recognitionTaskWithRequest:request resultHandler:^(SFSpeechRecognitionResult *result, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong __typeof(weakSelf) self = weakSelf;
            if (!self || generation != self->_recognitionGeneration)
                return;
            if (result) {
                NSString *text = result.isFinal ? [self commandFromResult:result] : result.bestTranscription.formattedString;
                if (result.isFinal) {
                    [self stopListening];
                    [self.delegate voiceManagerDidRecognizeText:text isFinal:YES];
                    return;
                }
                if (text.length > 0) {
                    self->_hasReceivedSpeech = YES;
                    [self.delegate voiceManagerDidRecognizeText:text isFinal:NO];
                    if (!self->_finishingRecognition)
                        [self resetSilenceTimer];
                }
            }
            if (error) {
                [self stopListening];
                [self reportRecordingError:error];
            }
        });
    }];

    // Capture this request rather than the mutable request for a later session.
    [inputNode installTapOnBus:0 bufferSize:1024 format:recordingFormat block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
        [request appendAudioPCMBuffer:buffer];
    }];
    _inputTapInstalled = YES;
    [_audioEngine prepare];
    NSError *error = nil;
    if (![_audioEngine startAndReturnError:&error]) {
        [self stopListening];
        [self reportRecordingError:error];
        return;
    }
    NSLog(@"Voice recording started (startup %.0f ms)",
          (NSProcessInfo.processInfo.systemUptime - startupTime) * 1000.0);
    [self.delegate voiceManagerDidStartListening];
}

- (void)stopListening {
    BOOL wasListening = self.isListening;
    ++_recognitionGeneration; // Invalidate queued results before canceling the task.
    [_silenceTimer invalidate];
    _silenceTimer = nil;
    [_audioEngine stop];
    if (_inputTapInstalled) {
        [_audioEngine.inputNode removeTapOnBus:0];
        _inputTapInstalled = NO;
    }
    [_recognitionRequest endAudio];
    _recognitionRequest = nil;
    [_recognitionTask cancel];
    _recognitionTask = nil;
    _finishingRecognition = NO;
    if (!_changingVoiceDirection && !_synthesizer.isSpeaking)
        [self deactivateAudioSession];
    if (wasListening) {
        NSLog(@"Voice recording stopped");
        [self.delegate voiceManagerDidStopListening];
    }
}

- (void)resetSilenceTimer {
    [_silenceTimer invalidate];
    if (!_hasReceivedSpeech)
        return;
    _silenceTimer = [NSTimer scheduledTimerWithTimeInterval:1.2 target:self
                                                  selector:@selector(silenceTimerFired) userInfo:nil repeats:NO];
}

- (void)silenceTimerFired {
    if (!_audioEngine.isRunning || _finishingRecognition)
        return;
    [_audioEngine stop];
    if (_inputTapInstalled) {
        [_audioEngine.inputNode removeTapOnBus:0];
        _inputTapInstalled = NO;
    }
    _finishingRecognition = YES;
    [_recognitionRequest endAudio];
    // Bound the wait for a final result if the speech service never responds.
    _silenceTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self
                                                  selector:@selector(recognitionTimedOut) userInfo:nil repeats:NO];
}

- (void)recognitionTimedOut {
    [self stopListening];
    [self reportRecordingError:[NSError errorWithDomain:@"FrotzVoice" code:3
                                              userInfo:@{NSLocalizedDescriptionKey: @"Speech recognition timed out. Tap to try again."}]];
}

- (void)reportRecordingError:(NSError *)error {
    [self.delegate voiceManagerSTTError:error];
}

#pragma mark - Audio Session

- (BOOL)configureAudioSessionForPlayback {
    if (self.sttEnabled) return [self configureAudioSessionForRecording];
    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    return [session setCategory:AVAudioSessionCategoryPlayback
                   withOptions:AVAudioSessionCategoryOptionDuckOthers error:&error]
        && [session setActive:YES error:&error];
}

- (AVAudioSession *)recordingAudioSession { return AVAudioSession.sharedInstance; }

- (BOOL)configureAudioSessionForRecording {
    NSError *error = nil;
    AVAudioSession *session = [self recordingAudioSession];
    NSString *mode = self.isVoiceOverEnabled ? AVAudioSessionModeVoiceChat : AVAudioSessionModeDefault;
    AVAudioSessionCategoryOptions options = AVAudioSessionCategoryOptionDefaultToSpeaker | AVAudioSessionCategoryOptionAllowBluetooth;
    BOOL configured = ([session.category isEqual:AVAudioSessionCategoryPlayAndRecord]
                       && [session.mode isEqual:mode] && session.categoryOptions == options)
        || [session setCategory:AVAudioSessionCategoryPlayAndRecord mode:mode options:options error:&error];
    if (configured) {
        if (@available(iOS 13.0, *)) {
            // Otherwise iOS suppresses the readiness cue once recording begins.
            [session setAllowHapticsAndSystemSoundsDuringRecording:YES error:nil];
        }
        configured = [session setActive:YES error:&error];
    }
    if (!configured)
        [self reportRecordingError:error];
    return configured;
}

- (void)deactivateAudioSession {
    [[AVAudioSession sharedInstance] setActive:NO
                                  withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
}

- (void)audioSessionInterrupted:(NSNotification *)notification {
    if (self.voiceMode == VoiceModeOff && !self.isSpeaking && !self.isListening) return;
    if ([notification.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue] != AVAudioSessionInterruptionTypeBegan)
        return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self stopListening];
        [self stopSpeaking];
        [self reportRecordingError:[NSError errorWithDomain:@"FrotzVoice" code:4
                                                  userInfo:@{NSLocalizedDescriptionKey: @"Audio was interrupted. Tap to try again."}]];
    });
}

#pragma mark - Translation

- (NSString *)translateForCharInput:(NSString *)spokenText {
    NSString *lower = [[spokenText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if (lower.length == 0)
        return @"";
    NSString *mapped = _charInputMap[lower];
    if (mapped)
        return mapped;

    // If it's a single character already, pass through
    if (lower.length == 1)
        return lower;

    // Try first character as fallback
    return [lower substringWithRange:[lower rangeOfComposedCharacterSequenceAtIndex:0]];
}

- (NSString *)commandConfirmationDescription {
    switch (self.commandConfirmationMode) {
        case VoiceCommandConfirmationAsNeeded: return @"As Needed";
        case VoiceCommandConfirmationAlways: return @"Always";
        default: return @"Off";
    }
}

#pragma mark - Persistence

- (void)savePreferences {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:self.commandConfirmationMode forKey:kCommandConfirmationModeKey];
    [defaults setInteger:_voiceMode forKey:kVoiceModeKey];
    [defaults setFloat:_speechRate forKey:kSpeechRateKey];
    [defaults setObject:self.speechVoiceIdentifier forKey:kSpeechVoiceKey];
    [defaults setObject:self.speechRecognitionLanguage forKey:kRecognitionLanguageKey];
    [defaults synchronize];
}

- (void)loadPreferences {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kCommandConfirmationModeKey]) {
        NSInteger storedMode = [defaults integerForKey:kCommandConfirmationModeKey];
        self.commandConfirmationMode = storedMode >= VoiceCommandConfirmationOff && storedMode <= VoiceCommandConfirmationAlways
            ? (VoiceCommandConfirmationMode)storedMode : VoiceCommandConfirmationOff;
    } else {
        // Preserve the old switch choice; absent preferences default to Off.
        self.commandConfirmationMode = [defaults boolForKey:kLegacyCommandConfirmationKey]
            ? VoiceCommandConfirmationAsNeeded : VoiceCommandConfirmationOff;
    }
    self.speechVoiceIdentifier = [defaults stringForKey:kSpeechVoiceKey];
    self.speechRecognitionLanguage = [defaults stringForKey:kRecognitionLanguageKey];
    if ([defaults objectForKey:kVoiceModeKey]) {
        NSInteger storedMode = [defaults integerForKey:kVoiceModeKey];
        _voiceMode = storedMode >= VoiceModeOff && storedMode <= VoiceModeBoth ? (VoiceMode)storedMode : VoiceModeOff;
    }
    if ([defaults objectForKey:kSpeechRateKey]) {
        _speechRate = [defaults floatForKey:kSpeechRateKey];
    }
    if (_speechRate < 0.5f) _speechRate = 0.5f;
    if (_speechRate > 3.0f) _speechRate = 3.0f;
}

@end
