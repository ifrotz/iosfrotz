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
static NSString *const kCommandConfirmationKey = @"FrotzVoiceCommandConfirmationEnabled";

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

    // TTS state
    NSString *_currentUtteranceText;  // full text of current utterance for range mapping
    BOOL _isPaused;
    AVSpeechUtterance *_activeUtterance;

    // Char input translation dictionary
    NSDictionary<NSString *, NSString *> *_charInputMap;
}

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
        _synthesizer = [[AVSpeechSynthesizer alloc] init];
        _synthesizer.delegate = self;

        _audioEngine = [[AVAudioEngine alloc] init];
        _speechRecognizer = [[SFSpeechRecognizer alloc] initWithLocale:[NSLocale localeWithLocaleIdentifier:@"en-US"]];
        _speechRecognizer.queue = [NSOperationQueue mainQueue];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioSessionInterrupted:)
                                                    name:AVAudioSessionInterruptionNotification object:nil];

        _playerWords = [NSMutableOrderedSet orderedSet];
        _speechRate = 1.0f;
        _voiceMode = VoiceModeOff;
        _isPaused = NO;

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
    return _voiceMode == VoiceModeTTSOnly || _voiceMode == VoiceModeBoth;
}

- (BOOL)sttEnabled {
    return _voiceMode == VoiceModeSTTOnly || _voiceMode == VoiceModeBoth;
}

- (BOOL)isSpeaking {
    return _activeUtterance != nil && !_isPaused;
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
    return @[@"take", @"get", @"drop", @"put", @"look", @"examine", @"open", @"close", @"read", @"wear", @"remove", @"go", @"give", @"ask", @"tell", @"wait", @"inventory", @"save", @"restore", @"quit", @"north", @"south", @"east", @"west", @"up", @"down", @"in", @"out", @"at", @"to", @"with", @"from", @"the", @"a", @"an", @"on", @"off", @"all", @"it", @"me"];
}

- (void)rememberPlayerCommand:(NSString *)text {
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
    if ([self.effectiveRecognitionLanguage.lowercaseString hasPrefix:@"en"])
        [hints addObjectsFromArray:[[self class] ordinaryEnglishCommands]];
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
        if (!safe || changes > 2 || score <= originalScore) continue;
        if (score > bestScore) { bestScore = score; best = alternative.formattedString; tied = NO; }
        else if (score == bestScore && ![best.lowercaseString isEqualToString:alternative.formattedString.lowercaseString]) tied = YES;
    }
    return tied ? original : best;
}

#pragma mark - TTS

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
    [self speakVoiceText:text inView:view];
}

- (void)speakConfirmationPrompt:(NSString *)text {
    [self stopSpeaking];
    [self speakVoiceText:text inView:nil];
}

- (void)speakVoiceText:(NSString *)text inView:(RichTextView *)view {
    if (text.length == 0) return;

    // Strip leading/trailing whitespace but preserve internal structure
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0)
        return;

    _activeView = view;
    _currentUtteranceText = trimmed;

    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:trimmed];
    utterance.rate = rateMultiplierToAVRate(_speechRate);
    utterance.pitchMultiplier = 1.0f;
    utterance.preUtteranceDelay = 0.0f;
    utterance.postUtteranceDelay = 0.05f;

    utterance.voice = self.speechVoice;

    [self stopListening];
    if (![self configureAudioSessionForPlayback])
        return;
    _activeUtterance = utterance;
    [_synthesizer speakUtterance:utterance];
    NSLog(@"Voice speech started");
    [self.delegate voiceManagerDidStartSpeaking];
}

- (void)stopSpeaking {
    _activeUtterance = nil;
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
        [self.delegate voiceManagerHighlightRange:characterRange inView:view];
    }
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didFinishSpeechUtterance:(AVSpeechUtterance *)utterance {
    if (utterance != _activeUtterance)
        return;
    _activeUtterance = nil;
    _currentUtteranceText = nil;
    _isPaused = NO;
    [self clearHighlight];
    [self deactivateAudioSession];
    NSLog(@"Voice speech finished");
    [self.delegate voiceManagerDidFinishSpeaking];
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didCancelSpeechUtterance:(AVSpeechUtterance *)utterance {
    if (utterance != _activeUtterance)
        return;
    _activeUtterance = nil;
    _currentUtteranceText = nil;
    _isPaused = NO;
    [self clearHighlight];
}

#pragma mark - STT

- (void)requestSTTPermissionsWithCompletion:(void (^)(BOOL granted))completion {
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
    if (!self.sttEnabled || self.isListening)
        return;
    if (![[self class] recognitionLanguageForLanguage:self.speechRecognitionLanguage ?: self.storyLanguage ?: @"en-US"]) {
        [self reportRecordingError:[NSError errorWithDomain:@"FrotzVoice" code:3
                                                  userInfo:@{NSLocalizedDescriptionKey: @"The story language is not supported for speech recognition. Choose a Speech Input Language in Settings."}]];
        return;
    }
    if (![self recordingIsAuthorized] || !_speechRecognizer.isAvailable) {
        [self reportRecordingError:[NSError errorWithDomain:@"FrotzVoice" code:1
                                                  userInfo:@{NSLocalizedDescriptionKey: @"Speech recognition is unavailable. Check microphone and speech permissions in Settings."}]];
        return;
    }

    [self stopListening];
    [self stopSpeaking];
    if (![self configureAudioSessionForRecording])
        return;

    _hasReceivedSpeech = NO;
    _recognitionRequest = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
    _recognitionRequest.shouldReportPartialResults = YES;
    NSArray *controls = [[self class] confirmationWordsForLanguage:self.effectiveRecognitionLanguage];
    if (self.recognizingCharacterInput) {
        _recognitionRequest.contextualStrings = @[];
    } else if (self.recognizingConfirmation) {
        _recognitionRequest.contextualStrings = controls;
    } else {
        _recognitionRequest.contextualStrings = _commandHints ?: @[];
    }
    if (@available(iOS 13.0, *)) {
        if (_speechRecognizer.supportsOnDeviceRecognition)
            _recognitionRequest.requiresOnDeviceRecognition = YES;
    }

    AVAudioInputNode *inputNode = _audioEngine.inputNode;
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
    if (!_synthesizer.isSpeaking)
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
    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    return [session setCategory:AVAudioSessionCategoryPlayback
                   withOptions:AVAudioSessionCategoryOptionDuckOthers error:&error]
        && [session setActive:YES error:&error];
}

- (BOOL)configureAudioSessionForRecording {
    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    BOOL configured = [session setCategory:AVAudioSessionCategoryPlayAndRecord
                              withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker | AVAudioSessionCategoryOptionAllowBluetooth error:&error]
        && [session setActive:YES error:&error];
    if (!configured)
        [self reportRecordingError:error];
    return configured;
}

- (void)deactivateAudioSession {
    [[AVAudioSession sharedInstance] setActive:NO
                                  withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
}

- (void)audioSessionInterrupted:(NSNotification *)notification {
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

#pragma mark - Persistence

- (void)savePreferences {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:self.commandConfirmationEnabled forKey:kCommandConfirmationKey];
    [defaults setInteger:_voiceMode forKey:kVoiceModeKey];
    [defaults setFloat:_speechRate forKey:kSpeechRateKey];
    [defaults setObject:self.speechVoiceIdentifier forKey:kSpeechVoiceKey];
    [defaults setObject:self.speechRecognitionLanguage forKey:kRecognitionLanguageKey];
    [defaults synchronize];
}

- (void)loadPreferences {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.commandConfirmationEnabled = [defaults boolForKey:kCommandConfirmationKey];
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
