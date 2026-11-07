
//
//  StoryInputLine.m
//  Frotz
//
//  Created by Craig Smith on 2/9/10.
//  Copyright 2010 Craig Smith. All rights reserved.
//

#import "StoryInputLine.h"
#import "StoryView.h"
#import "StatusLine.h"

#include "iosfrotz.h"

@implementation StoryInputLine

-(void)enterButtonPressed:(id)sender {
    StoryMainViewController *storyController = (StoryMainViewController*)self.delegate;
    if (self.text.length > 0) {
        [self handleCompletion: @"\n"];
        [storyController performSelector: @selector(textFieldFakeDidEndEditing:) withObject: self afterDelay: 0.02];
    }
}

-(void)clearButtonPressed:(id)sender {
    NSString *text = [self text];
    NSUInteger len = [text length];
    NSRange r = [text rangeOfString: @" " options:NSBackwardsSearch range:NSMakeRange(0, len)];
    if (r.length)
        [self setText: [text substringToIndex: r.location]];
    else
        [self setText: @""];
}

-(StoryInputLine*)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame: frame])) {
        m_inputHelper = [[FrotzInputHelper alloc] init];
        [m_inputHelper setDelegate: self];
        UIButton *enterButton = [UIButton buttonWithType: UIButtonTypeCustom];

        [enterButton setTitle:@"  \u23CE   " forState: UIControlStateNormal];
        [enterButton setTitleColor: [UIColor grayColor] forState: UIControlStateNormal];
        [enterButton sizeToFit];

        UIImage *clearButtonImage = [UIImage imageNamed: @"glyph-input-clear"];
        CGFloat ecHeight = [clearButtonImage size].height+4;
        [enterButton setFrame: CGRectMake(0,1, enterButton.frame.size.width, ecHeight)];
        enterButton.backgroundColor = [UIColor clearColor];
        [enterButton addTarget:self action:@selector(enterButtonPressed:) forControlEvents: UIControlEventTouchDown];

        const CGFloat spacingBetweenButtons = 8;
        UIButton *clearButton = [UIButton buttonWithType: UIButtonTypeCustom];
        [clearButton setImage: clearButtonImage forState: UIControlStateNormal];
        [clearButton setFrame: CGRectMake(enterButton.frame.size.width+spacingBetweenButtons,0,[clearButtonImage size].width+8, ecHeight)];
        clearButton.backgroundColor = [UIColor clearColor];
        [clearButton addTarget:self action:@selector(clearButtonPressed:) forControlEvents: UIControlEventTouchDown];

        m_enterAndClearView = [[UIView alloc] initWithFrame: CGRectMake(0,0,enterButton.frame.size.width+spacingBetweenButtons+clearButton.frame.size.width,ecHeight)];
        [m_enterAndClearView addSubview: enterButton];
        [m_enterAndClearView addSubview: clearButton];
        
        self.rightView = m_enterAndClearView;
        self.rightViewMode = UITextFieldViewModeWhileEditing;
        
        UIButton *inputHelperButton = [UIButton buttonWithType: UIButtonTypeCustom];
        UIImage *inputMenuImage = [UIImage imageNamed: @"glyph-input-helper"];
        [inputHelperButton setImage: inputMenuImage forState: UIControlStateNormal];
        [inputHelperButton setFrame: CGRectMake(0,0,[inputMenuImage size].width, [inputMenuImage size].height)];
        [inputHelperButton addTarget:self action:@selector(toggleInputHelper) forControlEvents: UIControlEventTouchUpInside];
        inputHelperButton.backgroundColor = [UIColor clearColor];

        self.leftView = inputHelperButton;
        self.leftViewMode = UITextFieldViewModeUnlessEditing;
        [self setInputMenuButtonAlpha];
    }
    return self;
}

- (CGRect)leftViewRectForBounds:(CGRect)bounds {
    CGRect rect = [super leftViewRectForBounds:bounds];
    return rect;
}

- (CGRect)editingRectForBounds:(CGRect)bounds {
    CGRect rect = [super editingRectForBounds: bounds];
    CGRect lrRect = [self leftViewRectForBounds: bounds];
    if (rect.origin.x >= lrRect.size.width) {
        rect.origin.x -= lrRect.size.width;
        rect.size.width += lrRect.size.width;
    }
    StoryMainViewController *storyController = (StoryMainViewController*)[m_storyView delegate];
    if ([storyController isKBLocked])
        rect.size.width -= m_enterAndClearView.frame.size.width;
    return rect;
}

-(void)dealloc {
    self.rightView = nil;
    self.leftView = nil;
    m_completionLabel = nil;
    m_inputHelper = nil;
}

-(UIView*) inputHelperView {
    return [m_inputHelper helperView];
}

-(void)hideInputHelper {
    if (m_completionLabel) {
        [m_completionLabel removeFromSuperview];
    }
    [m_inputHelper hideInputHelper];
}

-(BOOL)becomeFirstResponder {
    if (![self isFirstResponder] && [self canBecomeFirstResponder])
        [m_inputHelper hideInputHelper];
    return [super becomeFirstResponder];
}

-(void)inputHelperString:(NSString*)string {
    [self hideInputHelper];
    NSUInteger len = [self.text length];
    if (len > 0) {
        if ([self.text characterAtIndex:len-1]!=' ' && !ispunct([self.text characterAtIndex:len-1]))
            string = [@" " stringByAppendingString: string];
        string = [self.text stringByAppendingString: string];
    }
    [self setText: string];
}

#if EnableStoryDictation
// While the input line is editing, VoiceOver gives its Magic Tap to the first responder before
// anyone else, and a text field's default is to start the system keyboard dictation. The gesture
// means Frotz's own dictation here, so it goes to the story controller (see its
// accessibilityPerformMagicTap), which answers as the mic button would.
-(BOOL)accessibilityPerformMagicTap {
    StoryMainViewController *storyController = (StoryMainViewController*)[m_storyView delegate];
    return [storyController accessibilityPerformMagicTap];
}

-(BOOL)validateWord:(NSString*)word {
    StoryMainViewController *storyController = (StoryMainViewController*)[m_storyView delegate];
    return [storyController dictionaryHasWord: word];
}

// What the player is likely to say, for the recognizer to favor (see dictationContextWords in
// InputHelper.h). The recognizer's own vocabulary is everyday English; a parser game's is the
// nouns of its rooms and the verbs of the form, so without this "take the lantern" came back as
// "take the lantern" only by luck and "xyzzy" never did. Drawing the hints from three sources,
// recent commands, the text on screen and a stock of common verbs, is Anand M.'s idea (anandman
// on GitHub), from his own independent voice-mode branch of Frotz. Most useful first:
//  - the player's recent commands, whole, since commands repeat ("examine lamp", "take lamp");
//  - the words the story has printed that the game's dictionary knows, most recent and most
//    repeated first (StoryVocabulary), since what a command refers to is almost always something
//    the player has read (and this leaks no spoilers: it is only what has been printed, unlike
//    the game's dictionary as a whole would be);
//  - the ordinary verbs and directions of the form, which the output may not contain.
// Capped: Apple gives no limit for contextual strings, but the hint is per utterance and a few
// hundred strings is plenty.
static const NSUInteger kDictationContextMaxCommands = 20;
static const NSUInteger kDictationContextMaxWords = 200;
static NSArray<NSString*> *OrdinaryCommandWords(void);

// Whether the game's dictionary knows a word, for StoryVocabulary's queries.
-(BOOL (^)(NSString*))gameKnowsWord {
    StoryMainViewController *storyController = (StoryMainViewController*)[m_storyView delegate];
    return ^BOOL(NSString *word) { return [storyController dictionaryHasWord: word]; };
}

-(NSArray<NSString*>*)dictationContextWords {
    NSMutableOrderedSet<NSString*> *context = [NSMutableOrderedSet orderedSet];
    NSArray<NSString*> *history = [m_inputHelper historyItems];
    for (NSString *command in [history reverseObjectEnumerator]) {
        NSString *trimmed = [[command stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
        if ([trimmed length] > 1)
            [context addObject: trimmed];
        if ([context count] >= kDictationContextMaxCommands)
            break;
    }
    StoryMainViewController *storyController = (StoryMainViewController*)[m_storyView delegate];
    [context addObjectsFromArray: [storyController.storyVocabulary recentWords: kDictationContextMaxWords known: [self gameKnowsWord]]];
    [context addObjectsFromArray: OrdinaryCommandWords()];
    return [context array];
}

// The ordinary verbs and directions of the form, which may begin a command whatever the game.
static NSArray<NSString*> *OrdinaryCommandWords(void) {
    static NSArray<NSString*> *ordinary;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ordinary = @[ @"look", @"examine", @"take", @"get", @"drop", @"put", @"open", @"close", @"read", @"search",
                      @"inventory", @"wait", @"again", @"go", @"enter", @"exit", @"climb", @"push", @"pull", @"turn",
                      @"give", @"ask", @"tell", @"say", @"wear", @"remove", @"unlock", @"lock", @"light", @"attack",
                      @"north", @"south", @"east", @"west", @"northeast", @"northwest", @"southeast", @"southwest",
                      @"up", @"down", @"in", @"out", @"save", @"restore", @"undo", @"quit", @"xyzzy" ];
    });
    return ordinary;
}

// A command starts with a verb (or is a bare direction), and a transcript that doesn't is likely a
// near-miss: after the story prints "book" a dozen times, "look" said quickly comes back as "book".
// The game's dictionary says which words are verbs when it is an Inform story (game-specific
// verbs included, though not every game flags its odd command words: Balances' spell names are
// nouns to its dictionary); the ordinary verbs and directions count for any game.
-(BOOL)dictationStartsWithVerb:(NSString*)text {
    NSCharacterSet *separators = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *first = [[[[text stringByTrimmingCharactersInSet: separators] componentsSeparatedByCharactersInSet: separators] firstObject]
                       stringByTrimmingCharactersInSet: [NSCharacterSet punctuationCharacterSet]];
    first = [first lowercaseString];
    if (![first length])
        return NO;
    if ([OrdinaryCommandWords() containsObject: first])
        return YES;
    StoryMainViewController *storyController = (StoryMainViewController*)[m_storyView delegate];
    return [storyController dictionaryWordIsVerb: first] == 1;
}

// The recognizer knows everyday English, not a game's invented words ("yomin") or its spellings
// ("driver's"), so for those it lands on the nearest real word. The game's dictionary says which
// transcript words it won't understand; for each, the nearest word the story has printed that the
// game does understand replaces it, if it is near enough (StoryVocabulary nearestKnownWordTo:;
// "yemen" to "yomin" is two substitutions in five letters, the case this exists for). Only words
// the game would have rejected anyway are touched, and only words the player has already seen
// are candidates, so a miss costs one parser error for another and nothing is revealed.
// Two kinds of unknown word are deliberately left alone: one in capitals, which the recognizer
// produces when the player spells a word letter by letter, and one the recognizer was confident
// of (confidentRanges), where a careful speaker most likely said exactly that and the parser's
// own complaint is more useful than a guess ("pet horse" turned into "path horse" is not).
-(NSString*)dictationCorrectedText:(NSString*)text confidentRanges:(NSIndexSet*)confidentRanges {
    NSArray<NSString*> *words = [text componentsSeparatedByString: @" "];
    NSMutableArray<NSString*> *out = [NSMutableArray arrayWithCapacity: [words count]];
    NSCharacterSet *punctuation = [NSCharacterSet punctuationCharacterSet];
    StoryMainViewController *storyController = (StoryMainViewController*)[m_storyView delegate];
    BOOL (^known)(NSString*) = [self gameKnowsWord];
    BOOL changed = NO;
    NSUInteger wordStart = 0; // offset of `word` within text; the words are split on single spaces
    for (NSString *word in words) {
        NSRange coreRange = [word rangeOfCharacterFromSet: [punctuation invertedSet]];
        NSString *core = [word stringByTrimmingCharactersInSet: punctuation];
        NSString *lower = [core lowercaseString];
        BOOL spelledOut = [core isEqualToString: [core uppercaseString]];
        BOOL confident = coreRange.location != NSNotFound
            && [confidentRanges intersectsIndexesInRange: NSMakeRange(wordStart + coreRange.location, [core length])];
        wordStart += [word length] + 1;
        if ([lower length] < 3 || [lower rangeOfCharacterFromSet: [NSCharacterSet letterCharacterSet]].location == NSNotFound
            || spelledOut || known(lower)) {
            [out addObject: word];
            continue;
        }
        NSString *best = [storyController.storyVocabulary nearestKnownWordTo: lower known: known];
        // A word the recognizer was sure of is only respelled, never replaced: "drivers" becomes
        // the printed "driver's" (the same word once apostrophes and hyphens are ignored, which
        // the recognizer never writes), but "pet" does not become "path".
        if (best && confident) {
            NSCharacterSet *joiners = [NSCharacterSet characterSetWithCharactersInString: @"'-"];
            NSString *bareBest = [[best componentsSeparatedByCharactersInSet: joiners] componentsJoinedByString: @""];
            NSString *bareHeard = [[lower componentsSeparatedByCharactersInSet: joiners] componentsJoinedByString: @""];
            if (![bareBest isEqualToString: bareHeard])
                best = nil;
        }
        if (best) {
            // Keep whatever punctuation surrounded the word in the transcript.
            [out addObject: [word stringByReplacingCharactersInRange: NSMakeRange(coreRange.location, [core length]) withString: best]];
            changed = YES;
        } else
            [out addObject: word];
    }
    return changed ? [out componentsJoinedByString: @" "] : text;
}

// Between one key read and the next the interpreter disables input for a moment, so a hypothesis
// arriving then would see neither mode; the last mode the story asked for is remembered across
// that gap. Otherwise a letter dictated at a menu was shown as line text by one hypothesis and
// sent as a key by the final result.
-(BOOL)dictationExpectsSingleKey {
    if (ipzAllowInput & kIPZRequestInput)
        m_lastInputRequestWasKey = (ipzAllowInput & kIPZNoEcho) || cwin == 1;
    return m_lastInputRequestWasKey;
}

static NSString *KeyForSpokenText(NSString *spoken, NSUInteger *score);

-(NSUInteger)dictationKeyScore:(NSString*)text {
    NSUInteger score = 0;
    KeyForSpokenText(text, &score);
    return score;
}

// The key for what was said at a single-key prompt ("press any key", a yes/no question, a menu).
// Words a player would naturally say for a key map to it; anything else gives its first letter,
// so "Q" or "quit" is 'q' (and so does the NATO alphabet: "november" is 'n'). Letter names the
// recognizer renders as words ("bee", "why", "are", "in") map to their letter; a leading "letter"
// or "the letter" is dropped. The recognizer is primed with the letters themselves for these
// prompts (StoryDictationController), so this is the backstop. Case is dropped: key prompts in IF
// take either, and menus list lower-case letters. `score`, if asked for, is how directly the text
// named its key: 2 a bare letter or digit, 1 a word for a key or a letter's name, 0 a first letter
// borrowed (see dictationKeyScore: in InputHelper.h).
static NSString *KeyForSpokenText(NSString *spoken, NSUInteger *score) {
    if (score)
        *score = 0;
    NSString *word = [[spoken stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    word = [word stringByTrimmingCharactersInSet: [NSCharacterSet punctuationCharacterSet]];
    for (NSString *prefix in @[ @"the letter ", @"letter " ])
        if ([word hasPrefix: prefix])
            word = [word substringFromIndex: [prefix length]];
    if (![word length])
        return @"";
    static NSDictionary<NSString*, NSString*> *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @{ @"yes": @"y", @"yeah": @"y", @"yep": @"y", @"yup": @"y",
                  @"no": @"n", @"nope": @"n",
                  // letter names as the recognizer tends to spell them
                  @"be": @"b", @"bee": @"b", @"see": @"c", @"sea": @"c", @"dee": @"d", @"gee": @"g",
                  @"jay": @"j", @"kay": @"k", @"el": @"l", @"em": @"m", @"en": @"n", @"in": @"n",
                  @"oh": @"o", @"pee": @"p", @"pea": @"p", @"queue": @"q", @"cue": @"q", @"are": @"r",
                  @"ess": @"s", @"tee": @"t", @"tea": @"t", @"you": @"u", @"vee": @"v",
                  @"double you": @"w", @"ex": @"x", @"why": @"y", @"zee": @"z", @"zed": @"z",
                  @"space": @" ", @"continue": @" ", @"any key": @" ", @"more": @" ",
                  @"enter": @"\n", @"return": @"\n",
                  @"escape": @"\x1b", @"cancel": @"\x1b",
                  @"backspace": @"\b", @"delete": @"\b",
                  @"up": @ZC_IPS_ARROW_UP, @"down": @ZC_IPS_ARROW_DOWN,
                  @"left": @ZC_IPS_ARROW_LEFT, @"right": @ZC_IPS_ARROW_RIGHT,
                  @"zero": @"0", @"one": @"1", @"two": @"2", @"three": @"3", @"four": @"4",
                  @"five": @"5", @"six": @"6", @"seven": @"7", @"eight": @"8", @"nine": @"9" };
    });
    NSString *key = keys[word];
    if (key) {
        if (score)
            *score = 1;
        return key;
    }
    if ([word length] == 1) { // a letter or digit as such
        if (score)
            *score = 2;
        return word;
    }
    return [word substringWithRange: [word rangeOfComposedCharacterSequenceAtIndex: 0]];
}

// The story is waiting for a single key. Nothing is shown in the line, for partial results or the
// final one: the story's own reaction to the key is the feedback, as when a key is typed. (Showing
// the key was tried: partial results gave the recognizer's first guess, so "P" appeared as H and
// then changed; and a key shown after sending was blanked and redrawn by the caret-resize trick
// the controller applies when the story's next key prompt arrives, then sat in the line when a key
// ended a menu.) The final result's key (KeyForSpokenText, the controller having picked the
// alternative that best names a key) is fed as a typed key is, by the same delayed path
// keyboardInput:shouldInsertText: uses. It is not submitted as a line: that would feed the whole
// utterance a character at a time, the prompt taking the first and the story's next line input
// starting with the rest. None of the line dictation state applies, so it is reset.
-(void)acceptDictationAsKey:(NSString*)string final:(BOOL)isFinal {
    m_textBeforeDictation = nil;
    m_lastDictationShown = nil;
    m_dictationSuffix = nil;
    m_dictationHold = NO;
    if (!isFinal)
        return;
    NSString *key = KeyForSpokenText(string, NULL);
#if StoryDictationDebugLogging
    NSLog(@"key for \"%@\": %@", string, key);
#endif
    if ([key length]) {
        [(StoryMainViewController*)[m_storyView delegate] dictatedCommandSubmitted]; // what follows the key is announced over any reading still going
        [self performSelector: @selector(delayedInput:) withObject: key afterDelay: 0.04];
    }
}

// Dictation is added to whatever was typed before the utterance began rather than put in its
// place. The typed part is captured when the utterance's first hypothesis arrives and kept for
// the rest of it, each hypothesis replacing the previous one after it. Anything added after the
// transcript meanwhile (a word double-tapped in the story, say "examine" then tap "book") is kept
// after it: the line is rebuilt as typed part, new transcript, added words, so the final result
// gives "examine book". Without that the line no longer matched what was last shown here, the
// whole of it became the new base, and the final transcript was appended again: "examine book
// examine". If the line has changed in some other way (typing in the middle, clearing), the
// current text becomes the new base.
//
// The final result is submitted as a command, all parts included, unless the player has edited
// the line (tapped or typed) since the last words were heard: then they are still composing, and
// the silence that produced the final result was them working, not them finishing. The line is
// left for them to finish with Return or by speaking again (the next utterance takes the line as
// its base and its own final result submits). Speech after an edit, within the same utterance,
// re-arms the submit: hypotheses only arrive with speech, so a hypothesis that finds the suffix
// unchanged since the one before means the last thing the player did was speak. Opening the input
// helper counts as an edit too (holdDictationCommit), though it changes no text: the player has
// gone to pick a word, and speech again re-arms in the same way.
//
// When the story is waiting for a single key instead of a line, the utterance becomes one key;
// see acceptDictationAsKey:final:.
-(void)acceptDictation:(NSString*)string final:(BOOL)isFinal {
    if ([self dictationExpectsSingleKey]) {
        [self acceptDictationAsKey: string final: isFinal];
        return;
    }
    NSString *current = self.text ?: @"";
    NSString *suffix = @"";
    BOOL rebased = NO;
    BOOL held = m_dictationHold;
    if (!isFinal)
        m_dictationHold = NO; // speech since the helper was opened
    if (!m_textBeforeDictation || !m_lastDictationShown)
        m_textBeforeDictation = current;
    else if (![m_lastDictationShown length] || [current hasPrefix: m_lastDictationShown]) // hasPrefix: is NO for an empty prefix
        suffix = [current substringFromIndex: [m_lastDictationShown length]]; // empty when unchanged
    else {
        m_textBeforeDictation = current;
        rebased = YES;
    }
    BOOL editedSinceLastSpeech = rebased || ![suffix isEqualToString: m_dictationSuffix ?: @""];
    m_dictationSuffix = suffix;
    // With VoiceOver on and the keyboard up (this field editing), VoiceOver echoes every change
    // made to the field's text in its typing voice, so the running transcript came back once per
    // hypothesis and again on the final, on top of the story's own echo of the command. In that
    // case the hypotheses aren't shown at all (the player can't see them), the final text is set
    // once, and the command is submitted at once so the field is cleared before VoiceOver reads
    // it; the story's announcement then echoes the command the one time.
    BOOL silentField = UIAccessibilityIsVoiceOverRunning() && [self isFirstResponder];
    if (silentField && !isFinal) {
        m_lastDictationShown = m_textBeforeDictation; // what is actually shown, so the suffix is still found next time
        return;
    }
    NSString *shown = m_textBeforeDictation;
    if ([shown length] && [shown characterAtIndex: [shown length] - 1] != ' ' && !ispunct([shown characterAtIndex: [shown length] - 1]))
        shown = [shown stringByAppendingString: @" "];
    shown = [shown stringByAppendingString: string];
    [self hideInputHelper];
    m_lastDictationShown = shown; // typed part and transcript, without the suffix, so it is found again next time
    [self setText: [shown stringByAppendingString: suffix]];
    if (isFinal) {
        m_textBeforeDictation = nil;
        m_lastDictationShown = nil;
        m_dictationSuffix = nil;
        m_dictationHold = NO;
        if (!editedSinceLastSpeech && !held) {
            StoryMainViewController *storyController = (StoryMainViewController*)[m_storyView delegate];
            [storyController dictatedCommandSubmitted]; // its reply is announced over any reading still going
            if (silentField)
                [storyController textFieldFakeDidEndEditing: self];
            else
                [storyController performSelector: @selector(textFieldFakeDidEndEditing:) withObject: self afterDelay: 0.1];
        }
    }
}

// Forget the utterance's base: the line as it stands, partial included, is what the next
// utterance's words follow. Without this a pause mid-command ("put the brass lantern", off to
// the notes page and back) had the resumed words replace the first half instead of continuing it.
-(void)abandonDictation {
    m_textBeforeDictation = nil;
    m_lastDictationShown = nil;
    m_dictationSuffix = nil;
    m_dictationHold = NO;
}
#endif

// See acceptDictation:final:. Harmless when no utterance is in progress: the flag is cleared by
// the next hypothesis or final result, and only read when a final result arrives.
-(void)holdDictationCommit {
    m_dictationHold = YES;
}

-(CGPoint)helperLaunchPosition {
    UIView *parentView = [m_storyView superview];
    CGFloat ypos = [self convertPoint: CGPointZero toView: parentView].y;
    StoryMainViewController *storyController = (StoryMainViewController*)[m_storyView delegate];
    BOOL isLandscape = [storyController isLandscape];
    CGPoint ihpt = CGPointMake(isLandscape ? 100 : 2, ypos-8);
    BOOL regularWidth = self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular;
    if (regularWidth)
        ihpt.x += self.frame.origin.x;
    else if (!regularWidth && ![storyController isKBLocked] && [self isFirstResponder]
                && isLandscape)
        ihpt = CGPointMake(100, ypos);
    // point is bottom-LEFT of helper view; 140 is height of helper
    if (ihpt.y < 140) ihpt.y = 140;
    return ihpt;
}

-(void)launchInputHelper:(id)unused {
    UIView *parentView = [m_storyView superview];
    CGPoint ihpt = [self helperLaunchPosition];
    if (m_completionLabel)
        [m_completionLabel removeFromSuperview];
    [self holdDictationCommit];
    [m_inputHelper showInputHelperInView:parentView atPoint: ihpt withMode: FrotzInputHelperModeWords];
}

-(void)setInputMenuButtonAlpha {
    UIButton *ivButton = (UIButton*)self.leftView;
    FrotzInputHelperMode mode = [m_inputHelper mode];
    if ((ipzAllowInput & kIPZNoEcho) || cwin == 1)
        ivButton.imageView.alpha = 0.0;
    else if (mode == FrotzInputHelperModeNone)
        ivButton.imageView.alpha = 0.25;
    else
        ivButton.imageView.alpha = 0.70;
}

-(void)toggleInputHelper {
    // we don't actually need to do anything special here since the general touuch handler handles this for anywhere on the input line
    FrotzInputHelperMode mode = [m_inputHelper mode];
    if (mode == FrotzInputHelperModeNone) {
        [self performSelector:@selector(setInputMenuButtonAlpha) withObject:nil afterDelay:0.2];
    }
}

- (BOOL)handleTouch: (UITouch*)touch withEvent: (UIEvent*)event {
    UITouchPhase phase = [touch phase];
    NSUInteger tapCount = [touch tapCount];
    FrotzInputHelperMode mode = [m_inputHelper mode];
    //    NSLog(@"touch phase %d tapc %d mode %d\n", phase, tapCount, mode);
    if (phase == UITouchPhaseCancelled) {
        if (m_inputHelper)
            [self hideInputHelper];
        m_lastTouchPhaseSeen = phase;
        return YES;
    }
    // long tap on history for single word??
    StoryMainViewController *storyController = (StoryMainViewController*)self.delegate;
    UIView *parentView = [m_storyView superview];
    BOOL isInputHelperTouch =  [touch locationInView:self].x < self.frame.size.width * 0.8;
    CGPoint currentTouchPosition = [touch locationInView:self];

    //CGRect rtRect = [self rightViewRectForBounds:self.bounds];
    //NSLog(@"sit ht (%f,%f) (x %f- wid %f)",currentTouchPosition.x, currentTouchPosition.y, rtRect.origin.x, rtRect.size.width);

    BOOL kbLocked = [storyController isKBLocked];
    if (![storyController isKBShown] && !kbLocked
        && !CGRectContainsPoint([self leftViewRectForBounds:self.bounds], currentTouchPosition)
        || (ipzAllowInput & kIPZNoEcho) || cwin == 1)
        isInputHelperTouch = NO;

    if (CGRectContainsPoint([self rightViewRectForBounds:self.bounds], currentTouchPosition))
        return YES;
    
    CGPoint ihpt = [self helperLaunchPosition];
    
    if (phase == UITouchPhaseEnded) {
        CGFloat xdist = ABS(m_touchBeganPosition.x - currentTouchPosition.x);
        CGFloat ydist = ABS(m_touchBeganPosition.y - currentTouchPosition.y);
        if (tapCount == 0 &&  ydist >= 70 && xdist <= 40 && m_touchBeganPosition.y > currentTouchPosition.y) {// Check for upward swipe
            if (self.text.length > 0)
                [storyController performSelector: @selector(textFieldFakeDidEndEditing:) withObject: self afterDelay: 0.02];
        }
        else if (tapCount == 1 && isInputHelperTouch && mode == FrotzInputHelperModeNone)
            [self performSelector: @selector(launchInputHelper:) withObject:nil afterDelay:0.14];
        else if (tapCount == 2 && isInputHelperTouch &&  mode != FrotzInputHelperModeWords) {
            ihpt.y -= 10;
            ihpt.x += 20;
            [self holdDictationCommit];
            [m_inputHelper showInputHelperInView:parentView atPoint: ihpt withMode: FrotzInputHelperModeHistory];
        } else if (mode != FrotzInputHelperModeNone && tapCount) {
            [self hideInputHelper];
            m_justHidHelper = YES;
    	    m_lastTouchTimestamp = [touch timestamp];
        } else {
            m_justHidHelper = NO;
        }
    } else if (phase == UITouchPhaseBegan) {
        if (tapCount == 1) {
            m_touchBeganPosition = [touch locationInView: self];
            m_lastTouchTimestamp = [touch timestamp];
        } else if (tapCount == 2)
            [NSRunLoop cancelPreviousPerformRequestsWithTarget: self];
    } 
    m_lastTouchPhaseSeen = phase;
    return YES;
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    BOOL retValue = YES;
    FrotzInputHelperMode mode = [m_inputHelper mode];
    if (mode != FrotzInputHelperModeNone)
        return NO;
    if ((ipzAllowInput & kIPZNoEcho) || cwin == 1 || m_justHidHelper) {
        if (action == @selector(upArrow:) || action == @selector(downArrow:)
            || action == @selector(leftArrow:) || action == @selector(rightArrow:) || action == @selector(escapeKey:))
            return YES;
        return NO;
    }
    if (action == @selector(paste:) ) {
        // can only get paste menu by long touch when helper menu isn't showing
        if ([[m_inputHelper view] superview]) // m_lastTouchPhaseSeen == UITouchPhaseEnded || 
            retValue = NO;
    } else
        retValue = [super canPerformAction: action withSender:sender];
    return retValue;
}

-(NSUInteger)addHistoryItem:(NSString*)historyItem {
    return [m_inputHelper addHistoryItem:  historyItem];
}

@synthesize storyView=m_storyView;
@synthesize statusLine=m_statusLine;

-(void)resetState {
    m_firstKeyPressed = NO;
    [self setClearButtonMode: UITextFieldViewModeAlways];
}

BOOL cursorVisible = YES;

-(BOOL)canBecomeFirstResponder {
    StoryMainViewController *controller = (StoryMainViewController*)[self delegate];
    if ([controller isKBLocked])
        return NO;
    return [super canBecomeFirstResponder];
}

-(BOOL)updatePosition {
    static BOOL insideUpdatePosition;
    if (insideUpdatePosition) // prevent recursive update (setText: can cause this)
        return NO;
    insideUpdatePosition = YES;
    CGRect myFrame = [self frame];
    FrotzView *curTextView = m_storyView;
    StoryMainViewController *controller = (StoryMainViewController*)[self delegate];
    BOOL isGrid = NO;
    if (cwin >= 1) {
        curTextView = m_statusLine;
        isGrid = YES;
        FrotzView *v = [controller glkView: cwin];
        if (v) {
            curTextView = v;
            isGrid = [controller glkViewTypeIsGrid: cwin];
        }
    }
    CGRect frame = [curTextView frame];
    cursorVisible = YES;
    if (!(ipzAllowInput & kIPZRequestInput)) {
        myFrame.origin.x = 0;
        myFrame.origin.y = frame.size.height + 1024; // make sure offscreen, not under kb
    }
    else if (isGrid) {
        //  NSLog(@"udp bounds=%f %f %f %f", bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height);
#if UseRichTextView
        CGPoint cursorPt = [controller cursorOffset];
        myFrame.origin.x = frame.origin.x + cursorPt.x; // cursor_col * fixedFontWidth - bounds.origin.x;
        myFrame.origin.y = frame.origin.y + cursorPt.y; // cursor_row * (fixedFontHeight) - bounds.origin.y;
        if (cursorPt.y >= frame.size.height) {
            myFrame.origin.y = [curTextView frame].size.height;
            cursorVisible = NO;
        }
#else
        int fixedFontWidth = [controller statusFixedFontPixelWidth];
        int fixedFontHeight = [controller statusFixedFontPixelHeight];
        CGRect bounds = [curTextView bounds];
        myFrame.origin.x = frame.origin.x + cursor_col * fixedFontWidth - bounds.origin.x + 2;
        myFrame.origin.y = frame.origin.y + cursor_row * (fixedFontHeight-1) - bounds.origin.y + 8;
#endif
        if (frame.origin.x != myFrame.origin.x) {
            NSString *text = [self text];
            [self setText: @" "];
            [self setText: text];
        }
    }
    else
    {
        CGRect bounds = [curTextView bounds];
        //  NSLog(@"udp bounds=%f %f %f %f", bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height);
        CGSize sz = [curTextView contentSize];
#if UseRichTextView
        CGPoint cursorPt = sz.height > 40 ? [curTextView cursorPoint] : CGPointMake(0,0);
#else
        NSRange range = [curTextView selectedRange];
        if (range.location == INT32_MAX)
            range.location = 0;
        CGRect selRect = sz.height > 40 ? [curTextView rectForSelection: range] : CGRectMake(0,0,0,0);
        CGPoint cursorPt = selRect.origin;
#endif
        myFrame.origin.x = frame.origin.x + cursorPt.x - bounds.origin.x;
        myFrame.origin.y = frame.origin.y + cursorPt.y - bounds.origin.y;
        if (myFrame.origin.y > frame.origin.y + frame.size.height - [controller fontSize])
            cursorVisible = NO;
    }
    
    //NSLog(@"udp cwin %d myFrame=%f %f %f %f vis=%d", cwin, myFrame.origin.x, myFrame.origin.y, myFrame.size.width, myFrame.size.height, cursorVisible);
    myFrame.size.width = frame.size.width - (myFrame.origin.x - frame.origin.x) - [curTextView rightMargin];
    int pad = 2;
    myFrame.size.height = [[self font] lineHeight]+pad;

    [self setFrame: myFrame];
    if (m_completionLabel) {
        CGRect labelFrame = [m_completionLabel frame];
        labelFrame.origin.y = myFrame.origin.y - myFrame.size.height-pad-4;
        [m_completionLabel setOrigin: labelFrame.origin];
    }


    if (cursorVisible)
        [[self superview] bringSubviewToFront: self];
    else
        [[self superview] sendSubviewToBack: self];
    [self setClearButtonMode];
    insideUpdatePosition = NO;
   
    return cursorVisible;
}

-(void) setClearButtonMode {
    CGRect frame = self.frame;
    CGRect parentFrame = self.superview.frame;
    if (frame.origin.x > parentFrame.size.width - 60)
        [self setClearButtonMode: UITextFieldViewModeNever];
    else
        [self setClearButtonMode: UITextFieldViewModeWhileEditing];
    [self maybeShowEnterKey];
}

-(void)maybeShowEnterKey {
    StoryMainViewController *storyController = (StoryMainViewController*)[self delegate];
    
    [self setInputMenuButtonAlpha];
    
    if ([storyController isKBLocked] && (self.text.length > 0 && !m_lastCharDeleted || m_firstKeyPressed)) {
        m_firstKeyPressed = NO;
        self.rightViewMode = UITextFieldViewModeAlways;
        [self setClearButtonMode: UITextFieldViewModeNever];
        self.leftViewMode = UITextFieldViewModeNever;
    }
    else {
        self.rightViewMode = UITextFieldViewModeNever;
        if (self.text.length == 0)
            self.leftViewMode = UITextFieldViewModeUnlessEditing;
        else
            self.leftViewMode = UITextFieldViewModeNever;
        m_lastCharDeleted = NO;
    }
}

-(void)hideEnterKey {
    m_lastCharDeleted = YES;
    [self setClearButtonMode];
}

const int kCompletionViewTag = 21;

-(void)setFont:(UIFont *)font {
    if (font == self.font)
        return;
    [super setFont: font];
    if (m_completionLabel)
        [m_completionLabel setFont: font];
}

-(void)setText:(NSString *)text {
    [super setText: text];
    iosif_feed_input_line(text);

    if (m_completionLabel) {
        [m_completionLabel setText: nil];
        [m_completionLabel removeFromSuperview];
    }
    [self maybeShowEnterKey];
//    NSLog(@"set text %@", text);
}

-(void)setTextKeepCompletion:(NSString*)text {
    [super setText: text];
}

-(void)delayedInput:(NSString*)text {
    iosif_feed_input(text);
}

#if 0
-(BOOL)respondsToSelector:(SEL)aSelector {
    NSLog(@"rts %s", aSelector);
    if (aSelector == @selector(keyboardInput:shouldInsertText:isMarkedText:))
        return YES;
    return [super respondsToSelector: aSelector];
}
#endif

-(BOOL)keyboardInput:(id)sender shouldInsertText:(NSString*)text isMarkedText:(BOOL)imt {
    if (!m_firstKeyPressed && self.text.length==0) {
        // the clearButtonMode set is done to work around a bug where the input line doesn't draw
        // properly right after an autorestore.  All it does it set the field and call setNeedsLayout,
        // but just calling that directly didn't work; it doesn't force a redraw if nothing's really changed
        m_firstKeyPressed = YES;
        if (!(ipzAllowInput & kIPZAllowInput))
            [self setClearButtonMode]; // else updatePosition below will do it
    }

    StoryMainViewController *storyController = (StoryMainViewController*)[self delegate];
    
    [self hideInputHelper];
    [storyController hideNotes];
    
    if ((ipzAllowInput & kIPZAllowInput)) {
        // some love for users of bluetooth keyboards
        if ([text isEqualToString: @" "]) { // option-space = scroll up one page
            [storyController scrollStoryViewUpOnePage:[self storyView] fraction: 1.0];
            return NO;
        }
        if (![self updatePosition]) {
            if ([text isEqualToString:@" "]) { // space = scroll down one page
                [storyController scrollStoryViewOnePage:[self storyView] fraction:1.0];
                return NO;
            }
            [storyController scrollStoryViewToEnd: YES];
            [self updatePosition];
        }
        
        CGSize sz = [[self storyView] contentSize];
        lastVisibleYPos[cwin] = sz.height;
        
        if ((ipzAllowInput & kIPZNoEcho) || cwin == 1) {// was below
            // Not fed to the interpreter directly: a direct iosif_feed_input call causes an odd
            // performance issue (Bureaucracy).
            [self performSelector:@selector(delayedInput:) withObject:text afterDelay:0.04];
            return NO;
        }
    }
    
    if ((ipzAllowInput & kIPZNoEcho) || cwin == 1)
        return NO;

    BOOL result = (BOOL)[super keyboardInput:sender shouldInsertText:text isMarkedText:imt];

    if (![storyController isCompletionEnabled])
        return result;
    if (result)
        result = [self handleCompletion:text];
    
    return result;
}


-(BOOL)handleCompletion:(NSString*)text {
    StoryMainViewController *storyController = (StoryMainViewController*)[self delegate];
    BOOL result = YES;
    UIView *parentView = [self superview];
    CGRect frame = [self frame];
    if (!m_completionLabel) {
        m_completionLabel = [[CompletionLabel alloc] initWithFont:[self font]];
    }
    NSString *word = [self text];
    NSString *prevString = nil;
    NSUInteger len = [word length];
    NSRange r = [word rangeOfString: @" " options:NSBackwardsSearch range:NSMakeRange(0, len)];
    if (r.length)
        prevString = [word substringToIndex: r.location+1];
    if (r.length)
        ++r.location;
    else r.location = 0;
    r.length = len-r.location;
    word = [word substringWithRange: r];
    if ([text isEqualToString: @" "] || [text isEqualToString:@"."] || [text isEqualToString: @"\n"]) {
        if ([m_completionLabel text] && [[m_completionLabel text] length] > 0) {
            NSString *completion = [m_completionLabel text];
            if ([text isEqualToString: @"\n"]) {
                [self setText: prevString ? [prevString stringByAppendingString: completion] : completion];
                [m_completionLabel removeFromSuperview];
                [m_completionLabel setText: nil];
            } else {
                [super setText: prevString];
                [parentView addSubview: m_completionLabel];
                if ((![text isEqualToString: @"."] || ![completion hasSuffix: @". "]) && !m_completionAmbiguous)
                    completion = [completion stringByAppendingString: text];
                [storyController textSelected:completion animDuration:0.02 hilightView:m_completionLabel];
                return NO;
            }
        }
        return result;
    } else {
        word = [word stringByAppendingString: text];
        NSString *completion = [storyController completeWord: word prevString:prevString isAmbiguous:&m_completionAmbiguous];
        if (completion && ![completion isEqualToString: word]) {
            [m_completionLabel setText: completion];
            CGFloat inputLineWidth = frame.size.width;
            CGSize textSize = [completion sizeWithFont:[self font]];
            CGFloat clearButtonWidth = [self clearButtonRectForBounds: [self bounds]].size.width+1;
            CGFloat textWidth = prevString ? [prevString sizeWithFont: [self font]].width : 0;
            if (textWidth + textSize.width < inputLineWidth - clearButtonWidth)
                frame.origin.x = textWidth;
            else
                frame.origin.x = inputLineWidth - textSize.width - clearButtonWidth;
            frame.size = textSize;
            frame.origin.y = -frame.size.height-4;
            frame = [self convertRect:frame toView:parentView];
            [m_completionLabel setOrigin: frame.origin];
            [parentView addSubview: m_completionLabel];
        } else {
            [m_completionLabel removeFromSuperview];
            [m_completionLabel setText: nil];
        }
    }
    return result;
}

-(BOOL)keyboardInputShouldDelete:(id)sender {
    if (m_completionLabel) {
        [m_completionLabel removeFromSuperview];
        [m_completionLabel setText: nil];
    }
    if ((ipzAllowInput & kIPZAllowInput)) {
        if ((ipzAllowInput & kIPZNoEcho) || cwin == 1) {
            [self setText: @""];
            iosif_feed_input([NSString stringWithFormat:@"%c", ZC_BACKSPACE]);
        }
        if (self.text.length == 1)
            m_lastCharDeleted = YES;
    	[self updatePosition];
    }
  
    return (BOOL)[super keyboardInputShouldDelete:sender];
    
}

- (NSArray *) keyCommands
{
    NSArray<UIKeyCommand*> *ret = nil;
    if ((ipzAllowInput & kIPZNoEcho)) {
        UIKeyCommand *upArrow = [UIKeyCommand keyCommandWithInput: UIKeyInputUpArrow modifierFlags: 0 action: @selector(upArrow:)];
        UIKeyCommand *downArrow = [UIKeyCommand keyCommandWithInput: UIKeyInputDownArrow modifierFlags: 0 action: @selector(downArrow:)];
        UIKeyCommand *leftArrow = [UIKeyCommand keyCommandWithInput: UIKeyInputLeftArrow modifierFlags: 0 action: @selector(leftArrow:)];
        UIKeyCommand *rightArrow = [UIKeyCommand keyCommandWithInput: UIKeyInputRightArrow modifierFlags: 0 action: @selector(rightArrow:)];
        UIKeyCommand *escapeKey = [UIKeyCommand keyCommandWithInput: UIKeyInputEscape modifierFlags: 0 action: @selector(escapeKey:)];
        UIKeyCommand *ctrlP = [UIKeyCommand keyCommandWithInput: @"p" modifierFlags: UIKeyModifierControl action: @selector(upArrow:)];
        UIKeyCommand *ctrlN = [UIKeyCommand keyCommandWithInput: @"n" modifierFlags: UIKeyModifierControl action: @selector(downArrow:)];
        UIKeyCommand *ctrlB = [UIKeyCommand keyCommandWithInput: @"b" modifierFlags: UIKeyModifierControl action: @selector(leftArrow:)];
        UIKeyCommand *ctrlF = [UIKeyCommand keyCommandWithInput: @"f" modifierFlags: UIKeyModifierControl action: @selector(rightArrow:)];
        ret = @[upArrow, downArrow, leftArrow, rightArrow, escapeKey, ctrlP, ctrlN, ctrlB, ctrlF];
    } else {
        UIKeyCommand *upArrow = [UIKeyCommand keyCommandWithInput: UIKeyInputUpArrow modifierFlags: 0 action: @selector(upArrow:)];
        UIKeyCommand *downArrow = [UIKeyCommand keyCommandWithInput: UIKeyInputDownArrow modifierFlags: 0 action: @selector(downArrow:)];
        UIKeyCommand *ctrlP = [UIKeyCommand keyCommandWithInput: @"p" modifierFlags: UIKeyModifierControl action: @selector(upArrow:)];
        UIKeyCommand *ctrlN = [UIKeyCommand keyCommandWithInput: @"n" modifierFlags: UIKeyModifierControl action: @selector(downArrow:)];
        ret = @[upArrow, downArrow, ctrlP, ctrlN];
    }
    if (@available(iOS 15.0, *)) {
        for (UIKeyCommand *k in ret)
            k.wantsPriorityOverSystemBehavior = YES;
    }
    return ret;
}

- (void) upArrow: (UIKeyCommand *) keyCommand
{
    if ((ipzAllowInput & kIPZNoEcho))
        iosif_feed_input(@ZC_IPS_ARROW_UP);
    else
        self.text = [m_inputHelper getPrevHistoryItem];
}

- (void) downArrow: (UIKeyCommand *) keyCommand
{
    if ((ipzAllowInput & kIPZNoEcho))
        iosif_feed_input(@ZC_IPS_ARROW_DOWN);
    else
        self.text = [m_inputHelper getNextHistoryItem];
}

- (void) leftArrow: (UIKeyCommand *) keyCommand
{
    iosif_feed_input(@ZC_IPS_ARROW_LEFT);
}

- (void) rightArrow: (UIKeyCommand *) keyCommand
{
    iosif_feed_input(@ZC_IPS_ARROW_RIGHT);
}
- (void) escapeKey: (UIKeyCommand *) keyCommand
{
    iosif_feed_input(@"\x1b");
}

@end
