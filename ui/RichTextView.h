//  MyUITextView.h
//  TextViewBug
#import <UIKit/UIKit.h>
#import "WordSelectionProtocol.h"
#import "RichTextStyle.h"

NS_ASSUME_NONNULL_BEGIN

@class RichTextView;
@class RichTextAE;

@interface RichTextTile : UIView {
    RichTextView *__weak m_textView;
}
@property(nonatomic, weak) RichTextView *textView;
@end

@protocol RTSelected <NSObject>
-(void)textSelected:(NSString*)text animDuration:(CGFloat)duration hilightView:(UIView <WordSelection>*)view;
@end

typedef UIImage *__nonnull(*__nonnull RichDataGetImageCallback)(int imageNum);

@interface RichTextView : UIScrollView <UIScrollViewDelegate> {
    NSMutableString *m_text;
    CGFloat m_fontSize, m_fixedFontSize;
    CGSize m_tileSize;
    NSInteger m_numLines;
    NSMutableArray *m_textRuns;   // text fragments
    NSMutableArray *m_textStyles; // bit set, bold, italic, etc.
    NSMutableArray *m_colorIndex; // fg/bg color for run
    NSMutableArray *m_hyperlinks;

    NSMutableArray<NSValue*> *m_textPos;     // beginning point of each text run
    NSMutableArray *m_textLineNum; // which line (0..n) each run starts on

    NSMutableArray *m_lineYPos;    // Y position of each line; indexed by line number, not run
    NSMutableArray *m_lineWidth;    // width of each text line
    NSMutableArray *m_lineDescent;  // height of line below text origin

    NSMutableArray *m_imageviews;  // inline image views container
    NSMutableArray *m_imageIDs;
    
    NSMutableArray *m_colorArray;
    UIColor *m_fgColor, *m_bgColor;
    UIColor *m_currBgColor; // weak ref
    NSInteger m_firstVisibleTextRunIndex;
    CGFloat m_savedTopYOffset;    
    
    unsigned int m_topMargin, m_leftMargin, m_rightMargin, m_bottomMargin;
    unsigned int m_tempLeftMargin, m_tempRightMargin;
    unsigned int m_tempLeftYThresh, m_tempRightYThresh;
    unsigned int m_extraLineSpacing;

    CGPoint m_prevPt, m_lastPt;
    
    UIFont *m_normalFont, *m_boldFont;
    UIFont *m_italicFont, *m_boldItalicFont;
    UIFont *m_fixedNormalFont, *m_fixedBoldFont;
    UIFont *m_fixedItalicFont, *m_fixedBoldItalicFont;
    
    RichTextStyle m_currentTextStyle;
    NSUInteger m_currentTextColorIndex, m_currentBGColorIndex;
    NSInteger m_hyperlinkIndex;
    
    NSMutableSet *m_reusableTiles;    
    UIView *m_tileContainerView;
    CGFloat m_fontHeight, m_fixedFontHeight, m_fixedFontWidth, m_fontMinWidth, m_fontMaxWidth;
    CGFloat m_firstVisibleRow, m_firstVisibleColumn, m_lastVisibleRow, m_lastVisibleColumn;
    UIViewController<UIScrollViewDelegate> *__weak m_controller;
    
    CGFloat m_origY;
    BOOL m_prevLineNotTerminated;
    
    NSMutableArray *m_accessibilityElements;
    NSInteger m_lastAEIndexAccessed, m_lastAEIndexAnnounced;
    
    NSInteger m_selectedRun;
    NSRange m_selectedColumnRange;
    UILabelWA *m_selectionView;
    BOOL m_selectionDisabled;
    BOOL m_hyperlinkTest;
    
    id<RTSelected> __weak m_selectionDelegate;
    
    BOOL m_freezeDisplay;
    CGRect m_delayedFrame;
    CGRect m_origFrame;
    RichDataGetImageCallback m_richDataGetImageCallback;
}

@property(nonatomic, strong) NSString *text;
@property(nonatomic, assign) CGSize tileSize;
@property(nonatomic, readonly) NSMutableArray* textRuns;
@property(nonatomic, assign) CGPoint lastPt;
@property(nonatomic, assign) RichTextStyle textStyle;
@property(nonatomic, assign) NSUInteger textColorIndex;
@property(nonatomic, assign) NSUInteger bgColorIndex;
@property(nonatomic, assign) NSInteger hyperlinkIndex;
@property(nonatomic, weak) UIViewController<UIScrollViewDelegate>* controller;
@property(nonatomic, assign) unsigned int topMargin;
@property(nonatomic, assign) unsigned int leftMargin;
@property(nonatomic, assign) unsigned int rightMargin;
@property(nonatomic, assign) unsigned int bottomMargin;
@property(nonatomic, assign) unsigned int lineSpacing;
@property(nonatomic, assign) NSInteger lastAEIndexAccessed;
//@property(nonatomic, assign) NSInteger selectedRun;
//@property(nonatomic, assign) NSRange selectedColumnRange;
@property(nonatomic, weak) id<RTSelected> selectionDelegate;
@property(nonatomic, assign) BOOL selectionDisabled;
@property(nonatomic, assign, getter=displayFrozen) BOOL freezeDisplay;
@property(nonatomic, assign) RichDataGetImageCallback richDataGetImageCallback;

- (RichTextView*)initWithFrame: (CGRect)frame NS_DESIGNATED_INITIALIZER;
- (RichTextView*)initWithFrame: (CGRect)frame border:(BOOL)border;
-(instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
-(instancetype)initWithCoder:(NSCoder *)aDecoder NS_UNAVAILABLE;
- (void)clearSelection;
- (UIFont*)fontForStyle: (RichTextStyle)style;
- (void) drawRect:(CGRect)rect inView:(RichTextTile*)view;
- (RichTextTile *)tileForRow:(int)row column:(int)column;
- (BOOL)findHotText:(NSString *)text charOffset:(int)charsDone pos:(CGPoint)pos minX:(CGFloat)minXPos hotPoint:(CGPoint*)hotPoint font:(UIFont*)font fontHeight:(CGFloat)fontHeight
 width:(CGFloat) width;
- (void)updateLine:(NSInteger)lineNum withYPos:(CGFloat)yPos;
- (void)updateLine:(NSInteger)lineNum withDescent:(CGFloat)desent;
- (void)updateLine:(NSInteger)lineNum width:(CGFloat)width;
- (BOOL)wordWrapTextSize:(NSString*)text atPoint:(CGPoint*)pos font:(UIFont*)font style:(RichTextStyle)style fgColor:(nullable UIColor*)fgColor
   bgColor:(nullable UIColor*)bgColor withRect:(CGRect)rect  lineNumber:(NSInteger)lineNum nextPos:(CGPoint*)nextPos hotPoint:(nullable CGPoint*)hotPoint doDraw:(BOOL)doDraw;
- (void)appendText:(NSString*)text;
- (void)appendImage:(int)imageNum withAlignment:(int)imageAlign;
- (BOOL)placeImage:(UIImage*)image imageView:(nullable UIImageView*)imageView atPoint:(CGPoint)pt withAlignment:(int)imageAlign prevLineY:(CGFloat)prevY newTextPoint:(CGPoint*)newTextPoint inDraw:(BOOL)inDraw textStyle:(RichTextStyle)textStyle;
- (NSInteger) getTextRunAtPoint:(CGPoint)touchPoint;
- (int)hyperlinkAtPoint:(CGPoint)point;
- (void)populateZeroHyperlinks;
@property (nonatomic, readonly, strong) RichTextTile *dequeueReusableTile;
- (void)prepareForKeyboardShowHide;
- (void)rememberTopLineForReflow;
@property (nonatomic, getter=getCurrentTextColor, readonly, copy) UIColor *currentTextColor;
- (void)resetColors;
- (void)resetMargins;
- (void)setNiceMargins:(BOOL)reflow;
- (void)setNoMargins;
- (void)layoutSubviews;
- (void)reloadData;
- (void)reset;
- (void)clear;
- (void)reflowText;
- (void)repositionAfterReflow;
- (void)reloadImages;
@property (nonatomic, weak) UIViewController<UIScrollViewDelegate> *delegate;
@property (nonatomic, copy) UIFont *font;
@property (nonatomic, copy) UIFont *fixedFont;
@property (nonatomic, readonly) CGSize fixedFontSize;
- (BOOL)setFontBase:(UIFont*)fontBase size:(NSInteger)newSize;
- (BOOL)setFixedFontBase:(UIFont*)fontBase size:(NSInteger)newSize;
- (void)setFontSize:(CGFloat)newFontSize;
@property (nonatomic, strong) UIColor *textColor;
@property (nonatomic, readonly) CGRect visibleRect;
- (NSUInteger)getOrAllocColorIndex:(UIColor*)color;
- (void)populateAccessibilityElements;
- (void)clearAE;
- (RichTextAE *)updateAE;
- (void)appendAE;
- (void)markWaitForInput;
@property (nonatomic, getter=getTextPos, readonly, copy) NSArray<NSValue*> *textPos;
@property (nonatomic, getter=getSaveDataDict, readonly, copy) NSDictionary *saveDataDict;
- (void)restoreFromSaveDataDict: (NSDictionary*)saveData;
@property (nonatomic, readonly) CGPoint cursorPoint;
@end

NS_ASSUME_NONNULL_END


