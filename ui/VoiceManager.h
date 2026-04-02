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
