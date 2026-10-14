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

NS_ASSUME_NONNULL_BEGIN

@class RichTextView;

typedef NS_ENUM(NSInteger, VoiceMode) {
    VoiceModeOff = 0,
    VoiceModeTTSOnly,
    VoiceModeSTTOnly,
    VoiceModeBoth
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
@end

@interface VoiceManager : NSObject <AVSpeechSynthesizerDelegate>

+ (instancetype)shared;

// State
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

@property (nonatomic, weak, nullable) id<VoiceManagerDelegate> delegate;

// The view currently being read aloud (for word highlighting)
@property (nonatomic, weak, nullable) RichTextView *activeView;

// TTS
- (void)speakText:(NSString *)text inView:(RichTextView *)view;
- (void)stopSpeaking;
- (void)pauseSpeaking;
- (void)resumeSpeaking;

// Spoiler-safe command context comes only from displayed text and player input.
@property (nonatomic, readonly) BOOL recognizedCommandNeedsConfirmation;
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
