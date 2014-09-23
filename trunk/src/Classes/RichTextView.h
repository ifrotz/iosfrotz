//  MyUITextView.h
//  TextViewBug
#import <UIKit/UIKit.h>
#import "WordSelectionProtocol.h"
#import "UIFontExt.h"
#import "RichTextStyle.h"

@class RichTextView;
@class RichTextAE;

@interface RichTextTile : UIView {
    RichTextView *m_textView;
}
@property(nonatomic, assign) RichTextView *textView;
@end

@protocol RTSelected
-(void)textSelected:(NSString*)text animDuration:(CGFloat)duration hilightView:(UIView <WordSelection>*)view;
@end

typedef UIImage *(*RichDataGetImageCallback)(int imageNum);

@interface RichTextView : UIScrollView <UIScrollViewDelegate> {
    NSMutableString *m_text;
    CGFloat m_fontSize, m_fixedFontSize;
    CGSize m_tileSize;
    int m_numLines;
    NSMutableArray *m_textRuns;   // text fragments
    NSMutableArray *m_textStyles; // bit set, bold, italic, etc.
    NSMutableArray *m_colorIndex; // fg/bg color for run
    NSMutableArray *m_hyperlinks;

    NSMutableArray *m_textPos;     // beginning point of each text run
    NSMutableArray *m_textLineNum; // which line (0..n) each run starts on

    NSMutableArray *m_lineYPos;    // Y position of each line; indexed by line number, not run
    NSMutableArray *m_lineWidth;    // width of each text line
    NSMutableArray *m_lineDescent;  // height of line below text origin

    NSMutableArray *m_imageviews;  // inline image views container
    NSMutableArray *m_imageIDs;
    
    NSMutableArray *m_colorArray;
    UIColor *m_fgColor, *m_bgColor;
    UIColor *m_currBgColor; // weak ref
    int m_firstVisibleTextRunIndex;
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
    unsigned int m_currentTextColorIndex, m_currentBGColorIndex;
    int m_hyperlinkIndex;
    
    NSMutableSet *m_reusableTiles;    
    UIView *m_tileContainerView;
    CGFloat m_fontHeight, m_fixedFontHeight, m_fixedFontWidth, m_fontMinWidth, m_fontMaxWidth;
    CGFloat m_firstVisibleRow, m_firstVisibleColumn, m_lastVisibleRow, m_lastVisibleColumn;
    UIViewController<UIScrollViewDelegate> *m_controller;
    
    CGFloat m_origY;
    BOOL m_prevLineNotTerminated;
    
    NSMutableArray *m_accessibilityElements;
    int m_lastAEIndexAccessed, m_lastAEIndexAnnounced;
    
    int m_selectedRun;
    NSRange m_selectedColumnRange;
    UILabelWA *m_selectionView;
    BOOL m_selectionDisabled;
    BOOL m_hyperlinkTest;
    
    NSObject<RTSelected>* m_selectionDelegate;
    
    BOOL m_freezeDisplay;
    CGRect m_delayedFrame;
    CGRect m_origFrame;
    RichDataGetImageCallback m_richDataGetImageCallback;
}

@property(nonatomic, retain) NSString *text;
@property(nonatomic, assign) CGSize tileSize;
@property(nonatomic, readonly) NSMutableArray* textRuns;
@property(nonatomic, assign) CGPoint lastPt;
@property(nonatomic, assign) RichTextStyle textStyle;
@property(nonatomic, assign) unsigned int textColorIndex;
@property(nonatomic, assign) unsigned int bgColorIndex;
@property(nonatomic, assign) int hyperlinkIndex;
@property(nonatomic, assign) UIViewController<UIScrollViewDelegate>* controller;
@property(nonatomic, assign) unsigned int topMargin;
@property(nonatomic, assign) unsigned int leftMargin;
@property(nonatomic, assign) unsigned int rightMargin;
@property(nonatomic, assign) unsigned int bottomMargin;
@property(nonatomic, assign) unsigned int lineSpacing;
@property(nonatomic, assign) int lastAEIndexAccessed;
//@property(nonatomic, assign) int selectedRun;
//@property(nonatomic, assign) NSRange selectedColumnRange;
@property(nonatomic, assign) NSObject<RTSelected>* selectionDelegate;
@property(nonatomic, assign) BOOL selectionDisabled;
@property(nonatomic, assign, getter=displayFrozen) BOOL freezeDisplay;
@property(nonatomic, assign) RichDataGetImageCallback richDataGetImageCallback;

- (RichTextView*)initWithFrame: (CGRect)frame;
- (RichTextView*)initWithFrame: (CGRect)frame border:(BOOL)border;
- (void)clearSelection;
- (UIFont*)fontForStyle: (RichTextStyle)style;
- (void) drawRect:(CGRect)rect inView:(RichTextTile*)view;
- (RichTextTile *)tileForRow:(int)row column:(int)column;
- (BOOL)findHotText:(NSString *)text charOffset:(int)charsDone pos:(CGPoint)pos minX:(CGFloat)minXPos hotPoint:(CGPoint*)hotPoint font:(UIFont*)font fontHeight:(CGFloat)fontHeight
 width:(CGFloat) width;
- (void)updateLine:(int)lineNum withYPos:(CGFloat)yPos;
- (void)updateLine:(int)lineNum withDescent:(CGFloat)desent;
- (void)updateLine:(int)lineNum width:(CGFloat)width;
- (BOOL)wordWrapTextSize:(NSString*)text atPoint:(CGPoint*)pos font:(UIFont*)font style:(RichTextStyle)style fgColor:(UIColor*)fgColor
   bgColor:(UIColor*)bgColor withRect:(CGRect)rect  lineNumber:(int)lineNum nextPos:(CGPoint*)nextPos hotPoint:(CGPoint*)hotPoint doDraw:(BOOL)doDraw;
- (void)appendText:(NSString*)text;
- (void)appendImage:(int)imageNum withAlignment:(int)imageAlign;
- (BOOL)placeImage:(UIImage*)image imageView:(UIImageView*)imageView atPoint:(CGPoint)pt withAlignment:(int)imageAlign prevLineY:(CGFloat)prevY newTextPoint:(CGPoint*)newTextPoint inDraw:(BOOL)inDraw textStyle:(RichTextStyle)textStyle;
- (int) getTextRunAtPoint:(CGPoint)touchPoint;
- (int)hyperlinkAtPoint:(CGPoint)point;
- (void)populateZeroHyperlinks;
- (RichTextTile *)dequeueReusableTile;
- (void)prepareForKeyboardShowHide;
- (void)rememberTopLineForReflow;
- (UIColor*)getCurrentTextColor;
- (void)resetColors;
- (void)resetMargins;
- (void)setNiceMargins:(BOOL)reflow;
- (void)setNoMargins;
- (void)layoutSubviews;
- (void)reloadData;
- (void)reset;
- (void)clear;
- (void)reflowText;
- (void)reloadImages;
- (void)dealloc;
- (void)setDelegate:(UIViewController<UIScrollViewDelegate>*)delegate;
- (UIViewController<UIScrollViewDelegate>*)delegate;
- (void)setFont:(UIFont*)font;
- (void)setFixedFont:(UIFont*)newFont;
- (UIFont*)font;
- (UIFont*)fixedFont;
- (CGSize) fixedFontSize;
- (BOOL)setFontFamily:(NSString*)fontFamily size:(int)newSize;
- (BOOL)setFixedFontFamily:(NSString*)familyName size:(int)newSize;
- (void)setTextColor:(UIColor*)color;
- (CGRect)visibleRect;
- (int)getOrAllocColorIndex:(UIColor*)color;
- (void)populateAccessibilityElements;
- (void)clearAE;
- (RichTextAE*)updateAE;
- (void)appendAE;
- (void)markWaitForInput;
- (NSArray*)getTextPos;
- (NSDictionary*)getSaveDataDict;
- (void)restoreFromSaveDataDict: (NSDictionary*)saveData;
- (CGPoint)cursorPoint;
@end



