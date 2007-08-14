#import <UITextTraitsClientProtocol.h>

@protocol UIKeyboardInput <UITextTraitsClient>
- (void)deleteBackward;
- (void)insertText:(id)fp8;
- (void)replaceCurrentWordWithText:(id)fp8;
- (void)setMarkedText:(id)fp8;
- (id)markedText;
- (unsigned short)characterInRelationToCaretSelection:(int)fp8;
- (unsigned short)characterBeforeCaretSelection;
- (unsigned short)characterAfterCaretSelection;
- (struct __GSFont *)fontForCaretSelection;
- (struct CGColor *)textColorForCaretSelection;
- (struct CGRect)rectContainingCaretSelection;
- (id)wordRangeContainingCaretSelection;
- (id)wordContainingCaretSelection;
- (id)wordInRange:(id)fp8;
- (void)expandSelectionToStartOfWordContainingCaretSelection;
- (int)wordOffsetInRange:(id)fp8;
- (BOOL)spaceFollowsWordInRange:(id)fp8;
- (id)previousNGrams:(unsigned int)fp8;
- (struct _NSRange)selectionRange;
- (BOOL)hasSelection;
- (BOOL)selectionAtDocumentStart;
- (BOOL)selectionAtSentenceStart;
- (BOOL)selectionAtWordStart;
- (BOOL)rangeAtSentenceStart:(id)fp8;
- (void)markCurrentWordForAutoCorrection:(id)fp8 correction:(id)fp12;
- (void)moveBackward:(unsigned int)fp8;
- (void)moveForward:(unsigned int)fp8;
- (void)selectAll;
- (void)setText:(id)fp8;
- (id)text;
- (void)updateSelectionWithPoint:(struct CGPoint)fp8;
- (void)setCaretChangeListener:(id)fp8;
- (struct CGRect)caretRect;
- (struct CGRect)convertCaretRect:(struct CGRect)fp8;
- (id)keyboardInputView;
- (BOOL)isShowingPlaceholder;
- (void)setupPlaceholderTextIfNeeded;
- (BOOL)isProxyFor:(id)fp8;
@end

