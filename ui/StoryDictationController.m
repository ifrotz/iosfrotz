//
//  StoryDictationController.m
//  Frotz
//
//  Created by Craig Smith on 6/19/23.
//

#import "StoryDictationController.h"

#if EnableStoryDictation

#import <AudioToolbox/AudioToolbox.h>
#import <NaturalLanguage/NaturalLanguage.h>


@interface NSString (IFDictation)
-(NSString*)stringWithHyphenatedDashes;
-(NSString*)stringWithSanitizedDictation;
@end

@implementation NSString (IFDictation)
// En and em dashes as hyphens, one character for one so positions in the text still hold (the
// recognizer's confidence ranges are character ranges). Applied before the alternatives are
// scored and corrected, so "s–remover" is the hyphenated word the game knows as "s-remover".
-(NSString*)stringWithHyphenatedDashes {
    NSString *str = [self stringByReplacingOccurrencesOfString:@"–" withString:@"-"];
    return [str stringByReplacingOccurrencesOfString:@"—" withString:@"-"];
}

-(NSString*)stringWithSanitizedDictation {
    // Counterfeit Monkey helper.  Convert en dashes and em dashes to hyphens, remove surrounding spaces, so
    // "Wave x-remover at ..." dictates better.
    NSString *str = [self stringWithHyphenatedDashes];
    str = [str stringByReplacingOccurrencesOfString:@" - " withString:@"-"];
    // The recognizer writes sentences: a capital first word, capitals on whatever it takes for a
    // name. Commands are typed in lower case and parsers ignore case, so the line shows it that
    // way. Done here, after the correction pass, which reads all capitals as a word spelled out.
    return [str lowercaseString];
}
@end

// A transcript segment at or above this confidence (0 to 1, final results only) is taken as
// heard even if the game doesn't know the word; see didFinishRecognition.
static const float kDictationConfidentWord = 0.9f;

// Added to an alternative transcript's score when it begins with a verb; see dictationDictionaryScore:.
static const NSUInteger kDictationVerbFirstBonus = 2;

// The recognizer locale until a story's language says otherwise; see storyLanguage.
static NSString *const kDictationDefaultLocale = @"en-US";

// The recognizer reports its failures as error codes in the assistant domain, with no public
// constants; the table in the error property's comment in SFSpeechRecognitionTask.h lists them.
// 203, "failure occurred during speech recognition", is what a task ends with when the audio it
// was given held nothing it could recognize (a pause with no speech, say); 1110, "failed to
// recognize any speech", is the same outcome by its description. The task is over at that point,
// so the reference is dropped and the commit timer starts a fresh one.
static NSString *const kSpeechAssistantErrorDomain = @"kAFAssistantErrorDomain";
static const NSInteger kSpeechErrorRecognitionFailed = 203;
static const NSInteger kSpeechErrorNoSpeechRecognized = 1110;

static BOOL ErrorEndsRecognitionTask(NSError *error) {
    return (error.code == kSpeechErrorRecognitionFailed || error.code == kSpeechErrorNoSpeechRecognized)
        && [error.domain isEqualToString: kSpeechAssistantErrorDomain];
}

static const NSTimeInterval kDictationDefaultSilenceInterval = 0.8;

// After a command, how long to wait for the reply to be posted as an announcement before taking
// it that none is coming (a key prompt that printed nothing, Speak Screen rather than VoiceOver)
// and reopening the mic; and, once one is posted, the longest to wait for its finish notice. See
// commitTranscription and replyAnnouncementPosted.
static const NSTimeInterval kDictationReplyAnnouncementWait = 1.5;
static const NSTimeInterval kDictationReplyReadingLimit = 60;

// A screen reader that will speak through the device's own speaker while the mic is open:
// VoiceOver, or Spoken Content's Speak Screen or Speak Selection when enabled in Settings (there
// is no way to ask whether they are speaking at this moment, only whether they are turned on).
// Without echo cancellation their speech is transcribed as if the player had said it.
static BOOL ScreenReaderInUse(void) {
    return UIAccessibilityIsVoiceOverRunning() || UIAccessibilityIsSpeakScreenEnabled() || UIAccessibilityIsSpeakSelectionEnabled();
}

// Reads the <language> of an iFiction record's bibliographic section and nothing else; see
// languageFromBlorbAtPath:.
@interface StoryLanguageParser : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) NSMutableArray<NSString*> *elements;
@property (nonatomic, strong) NSMutableString *text;
@property (nonatomic, copy) NSString *language;
@end

@implementation StoryLanguageParser
-(void)parser:(NSXMLParser*)parser didStartElement:(NSString*)element namespaceURI:(NSString*)uri qualifiedName:(NSString*)name attributes:(NSDictionary*)attributes {
    [self.elements addObject: element];
    if ([self.elements isEqualToArray: @[@"ifindex", @"story", @"bibliographic", @"language"]])
        self.text = [NSMutableString string];
}
-(void)parser:(NSXMLParser*)parser foundCharacters:(NSString*)string {
    if (self.text)
        [self.text appendString: string];
}
-(void)parser:(NSXMLParser*)parser didEndElement:(NSString*)element namespaceURI:(NSString*)uri qualifiedName:(NSString*)name {
    if ([element isEqualToString: @"language"] && self.text) {
        if (!self.language)
            self.language = [self.text stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        self.text = nil;
    }
    [self.elements removeLastObject];
}
@end

static uint32_t BlorbWord(const unsigned char *bytes) {
    return ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) | ((uint32_t)bytes[2] << 8) | bytes[3];
}

@implementation StoryDictationController

@synthesize delegate = m_delegate;
@synthesize stateDelegate = m_stateDelegate;
@synthesize silenceInterval = m_silenceInterval;
@synthesize listensWhileScreenReaderSpeaks = m_listensWhileScreenReaderSpeaks;

-(void)notifyStateChanged {
    [m_stateDelegate dictationListeningStateChanged: self];
}

-(StoryDictationAvailability)availability {
    if (!m_sfrecog.isAvailable)
        return kStoryDictationRecognizerUnavailable;
    if (!m_sfrecog.supportsOnDeviceRecognition) // requests here set requiresOnDeviceRecognition
        return kStoryDictationOnDeviceUnsupported;
    return kStoryDictationAvailable;
}

// SFSpeechRecognizerDelegate. The recognizer can go away mid-session (Siri and Dictation turned
// off in Settings, say); a task in flight would just fail, so stop cleanly and say why.
- (void)speechRecognizer:(SFSpeechRecognizer *)speechRecognizer availabilityDidChange:(BOOL)available {
    DictationLog(@"recognizer available: %d", available);
    if (available || !([self isListening] || m_isPaused))
        return;
    [self stopListening];
    [m_stateDelegate dictationBecameUnavailable: self];
}

-(instancetype)init {
    self = [super init];
    if (self) {
        [self createRecognizerForLocale: kDictationDefaultLocale];

        m_audioEngine = [[AVAudioEngine alloc] init];
        m_audioSession = [AVAudioSession sharedInstance];
        m_silenceInterval = kDictationDefaultSilenceInterval;

        // The system can take the audio away or reconfigure it under us; see the handlers below.
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver: self selector: @selector(audioSessionInterrupted:) name: AVAudioSessionInterruptionNotification object: m_audioSession];
        [center addObserver: self selector: @selector(mediaServicesWereReset:) name: AVAudioSessionMediaServicesWereResetNotification object: m_audioSession];
        [center addObserver: self selector: @selector(audioEngineConfigurationChanged:) name: AVAudioEngineConfigurationChangeNotification object: m_audioEngine];
        [center addObserver: self selector: @selector(applicationDidEnterBackground:) name: UIApplicationDidEnterBackgroundNotification object: nil];
        [center addObserver: self selector: @selector(voiceOverStatusChanged:) name: UIAccessibilityVoiceOverStatusDidChangeNotification object: nil];
        [center addObserver: self selector: @selector(announcementDidFinish:) name: UIAccessibilityAnnouncementDidFinishNotification object: nil];
        [center addObserver: self selector: @selector(voiceOverStatusChanged:) name: UIAccessibilitySpeakScreenStatusDidChangeNotification object: nil];
        [center addObserver: self selector: @selector(voiceOverStatusChanged:) name: UIAccessibilitySpeakSelectionStatusDidChangeNotification object: nil];
    }
    return self;
}

// Leaving Frotz for another app ends dictation, like leaving the story for the Story List does:
// the mic shouldn't stay open behind another app, and listening comes back only when the player
// asks for it again. (Posted once every scene is in the background, so a second window on the
// iPad or the Duo keeps listening while it is still up.)
-(void)applicationDidEnterBackground:(NSNotification*)note {
    if ([self isListening] || m_isPaused) {
        DictationLog(@"app went to the background");
        [self stopListening];
    }
}

-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}

#pragma mark - Language

-(void)createRecognizerForLocale:(NSString*)identifier {
    m_sfrecog.delegate = nil;
    m_recognitionLocaleIdentifier = identifier;
    m_sfrecog = [[SFSpeechRecognizer alloc] initWithLocale: [NSLocale localeWithLocaleIdentifier: identifier]];
    m_sfrecog.delegate = self;
}

-(NSString*)storyLanguage {
    return m_storyLanguage;
}

-(void)setStoryLanguage:(NSString*)language {
    m_storyLanguage = [language copy];
    NSString *identifier = ([language length] ? [[self class] recognitionLocaleForLanguage: language] : nil) ?: kDictationDefaultLocale;
    if ([identifier isEqualToString: m_recognitionLocaleIdentifier])
        return;
    DictationLog(@"story language %@: recognizer locale %@ (was %@)", language, identifier, m_recognitionLocaleIdentifier);
    if ([self isListening] || m_isPaused)
        [self stopListening]; // the task in flight belongs to the old recognizer
    [self createRecognizerForLocale: identifier];
}

-(NSString*)recognitionLocaleIdentifier {
    return m_recognitionLocaleIdentifier;
}

-(NSString*)recognitionLanguageName {
    NSString *base = [[m_recognitionLocaleIdentifier componentsSeparatedByCharactersInSet: [NSCharacterSet characterSetWithCharactersInString: @"-_"]] firstObject];
    return [[NSLocale currentLocale] localizedStringForLanguageCode: base] ?: m_recognitionLocaleIdentifier;
}

// The recognizer locale for a language tag: an exact match among the supported locales if there
// is one; else, for a bare language ("fr", which is all text detection gives), the device's own
// regional variant when it is among them ("en" on a British phone is en-GB), else the language's
// home region (fr-FR, de-DE: the variants best supported on device, and alphabetical order
// would give fr-BE and de-AT), else the first supported variant; nil for an unsupported
// language. This is Anand M.'s (anandman on GitHub) matching from his voice-mode branch, with
// the home-region rule added and the device language read from NSLocale.
+(NSString*)recognitionLocaleForLanguage:(NSString*)language {
    NSString *normalized = [[[NSLocale canonicalLanguageIdentifierFromString: language] stringByReplacingOccurrencesOfString: @"_" withString: @"-"] lowercaseString];
    NSString *base = [[normalized componentsSeparatedByString: @"-"] firstObject];
    if (![base length])
        return nil;
    NSArray<NSLocale*> *locales = [[[SFSpeechRecognizer supportedLocales] allObjects] sortedArrayUsingComparator: ^NSComparisonResult(NSLocale *a, NSLocale *b) {
        return [a.localeIdentifier compare: b.localeIdentifier];
    }];
    NSString *deviceLanguage = [[[NSLocale preferredLanguages] firstObject] stringByReplacingOccurrencesOfString: @"_" withString: @"-"];
    NSString *homeRegion = [NSString stringWithFormat: @"%@-%@", base, [base uppercaseString]];
    NSString *deviceMatch = nil, *homeMatch = nil, *firstMatch = nil;
    for (NSLocale *locale in locales) {
        NSString *candidate = [locale.localeIdentifier stringByReplacingOccurrencesOfString: @"_" withString: @"-"];
        if ([[candidate lowercaseString] isEqualToString: normalized])
            return candidate;
        if (![[[[candidate lowercaseString] componentsSeparatedByString: @"-"] firstObject] isEqualToString: base])
            continue;
        if ([candidate isEqualToString: deviceLanguage])
            deviceMatch = candidate;
        else if ([candidate isEqualToString: homeRegion])
            homeMatch = candidate;
        else if (!firstMatch)
            firstMatch = candidate;
    }
    return deviceMatch ?: homeMatch ?: firstMatch;
}

// Walks the Blorb's chunks to the IFmd (iFiction metadata) chunk, if any, and parses it for the
// language. Bounded: a malformed file or an outsized chunk gives nil, never a crash. Only the
// bibliographic language is used; the story's text is never read here. The parser above and
// this walk are Anand M.'s (anandman on GitHub), from his voice-mode branch of Frotz.
+(NSString*)languageFromBlorbAtPath:(NSString*)path {
    NSData *data = [path length] ? [NSData dataWithContentsOfFile: path options: NSDataReadingMappedIfSafe error: nil] : nil;
    if ([data length] < 12)
        return nil;
    const unsigned char *bytes = [data bytes];
    if (memcmp(bytes, "FORM", 4) || memcmp(bytes + 8, "IFRS", 4))
        return nil;
    uint64_t end = (uint64_t)BlorbWord(bytes + 4) + 8;
    if (end > [data length] || end < 12)
        return nil;
    for (uint64_t offset = 12; offset + 8 <= end;) {
        uint32_t size = BlorbWord(bytes + offset + 4);
        uint64_t next = offset + 8 + size + (size & 1);
        if (next > end)
            return nil;
        if (!memcmp(bytes + offset, "IFmd", 4)) {
            if (size > 1024 * 1024)
                return nil;
            NSXMLParser *parser = [[NSXMLParser alloc] initWithData: [data subdataWithRange: NSMakeRange((NSUInteger)offset + 8, size)]];
            StoryLanguageParser *reader = [StoryLanguageParser new];
            reader.elements = [NSMutableArray array];
            parser.delegate = reader;
            parser.shouldProcessNamespaces = YES;
            parser.shouldResolveExternalEntities = NO;
            if (![parser parse])
                return nil;
            NSString *language = reader.language;
            NSRange valid = [language rangeOfString: @"^[A-Za-z]{2,3}(-[A-Za-z]{2})?$" options: NSRegularExpressionSearch];
            return [language length] && valid.location != NSNotFound ? language : nil;
        }
        offset = next;
    }
    return nil;
}

// On-device language identification of the text. The judgement is only trusted on a fair amount
// of text and when the recognizer is fairly sure: a short banner, or one with an English
// copyright line under a French title, must not set the language. The most recent text is used,
// since the top of a transcript is the interpreter's banner.
static const NSUInteger kLanguageDetectionMinimumLength = 200;
static const NSUInteger kLanguageDetectionSampleLength = 4000;
static const double kLanguageDetectionMinimumConfidence = 0.6;

+(NSString*)languageOfText:(NSString*)text {
    if ([text length] < kLanguageDetectionMinimumLength)
        return nil;
    NSString *sample = [text length] > kLanguageDetectionSampleLength ? [text substringFromIndex: [text length] - kLanguageDetectionSampleLength] : text;
    NLLanguageRecognizer *recognizer = [[NLLanguageRecognizer alloc] init];
    [recognizer processString: sample];
    NSDictionary<NLLanguage, NSNumber*> *hypotheses = [recognizer languageHypothesesWithMaximum: 1];
    NLLanguage best = [[hypotheses allKeys] firstObject];
    DictationLog(@"text language %@ (%.2f) from %lu chars", best, [hypotheses[best] doubleValue], (unsigned long)[sample length]);
    if (!best || [hypotheses[best] doubleValue] < kLanguageDetectionMinimumConfidence)
        return nil;
    return best;
}

// The system took the audio away (Speak Screen, VoiceOver, a phone call, Siri) and stopped the
// engine, which nothing here would otherwise notice: no hypotheses arrive and the mic icon stays
// lit. Listening is over as far as the user can tell, so make it so: drop the utterance in flight
// and report "not listening", so the icon goes dark and a tap starts dictation again. If the
// system later says the interruption has ended and audio may resume, start again by ourselves,
// unless the user has restarted or stopped dictation meanwhile. That notice is not guaranteed
// (system speech in particular may never send it), which is why the state can't wait for it.
// A pause the UI already made (isListening false) is left to the UI to end.
-(void)audioSessionInterrupted:(NSNotification*)note {
    NSDictionary *info = note.userInfo;
    dispatch_async(dispatch_get_main_queue(), ^{
        AVAudioSessionInterruptionType type = [info[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
        if (type == AVAudioSessionInterruptionTypeBegan) {
            if (![self isListening])
                return;
            DictationLog(@"audio interrupted");
            [self abandonUtterance];
            [m_audioEngine stop];
            m_resumeAfterInterruption = YES;
            [self notifyStateChanged];
        } else if (m_resumeAfterInterruption) {
            m_resumeAfterInterruption = NO;
            AVAudioSessionInterruptionOptions options = [info[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue];
            BOOL resume = (options & AVAudioSessionInterruptionOptionShouldResume) != 0;
            DictationLog(@"audio interruption ended, resume %d", resume);
            if (resume)
                [self listenForSpeech];
        }
    });
}

// The engine stopped itself because the audio route or format changed (headphones in or out, a
// Bluetooth device, VoiceOver claiming the speaker). The tap was installed for the old input
// format and must be put back for the new one, so drop the utterance and restart from scratch;
// if listening was paused, stay paused and let the resume do the reinstalling.
-(void)audioEngineConfigurationChanged:(NSNotification*)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        DictationLog(@"audio engine configuration changed");
        [self restartAudioForChangedConfiguration];
    });
}

// Whether a screen reader is in use decides whether voice processing is wanted (see
// startListening), so a change while dictation is on means tearing the engine down and setting
// it up again the other way. VoiceOver, Speak Screen and Speak Selection all come here.
// VoiceOver has finished reading an announcement, or the player silenced it (a two-finger tap,
// the usual way to interrupt VoiceOver, which is how a reply is spoken over when the mic is
// closed for it): the story's reply, if the mic was closed for it (see commitTranscription).
// Listening starts again now rather than at the reading limit.
-(void)announcementDidFinish:(NSNotification*)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!m_quietForReply || m_isPaused)
            return;
        // A reply read in several announcements reopens the mic after the last; an interruption
        // cuts the whole queue short, so an unsuccessful finish reopens it at once.
        BOOL completed = [note.userInfo[UIAccessibilityAnnouncementKeyWasSuccessful] boolValue];
        if (m_replyAnnouncementsPending > 0)
            m_replyAnnouncementsPending--;
        if (completed && m_replyAnnouncementsPending > 0)
            return;
        DictationLog(@"reading finished (completed %d); mic reopens", completed);
        [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(listenForSpeech) object: nil];
        m_reopenedAfterReadingAt = [NSDate timeIntervalSinceReferenceDate];
        [self listenForSpeech];
        if ([self isListening])
            [m_stateDelegate dictationReopenedAfterReading: self];
    });
}

-(void)voiceOverStatusChanged:(NSNotification*)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        // VoiceOver going off during a reading hold: its finish notice will never come, so the
        // mic reopens now.
        if (m_quietForReply && !UIAccessibilityIsVoiceOverRunning()) {
            DictationLog(@"VoiceOver off during a reading hold; mic reopens");
            [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(listenForSpeech) object: nil];
            [self listenForSpeech];
            return;
        }
        // Only if the change would alter voice processing. Usually it wouldn't: dictation started
        // with nothing else playing already has it on (see startAudioEngineWithVoiceProcessing:),
        // and the restart would be nothing but a needless tear-down and rebuild of the engine
        // under VoiceOver's own "VoiceOver on". (It was suspected of the crackle in VoiceOver's
        // speech; that proved to be VoiceOver's ducking, see commitTranscription.) A paused
        // engine is left to the resume, which sets everything up afresh anyway.
        BOOL wantVoiceProcessing = ScreenReaderInUse() || !m_audioSession.isOtherAudioPlaying;
        BOOL haveVoiceProcessing = [m_audioEngine inputNode].isVoiceProcessingEnabled;
        DictationLog(@"screen reader: %d; voice processing wanted %d, have %d", ScreenReaderInUse(), wantVoiceProcessing, haveVoiceProcessing);
        if (m_isPaused || ![m_audioEngine isRunning] || wantVoiceProcessing == haveVoiceProcessing)
            return;
        [self restartAudioForChangedConfiguration];
    });
}

// Drops the utterance and sets the engine up again from scratch (startListening reinstalls the
// tap, and decides voice processing afresh). Paused dictation stays paused; the resume does it.
//
// The engine is replaced rather than reused, and the audio session is left active throughout.
// Toggling voice processing on an engine that has already run is what Apple warns against, and
// doing it when VoiceOver came on mid-dictation left VoiceOver's speech choppy with pops behind
// it, where starting dictation with VoiceOver already on (a fresh engine, processing set before
// its first start) was clean; a new engine makes the two paths the same. Keeping the session
// active spares VoiceOver, which is speaking "VoiceOver on" at that moment, the interruption a
// deactivate-and-reactivate would be.
-(void)restartAudioForChangedConfiguration {
    BOOL wasListening = m_sfRecogRequest != nil && !m_isPaused; // not isListening: the engine may already have stopped
    if (!wasListening && !m_isPaused)
        return;
    [self abandonUtterance];
    [self cancelLongIdleTimer];
    [self rebuildAudioEngine];
    if (wasListening)
        [self listenForSpeech]; // the same full setup a fresh start gets; the session is already active
}

-(void)stopListening {
    DictationLog(@"stopListening (held for reply %d)", m_quietForReply);
    // Task, request, transcript and the input line's utterance state go together, as for a pause:
    // partial text already shown stays on the line as typed text, so the next utterance adds to it
    // instead of replacing it or submitting it.
    [self abandonUtterance];
    [self cancelLongIdleTimer];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(listenForSpeech) object:nil];
    m_quietForReply = NO;

    m_isPaused = NO;
    m_resumeAfterInterruption = NO;
    [self releaseAudio];
    [self notifyStateChanged];
}

// Stops the engine, removes the tap and gives the audio system back: the mic indicator goes off,
// and other apps are told they may resume anything the session's activation had interrupted.
// Shared by stopping and pausing, so that the two leave the audio in the same state and the next
// start, from either, is the same full setup (see startListening). An engine merely paused, or
// stopped with the session left active, was resumed with a bare restart, and after one such
// resume the stop cue came out loud and thunking on every pause until a full stop and start.
// Failure to deactivate is only worth a log.
-(void)releaseAudio {
    [m_audioEngine stop];
    [[m_audioEngine inputNode] removeTapOnBus: 0];
    m_tapInstalled = NO;
    NSError *error = nil;
    if (![m_audioSession setActive: NO withOptions: AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error: &error])
        NSLog(@"Error AVAudioSession setActive:NO: %@", error);
}

// Called when the task first detects speech in the source audio
- (void)speechRecognitionDidDetectSpeech:(SFSpeechRecognitionTask *)task {
    DictationLog(@"task detected speech");
}

// Called for all recognitions, including non-final hypothesis
- (void)speechRecognitionTask:(SFSpeechRecognitionTask *)task didHypothesizeTranscription:(SFTranscription *)transcription {
    if (task != m_recognitionTask)
        return; // a task listenForSpeech has already replaced; see didFinishSuccessfully
    NSString *text = [[transcription formattedString] stringWithSanitizedDictation]; // as the final will be shown
    DictationLog(@"speechRecognitionTask:didHypothesizeTranscription: %@", text);
    if (![text isEqualToString: m_currentTranscription]) {
        m_currentTranscription = text;
        if (m_delegate && text.length > 0)
            [m_delegate acceptDictation: text final: NO];
    }
    // Every hypothesis, changed or not, means speech is still coming in.
    [self restartSilenceTimer];
    [self restartLongIdleTimer];
}

-(NSUInteger)dictationDictionaryScore:(NSString *)text {
    NSUInteger score = 0;
    NSMutableCharacterSet *separatorSet = [NSMutableCharacterSet whitespaceAndNewlineCharacterSet];
    [separatorSet formUnionWithCharacterSet: [NSCharacterSet punctuationCharacterSet]];
    // Apostrophes and hyphens are inside words. Splitting "s-remover" made it two words, and the
    // fewer-words term below then preferred the alternative "remover" alone, dropping the "s-".
    [separatorSet removeCharactersInString: @"'-"];
    // "S - remover" is shown as "s-remover" (stringWithSanitizedDictation), so it is scored as one word.
    NSString *joined = [text stringByReplacingOccurrencesOfString: @" - " withString: @"-"];
    // Quoted phrases aren't scored, so the recognizer's first choice stands; see dictationCorrectedText:.
    joined = [joined stringByReplacingOccurrencesOfString: @"[\"“„«][^\"”»]*([\"”»]|$)" withString: @" "
                                                  options: NSRegularExpressionSearch range: NSMakeRange(0, [joined length])];
    NSArray *words = [[joined componentsSeparatedByCharactersInSet:separatorSet]
                      filteredArrayUsingPredicate: [NSPredicate predicateWithFormat: @"length > 0"]];
    int i = 0;
    NSUInteger count = [words count];
    NSUInteger wordCountScore = count >= 10 ? 0 : 10 - count;
    score += wordCountScore;
    for (NSString *word in words) {
        if ([word length] > 2) {
            if ([m_delegate validateWord:word]) {
                DictationLog(@"  validated: %@", word);
                score++;
            }
            i++;
        }
    }
    // A command begins with a verb: among alternatives that differ by a sound ("book" for "look"),
    // the one that does wins. Worth more than one known word, so it outweighs a printed noun.
    // Counted for each command when several are chained ("take lamp then look").
    score += kDictationVerbFirstBonus * [m_delegate dictationCommandsStartingWithVerb: text];
    return score;
}

// Called only for final recognitions of utterances. No more about the utterance will be reported
- (void)speechRecognitionTask:(SFSpeechRecognitionTask *)task didFinishRecognition:(SFSpeechRecognitionResult *)result {
    if (task != m_recognitionTask)
        return; // a task listenForSpeech has already replaced; see didFinishSuccessfully
    BOOL isFinal = [result isFinal];
    DictationLog(@"speechRecognitionTask:didFinishRecognition final=%d", isFinal);
    NSArray<SFTranscription *> *transcriptions = [result transcriptions];
    int i = 0, bestIndex = -1;
    NSUInteger bestScore = 0;
    BOOL wantKey = [m_delegate dictationExpectsSingleKey];
    //SFTranscription *transcription = [result bestTranscription];
    for (SFTranscription *transcription in transcriptions) {
        NSString *text = [[transcription formattedString] stringWithHyphenatedDashes];
        if (wantKey) {
            // A key prompt: the recognizer's first choice for a spoken letter is often a common
            // word ("in" for N, "you" for Q), with the letter itself further down its list. The
            // alternative that names a key most directly wins, a bare letter over a word for one,
            // the earlier of equals; the game's dictionary is no guide here.
            NSUInteger score = [m_delegate dictationKeyScore: text];
            DictationLog(@"  Count: %d Key score: %lu Recog: %@", i, (unsigned long)score, text);
            if (score > bestScore) {
                bestScore = score;
                bestIndex = i;
            }
            ++i;
            continue;
        }
        NSUInteger score = [self dictationDictionaryScore: text];
        DictationLog(@"  Count: %d Score: %lu Recog: %@", i, score, text);
        if (score > bestScore) {
            bestScore = score;
            bestIndex = i;
        }
        ++i;
    }
    SFTranscription *transcription;
    if (bestIndex >= 0)
        transcription = transcriptions[bestIndex];
    else
        transcription = [result bestTranscription];
    NSString *text = [[transcription formattedString] stringWithHyphenatedDashes];
    if (isFinal && !wantKey) {
        // Words the game won't know, swapped for near matches it will (see dictationCorrectedText:
        // in InputHelper.h). Final results only: a partial is still changing, and only a final
        // result carries per-word confidence; words the recognizer was sure of are left as heard,
        // since a careful speaker saying a verb the game lacks is better told so by the parser.
        NSMutableIndexSet *confident = [NSMutableIndexSet indexSet];
        for (SFTranscriptionSegment *segment in [transcription segments]) {
            DictationLog(@"  segment \"%@\" confidence %.2f", [segment substring], [segment confidence]);
            if ([segment confidence] >= kDictationConfidentWord)
                [confident addIndexesInRange: [segment substringRange]];
        }
        NSString *corrected = [m_delegate dictationCorrectedText: text confidentRanges: confident];
        if (corrected && ![corrected isEqualToString: text]) {
            DictationLog(@"corrected \"%@\" to \"%@\"", text, corrected);
            text = corrected;
        }
    }
    DictationLog(@"Final: %d Recog: %@", isFinal, text);
    m_currentTranscription = [text stringWithSanitizedDictation];

    NSError *error = [task error];
    if (error)
        NSLog(@"recognitionTaskWithRequest error: %@", error);
    if (isFinal || ErrorEndsRecognitionTask(error))
        [self commitTranscription]; // the task is over; this is the utterance
    else
        [self restartSilenceTimer];
}

// Called when the task is no longer accepting new audio but may be finishing final processing
- (void)speechRecognitionTaskFinishedReadingAudio:(SFSpeechRecognitionTask *)task {
    DictationLog(@"Task finished audio");
}

// Called when the task has been cancelled, either by client app, the user, or the system
- (void)speechRecognitionTaskWasCancelled:(SFSpeechRecognitionTask *)task {
    DictationLog(@"Task canceled");
}

// Called when recognition of all requested utterances is finished.
// If successfully is false, the error property of the task will contain error information
- (void)speechRecognitionTask:(SFSpeechRecognitionTask *)task didFinishSuccessfully:(BOOL)successfully {
    // These callbacks arrive asynchronously, so one from a task that listenForSpeech has since
    // finished and replaced can land after the new task is running. Only the current task may
    // report results or clear m_recognitionTask; otherwise the new task's results were lost and
    // the commit timer took the cleared task as the signal to accept whatever text it had.
    if (task != m_recognitionTask)
        return;
    // Normally didFinishRecognition has already committed and cleared the task, and the guard
    // above skips this. It matters when the task ends without a final result: with nothing
    // heard, say, which commitTranscription treats as an empty utterance and listens again.
    BOOL taskEnded = successfully;
    if (!successfully) {
        NSError *error = [task error];
        if (error)
            NSLog(@"speechRecognitionTask:didFinishSuccessfully error: %@", error);
        taskEnded = ErrorEndsRecognitionTask(error);
    }
    if (taskEnded)
        [self commitTranscription];
    else if ([self isListening])
        [self restartSilenceTimer];
}

-(BOOL)isListening {
    return (m_sfRecogRequest != nil && [m_audioEngine isRunning]) || m_quietForReply;
}

-(BOOL)isPaused {
    return m_isPaused;
}

-(BOOL)willResume {
    return m_isPaused || m_resumeAfterInterruption;
}

// Drops the utterance in progress without committing it: the silence timer, task, request and
// text all go, and the delegate is told so that the next words follow what is already shown
// rather than replacing it. The task is dropped before it is cancelled so its cancellation
// callback is ignored as stale.
-(void)abandonUtterance {
    [m_speechCommitTimer invalidate];
    m_speechCommitTimer = nil;
    SFSpeechRecognitionTask *task = m_recognitionTask;
    m_recognitionTask = nil;
    [m_sfRecogRequest endAudio];
    m_sfRecogRequest = nil;
    [task cancel];
    m_currentTranscription = nil;
    [m_delegate abandonDictation];
}

// A pause is an interruption (the notes page or the file chooser came up), not the end of a
// command, so an utterance in progress is abandoned rather than committed: otherwise the silence
// that follows would commit "put the brass lantern" as a command while the player was elsewhere.
// The partial text already shown stays in the input line to be finished or cleared on return.
-(void)pauseListening {
    [self abandonUtterance];
    [self cancelLongIdleTimer]; // nothing can be heard while paused; the clock restarts with the resume
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(listenForSpeech) object:nil]; // a reopening after a reply
    m_quietForReply = NO;
    // The audio is released exactly as a stop releases it (see releaseAudio); only the dictation
    // state differs, so that the UI's resume brings listening back without the player asking.
    [self releaseAudio];
    m_isPaused = YES;
    DictationLog(@"pauseListening");
    [self notifyStateChanged];
}

// Starts (or, when paused, resumes) listening. Every way out reports the resulting state to the
// state delegate, since the audio engine may refuse to start and leave nothing listening.
-(void)listenForSpeech {
    [self startListening];
    // The idle clock starts only when none is running: a start or resume (stop and pause cancel
    // it), or the reopening after a reply. A task that ended with nothing heard also comes through
    // here, and must not reset it, or tasks ending that way every minute would keep the mic open
    // for ever. Speech itself restarts it, per hypothesis.
    if ([self isListening] && !m_longIdleTimer)
        [self restartLongIdleTimer];
    [self notifyStateChanged];
}

// The mic doesn't stay open indefinitely: with no speech heard for this long, dictation switches
// itself off (mic icon and all), as if the player had tapped it. Reading, or a break, shouldn't
// leave the recording indicator lit and the battery draining. Each hypothesis restarts the clock.
static const NSTimeInterval kDictationLongIdleTimeout = 90;

-(void)restartLongIdleTimer {
    [m_longIdleTimer invalidate];
    __weak StoryDictationController *weakSelf = self;
    m_longIdleTimer = [NSTimer scheduledTimerWithTimeInterval: kDictationLongIdleTimeout repeats: NO block: ^(NSTimer *timer) {
        [weakSelf longIdleTimerFired];
    }];
}

-(void)cancelLongIdleTimer {
    [m_longIdleTimer invalidate];
    m_longIdleTimer = nil;
}

-(void)longIdleTimerFired {
    m_longIdleTimer = nil;
    DictationLog(@"idle for %.0fs, stopping", kDictationLongIdleTimeout);
    [self stopListening];
}

// The system's audio daemon was restarted (it happens after a long idle, under memory pressure,
// or when it crashes). Every audio object from before is dead: the engine can't be started again,
// its input node reports no format, and installing a tap throws. Apple's instruction is to
// recreate them, so the engine is rebuilt here; listening, if it was on, is over, and the mic
// button shows it. Without this a tap on the mic failed silently from then until the app was
// relaunched.
-(void)mediaServicesWereReset:(NSNotification*)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL wasOn = [self isListening] || m_isPaused;
        NSLog(@"Media services were reset; rebuilding the dictation audio engine");
        [self stopListening];
        [self rebuildAudioEngine];
        if (wasOn)
            [m_stateDelegate dictationBecameUnavailable: self];
    });
}

// A fresh engine in place of one that can't be started. The configuration-change observer is
// bound to the engine object, so it moves to the new one.
-(void)rebuildAudioEngine {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver: self name: AVAudioEngineConfigurationChangeNotification object: m_audioEngine];
    [m_audioEngine stop];
    m_audioEngine = [[AVAudioEngine alloc] init];
    m_tapInstalled = NO;
    [center addObserver: self selector: @selector(audioEngineConfigurationChanged:) name: AVAudioEngineConfigurationChangeNotification object: m_audioEngine];
}

// Sets up the input node and starts the engine, with the tap installed for the node's current
// format. Returns whether the engine is running with the tap in place; every failure is logged
// and returns NO rather than leaving a half-started engine for a task to wait on in silence.
-(BOOL)startAudioEngineWithVoiceProcessing:(BOOL)wantVoiceProcessing {
    NSError *error = nil;
    AVAudioInputNode *audioInputNode = [m_audioEngine inputNode];
    // Voice processing: echo cancellation against the device's own speaker output, plus noise
    // suppression and gain control, the same treatment FaceTime's microphone gets. Without the
    // echo cancellation VoiceOver's speech is picked up and transcribed as if the player had said
    // it, "VoiceOver on" included, and feeds back on every announcement after; the suppression
    // helps anyone dictating somewhere noisy. But the voice-processing unit interrupts other
    // apps' audio when it starts, whatever the session's mixing options say (measured: the
    // options took, the music still paused when the engine started), so it is a choice between
    // it and the player's music. Taken when VoiceOver is on, which needs it, or when nothing
    // else is playing, where it costs nothing; a VoiceOver change restarts the engine to redo
    // it. It has to be set while the engine is stopped, it needs the output node in the graph,
    // and it changes the input format, so the tap's format is read after it. Dictation still
    // works without it if enabling fails.
    DictationLog(@"voice processing %s (screen reader %d, other audio now %d, was enabled %d)", wantVoiceProcessing ? "on" : "off",
                 ScreenReaderInUse(), m_audioSession.isOtherAudioPlaying, audioInputNode.isVoiceProcessingEnabled);
    // The voice-processing unit is full duplex: besides capturing it renders the engine's output
    // every cycle, pulling from the output node, and with nothing connected to that node the
    // pull fails, which the unit logs as "auou/vpio/appl, render err: -1" on every cycle (no
    // audible effect was found; VoiceOver's crackle turned out to be its own ducking of this
    // session, see commitTranscription). Asking for the main mixer creates it connected to the
    // output node, so the output render has a (silent) source and the log stays quiet. Frotz
    // plays nothing through the engine, hence the volume.
    AVAudioMixerNode *mixer = [m_audioEngine mainMixerNode];
    mixer.outputVolume = 0;
    if (audioInputNode.isVoiceProcessingEnabled != wantVoiceProcessing) {
        if (![audioInputNode setVoiceProcessingEnabled: wantVoiceProcessing error: &error]) {
            NSLog(@"Error %s voice processing on the audio input: %@", wantVoiceProcessing ? "enabling" : "disabling", error);
            error = nil;
        }
    }
    // While voice processing runs it also ducks any other audio that does start. iOS 17 lets the
    // ducking be set to the shallowest level, and that is all that is asked: a steady slight dip,
    // so VoiceOver stays audible. "Advanced" ducking, which ducks only while the unit hears local
    // speech, was tried and made VoiceOver choppy: the echo canceller never removes all of
    // VoiceOver's own voice from the mic, so the unit took the remainder for speech and ducked
    // VoiceOver in and out in time with itself. (VoiceOver's crackle turned out to be VoiceOver's
    // own ducking of us, not this; see commitTranscription.)
    if (wantVoiceProcessing) {
        if (@available(iOS 17.0, *)) {
            AVAudioVoiceProcessingOtherAudioDuckingConfiguration ducking = { .enableAdvancedDucking = NO, .duckingLevel = AVAudioVoiceProcessingOtherAudioDuckingLevelMin };
            audioInputNode.voiceProcessingOtherAudioDuckingConfiguration = ducking;
        }
    }
    AVAudioFormat *recordingFormat = [audioInputNode outputFormatForBus: 0];
    [audioInputNode removeTapOnBus:0];
    m_tapInstalled = NO;
    // A node with no usable format is the sign of a dead engine (see mediaServicesWereReset:);
    // installing a tap for it throws, so it is checked first and the @try is the backstop.
    if (recordingFormat.sampleRate <= 0 || recordingFormat.channelCount == 0) {
        NSLog(@"Audio input has no usable format (%@); the engine can't be started", recordingFormat);
        return NO;
    }
    @try {
        [audioInputNode installTapOnBus:0 bufferSize:1024 format:recordingFormat block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
            if (m_sfRecogRequest)
                [m_sfRecogRequest appendAudioPCMBuffer: buffer];
        }];
        m_tapInstalled = YES;
        [m_audioEngine prepare];
        if (![m_audioEngine startAndReturnError: &error]) {
            NSLog(@"Error audioEngine:startAndReturnError: %@", error);
            return NO;
        }
    }
    @catch (NSException *exception) {
        NSLog(@"Exception starting the audio engine: %@", exception);
        return NO;
    }
    return [m_audioEngine isRunning];
}

-(void)startListening {
    NSError *error = nil;
    m_quietForReply = NO; // whether this is the reopening after a reply or any other start
    // Read before the session is touched below: whether someone else is playing decides voice
    // processing, and the answer must not be coloured by our own activation.
    BOOL otherAudioPlaying = m_audioSession.isOtherAudioPlaying;
    m_resumeAfterInterruption = NO; // the user (or the UI) is starting it; the interruption's end needn't
    // A resume from a pause is a start like any other: the pause released the audio (releaseAudio),
    // so the full setup below runs. Nothing is restarted in place.
    if (m_isPaused) {
        DictationLog(@"listenForSpeech resuming from pause");
        m_isPaused = NO;
    }
    // Cancel the previous task if it's running.
    if (m_recognitionTask) {
        [m_recognitionTask finish];
        m_recognitionTask = nil;
        m_sfRecogRequest = nil;
    }
    // The tap must match the input node's current format, so it is (re)installed whenever the
    // engine is down or a configuration change has removed it, with the engine stopped meanwhile.
    // The session is configured here too, and only here: this method also runs after every
    // committed command to start the next task, and reconfiguring and reactivating a live session
    // each time is wasted work at best (and was a suspect for the player's music pausing).
    if (![m_audioEngine isRunning] || !m_tapInstalled) {
        if ([m_audioEngine isRunning])
            [m_audioEngine stop];

        // The session must be a recording session before the engine is touched. Voice processing
        // (below) routes output to the earpiece unless told otherwise, which would make VoiceOver
        // and the story's sounds go quiet, hence DefaultToSpeaker. Play-and-record ignores
        // Bluetooth headsets unless asked: the hands-free option admits a headset's own mic (and
        // sends output to it), the A2DP option lets output use the music profile while the phone's
        // mic records, and with both iOS picks what the headset supports. Wired headphones need
        // no asking. MixWithOthers keeps the player's music or podcast going: Frotz plays nothing
        // itself, so there is no reason to silence anyone. Record-only can't mix, nor host voice
        // processing, which is why the category is play-and-record at all.
        // The mode stays Default: voice-chat mode, with and without mixing, was tried for the
        // voice-processing unit's sake and changed nothing, and it would force Bluetooth headsets
        // onto the hands-free profile.
        BOOL wantVoiceProcessing = ScreenReaderInUse() || !otherAudioPlaying;
        [m_audioSession setCategory: AVAudioSessionCategoryPlayAndRecord mode: AVAudioSessionModeDefault
                             options: AVAudioSessionCategoryOptionDefaultToSpeaker | AVAudioSessionCategoryOptionAllowBluetoothHFP
                                    | AVAudioSessionCategoryOptionAllowBluetoothA2DP | AVAudioSessionCategoryOptionMixWithOthers
                               error: &error];
        if (error) {
            NSLog(@"Error AVAudioSession setCategory: %@", error);
            error = nil;
        }
        // iOS mutes haptics and system sounds while the mic is live unless told otherwise, and the
        // started and resumed cues (StoryDictationCuePlayer) play once the engine is running.
        if (![m_audioSession setAllowHapticsAndSystemSoundsDuringRecording: YES error: &error]) {
            NSLog(@"Error AVAudioSession setAllowHapticsAndSystemSoundsDuringRecording: %@", error);
            error = nil;
        }
        [m_audioSession setActive: YES error: &error];
        if (error) {
            NSLog(@"Error AVAudioSession setActive: %@", error);
            error = nil;
        }
        DictationLog(@"audio session: category %@, mode %@, options 0x%lx, rate %.0f, IO buffer %.1f ms, other audio playing %d, route %@",
                     m_audioSession.category, m_audioSession.mode, (unsigned long)m_audioSession.categoryOptions,
                     m_audioSession.sampleRate, m_audioSession.IOBufferDuration * 1000,
                     m_audioSession.isOtherAudioPlaying, m_audioSession.currentRoute);

        // If the engine won't start, it is most likely dead from a media services reset that
        // went unannounced (the notification isn't guaranteed), so it is rebuilt and tried once
        // more; the mic button shouldn't fail silently in any case, hence the delegate call. No
        // task is started against an engine that isn't running: it would wait forever for audio.
        if (![self startAudioEngineWithVoiceProcessing: wantVoiceProcessing]) {
            NSLog(@"The dictation audio engine failed to start; rebuilding it and trying again");
            [self rebuildAudioEngine];
            if (![self startAudioEngineWithVoiceProcessing: wantVoiceProcessing]) {
                [self stopListening];
                [m_stateDelegate dictationFailedToStart: self];
                return;
            }
        }
    }

    m_sfRecogRequest = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
    m_sfRecogRequest.shouldReportPartialResults = YES;
    m_sfRecogRequest.requiresOnDeviceRecognition = YES;
    if ([m_delegate dictationExpectsSingleKey]) {
        // A key prompt: the player will say a letter's name, "yes" or "no", or a key's name. Left
        // to itself the recognizer hears common words instead ("in" for N, "the" for P), so the
        // letters and key words are offered as context, and the task is told to expect a short
        // confirmation-style reply. Decided per task, so a prompt that arrives mid-task is
        // primed from the next utterance on.
        m_sfRecogRequest.contextualStrings = [self singleKeyContextualStrings];
        m_sfRecogRequest.taskHint = SFSpeechRecognitionTaskHintConfirmation;
    } else {
        // A command: favour the words of the story on screen, the player's recent commands and
        // the form's ordinary verbs (see dictationContextWords in InputHelper.h).
        m_sfRecogRequest.contextualStrings = [m_delegate dictationContextWords] ?: @[];
    }
    m_recognitionTask = [m_sfrecog recognitionTaskWithRequest: m_sfRecogRequest delegate: self];
    DictationLog(@"recognition task started, other audio playing %d", m_audioSession.isOtherAudioPlaying);
}

// An utterance ends when the recognizer has sent no hypothesis for silenceInterval. Each
// hypothesis restarts the timer, so it only ever fires once, after the speaker has stopped.
// The letters A to Z, the digits, and the words KeyForSpokenText (StoryInputLine) understands.
-(NSArray<NSString*>*)singleKeyContextualStrings {
    static NSArray<NSString*> *strings;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *s = [NSMutableArray arrayWithCapacity: 60];
        for (unichar c = 'A'; c <= 'Z'; c++)
            [s addObject: [NSString stringWithCharacters: &c length: 1]];
        for (unichar c = '0'; c <= '9'; c++)
            [s addObject: [NSString stringWithCharacters: &c length: 1]];
        [s addObjectsFromArray: @[ @"yes", @"no", @"space", @"continue", @"more", @"any key", @"enter", @"return",
                                   @"escape", @"cancel", @"backspace", @"delete", @"up", @"down", @"left", @"right" ]];
        strings = s;
    });
    return strings;
}

-(void)deferCommit {
    if (m_speechCommitTimer) {
        DictationLog(@"commit deferred");
        [self restartSilenceTimer];
    }
}

// At a key prompt the utterance is one word, or "the letter" and one, so the quiet time before it
// is taken as finished can be much shorter than the Settings value meant for whole commands: long
// enough for the recognizer to settle on a letter and for the gap between words, no longer.
static const NSTimeInterval kDictationKeySilenceInterval = 0.4;

-(void)restartSilenceTimer {
    [m_speechCommitTimer invalidate];
    NSTimeInterval interval = [m_delegate dictationExpectsSingleKey] ? MIN(kDictationKeySilenceInterval, m_silenceInterval) : m_silenceInterval;
    __weak StoryDictationController *weakSelf = self;
    m_speechCommitTimer = [NSTimer scheduledTimerWithTimeInterval: interval repeats: NO block: ^(NSTimer *timer) {
        [weakSelf silenceTimerFired];
    }];
}

// The speaker has paused. Ask the task to finish; its final result comes back through
// didFinishRecognition, which commits. A task that is already winding down (or gone) has no
// final result coming, so commit what there is.
-(void)silenceTimerFired {
    m_speechCommitTimer = nil;
    DictationLog(@"silence: ct:%@", m_currentTranscription);
    if (m_recognitionTask && m_recognitionTask.state <= SFSpeechRecognitionTaskStateRunning) {
        DictationLog(@" calling recognitionTask finish");
        [m_recognitionTask finish];
        return;
    }
    [self commitTranscription];
}

// Hands the utterance to the delegate as a command (if there was one) and starts listening for
// the next; the current task, if any, is done with.
-(void)commitTranscription {
    [m_speechCommitTimer invalidate];
    m_speechCommitTimer = nil;
    m_recognitionTask = nil;
    DictationLog(@"Final transcript: %@", m_currentTranscription);
    BOOL heardSomething = [m_currentTranscription length] > 0;
    if (m_delegate && heardSomething)
        [m_delegate acceptDictation: m_currentTranscription final:YES];
    m_currentTranscription = nil;
    // Not while paused: the pause stops the hypotheses, so the silence timer fires soon after
    // and lands here, and listening again would undo the pause behind the UI's back. The
    // resume (listenForSpeech with m_isPaused set) finds no task and starts a fresh one.
    if (m_isPaused)
        return;
    // Nothing heard (the task ended on its own, or the silence timer fired on an empty utterance):
    // no command went in, so no reply is coming to hold for, and the idle clock keeps running.
    if (!heardSomething) {
        [self performSelector: @selector(listenForSpeech) withObject: nil afterDelay: 0];
        return;
    }
    // With a screen reader on, and unless asked to listen through it (listensWhileScreenReaderSpeaks),
    // the mic closes completely, engine and session as a stop would, while the reply is read, and
    // reopens when the reading ends (announcementDidFinish:), or soon if no reading is posted
    // (replyAnnouncementPosted). VoiceOver ducks other audio while it speaks and an active
    // play-and-record session counts, even one playing silence; the ducking ramp racing the start
    // of VoiceOver's speech leaves whole utterances loud and crackling, at random, until
    // VoiceOver next falls silent (confirmed by the crackle vanishing with VoiceOver's Audio
    // Ducking turned off). Nothing else about the engine, session or recognizer mattered. The
    // UI isn't told: the player is still, as far as they are concerned, dictating.
    // VoiceOver specifically, not ScreenReaderInUse(): the reading is a VoiceOver announcement and
    // only VoiceOver sends the finish notice that reopens the mic. With Speak Screen enabled but
    // VoiceOver off, the hold waited the whole reading limit for a notice that never came, and
    // dictation seemed to stop after every command.
    if (UIAccessibilityIsVoiceOverRunning() && !m_listensWhileScreenReaderSpeaks) {
        [self releaseAudio];
        [self cancelLongIdleTimer]; // nothing can be heard during the hold; the clock restarts with the reopening
        m_quietForReply = YES;
        m_replyAnnouncementsPending = 0;
        [self performSelector: @selector(listenForSpeech) withObject: nil afterDelay: kDictationReplyAnnouncementWait];
    } else
        [self performSelector: @selector(listenForSpeech) withObject: nil afterDelay: 0];
}

-(BOOL)isHoldingForReply {
    return m_quietForReply;
}

static const NSTimeInterval kDictationReopenGrace = 1.0;

-(BOOL)justReopenedAfterReading {
    return [self isListening] && [NSDate timeIntervalSinceReferenceDate] - m_reopenedAfterReadingAt < kDictationReopenGrace;
}

// Reached from the mic button or a Magic Tap while the mic is closed for a reading. (A Magic
// Tap usually makes VoiceOver discard the reading first, whose finish notice reopens the mic
// before the tap arrives, see justReopenedAfterReading; this is the path when it doesn't.) The
// mic simply reopens; the owner sounds the resume cue.
-(void)interruptReplyAndListen {
    if (!m_quietForReply)
        return;
    DictationLog(@"reading interrupted by the player; mic reopens");
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(listenForSpeech) object: nil];
    [self listenForSpeech];
}

-(void)replyAnnouncementPosted {
    if (!m_quietForReply)
        return;
    m_replyAnnouncementsPending++;
    DictationLog(@"reply announced (%ld pending); mic stays closed for the reading", (long)m_replyAnnouncementsPending);
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(listenForSpeech) object: nil];
    [self performSelector: @selector(listenForSpeech) withObject: nil afterDelay: kDictationReplyReadingLimit];
}

@end

#pragma mark - Cues

// The sounds are WAV files in the app bundle's Sounds folder (resources/Sounds, a folder
// reference; made by meta/make_dictation_cues.py): two quick strikes of A4 for a start, one for a
// resume, and the same an octave down, one strike of A3 for a pause and two for a stop. The second
// strike of a double cue begins this long in, and the second haptic tap goes with it.
static NSString *const kCueFileNames[kStoryDictationCueCount] = { @"DictationStarted", @"DictationResumed", @"DictationPaused", @"DictationStopped" };
static NSString *const kCueSoundsFolder = @"Sounds";
static const NSTimeInterval kCueSecondNoteOffset = 0.08; // SECOND_STRIKE in the script

@implementation StoryDictationCuePlayer
{
    SystemSoundID m_sounds[kStoryDictationCueCount]; // indexed by StoryDictationCue; 0 until first played
    UIImpactFeedbackGenerator *m_startHaptic;   // light taps for started and resumed
    UIImpactFeedbackGenerator *m_stopHaptic;    // firmer taps for paused and stopped
}

-(instancetype)init {
    self = [super init];
    if (self) {
        m_startHaptic = [[UIImpactFeedbackGenerator alloc] initWithStyle: UIImpactFeedbackStyleLight];
        m_stopHaptic = [[UIImpactFeedbackGenerator alloc] initWithStyle: UIImpactFeedbackStyleMedium];
    }
    return self;
}

-(void)dealloc {
    for (NSUInteger i = 0; i < kStoryDictationCueCount; i++)
        if (m_sounds[i])
            AudioServicesDisposeSystemSoundID(m_sounds[i]);
}

// Each cue's sound is registered with System Sound Services from its bundle file the first time
// it is needed.
-(SystemSoundID)soundForCue:(StoryDictationCue)cue {
    if (m_sounds[cue])
        return m_sounds[cue];
    NSString *name = kCueFileNames[cue];
    NSURL *url = [[NSBundle mainBundle] URLForResource: name withExtension: @"wav" subdirectory: kCueSoundsFolder];
    if (!url) {
        NSLog(@"Dictation cue sound %@/%@.wav is missing from the app bundle", kCueSoundsFolder, name);
        return 0;
    }
    OSStatus status = AudioServicesCreateSystemSoundID((__bridge CFURLRef)url, &m_sounds[cue]);
    if (status != noErr) {
        NSLog(@"Error creating dictation cue sound %@: %d", name, (int)status);
        m_sounds[cue] = 0;
    }
    return m_sounds[cue];
}

-(void)playCue:(StoryDictationCue)cue {
    SystemSoundID sound = [self soundForCue: cue];
    if (sound)
        AudioServicesPlaySystemSound(sound);

    // The haptic mirrors the tone: light for the high cues, firmer for the low ones, and two taps
    // timed with the double notes. Devices without a haptic engine (most iPads) ignore these.
    BOOL high = (cue == kStoryDictationCueStarted || cue == kStoryDictationCueResumed);
    BOOL doubled = (cue == kStoryDictationCueStarted || cue == kStoryDictationCueStopped);
    UIImpactFeedbackGenerator *haptic = high ? m_startHaptic : m_stopHaptic;
    [haptic impactOccurred];
    if (doubled) {
        [haptic prepare];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kCueSecondNoteOffset * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [haptic impactOccurred];
        });
    }
}

@end

#pragma mark - Vocabulary

// Levenshtein distance between two short strings.
static NSUInteger EditDistance(NSString *a, NSString *b) {
    NSUInteger la = [a length], lb = [b length];
    if (la > 32 || lb > 32)
        return NSUIntegerMax;
    NSUInteger prev[33], curr[33];
    for (NSUInteger j = 0; j <= lb; j++)
        prev[j] = j;
    for (NSUInteger i = 1; i <= la; i++) {
        curr[0] = i;
        unichar ca = [a characterAtIndex: i-1];
        for (NSUInteger j = 1; j <= lb; j++) {
            NSUInteger cost = (ca == [b characterAtIndex: j-1]) ? 0 : 1;
            NSUInteger best = MIN(prev[j] + 1, curr[j-1] + 1);
            curr[j] = MIN(best, prev[j-1] + cost);
        }
        memcpy(prev, curr, sizeof(curr));
    }
    return prev[lb];
}

// A word with its apostrophes and hyphens removed, for comparing against a transcript, which
// never has them ("drivers" for "driver's").
static NSString *BareWord(NSString *word) {
    static NSCharacterSet *joiners;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ joiners = [NSCharacterSet characterSetWithCharactersInString: @"'-"]; });
    return [[word componentsSeparatedByCharactersInSet: joiners] componentsJoinedByString: @""];
}

// American Soundex of a bare word: the first letter, then codes for the consonants that follow,
// vowels (and h, w, y) dropped, repeats merged, padded to four. Words that sound alike share a
// code whatever their spelling: "rezrov" and the recognizer's "reserv" are both R261.
static NSString *Soundex(NSString *word) {
    if (![word length])
        return @"";
    static const char codes[26] = { 0,1,2,3,0,1,2,0,0,2,2,4,5,5,0,1,2,6,2,3,0,1,0,2,0,2 }; // a..z
    unichar first = [word characterAtIndex: 0];
    NSMutableString *key = [NSMutableString stringWithFormat: @"%C", (unichar)toupper(first)];
    char last = (first >= 'a' && first <= 'z') ? codes[first - 'a'] : 0;
    for (NSUInteger i = 1; i < [word length] && [key length] < 4; i++) {
        unichar c = [word characterAtIndex: i];
        if (c < 'a' || c > 'z')
            continue;
        char code = codes[c - 'a'];
        if (c == 'h' || c == 'w')
            continue; // don't separate two consonants with the same code
        if (code && code != last)
            [key appendFormat: @"%d", code];
        last = code;
    }
    while ([key length] < 4)
        [key appendString: @"0"];
    return key;
}

static const NSUInteger kVocabularyCapacity = 5000; // more distinct words than most games print; insurance only
static const NSUInteger kVocabularyCountBonus = 25;   // in words of recency, per appearance, up to kVocabularyCountBonusLimit
static const NSUInteger kVocabularyCountBonusLimit = 40;

@implementation StoryVocabulary
{
    NSMutableDictionary<NSString*, NSNumber*> *m_lastSeen; // word -> sequence number of its latest appearance
    NSMutableDictionary<NSString*, NSNumber*> *m_counts;   // word -> appearances
    NSUInteger m_sequence;
    NSCharacterSet *m_nonWordChars;
}

-(instancetype)init {
    self = [super init];
    if (self) {
        m_lastSeen = [NSMutableDictionary dictionary];
        m_counts = [NSMutableDictionary dictionary];
        NSMutableCharacterSet *wordChars = [NSMutableCharacterSet letterCharacterSet];
        [wordChars addCharactersInString: @"'-"];
        m_nonWordChars = [wordChars invertedSet];
    }
    return self;
}

-(void)reset {
    [m_lastSeen removeAllObjects];
    [m_counts removeAllObjects];
    m_sequence = 0;
}

-(NSUInteger)count {
    return [m_lastSeen count];
}

// What a word is worth when ranking: its recency, plus a bonus for how often it has appeared.
-(NSUInteger)scoreOf:(NSString*)word {
    return [m_lastSeen[word] unsignedIntegerValue] + kVocabularyCountBonus * MIN([m_counts[word] unsignedIntegerValue], kVocabularyCountBonusLimit);
}

-(void)noteOutput:(NSString*)text {
    if (![text length])
        return;
    static NSCharacterSet *joiners;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ joiners = [NSCharacterSet characterSetWithCharactersInString: @"'-"]; });
    for (NSString *token in [[text lowercaseString] componentsSeparatedByCharactersInSet: m_nonWordChars]) {
        NSString *word = [token stringByTrimmingCharactersInSet: joiners];
        if ([word length] < 2)
            continue;
        m_lastSeen[word] = @(++m_sequence);
        m_counts[word] = @([m_counts[word] unsignedIntegerValue] + 1);
    }
    if ([m_lastSeen count] > kVocabularyCapacity)
        [self evict];
}

// Drops the lowest-scoring tenth: the words seen least often and longest ago. Rarely runs; a long
// game played right through might get here, at which point theYeah early, once-seen words go first.
-(void)evict {
    NSArray<NSString*> *ranked = [[m_lastSeen allKeys] sortedArrayUsingComparator: ^NSComparisonResult(NSString *a, NSString *b) {
        NSUInteger sa = [self scoreOf: a], sb = [self scoreOf: b];
        return sa < sb ? NSOrderedAscending : (sa > sb ? NSOrderedDescending : NSOrderedSame);
    }];
    NSUInteger dropping = [ranked count] / 10;
    DictationLog(@"Vocabulary at %lu words; evicting %lu, lowest-scoring: %@, highest kept: %@",
                 (unsigned long)[ranked count], (unsigned long)dropping,
                 [[ranked subarrayWithRange: NSMakeRange(0, MIN(dropping, 20))] componentsJoinedByString: @" "],
                 [[ranked subarrayWithRange: NSMakeRange([ranked count] - MIN([ranked count], 10), MIN([ranked count], 10))] componentsJoinedByString: @" "]);
    for (NSUInteger i = 0; i < dropping; i++) {
        [m_lastSeen removeObjectForKey: ranked[i]];
        [m_counts removeObjectForKey: ranked[i]];
    }
}

-(NSArray<NSString*>*)recentWords:(NSUInteger)max known:(BOOL (^)(NSString *word))known {
    NSArray<NSString*> *ranked = [[m_lastSeen allKeys] sortedArrayUsingComparator: ^NSComparisonResult(NSString *a, NSString *b) {
        NSUInteger sa = [self scoreOf: a], sb = [self scoreOf: b];
        return sa > sb ? NSOrderedAscending : (sa < sb ? NSOrderedDescending : NSOrderedSame);
    }];
    NSMutableArray<NSString*> *words = [NSMutableArray arrayWithCapacity: max];
    for (NSString *word in ranked) {
        if (known(word))
            [words addObject: word];
        if ([words count] >= max)
            break;
    }
    return words;
}

-(NSString*)nearestKnownWordTo:(NSString*)word known:(BOOL (^)(NSString *word))known {
    NSString *lower = [word lowercaseString];
    if ([lower length] < 3)
        return nil;
    NSString *bare = BareWord(lower);
    NSUInteger allowed = [bare length] <= 4 ? 1 : 2;
    unichar initial = [lower characterAtIndex: 0];
    NSString *best = nil;
    NSUInteger bestDistance = allowed + 1, bestSeen = 0;
    for (NSString *candidate in m_lastSeen) {
        if ([candidate characterAtIndex: 0] != initial)
            continue;
        NSString *bareCandidate = BareWord(candidate);
        NSInteger lengthGap = (NSInteger)[bareCandidate length] - (NSInteger)[bare length];
        if (lengthGap > (NSInteger)allowed || lengthGap < -(NSInteger)allowed)
            continue;
        NSUInteger distance = EditDistance(bare, bareCandidate);
        if (distance > allowed)
            continue;
        NSUInteger seen = [m_lastSeen[candidate] unsignedIntegerValue];
        if (distance < bestDistance || (distance == bestDistance && seen > bestSeen)) {
            if (!known(candidate))
                continue;
            best = candidate;
            bestDistance = distance;
            bestSeen = seen;
        }
    }
    if (best)
        return best;
    // Nothing near in spelling: try sound. The recognizer spells what it hears, so an invented
    // word can come back further from its spelling than from its sound ("reserv" for "rezrov"
    // is three edits). Among printed words with the same Soundex code, the closest in spelling,
    // then the most recent.
    NSString *sound = Soundex(bare);
    bestDistance = NSUIntegerMax;
    for (NSString *candidate in m_lastSeen) {
        if ([candidate characterAtIndex: 0] != initial)
            continue;
        NSString *bareCandidate = BareWord(candidate);
        if (![Soundex(bareCandidate) isEqualToString: sound])
            continue;
        NSUInteger distance = EditDistance(bare, bareCandidate);
        NSUInteger seen = [m_lastSeen[candidate] unsignedIntegerValue];
        if (distance < bestDistance || (distance == bestDistance && seen > bestSeen)) {
            if (!known(candidate))
                continue;
            best = candidate;
            bestDistance = distance;
            bestSeen = seen;
        }
    }
    return best;
}

@end

#endif // EnableStoryDictation
