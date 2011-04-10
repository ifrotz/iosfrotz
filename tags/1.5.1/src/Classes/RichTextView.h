//  MyUITextView.h
//  TextViewBug
#import <UIKit/UIKit.h>
#import "WordSelectionProtocol.h"
#import "UIFontExt.h"

@class RichTextView;
@class RichTextAE;

@interface RichTextTile : UIView {
    RichTextView *m_textView;
}
@property(nonatomic, assign) RichTextView *textView;
@end

typedef enum { kFTNormal=0, kFTBold=1, kFTItalic=2, kFTFixedWidth=4, kFTFontStyleMask=7, kFTReverse=8, kFTNoWrap=16,  } RichTextStyle;

@protocol RTSelected
-(void)textSelected:(NSString*)text animDuration:(CGFloat)duration hilightView:(UIView <WordSelection>*)view;
@end


@interface RichTextView : UIScrollView <UIScrollViewDelegate> {
    NSMutableString *m_text;
    CGFloat m_fontSize, m_fixedFontSize;
    CGSize m_lastSize;
    CGSize m_tileSize;
    int m_numLines;
    NSMutableArray *m_textRuns;
    NSMutableArray *m_textPos;
    NSMutableArray *m_textStyles;
    NSMutableArray *m_colorIndex;
    
    NSMutableArray *m_colorArray;
    UIColor *m_fgColor, *m_bgColor;
    UIColor *m_currBgColor; // weak ref
    int m_firstVisibleTextRunIndex;
    CGFloat m_savedTopYOffset;    
    
    unsigned int m_topMargin, m_leftMargin, m_rightMargin, m_bottomMargin;
    CGPoint m_prevPt, m_lastPt;
    
    UIFont *m_normalFont, *m_boldFont;
    UIFont *m_italicFont, *m_boldItalicFont;
    UIFont *m_fixedNormalFont, *m_fixedBoldFont;
    UIFont *m_fixedItalicFont, *m_fixedBoldItalicFont;
    
    RichTextStyle m_currentTextStyle;
    unsigned int m_currentTextColorIndex, m_currentBGColorIndex;
    
    NSMutableSet *m_reusableTiles;    
    UIView *m_tileContainerView;
    CGFloat m_fontHeight, m_fixedFontHeight, m_fixedFontWidth, m_fontMinWidth, m_fontMaxWidth;
    CGFloat m_firstVisibleRow, m_firstVisibleColumn, m_lastVisibleRow, m_lastVisibleColumn;
    UIViewController<UIScrollViewDelegate> *m_controller;
    
    CGFloat m_origY;
    BOOL m_prevReverse, m_prevLineNotTerminated;
    
    NSMutableArray *m_accessibilityElements;
    int m_lastAEIndexAccessed, m_lastAEIndexAnnounced;
    
    int m_selectedRun;
    NSRange m_selectedColumnRange;
    UILabelWA *m_selectionView;
    BOOL m_selectionDisabled;
    
    NSObject<RTSelected>* m_selectionDelegate;
    
    BOOL m_freezeDisplay;
    CGRect m_delayedFrame;
}

@property(nonatomic, retain) NSString *text;
@property(nonatomic, assign) CGSize tileSize;
@property(nonatomic, readonly) NSMutableArray* textRuns;
@property(nonatomic, assign) CGPoint lastPt;
@property(nonatomic, assign) RichTextStyle textStyle;
@property(nonatomic, assign) unsigned int textColorIndex;
@property(nonatomic, assign) unsigned int bgColorIndex;
@property(nonatomic, assign) UIViewController<UIScrollViewDelegate>* controller;
@property(nonatomic, assign) unsigned int topMargin;
@property(nonatomic, assign) unsigned int leftMargin;
@property(nonatomic, assign) unsigned int rightMargin;
@property(nonatomic, assign) unsigned int bottomMargin;
@property(nonatomic, assign) int lastAEIndexAccessed;
//@property(nonatomic, assign) int selectedRun;
//@property(nonatomic, assign) NSRange selectedColumnRange;
@property(nonatomic, assign) NSObject<RTSelected>* selectionDelegate;
@property(nonatomic, assign) BOOL selectionDisabled;
@property(nonatomic, assign, getter=displayFrozen) BOOL freezeDisplay;

- (RichTextView*)initWithFrame: (CGRect)frame;
- (RichTextView*)initWithFrame: (CGRect)frame border:(BOOL)border;
- (void)clearSelection;
- (UIFont*)fontForStyle: (RichTextStyle)style;
- (void) drawRect:(CGRect)rect inView:(RichTextTile*)view;
- (RichTextTile *)tileForRow:(int)row column:(int)column;
- (BOOL)findHotText:(NSString *)text charOffset:(int)charsDone pos:(CGPoint)pos minX:(CGFloat)minXPos hotPoint:(CGPoint*)hotPoint font:(UIFont*)font fontHeight:(CGFloat)fontHeight
 width:(CGFloat) width;
- (BOOL)wordWrapTextSize:(NSString*)text atPoint:(CGPoint*)pos font:(UIFont*)font style:(RichTextStyle)style fgColor:(UIColor*)fgColor
   bgColor:(UIColor*)bgColor withRect:(CGRect)rect nextPos:(CGPoint*)nextPos hotPoint:(CGPoint*)hotPoint doDraw:(BOOL)doDraw;
- (void)appendText:(NSString*)text;
- (RichTextTile *)dequeueReusableTile;
- (void)prepareForKeyboardShowHide;
- (void)rememberTopLineForReflow;
- (void)resetColors;
- (void)resetMargins;
- (void)layoutSubviews;
- (void)reloadData;
- (void)reset;
- (void)clear;
- (void)reflowText;
- (void)dealloc;
- (void)setDelegate:(UIViewController<UIScrollViewDelegate>*)delegate;
- (void)setFont:(UIFont*)font;
- (void)setFixedFont:(UIFont*)newFont;
- (UIFont*)font;
- (UIFont*)fixedFont;
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


