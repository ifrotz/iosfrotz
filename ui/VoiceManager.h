//
//  VoiceManager.h
//  Frotz
//
//  Voice mode manager: TTS (text-to-speech) and STT (speech-to-text)
//  for hands-free interactive fiction gameplay.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <Speech/Speech.h>
#import "VoiceFeatures.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const FrotzVoiceAvailabilityDidChangeNotification;

@class RichTextView;

typedef NS_ENUM(NSInteger, VoiceMode) {
    VoiceModeOff = 0,
    VoiceModeTTSOnly,
    VoiceModeSTTOnly,
    VoiceModeBoth
};

typedef NS_ENUM(NSInteger, VoiceCommandConfirmationMode) {
    VoiceCommandConfirmationOff = 0,
    VoiceCommandConfirmationAsNeeded,
    VoiceCommandConfirmationAlways
};

typedef NS_ENUM(NSInteger, VoiceFeedback) {
    VoiceFeedbackReady = 0,
    VoiceFeedbackStopped,
    VoiceFeedbackNavigationPaused,
    VoiceFeedbackError
};

@protocol VoiceManagerDelegate <NSObject>
// TTS callbacks
- (void)voiceManagerDidStartSpeaking;
- (void)voiceManagerDidFinishSpeaking;
- (void)voiceManagerHighlightRange:(NSRange)range inView:(RichTextView *)view;
- (void)voiceManagerDidClearHighlight;

// STT callbacks
- (void)voiceManagerDidRecognizeText:(NSString *)text isFinal:(BOOL)isFinal;
- (void)voiceManagerDidStartListening;
- (void)voiceManagerDidStopListening;
- (void)voiceManagerSTTError:(NSError *)error;
@optional
- (void)voiceManagerDidPauseForVoiceOverDiscardingInput:(BOOL)discardInput;
// Called after a response finishes; keep audio active only for a scheduled handoff.
- (BOOL)voiceManagerWillResumeListening;
@end

@interface VoiceManager : NSObject <AVSpeechSynthesizerDelegate>

+ (instancetype)shared;

// State
@property (nonatomic) BOOL narrationAvailable; // preferences default YES; no automatic start
@property (nonatomic) BOOL dictationAvailable;
@property (nonatomic) BOOL narrationSelected; // toolbar mode, retained when unavailable
@property (nonatomic) BOOL dictationSelected;
@property (nonatomic) VoiceMode voiceMode;
@property (nonatomic) float speechRate;        // multiplier, default 1.0
@property (nonatomic, copy, nullable) NSString *speechVoiceIdentifier; // nil means Automatic
@property (nonatomic, readonly, nullable) AVSpeechSynthesisVoice *speechVoice;
@property (nonatomic, readonly, nullable) AVSpeechSynthesisVoice *automaticSpeechVoice;
@property (nonatomic, readonly) NSString *speechVoiceDescription;
@property (nonatomic, copy, nullable) NSString *speechRecognitionLanguage; // nil means Automatic
@property (nonatomic, readonly) NSString *effectiveRecognitionLanguage;
@property (nonatomic, copy, nullable) NSString *storyLanguage; // current story metadata, not persisted
- (void)configureForStoryAtPath:(nullable NSString *)path;
+ (NSString *)qualityDescriptionForVoice:(AVSpeechSynthesisVoice *)voice;
@property (nonatomic, readonly) BOOL isSpeaking;
@property (nonatomic, readonly) BOOL isListening;
@property (nonatomic, readonly) BOOL ttsEnabled;
@property (nonatomic, readonly) BOOL sttEnabled;
@property (nonatomic, readonly, getter=isVoiceOverEnabled) BOOL voiceOverEnabled;
@property (nonatomic, readonly) BOOL voiceOverNavigationPaused;
- (void)resumeAfterVoiceOverNavigation;
- (void)pauseForVoiceOverNavigation;
// Coordinates the existing screen-reader narration when app narration is off.
- (void)speakAccessibilityText:(NSString *)text;
// Replay contains only output already narrated for this story, never UI prompts.
@property (nonatomic, readonly, copy, nullable) NSString *lastStoryResponse;
- (void)rememberStoryResponse:(NSString *)text;
- (BOOL)replayLastStoryResponse;
- (void)playVoiceFeedback:(VoiceFeedback)feedback;

@property (nonatomic, weak, nullable) id<VoiceManagerDelegate> delegate;

// The view currently being read aloud (for word highlighting)
@property (nonatomic, weak, nullable) RichTextView *activeView;

// TTS
- (void)speakText:(NSString *)text inView:(RichTextView *)view;
- (void)stopSpeaking;
- (void)pauseSpeaking;
- (void)resumeSpeaking;

// Spoiler-safe command context comes only from displayed text and player input.
@property (nonatomic) BOOL speakCommandConfirmations; // persisted, default YES; VoiceOver announces independently
@property (nonatomic) VoiceCommandConfirmationMode commandConfirmationMode; // persisted, default Off
@property (nonatomic, readonly) NSString *commandConfirmationDescription;
@property (nonatomic, readonly) BOOL recognizedCommandNeedsConfirmation; // uncertainty, independent of the preference
@property (nonatomic) BOOL recognizingConfirmation;
@property (nonatomic) BOOL recognizingCharacterInput;
- (void)updateCommandContextWithVisibleText:(NSString *)text;
- (void)rememberPlayerCommand:(NSString *)text;
+ (NSArray<NSString *> *)confirmationWordsForLanguage:(NSString *)language;
+ (nullable NSString *)confirmationActionForText:(NSString *)text language:(NSString *)language;
- (void)speakConfirmationPrompt:(NSString *)text; // also works when narration is disabled

// STT
- (void)startListening;
- (void)stopListening;

// Permissions
- (void)requestSTTPermissionsWithCompletion:(void (^)(BOOL granted))completion;

// Persistence
- (void)savePreferences;
- (void)loadPreferences;

// Translation for char-input mode
- (NSString *)translateForCharInput:(NSString *)spokenText;

@end

NS_ASSUME_NONNULL_END
