//
//  StoryDictationController.h
//  Frotz
//
//  Created by Craig Smith on 6/19/23.
//

#import <UIKit/UIKit.h>
#import "iosfrotz.h"

#if EnableStoryDictation
#import <Speech/Speech.h>
#import "InputHelper.h"

NS_ASSUME_NONNULL_BEGIN
@class SFSpeechAudioBufferRecognitionRequest, SFSpeechRecognitionTask, StoryDictationController;

// Whether the recognizer can take a request right now; see availability.
typedef NS_ENUM(NSInteger, StoryDictationAvailability) {
    kStoryDictationAvailable,
    kStoryDictationRecognizerUnavailable,   // the system recognizer is off: Siri and Dictation disabled, assets missing
    kStoryDictationOnDeviceUnsupported,     // this device can't recognize the locale offline, which is all we ask for
};

// Told whenever listening starts, pauses, resumes or stops, whether asked to or on its own (the
// audio engine failing to start, say); read isListening and isPaused for the new state. Lets the
// mic button show what the recognizer is actually doing. Also told when the system recognizer
// goes away while dictation is on, after listening has been stopped, so the user can be told;
// and when the microphone couldn't be started at all, so a tap on the mic never fails silently.
@protocol StoryDictationStateDelegate <NSObject>
-(void)dictationListeningStateChanged:(StoryDictationController*)controller;
-(void)dictationBecameUnavailable:(StoryDictationController*)controller;
-(void)dictationFailedToStart:(StoryDictationController*)controller;
@end

// Runs on-device speech recognition on the microphone and hands the transcriptions to its
// delegate (the input line). Not a view controller: it has no UI of its own.
@interface StoryDictationController : NSObject <SFSpeechRecognizerDelegate, SFSpeechRecognitionTaskDelegate>
{
    SFSpeechRecognizer *m_sfrecog;
    SFSpeechAudioBufferRecognitionRequest *m_sfRecogRequest;
    AVAudioEngine *m_audioEngine;
    AVAudioSession *m_audioSession;
    SFSpeechRecognitionTask *m_recognitionTask;
    
    NSString *m_storyLanguage;
    NSString *m_recognitionLocaleIdentifier; // the locale m_sfrecog was made for; see setStoryLanguage:
    NSString *m_currentTranscription;
    NSTimer *m_speechCommitTimer; // fires after a stretch of silence; see restartSilenceTimer
    NSTimer *m_longIdleTimer;     // stops listening after a long stretch with no speech at all; see restartLongIdleTimer
    NSTimeInterval m_silenceInterval;
    BOOL m_isPaused;
    BOOL m_resumeAfterInterruption; // an audio interruption stopped listening; start again if told it has ended
    BOOL m_tapInstalled;   // the input node has our tap, in the format current when it was installed
    id<FrotzInputDelegate> __weak m_delegate;
    id<StoryDictationStateDelegate> __weak m_stateDelegate;
}

-(instancetype)init NS_DESIGNATED_INITIALIZER;

// Check before listenForSpeech; a request made while the recognizer is unavailable just fails.
-(StoryDictationAvailability)availability;
-(void)listenForSpeech;
// The player is doing something with the story (scrolling, a touch that may become a double tap
// on a word): an utterance waiting out the silence gets the full interval again, so the word has
// time to land in the input line before the final result looks for edits.
-(void)deferCommit;
-(void)pauseListening;
-(BOOL)isListening;
-(BOOL)isPaused;
// Listening is off but due back without the player asking: paused by the UI, or taken by an audio
// interruption that may hand it back. Distinguishes a pause from a stop for the cues.
-(BOOL)willResume;
-(void)stopListening;

@property (nonatomic, weak) id<FrotzInputDelegate> delegate;
@property (nonatomic, weak) id<StoryDictationStateDelegate> stateDelegate;

// How long the speaker must be quiet before what was said is accepted as a command. The settings
// page's "Dictation Delay"; 0.8s unless set. Takes effect from the next utterance.
@property (nonatomic) NSTimeInterval silenceInterval;

// The language the story is written in, as a language tag ("fr", "de-DE"), or nil for unknown.
// The player must speak the story's language, whatever the device is set to, so this and not the
// device locale picks the recognizer's locale: the supported locale matching the tag, the
// device's regional variant of it when the tag names no region, or US English when nothing
// matches or nothing is known. Setting a language that changes the locale stops listening.
// The owner finds the language with languageFromBlorbAtPath: and languageOfText:.
@property (nonatomic, copy, nullable) NSString *storyLanguage;

// The recognizer's current locale, and the name of its language in the user's language
// ("English", "Français"), for messages about it.
@property (nonatomic, readonly) NSString *recognitionLocaleIdentifier;
@property (nonatomic, readonly) NSString *recognitionLanguageName;

// The language named in the iFiction record of a Blorb story file (the IFmd chunk), or nil when
// the file isn't a Blorb or carries none. Most story files have none.
+(nullable NSString*)languageFromBlorbAtPath:(nullable NSString*)path;
// The language a stretch of story text is written in, judged on device, or nil when there is too
// little text to say or the verdict is doubtful. A page of output is plenty.
+(nullable NSString*)languageOfText:(nullable NSString*)text;
// The identifier of the recognizer locale to use for a language tag, as storyLanguage picks it,
// or nil when speech recognition doesn't support the language.
+(nullable NSString*)recognitionLocaleForLanguage:(NSString*)language;
@end

// Audible and felt cues for the state changes the mic button shows; the main view controller
// decides which to play from the state delegate's callbacks.
typedef NS_ENUM(NSInteger, StoryDictationCue) {
    kStoryDictationCueStarted,  // the player started listening: two quick high notes
    kStoryDictationCueResumed,  // listening came back by itself (notes page closed, a call ended): one high note
    kStoryDictationCuePaused,   // listening is off but will come back by itself: one low note
    kStoryDictationCueStopped,  // listening is over until the player starts it again: two quick low notes
    kStoryDictationCueCount
};

// Plays each cue as a short tone and a haptic together. The tones are WAV files in the app bundle
// played through System Sound Services, so they need no audio session of ours and don't light the
// mic indicator when played after dictation has stopped; the haptic covers a phone in silent mode
// (iOS gives no way to ask about the ring/silent switch, and tones through the recording session
// ignore it anyway).
@interface StoryDictationCuePlayer : NSObject
-(void)playCue:(StoryDictationCue)cue;
@end

// The words a story has printed, for priming the recognizer with what the player is likely to say
// and for correcting what it hears. Every word of every chunk of story output is noted, with how
// often and how recently; nothing is forgotten when the story clears its window, because a game's
// vocabulary only grows. The owner (StoryMainViewController) resets it when a different story
// starts and rebuilds it from the restored text after an autorestore. Words are lower-cased.
// Whether the game actually knows a word (its dictionary) is decided by the caller's block, at
// use: dictionary lookups go through the interpreter's buffers and are only safe while it waits
// for input, which is when these are asked.
@interface StoryVocabulary : NSObject
-(void)noteOutput:(NSString*)text;
-(void)reset;
@property (nonatomic, readonly) NSUInteger count;
// The most recently printed words that `known` accepts, most recent first, up to max. A word
// printed often ranks somewhat above where its last appearance alone would put it.
-(NSArray<NSString*>*)recentWords:(NSUInteger)max known:(BOOL (^)(NSString *word))known;
// The printed word nearest to `word` that `known` accepts: same first letter, apostrophes and
// hyphens ignored, within one edit for words of up to four letters or two beyond; failing that,
// one that sounds the same (equal Soundex code), closest in spelling. Ties go to the more
// recently printed. nil when nothing is near enough.
-(nullable NSString*)nearestKnownWordTo:(NSString*)word known:(BOOL (^)(NSString *word))known;
@end

NS_ASSUME_NONNULL_END
#endif // EnableStoryDictation
