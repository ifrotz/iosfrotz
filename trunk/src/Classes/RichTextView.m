//
//  RichTextView.m
//  
// TTD:
//  Dont set font immed from settings, wait until Done
//  limit history to 2000 lines, optimize reflow on new orient
// dont go to sleep when ftp active
// undo 400 exception in setframe
// change color selection to show fg/bg and text in sample block
//  change text to 'grue' if bg black

#import <UIKit/UIKit.h>
#import <QuartzCore/CALayer.h>

#include "RichTextView.h"

#define NoAccessibility 0 // Set to turn off UIAccessibility support completely

static BOOL hasAccessibility;

#define DEFAULT_TILE_WIDTH  512
#define DEFAULT_TILE_HEIGHT 120

#define TEXT_TOP_MARGIN	    16
#define TEXT_RIGHT_MARGIN   6
#define TEXT_LEFT_MARGIN    6
#define TEXT_BOTTOM_MARGIN  8

#define DEBUG_TILE_LAYOUT 0

#if NoAccessibility
#define UIAccessibilityElement UIAccessibilityElement_NA

@interface  UIAccessibilityElement : NSObject {
}
@end
@implementation  UIAccessibilityElement
@end
#else
// This allows the UIAccessibility support in this file to load on pre-3.0 devices, since it is
// lazily allocated.  Also need to link with -Wl,-flat_namepace,-undefined,dynamic_lookup.
__asm__(".weak_reference _OBJC_CLASS_$_UIAccessibilityElement\n");
__asm__(".weak_reference _OBJC_METACLASS_$_UIAccessibilityElement\n");
__asm__(".weak_reference _UIAccessibilityScreenChangedNotification\n");

#endif

void removeAnim(UIView *view);

@interface  RichTextAE : UIAccessibilityElement
{
    int m_textIndex;
    int m_aeIndex;
    int m_runCount;
}
-(void)dealloc;
@property(assign) int textIndex;
@property(assign) int aeIndex;
@property(assign) int runCount;
@end

@interface UIAnimator
+(UIAnimator*)sharedAnimator;
-(void)removeAnimationsForTarget:(id)target;
@end

static void DrawViewBorder(CGContextRef context, CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2) {
    CGContextBeginPath(context);
    CGContextMoveToPoint(context, x1, y1);
    CGContextAddLineToPoint(context, x2, y2);
    CGContextClosePath(context);
    CGContextDrawPath(context, kCGPathStroke);
}

@implementation RichTextTile

@synthesize textView = m_textView;

- (void) drawRect:(CGRect)rect {
    [super drawRect: rect];
    [m_textView drawRect: rect inView: self];    
}
@end

@implementation RichTextView

@synthesize tileSize = m_tileSize;
@synthesize textRuns = m_textRuns;
@synthesize lastPt = m_lastPt;
@synthesize controller = m_controller;
@dynamic leftMargin;
@synthesize rightMargin = m_rightMargin;
@synthesize bottomMargin = m_bottomMargin;
@synthesize lastAEIndexAccessed = m_lastAEIndexAccessed; 
@synthesize selectionDelegate = m_selectionDelegate;
@synthesize selectionDisabled = m_selectionDisabled;

-(void)setLeftMargin:(unsigned int)m {
    if (m_leftMargin != m) {
        m_leftMargin = m;
        [self reflowText];
        if (m_firstVisibleTextRunIndex > 0 && m_firstVisibleTextRunIndex < [m_textPos count]) {
            CGPoint pt = [[m_textPos objectAtIndex: m_firstVisibleTextRunIndex] CGPointValue];
            self.contentOffset = CGPointMake(0, pt.y+m_savedTopYOffset);
        }
    }
}

-(unsigned int)leftMargin {
    return m_leftMargin;
}

-(void)setTextStyle:(RichTextStyle)style {
    if (m_currentTextStyle != style) {
        m_currentTextStyle = style;
        m_prevLineNotTerminated = NO;
    }
}
-(RichTextStyle)textStyle {
    return m_currentTextStyle;
}
-(void)setTextColorIndex:(unsigned int)index {
    if (index==1) index=0;
    if (index > [m_colorArray count])
        index = 0;
    if (m_currentTextColorIndex != index) {
        m_currentTextColorIndex = index;
        m_prevLineNotTerminated = NO;
    }
}
-(unsigned int)textColorIndex {
    return m_currentTextColorIndex;
}
-(void)setBgColorIndex:(unsigned int)index {
    if (index==1) index=0;
    if (index > [m_colorArray count])
        index = 0;
    if (m_currentBGColorIndex != index) {
        m_currentBGColorIndex = index;
    	if (index == 0) {
            m_currBgColor = m_bgColor;
        }
        m_prevLineNotTerminated = NO;
    }
}
-(unsigned int)bgColorIndex {
    return m_currentBGColorIndex;
}

-(unsigned int)topMargin {
    return m_topMargin;
}

-(void)setTopMargin:(unsigned int)topMargin {
    if (m_topMargin != topMargin) {
        m_topMargin = topMargin;
        CGRect frame = self.frame;
        [self setContentSize: CGSizeMake(frame.size.width, m_topMargin+ m_lastPt.y + m_fontHeight + m_bottomMargin)];
        [self reloadData];
    }
}

-(void)setText:(NSString*)text {
    [self clear];
    int length = [text length];
    m_currentTextStyle = kFTNormal;
    
    NSRange p = NSMakeRange(0, length);
    NSRange r = [text rangeOfString: @"\n\n"];
    while (r.length) {
        int nlPos = r.location;
        ++r.location;
        while ([text characterAtIndex: r.location] == '\n')
            ++r.location;
        if (nlPos > 0) {
            [self appendText: [text substringWithRange: NSMakeRange(p.location, r.location-p.location)]];
            r.length = length - r.location;
            p = r;
        } else
            r.length = length - r.location;
        r = [text rangeOfString:@"\n\n" options:0 range:r];
    }
    [self appendText: [text substringWithRange: NSMakeRange(p.location, length-p.location)]];
}

// !!! implement or remove callers
-(NSString*)text {
    NSMutableString *text = [NSMutableString stringWithUTF8String: ""];
    for (NSString *t in m_textRuns)
        [text appendString: t];
    return text;
}

-(CGPoint) cursorPoint {
    return CGPointMake(m_lastPt.x, m_topMargin+m_lastPt.y);
}

-(BOOL)setFontFamily:(NSString*)familyName size:(int)newSize {
    UIFont *normalFont = nil, *boldFont = nil, *italicFont = nil, *boldItalicFont = nil;
    
    NSArray *fonts = [UIFont fontNamesForFamilyName: familyName];
    UIFont *font = nil;
    for (NSString *aFontName in fonts) {
        font = [UIFont fontWithName: aFontName size: newSize];
        int traits = [font fontTraits];  // skip italic, etc. fonts.  traits not documented
        switch (traits & (UIBoldFontMask|UIItalicFontMask)) {
            case UINormalFontMask:
                normalFont = font;
                break;
            case UIItalicFontMask:
                italicFont = font;
                break;
            case UIBoldFontMask:
                boldFont = font;
                break;
            case UIItalicFontMask+UIBoldFontMask:
                boldItalicFont = font;
                break;
        }
    }
    if (normalFont) {
        [self rememberTopLineForReflow];
        m_fontSize = newSize;
    	if (!boldFont) boldFont = normalFont;
        if (!italicFont) italicFont = normalFont;
        if (!boldItalicFont) boldItalicFont = boldFont;
        m_normalFont = normalFont;
        m_boldFont = boldFont;
        m_italicFont = italicFont;
        m_boldItalicFont = boldItalicFont;
        CGSize letterSize  = [@"W" sizeWithFont: m_normalFont];
        m_fontHeight = letterSize.height;
        m_fontMaxWidth = letterSize.width;
        m_fontMinWidth = [@"i" sizeWithFont: m_normalFont].width;
        [self reflowText];
        return YES;
	}
    return NO;
}


-(BOOL)setFixedFontFamily:(NSString*)familyName size:(int)newSize {
    UIFont *normalFont = nil, *boldFont = nil, *italicFont = nil, *boldItalicFont = nil;
    
    NSArray *fonts = [UIFont fontNamesForFamilyName: familyName];
    UIFont *font = nil;
    for (NSString *aFontName in fonts) {
        font = [UIFont fontWithName: aFontName size: newSize];
        int traits = [font fontTraits];  // skip italic, etc. fonts.  traits not documented
        switch (traits & (UIBoldFontMask|UIItalicFontMask)) {
            case UINormalFontMask:
                normalFont = font;
                break;
            case UIItalicFontMask:
                italicFont = font;
                break;
            case UIBoldFontMask:
                boldFont = font;
                break;
            case UIItalicFontMask+UIBoldFontMask:
                boldItalicFont = font;
                break;
        }
    }
    if (normalFont) {
        [self rememberTopLineForReflow];
        m_fixedFontSize = newSize;
    	if (!boldFont) boldFont = normalFont;
        if (!italicFont) italicFont = normalFont;
        if (!boldItalicFont) boldItalicFont = boldFont;
        m_fixedNormalFont = normalFont;
        m_fixedBoldFont = boldFont;
        m_fixedItalicFont = italicFont;
        m_fixedBoldItalicFont = boldItalicFont;
        m_fixedFontHeight  = [@"W" sizeWithFont: m_normalFont].height;
        m_fixedFontWidth = [@"i" sizeWithFont: m_fixedNormalFont].width;
        [self reflowText];
        return YES;
	}
    return NO;
}

-(void)setFont:(UIFont*)newFont {
    NSString *familyName = [newFont familyName];
    int newSize = [newFont pointSize];
    [self setFontFamily: familyName size:newSize];
}

-(void)setFixedFont:(UIFont*)newFont {
    NSString *familyName = [newFont familyName];
    int newSize = [newFont pointSize];
    [self setFixedFontFamily: familyName size:newSize];
}

- (UIFont*)font {
    return m_normalFont;
}

- (UIFont*)fixedFont {
    return m_fixedNormalFont;
}

-(CGRect)visibleRect {
    CGRect frame = self.frame;
    CGPoint ofst = self.contentOffset;
    return CGRectMake(ofst.x, ofst.y, frame.size.width, frame.size.height);
}

- (void)setTextColor:(UIColor*)color {
    if (m_fgColor != color) {
        [m_fgColor release];
        m_fgColor = [color retain];
        //	if (m_selectionView) [m_selectionView setBackgroundColor: m_fgColor];
    }
    [self reloadData];
}

- (void)setBackgroundColor:(UIColor *)color {
    [super setBackgroundColor: color];
    if (m_bgColor != color) {
        [m_bgColor release];
        m_bgColor = [color retain];
        [super setBackgroundColor: m_bgColor];
        if (m_currBgColor)
            [m_currBgColor release];
        if (m_currentBGColorIndex > 1 && m_currentBGColorIndex <= [m_colorArray count])
            m_currBgColor = [[m_colorArray objectAtIndex: m_currentBGColorIndex-1] retain];
        else
            m_currBgColor = [m_bgColor retain];
        
        [m_tileContainerView setBackgroundColor: m_bgColor];
    }
    [self reloadData];
}

-(void)setFreezeDisplay:(BOOL)freeze {
    BOOL wasFrozen = m_freezeDisplay;
    m_freezeDisplay = freeze;
    if (wasFrozen && !freeze) {
        if (!CGRectEqualToRect(m_delayedFrame, self.frame))
            [self setFrame: m_delayedFrame];
        [self reloadData];
        [self setNeedsDisplay];
        [self layoutSubviews];
    } else if (!wasFrozen && freeze)
        m_delayedFrame = self.frame;
}

-(BOOL)displayFrozen {
    return m_freezeDisplay;
}

-(void)setContentSize:(CGSize)size {
    [super setContentSize: size];
}

-(void)setContentOffset:(CGPoint)offset {
    [super setContentOffset: offset];
}

-(void)setContentOffset:(CGPoint)contentOffset animated:(BOOL)animated {
    [super setContentOffset:contentOffset animated:animated];
}

- (RichTextView*)initWithFrame: (CGRect)frame border:(BOOL)border {
    if ((self = [self initWithFrame: frame])) {
        CALayer *layer = self.layer;
        layer.borderWidth = 1;
        layer.borderColor = [[UIColor darkGrayColor] CGColor];
    }
    return self;
}

- (RichTextView*)initWithFrame: (CGRect)frame {
    if ((self = [super initWithFrame: frame])) {
        hasAccessibility = [super respondsToSelector: @selector(setAccessibilityLabel:)];
        
        //	CGAffineTransform t = [self transform];
        //	t = CGAffineTransformRotate(t, M_PI/32);
        //	[self setTransform: t];
        
        [self setAutoresizesSubviews: YES];
        [self setAutoresizingMask: UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight];
        [super setDelegate: self];
        
        
        m_textRuns = [[NSMutableArray alloc] initWithCapacity: 1000];
        m_textPos = [[NSMutableArray alloc] initWithCapacity: 1000];
        m_textStyles = [[NSMutableArray alloc] initWithCapacity: 1000];
        m_colorIndex = [[NSMutableArray alloc] initWithCapacity: 1000];
        
        m_colorArray = [[NSMutableArray alloc] initWithCapacity: 16];
        m_numLines = 0;
        m_fontSize = 12.0;
        m_fixedFontSize = 8.0;
        
        m_normalFont = [UIFont fontWithName: @"Helvetica" size:m_fontSize];
        m_boldFont = [UIFont fontWithName: @"Helvetica-Bold" size:m_fontSize];
        if (!m_boldFont) m_boldFont = m_normalFont;
        m_italicFont = [UIFont fontWithName: @"Helvetica-Oblique" size:m_fontSize];
        if (!m_italicFont) m_italicFont = m_normalFont;
        m_boldItalicFont = [UIFont fontWithName: @"Helvetica-BoldOblique" size:m_fontSize];
        if (!m_boldItalicFont) m_boldItalicFont = m_boldFont;
        
        m_fixedNormalFont = [UIFont fontWithName: @"CourierNewPSMT" size:m_fixedFontSize];
        m_fixedBoldFont = [UIFont fontWithName: @"CourierNewPS-BoldMT" size:m_fixedFontSize];
        if (!m_fixedBoldFont) m_fixedBoldFont = m_fixedNormalFont;
        m_fixedItalicFont = [UIFont fontWithName: @"CourierNewPS-ItalicMT" size:m_fixedFontSize];
        if (!m_fixedItalicFont) m_fixedItalicFont = m_fixedNormalFont;
        m_fixedBoldItalicFont = [UIFont fontWithName: @"CourierNewPS-BoldItalicMT" size:m_fixedFontSize];
        if (!m_fixedBoldItalicFont) m_fixedBoldItalicFont = m_fixedBoldFont;
        
        CGSize letterSize  = [@"W" sizeWithFont: m_normalFont];
        m_fontHeight = letterSize.height;
        m_fontMaxWidth = letterSize.width;
        m_fontMinWidth = [@"i" sizeWithFont: m_normalFont].width;
        letterSize  = [@"i" sizeWithFont: m_fixedNormalFont];
        m_fixedFontHeight = letterSize.height;
        m_fixedFontWidth = letterSize.width;
        
        m_reusableTiles = [[NSMutableSet alloc] init];
        m_tileContainerView = [[UIView alloc] initWithFrame:frame];
        [self addSubview: m_tileContainerView];
        
        //	m_tileContainerView.opaque = NO;
        //	m_tileContainerView.clearsContextBeforeDrawing = YES;
        //	m_tileContainerView.contentMode = UIViewContentModeTopLeft;
        
        [self resetMargins];
        
        [self setTextColor: [UIColor blackColor]];
        [self setBackgroundColor: [UIColor whiteColor]];
        [self setTileSize:CGSizeMake(DEFAULT_TILE_WIDTH, DEFAULT_TILE_HEIGHT)];
        m_currentTextStyle = kFTNormal;
        [self clear];
        m_selectionView = [[UILabel alloc] initWithFrame: CGRectZero];
        [m_selectionView setTextColor: [UIColor blueColor]];
        [m_selectionView setShadowColor: [UIColor darkGrayColor]];
        [m_selectionView setBackgroundColor: [UIColor whiteColor]];
    }
    return self;
}

-(void)resetMargins {
    m_topMargin = TEXT_TOP_MARGIN;
    m_leftMargin = TEXT_LEFT_MARGIN;
    m_rightMargin = TEXT_RIGHT_MARGIN;
    m_bottomMargin = TEXT_BOTTOM_MARGIN;
}

- (void)setDelegate:(UIViewController<UIScrollViewDelegate>*)delegate {
    // don't set real delegate, we are our own
    [self setController: delegate];
}
- (id)delegate {
    return m_controller;
}

-(void)dealloc {
    NSLog(@"rtv %@ dealloc", self);
    if (m_selectionView) {
        [m_selectionView removeFromSuperview];
        [m_selectionView release];
        m_selectionView = nil;
    }
    [self clearAE];
    [m_textRuns release];
    [m_textPos release];
    [m_textStyles release];
    [m_colorIndex release];
    [m_colorArray release];
    [m_reusableTiles release];
    [m_tileContainerView release];
    m_textRuns = nil;
    m_textPos = nil;
    m_textStyles = nil;
    m_colorIndex = nil;
    m_colorArray = nil;
    m_reusableTiles = nil;
    m_tileContainerView = nil;
    
    [m_fgColor release];
    [m_bgColor release];
    if (m_currBgColor)
        [m_currBgColor release];
    m_currBgColor = nil;
    m_fgColor = m_bgColor = nil;
    [super dealloc];
}

-(void)clearSelection {
    m_selectedRun = -1;
    m_selectedColumnRange = NSMakeRange(0, 0);
    if (m_selectionView && [m_selectionView superview]) {
        [m_selectionView setText: @""];
        [m_selectionView removeFromSuperview];
    }
}

-(void)reset {
    m_currentTextStyle = kFTNormal;
    m_currentTextColorIndex = 0;
    m_currentBGColorIndex = 0;
    [self clear];
}

-(void)clear {
    [self clearSelection];
    [self clearAE];
    [m_textRuns removeAllObjects];
    [m_textPos removeAllObjects];
    [m_textStyles removeAllObjects];
    [m_colorIndex removeAllObjects];
    m_numLines = 0;
    
    if (m_currBgColor)
        [m_currBgColor release];
    if (m_currentBGColorIndex > 1 && m_currentBGColorIndex <= [m_colorArray count])
        m_currBgColor = [[m_colorArray objectAtIndex: m_currentBGColorIndex-1] retain];
    else
        m_currBgColor = [m_bgColor retain];
    [super setBackgroundColor: m_currBgColor];
    [m_tileContainerView setBackgroundColor: m_currBgColor];
    
    m_firstVisibleTextRunIndex = 0;
    m_prevPt = m_lastPt = CGPointMake(m_leftMargin, 0);
    
    m_origY = 0;
    m_prevReverse = NO;
    m_prevLineNotTerminated = NO;
    
    [self setContentOffset: CGPointMake(0, 0)];
    [self setContentSize: CGSizeMake(self.frame.size.width, m_topMargin + m_bottomMargin)];
    [self reflowText];
    [self layoutSubviews];
}

- (UIFont*)fontForStyle: (RichTextStyle)style {
    switch (style & kFTFontStyleMask) {
        case kFTNormal:
            return m_normalFont;
        case kFTBold:
            return m_boldFont;
        case kFTItalic:
            return m_italicFont;
        case kFTBold+kFTItalic:
            return m_boldItalicFont;
        case kFTNormal+kFTFixedWidth:
            return m_fixedNormalFont;
        case kFTBold+kFTFixedWidth:
            return m_fixedBoldFont;
        case kFTItalic+kFTFixedWidth:
            return m_fixedItalicFont;
        case kFTBold+kFTItalic+kFTFixedWidth:
            return m_fixedBoldItalicFont;
    }
    return m_normalFont;
}

- (void)resetColors {
    if (m_colorArray)
        [m_colorArray removeAllObjects];
}

- (int)getOrAllocColorIndex:(UIColor*)color {
    int idx = [m_colorArray indexOfObject: color];
    if (idx == NSNotFound) {
        idx = [m_colorArray count];
        [m_colorArray addObject: color];
    }
    return idx + 1;
}

- (void) drawRect:(CGRect)rect inView:(RichTextTile*)view {
    CGRect myRect = [view convertRect: rect toView: self];
    CGRect frame = self.frame;
    
    myRect.size.width = frame.size.width;
    int i, l = [m_textRuns count];
    CGPoint lastUniqPt = CGPointMake(0,0);
    int lastUniqIndex = 0;
    for (i=0; i < l; ++i) {
        CGPoint pt = [[m_textPos objectAtIndex: i] CGPointValue];
        pt.y += m_topMargin;
        if (pt.y > myRect.origin.y)
            break;
        if (pt.y > lastUniqPt.y)
            lastUniqIndex= i;
        lastUniqPt = pt;
    }
    i = lastUniqIndex > 0 ? lastUniqIndex-1 : 0;
    int j = 0;
    while (i < l) {
        NSString *text = [m_textRuns objectAtIndex: i];
        CGPoint pt = [[m_textPos objectAtIndex: i] CGPointValue], nextPos;
        pt.y += m_topMargin;
        if (pt.y >= myRect.origin.y + myRect.size.height)
            break;
        RichTextStyle style = [[m_textStyles objectAtIndex: i] unsignedIntValue];
        //	NSLog(@"drawRect i=%d pt=(%.0f,%0.f) view.origin.y=%.0f", i, pt.x, pt.y, view.frame.origin.y);
        UIFont *font = [self fontForStyle: style];
        unsigned int colorIndex = [[m_colorIndex objectAtIndex: i] unsignedIntValue];
        UIColor *fgColor = m_fgColor, *bgColor = m_bgColor;
        BOOL useBGColor = NO;
        if (colorIndex) {
            unsigned int bgIndex = (colorIndex >> 16);
            unsigned int fgIndex = (colorIndex & 0xFFFF);
            if (fgIndex > 1)
                fgColor = [m_colorArray objectAtIndex: fgIndex-1];
            if (bgIndex > 1) {
                bgColor = [m_colorArray objectAtIndex: bgIndex-1];
                useBGColor = YES;
            }
        }
        //	NSLog(@"i=%d pt=(%f,%f), fg=%@ bg=%@ usebg=%d s=%x t=[%@]", i, pt.x, pt.y, fgColor, bgColor, useBGColor, style, text);
        if (style & kFTReverse) {
            UIColor *tmpColor = fgColor;
            fgColor = bgColor;
            bgColor = tmpColor;
            useBGColor = YES;
        }
        pt = [self convertPoint:pt toView:view];
        
        [self wordWrapTextSize:text atPoint:&pt font:font style:style fgColor:fgColor bgColor:useBGColor ? bgColor:nil withRect:myRect 
                       nextPos:&nextPos hotPoint:nil doDraw:YES];
        
        i++; j++;
    }
    
}

-(BOOL)findHotText:(NSString *)text charOffset:(int)charsDone pos:(CGPoint)pos minX:(CGFloat)minXPos hotPoint:(CGPoint*)hotPoint font:(UIFont*)font fontHeight:(CGFloat)fontHeight
             width:(CGFloat) width {
    int maxChars = [text length];
    NSRange termRange = NSMakeRange(0, 0);
    NSRange range = NSMakeRange(0,  maxChars), prevRange;
    NSCharacterSet *cs = [NSCharacterSet characterSetWithCharactersInString: @" \t/\\,:!?;\"{}[]-=+@#^&*()`~<>"];
    CGSize textSize = CGSizeZero;
    int prevWidth;
    do {
        prevRange = termRange;
        termRange = [text rangeOfCharacterFromSet:cs options:0 range: range];
        prevWidth = textSize.width;
        if (termRange.length > 0)
            textSize = [[text substringToIndex:termRange.location+1] sizeWithFont:font constrainedToSize: CGSizeMake(width-pos.x, m_fontHeight) lineBreakMode:UILineBreakModeClip];
        else {
            termRange.location = [text length];
            textSize = [text sizeWithFont:font constrainedToSize: CGSizeMake(width-pos.x, m_fontHeight) lineBreakMode:UILineBreakModeClip];
        }
        if (minXPos+pos.x+textSize.width > hotPoint->x) {
            //NSLog(@"findhot:[%@]", [text substringToIndex:termRange.location]);
            if (prevRange.length)
                ++prevRange.location;
            [m_selectionView setFrame: CGRectMake(minXPos+pos.x+prevWidth, pos.y, textSize.width-prevWidth, fontHeight)];
            [m_selectionView setFont: font];
            NSString *selectedText = [text substringWithRange: NSMakeRange(prevRange.location, termRange.location-prevRange.location)];
            m_selectedColumnRange = NSMakeRange(charsDone + prevRange.location, termRange.location-prevRange.location);
            if ([selectedText hasSuffix: @"."]) {
                selectedText = [selectedText substringToIndex: [selectedText length]-1];
                m_selectedColumnRange.length--;
            }
            if ([selectedText length]>3 && [selectedText hasPrefix: @"'"] && [selectedText hasSuffix: @"'"]) {
                selectedText = [selectedText substringWithRange: NSMakeRange(1, [selectedText length]-2)];
                m_selectedColumnRange.location++;
                m_selectedColumnRange.length--;
            }
            [m_selectionView setText: selectedText];
            [self addSubview: m_selectionView];
            if (m_selectionDelegate && [m_selectionDelegate respondsToSelector: @selector(textSelected:animDuration:hilightView:)])
                [m_selectionDelegate textSelected:selectedText animDuration:-1 hilightView: m_selectionView];
            return YES;
        }
        if (termRange.length <= 0)
            break;
        range.location = termRange.location+1;
        range.length = maxChars - (termRange.location+1);
    } while (textSize.height <= fontHeight);
    return NO;
}

static CGFloat RTDrawFixedWidthText(CGContextRef context, NSString *text, CGFloat x, CGFloat y, BOOL doDraw) {
    char *buf = nil;
    if (!doDraw)
        x = y = 0;
    CGContextSaveGState(context);
    CGContextConcatCTM(context, CGAffineTransformMakeScale(1, -1));
    CGContextSetTextMatrix(context, CGAffineTransformIdentity);
    CGContextSetTextDrawingMode(context, doDraw ? kCGTextFill: kCGTextInvisible);
    const char *s = [text cStringUsingEncoding:NSMacOSRomanStringEncoding];
    int l = s ? strlen(s) : 0;
    if (!s) { // encoding failed because of missing characters
        s = [text cStringUsingEncoding:NSISOLatin1StringEncoding];
        l = strlen(s);
        buf = malloc(l+1);
        strncpy(buf, s, l);
        buf[l] = 0;
        unsigned char *t = (unsigned char*)buf;
        while (*t) {
            // Thorn, eth, and accented y do not exist in MacOS Roman, which is the only
            // font encoding we can render on the iPhone using Quartz 2D
            if (*t == 0xfd || *t == 0xdd || *t == 0xfe || *t == 0xd0 || *t == 0xf0 || *t == 0xde)
                *t = '?';
            ++t;
        }
        s = [[NSString stringWithCString:buf encoding:NSISOLatin1StringEncoding] cStringUsingEncoding: NSMacOSRomanStringEncoding];
        if (!s)
            s = buf;	
    }
    CGContextShowTextAtPoint(context, x, y, s, l);
    CGPoint p = CGContextGetTextPosition(context);
    CGContextRestoreGState(context);
    if (buf)
        free(buf);
    return p.x - x;
}

-(BOOL)wordWrapTextSize:(NSString*)text atPoint:(CGPoint*)ipos font:(UIFont*)font style:(RichTextStyle)style fgColor:(UIColor*)fgColor bgColor:(UIColor*)bgColor withRect:(CGRect)rect 
                nextPos:(CGPoint*)nextPos hotPoint:(CGPoint*)hotPoint doDraw:(BOOL)doDraw
{
    CGSize textSize;
    CGFloat fontHeight = [font leading];
    CGFloat width = rect.size.width - m_rightMargin;
    CGPoint pos = *ipos;
    NSString *restOfString = nil;
    int len = [text length];
    CGContextRef context = nil;
    CGFloat minXPos = -rect.origin.x;
    pos.x -= minXPos;
    int nLines = 0, charsDone = 0;
    CGFloat fontAscender = 0;
    BOOL noWrap = (style & kFTNoWrap) != 0;
    BOOL isFixed = (style & kFTFixedWidth);
    if (!len)
        return 0;
    
    if (doDraw) {
        context = UIGraphicsGetCurrentContext();	
        if (!bgColor) {
            if (fgColor)
                [fgColor set];
        }
    }
    if (isFixed) {
        if (!context) {
            UIGraphicsBeginImageContext(CGSizeMake(DEFAULT_TILE_WIDTH*2, DEFAULT_TILE_HEIGHT));
            context = UIGraphicsGetCurrentContext();
        }
        
        // Set fill and stroke colors
        CGContextSetFillColorWithColor(context, [fgColor CGColor]);
        CGContextSetStrokeColorWithColor(context, [fgColor CGColor]);
        
        // Set text parameters
        CGContextSelectFont(context, [[font fontName] UTF8String], m_fixedFontSize, kCGEncodingMacRoman);
        fontAscender = [font ascender];
    }
    while (text && len > 0) {
        NSRange termRange = [text rangeOfString: @"\n"];
        BOOL hasEOL = NO;
        if (termRange.length) {
            restOfString = [text substringFromIndex: termRange.location+1];
            text = [text substringToIndex: termRange.location];
            len = [text length];
            hasEOL = YES;
        } else
            restOfString = nil;
        
        while (text && len > 0) {
            if (pos.x <= 0)
                pos.x = m_leftMargin;
            if (pos.x >= width) {
                //text = nil;
                break; //continue;
            }
            int maxChars = (width - pos.x) / m_fontMinWidth;
            if (len < maxChars || /*noWrap && */isFixed/* && (style & kFTReverse)*/) {
                if (isFixed) {
                    textSize.height = fontHeight;
                    textSize.width = RTDrawFixedWidthText(context, text, 0, 0, NO);
                } else 
                    textSize = [text sizeWithFont:font constrainedToSize: CGSizeMake(width - pos.x, fontHeight + (noWrap ? 0 :fontHeight))
                                    lineBreakMode: noWrap ? UILineBreakModeClip:UILineBreakModeWordWrap];
                if (textSize.width > 0 && textSize.width < width-pos.x && textSize.height <= fontHeight || noWrap) {
                    if (doDraw) {
                        if (bgColor) {
                            [bgColor set];
                            if (pos.x <= m_leftMargin)
                                CGContextFillRect(context, CGRectMake(minXPos, pos.y, textSize.width+m_leftMargin + 2, fontHeight));
                            else
                                CGContextFillRect(context, CGRectMake(minXPos+ pos.x - 2, pos.y, textSize.width+2, fontHeight));
                            [fgColor set];
                        }
                        if (!isFixed)
                            textSize = [text drawInRect:CGRectMake(minXPos+pos.x, pos.y, width - pos.x, fontHeight) withFont:font lineBreakMode:UILineBreakModeClip];
                        else {
                            // Set fill and stroke colors
                            textSize.width = RTDrawFixedWidthText(context, text, minXPos+pos.x, -fontAscender-pos.y, YES);
                        }
                    }
                    //		    NSLog(@"ft (%f,%f) %@", minXPos+pos.x, pos.y, text);
                    *nextPos = CGPointMake(pos.x + textSize.width, pos.y);
                    if (hotPoint) {
                        if (hotPoint->y >= pos.y && hotPoint->y < pos.y+fontHeight && hotPoint->x >= minXPos+pos.x && hotPoint->x < minXPos+pos.x+textSize.width)
                            return [self findHotText:text charOffset:charsDone pos:pos minX:minXPos hotPoint:hotPoint font:font fontHeight:fontHeight width:width];
                    }
                    //if (!doDraw) NSLog(@"short str %d %x: (%.0f,%.0f) -> (%.0f,%.0f): \"%@\"", doDraw, style, pos.x, pos.y, nextPos->x, nextPos->y, text);
                    // text = nil;
                    pos = *nextPos;
                    break;
                }
                maxChars = len;
            }
            
            int minChars = (width-pos.x) / m_fontMaxWidth;
            if (minChars > len)
                minChars = len;
            if (minChars > maxChars-20)
                minChars = maxChars-20;
            if (maxChars < 20)
                minChars = 0;
            if (noWrap) {
                termRange = NSMakeRange(len-1, 1);
            } else {
                termRange = NSMakeRange(0, 0);
                NSRange range = NSMakeRange(minChars, maxChars-minChars), prevRange;
                NSCharacterSet *cs = [NSCharacterSet characterSetWithCharactersInString: @" \t-/\\:"]; // ,.!?
                do {
                    prevRange = termRange;
                    termRange = [text rangeOfCharacterFromSet:cs options:0 range: range];
                    if (termRange.length <= 0)
                        break;
                    textSize = [[text substringToIndex:termRange.location] sizeWithFont:font constrainedToSize: CGSizeMake(width - pos.x - m_fontMinWidth-1,
                                                                                                                           fontHeight*2) lineBreakMode:UILineBreakModeWordWrap];
                    // (The -m_fontMinWidth-1 is to prevent trailing hyphens from being clipped.  The sizeWithFont function
                    // won't wrap a trailing hyphen to the next line even if it won't fit in the given width.)
                    range.location = termRange.location+1;
                    range.length = maxChars - (termRange.location+1);
                } while (textSize.height <= fontHeight);
                termRange = prevRange;
            }
            if (termRange.length > 0) {
                while (termRange.location < len-1 && isspace([text characterAtIndex: termRange.location+1])) {
                    ++termRange.location;
                }
                NSString *subtext = [text substringToIndex: termRange.location+1];
                if (doDraw) {
                    if (bgColor) {
                        [bgColor set];
                        if (pos.x <= m_leftMargin)
                            CGContextFillRect(context, CGRectMake(minXPos, pos.y, width+m_leftMargin, fontHeight));
                        else
                            CGContextFillRect(context, CGRectMake(minXPos+pos.x, pos.y, width-pos.x, fontHeight));
                        [fgColor set];
                    }
                    if (!isFixed)
                        textSize = [subtext drawInRect:CGRectMake(minXPos+pos.x, pos.y, width-pos.x, fontHeight) withFont:font lineBreakMode:UILineBreakModeClip];
                    else {
                        textSize.height = fontHeight;
                        textSize.width = RTDrawFixedWidthText(context, subtext, minXPos+pos.x, -fontAscender-pos.y, YES);
                    }
                }
                else {
                    if (!isFixed)
                        textSize = [subtext sizeWithFont:font constrainedToSize: CGSizeMake(width - pos.x, fontHeight) lineBreakMode:UILineBreakModeClip];
                    else {
                        textSize.height = fontHeight;
                        textSize.width = RTDrawFixedWidthText(context, subtext, 0, 0, NO);			
                    }
                }
                if (noWrap)
                    *nextPos = CGPointMake(pos.x + width, pos.y);
                else
                    *nextPos = CGPointMake(0, pos.y + textSize.height);
                if (hotPoint) {
                    if (hotPoint->y >= pos.y && hotPoint->y < pos.y+fontHeight && hotPoint->x >= minXPos+pos.x && hotPoint->x < minXPos+pos.x+textSize.width)
                        return [self findHotText:text charOffset:charsDone pos:pos minX:minXPos hotPoint:hotPoint font:font fontHeight:fontHeight width:width];
                }
                
                //		if (!doDraw) NSLog(@"trunc str %d %x: (%.0f,%.0f) -> (%.0f,%.0f): \"%@\"", doDraw, style, pos.x, pos.y, nextPos->x, nextPos->y, subtext);
                charsDone += termRange.location+1;
                text = [text substringFromIndex: termRange.location+1];
                len = [text length];
            } else {
                if (pos.x <= m_leftMargin) { // entire string has no breakable chars in it and we're already at BOL, use char wrap
                    int maxLines = noWrap ? 1 : 100;
                    if (doDraw) {
                        if (bgColor) {
                            [bgColor set];
                            textSize = [text sizeWithFont:font constrainedToSize: CGSizeMake(width-pos.x, fontHeight*maxLines)
                                            lineBreakMode: noWrap ? UILineBreakModeClip:UILineBreakModeCharacterWrap];
                            CGContextFillRect(context, CGRectMake(minXPos, pos.y, width + m_leftMargin, textSize.height));
                            [fgColor set];
                        }
                        if (!isFixed)
                            textSize = [text drawInRect:CGRectMake(minXPos+pos.x, pos.y, width-pos.x, fontHeight*maxLines) withFont:font
                                          lineBreakMode: noWrap ? UILineBreakModeClip:UILineBreakModeCharacterWrap];
                        else {
                            textSize.width = RTDrawFixedWidthText(context, text, minXPos+pos.x, -fontAscender-pos.y, YES);
                        }
                    }
                    else
                        textSize = [text sizeWithFont:font constrainedToSize: CGSizeMake(width, fontHeight*maxLines)
                                        lineBreakMode: noWrap ? UILineBreakModeClip:UILineBreakModeCharacterWrap];
                    
                    *nextPos = CGPointMake(textSize.width, pos.y + textSize.height);
                    if (hotPoint) {
                        if (hotPoint->y >= pos.y && hotPoint->y < pos.y+fontHeight && hotPoint->x >= minXPos+pos.x && hotPoint->x < minXPos+pos.x+textSize.width)
                            return [self findHotText:text charOffset:charsDone pos:pos minX:minXPos hotPoint:hotPoint font:font fontHeight:fontHeight width:width];
                    }
                    //		    if (!doDraw) NSLog(@"endwrap str %d: (%.0f,%.0f) -> (%.0f,%.0f): %@", doDraw, pos.x, pos.y, nextPos->x, nextPos->y, text);
                    text = nil;
                } else {
                    nextPos->x = 0;
                    nextPos->y = pos.y + fontHeight;
                    ++nLines;
                    while ([text hasPrefix: @" "]) {
                        text = [text substringFromIndex: 1];
                        ++charsDone;
                        len--;
                    }
                }
            }
            pos = *nextPos;
        }
        if (hasEOL) {
            if (doDraw) {
                if (bgColor) {
                    [bgColor set];
                    if (pos.x <= m_leftMargin)
                        pos.x = 0;
                    CGContextFillRect(context, CGRectMake(minXPos+pos.x, pos.y, width+m_rightMargin-pos.x, fontHeight));
                    [fgColor set];
                }
            }
    	    pos.x = m_leftMargin; //bcs was 0
            pos.y += fontHeight;
            ++nLines;
            *nextPos = pos;
        }
        charsDone += len+1;
        text = restOfString;
        len = [text length];
    }
    nextPos->x += minXPos;
    if (doDraw)
        m_prevReverse = isFixed && (style & kFTReverse);
    else
        m_numLines += nLines;
    if (isFixed && !doDraw)
        UIGraphicsEndImageContext();
    
    return NO;
}

-(NSDictionary*)getSaveDataDict {
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                 m_textRuns, @"textRuns", m_textStyles, @"textStyles", m_colorIndex, @"colorIndex", nil ];
    
    NSMutableArray *savedColors = [NSMutableArray arrayWithCapacity: [m_colorArray count]];
    for (UIColor *color in m_colorArray) {	
        CGColorRef colorRef = [color CGColor];
        const CGFloat *colorRGB = CGColorGetComponents(colorRef);
        size_t nc = CGColorGetNumberOfComponents(colorRef);
        NSString *colorStr = [NSString stringWithFormat:  @"#%02X%02X%02X",
                              (int)(colorRGB[0]*255),
                              (int)(colorRGB[nc >=3 ? 1 : 0]*255),
                              (int)(colorRGB[nc >=3 ? 2 : 0]*255)];
        [savedColors addObject: colorStr];
    }
    [dict setObject: savedColors forKey: @"colorArray"];
    
    return dict;
}

- (void)restoreFromSaveDataDict: (NSDictionary*)saveData {
    [m_textRuns release];
    [m_textStyles release];
    [m_colorIndex release];
    
    NSArray *savedTextRuns = [saveData objectForKey: @"textRuns"];
    m_textRuns = [savedTextRuns mutableCopy];
    NSArray *savedStyles = [saveData objectForKey: @"textStyles"];
    m_textStyles = [savedStyles mutableCopy];
    NSArray *savedColorIndex = [saveData objectForKey: @"colorIndex"];
    m_colorIndex = [savedColorIndex mutableCopy];
    
    int count = [m_textRuns count];
    const int kMaxSavedRuns = 80;
    if (count > kMaxSavedRuns) {
        int i = count - kMaxSavedRuns;
        while (i < count-(kMaxSavedRuns-10)) {
            if ([[m_textRuns objectAtIndex: i] hasSuffix: @"\n"])
                break;
            ++i;
        }
        //	NSLog(@"Discarding oldest %d textRuns on restore", i);
        [m_textRuns removeObjectsInRange: NSMakeRange(0, i+1)];
        [m_textStyles removeObjectsInRange: NSMakeRange(0, i+1)];
        [m_colorIndex removeObjectsInRange: NSMakeRange(0, i+1)];
    }
    
    NSArray *savedColorArray = [saveData objectForKey: @"colorArray"];
    if (savedColorArray) {
        [m_colorArray removeAllObjects];
        for (NSString *colorStr in savedColorArray) {
            unsigned int intRGB;
            float floatRGB[4] = { 0.0f, 0.0f, 0.0f, 1.0f };
            
            UIColor *color = nil;
            if ([colorStr characterAtIndex: 0] == '#') {
                NSScanner *scanner = [NSScanner scannerWithString: colorStr];
                [scanner setScanLocation: 1];
                [scanner scanHexInt: &intRGB];
                floatRGB[0] = (float)((intRGB & 0xff0000) >> 16) / 255.0f;
                floatRGB[1] = (float)((intRGB & 0xff00) >> 8) / 255.0f;
                floatRGB[2] = (float)((intRGB & 0xff)) / 255.0f;
                color = [UIColor colorWithRed: floatRGB[0] green:floatRGB[1] blue:floatRGB[2] alpha:1.0];
                [m_colorArray addObject: color];
            }	
        }
    }
    
    // Sanity check - if there are any color indexes out of bounds of the color array, allocate dummy colors for them
    int maxColorIndex = -1;
    for (NSNumber *colIndex in m_colorIndex) {
        int encIndex = [colIndex intValue];
        int bgIndex = (encIndex >> 16) & 0xffff;
        int textIndex = (encIndex & 0xffff);
        if (bgIndex > maxColorIndex)
            maxColorIndex = bgIndex;
        if (textIndex > maxColorIndex)
            maxColorIndex = textIndex;
    }
    if (maxColorIndex > 0) {
        while (maxColorIndex > [m_colorArray count])
            [m_colorArray addObject: [UIColor darkGrayColor]];
    }
    [self reflowText];    
}

-(void)appendText:(NSString*)text {
    int length = [text length];
    if (length == 0)
        return;
    if (length >= 4) {
        // Frotz-specific, try to make sure prompt begins its own span
        NSRange r = [text rangeOfString: @"\n>"];
        if (r.length == 0)
            r = [text rangeOfString: @"\n >"];
        if (r.length > 0 && r.location > 0) {
            [self appendText: [text substringToIndex: r.location+1]];
            m_prevLineNotTerminated = NO;
            text = [text substringFromIndex: r.location+1];
            length -= r.location+1;
        }
    }
    
    if (m_origY > m_lastPt.y)
        m_origY = m_lastPt.y;
    BOOL lineNotTerminated = [text characterAtIndex: length-1] != '\n';
    
    CGFloat updateRowBegin = floorf((m_topMargin+ m_lastPt.y) / [self tileSize].height);
    NSNumber *style = [NSNumber numberWithInt: (int)m_currentTextStyle];
    CGRect frame= [self frame];
    
    CGPoint nextPoint = m_lastPt;
    UIFont *font = [self fontForStyle: m_currentTextStyle];
    
    //NSLog(@"app %@", text);
    if (m_prevLineNotTerminated) {
        int index = [m_textRuns count]-1;
        NSString *newText = [[m_textRuns objectAtIndex: index] stringByAppendingString: text];
        m_lastPt = m_prevPt;
        [self wordWrapTextSize:newText atPoint:&m_lastPt font:font style:m_currentTextStyle fgColor:nil bgColor:nil withRect:frame nextPos:&nextPoint hotPoint:nil doDraw:NO];
        [m_textRuns replaceObjectAtIndex: index withObject: [[newText copy] autorelease]];
    } else {
        [self wordWrapTextSize:text atPoint:&m_lastPt font:font style:m_currentTextStyle fgColor:nil bgColor:nil withRect:frame nextPos:&nextPoint hotPoint:nil doDraw:NO];
        [m_textRuns addObject: [[text copy] autorelease]];
        //NSLog(@"app text count=%d", [m_textRuns count]);
        [m_colorIndex addObject: [NSNumber numberWithInt: (m_currentBGColorIndex << 16) | m_currentTextColorIndex]];
        [m_textPos addObject: [NSValue valueWithCGPoint: m_lastPt]];
        [m_textStyles addObject: style];
    }
    m_prevPt = m_lastPt;
    m_lastPt = nextPoint;
    
    CGFloat updateRowEnd = floorf((m_topMargin+m_lastPt.y) / [self tileSize].height);
    if (updateRowBegin >= m_firstVisibleRow && updateRowBegin <= m_lastVisibleRow) {
        m_lastVisibleRow = updateRowBegin-1;
    } else if (updateRowEnd >= m_firstVisibleRow && updateRowEnd <= m_lastVisibleRow) {
        m_lastVisibleRow = updateRowEnd-1;	
    }
    
    if (m_topMargin+ m_lastPt.y > self.contentSize.height-m_fontHeight-m_bottomMargin) {
        [self setContentSize: CGSizeMake(self.contentSize.width, m_topMargin+ m_lastPt.y + (m_lastPt.x>0?m_fontHeight:0) + m_bottomMargin)];
        //NSLog(@"appendtext new contentsize (%.0f,%.0f) : %@", self.contentSize.width, self.contentSize.height, text);
	}
    int yoff = self.contentOffset.y;
    if (yoff < m_topMargin) {
        removeAnim(self);
        //	[[UIAnimator sharedAnimator] removeAnimationsForTarget:self];
    }
    
    if (m_topMargin+ m_lastPt.y - m_origY > DEFAULT_TILE_HEIGHT/2) {
        [self setNeedsLayout];
        m_origY = m_lastPt.y;
    } else {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(setNeedsLayout) object:nil];
        [self performSelector: @selector(setNeedsLayout) withObject:nil afterDelay:0.03];
    }
    if (m_accessibilityElements) {
        if (m_prevLineNotTerminated)
            [self updateAE];
        else {
            //int count = [m_textRuns count];
            //if (count <= 1 || [[m_textRuns objectAtIndex:count-2] hasSuffix: @"\n\n"])
            [self appendAE];
            //else [self updateAE];
        }
    }
    m_prevLineNotTerminated = lineNotTerminated;
    
}

-(void)setNeedsLayout {
    if (!m_freezeDisplay)
        [super setNeedsLayout];
}

-(void)setNeedsDisplay {
    [super setNeedsDisplay];
}

- (void)reflowText {
    [self clearSelection];
    
    [m_textPos removeAllObjects];
    int len = [m_textRuns count];
    m_lastPt = CGPointMake(m_leftMargin, 0);
    
    m_origY = 0;
    m_prevReverse = NO;
    m_numLines = 0;
    
    CGPoint nextPoint;
    m_prevPt = m_lastPt;
    CGRect frame = [self frame];
    
    for (int i = 0; i < len; ++i) {
        NSString *text = [m_textRuns objectAtIndex: i];
        RichTextStyle style = [[m_textStyles objectAtIndex: i] intValue];
        UIFont *font = [self fontForStyle: style];
        [self wordWrapTextSize:text atPoint:&m_lastPt font:font style:style fgColor:nil bgColor:nil withRect:frame nextPos:&nextPoint hotPoint:nil doDraw:NO];
        [m_textPos addObject: [NSValue valueWithCGPoint: m_lastPt]];
        m_lastPt = nextPoint;	
    }
    m_prevPt = m_lastPt;
    m_prevLineNotTerminated = NO;
    [self setContentSize: CGSizeMake(frame.size.width, m_topMargin+ m_lastPt.y + (m_lastPt.x>0?m_fontHeight:0) + m_bottomMargin)];
    
    [self reloadData];
}

- (RichTextTile *)dequeueReusableTile {
    RichTextTile *tile = [m_reusableTiles anyObject];
    if (tile) {
#if DEBUG_TILE_LAYOUT
        static int i;
        i = (i+1)&3;
        if (i==0)
            [tile setBackgroundColor: [UIColor yellowColor]];
        else if (i==1)
            [tile setBackgroundColor: [UIColor blueColor]];
        else if (i==2)
            [tile setBackgroundColor: [UIColor redColor]];
        else
            [tile setBackgroundColor: [UIColor greenColor]];
#else
        [tile setBackgroundColor: m_currBgColor ? m_currBgColor : m_bgColor];
#endif
        // the only object retaining the tile is our reusableTiles set, so we have to retain/autorelease it
        // before returning it so that it's not immediately deallocated when we remove it from the set
        [[tile retain] autorelease];
        [m_reusableTiles removeObject:tile];
    }
    return tile;
}

- (void)reloadData {
    
    if (m_freezeDisplay)
        return;
    // recycle all tiles so that every tile will be replaced in the next layoutSubviews
    for (UIView *view in [m_tileContainerView subviews]) {
        [m_reusableTiles addObject:view];
        [view removeFromSuperview];
    }
    
    // no rows or columns are now visible; note this by making the firsts very high and the lasts very low
    m_firstVisibleRow = m_firstVisibleColumn = NSIntegerMax;
    m_lastVisibleRow  = m_lastVisibleColumn  = NSIntegerMin;
    
    [self setNeedsLayout];
}

- (void)delayedReloadData {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reloadData) object:nil];
    [self performSelector: @selector(reloadData) withObject:nil afterDelay:0.05];
}

- (RichTextTile *)tileForRow:(int)row column:(int)column {
    
    // re-use a tile rather than creating a new one, if possible
    RichTextTile *tile = [self dequeueReusableTile];
    
    if (!tile) {
        // the scroll view will handle setting the tile's frame, so we don't have to worry about it
        tile = [[[RichTextTile alloc] initWithFrame:CGRectZero] autorelease];
        [tile setBackgroundColor: m_currBgColor ? m_currBgColor : m_bgColor];
        [tile setTextView: self];
        
        // Some of the tiles won't be completely filled, because they're on the right or bottom edge.
        // By default, the image would be stretched to fill the frame of the image view, but we don't
        // want this. Setting the content mode to "top left" ensures that the images around the edge are
        // positioned properly in their tiles. 
        [tile setContentMode:UIViewContentModeTopLeft]; 
    }
    
    return tile;
}

- (void)layoutSubviews {
    if (m_freezeDisplay)
        return;
    [super layoutSubviews];
    
    CGRect visibleBounds = [self bounds];
    float scaledTileWidth  = [self tileSize].width;
    float scaledTileHeight = [self tileSize].height;
    
    // first recycle all tiles that are no longer visible
    for (UIView *tile in [m_tileContainerView subviews]) {
        
        // We want to see if the tiles intersect our (i.e. the scrollView's) bounds, so we need to convert their
        // frames to our own coordinate system
        CGRect scaledTileFrame = [m_tileContainerView convertRect:[tile frame] toView: self];
        scaledTileFrame.origin.y -= 2;  // if layout is called again right after a tile comes to view, at the same coords, it will be recycled w/o this
        scaledTileFrame.size.height += 4;
        // If the tile doesn't intersect, it's not visible, so we can recycle it
        if (! CGRectIntersectsRect(scaledTileFrame, visibleBounds)) {
            [m_reusableTiles addObject:tile];
            //NSLog(@"recycle %@ scaledFrme (%.0f,%.0f,%.0f,%.0f) vis (%.0f,%.0f,%.0f,%.0f)", tile, scaledTileFrame.origin.x, scaledTileFrame.origin.y, scaledTileFrame.size.width, scaledTileFrame.size.height,  visibleBounds.origin.x, visibleBounds.origin.y, visibleBounds.size.width, visibleBounds.size.height);
            [tile removeFromSuperview];
        }
    }
    
    CGSize maxRect = [self contentSize];
    // calculate which rows and columns are visible by doing a bunch of math.
    int maxRow = floorf((maxRect.height-1) / scaledTileHeight); // this is the maximum possible row
    int maxCol = floorf((maxRect.width-1)  / scaledTileWidth);  // and the maximum possible column
    int firstNeededRow = MAX(0, floorf(visibleBounds.origin.y / scaledTileHeight));
    int firstNeededCol = MAX(0, floorf(visibleBounds.origin.x / scaledTileWidth));
    int lastNeededRow  = MIN(maxRow, floorf(CGRectGetMaxY(visibleBounds) / scaledTileHeight));
    int lastNeededCol  = MIN(maxCol, floorf(CGRectGetMaxX(visibleBounds) / scaledTileWidth));
    
    //    CGAffineTransform tr = (CGAffineTransform)[self.superview transform];
    //     NSLog(@"layout subv a=%f b=%f c=%f d=%f tx=%f ty=%f", tr.a, tr.b, tr.c, tr.d, tr.tx, tr.ty);
    
    // iterate through needed rows and columns, adding any tiles that are missing
    for (int row = firstNeededRow; row <= lastNeededRow; row++) {
        for (int col = firstNeededCol; col <= lastNeededCol; col++) {
            
            BOOL tileIsMissing = (m_firstVisibleRow > row || m_firstVisibleColumn > col || 
                                  m_lastVisibleRow  < row || m_lastVisibleColumn  < col);
            if (tileIsMissing) {
                //		NSLog(@"layout row %d col %d fvr %.0f lvr %.0f miss %d visBounds (%.0f,%.0f,%.0f,%.0f) contentSize (%.0f,%.0f)", row, col, m_firstVisibleRow, m_lastVisibleRow, tileIsMissing, visibleBounds.origin.x, visibleBounds.origin.y,		visibleBounds.size.width, visibleBounds.size.height, maxRect.width, maxRect.height);
                UIView *tile = [self tileForRow:row column:col];
                // set the tile's frame so we insert it at the correct position
                
#if 1
                CGRect bounds = CGRectMake(0, 0, scaledTileWidth, scaledTileHeight);
                CGPoint center = CGPointMake(scaledTileWidth * (col+0.5), scaledTileHeight * (row+0.5));
                [tile setCenter: center];
                [tile setBounds: bounds];
#if 0
                CGRect myFrame = [m_tileContainerView frame];
                CGPoint parentCenter = [self center];
                parentCenter.x = myFrame.size.width/2, parentCenter.y = myFrame.size.height/2;
                CGFloat pdx = parentCenter.x - center.x, pdy = parentCenter.y - center.y;
                NSLog(@"parentcenter %f,%f", parentCenter.x, parentCenter.y);
                [tile setCenter: parentCenter];
                [tile setBounds: CGRectMake((col+0.5)*scaledTileWidth-parentCenter.x + random()%511,
                                            (row+0.5)*scaledTileHeight-parentCenter.y + random()%511,
                                            scaledTileWidth, scaledTileHeight)];
#endif
#else
                CGRect frame = CGRectMake(scaledTileWidth * col, scaledTileHeight * row, scaledTileWidth, scaledTileHeight);
                [tile setFrame:frame];
                CGPoint c = [tile center];
                CGRect b = [tile bounds];
                CGRect f = [tile frame];
                NSLog(@"row=%d col=%d, cx=%f, cy=%f, b=(%f,%f,%f,%f) f=(%f,%f,...)", row, col, c.x, c.y, b.origin.x, b.origin.y, b.size.width, b.size.height,
                      f.origin.x, f.origin.y);
#endif
                
                
                //		NSLog(@"got tile %@", tile);
                [m_tileContainerView addSubview:tile];
                [m_tileContainerView bringSubviewToFront: tile];
                //		[self annotateTile: tile];
                [tile setNeedsDisplay];
            }
        }
    }
    
    // update our record of which rows/cols are visible
    m_firstVisibleRow = firstNeededRow; m_firstVisibleColumn = firstNeededCol;
    m_lastVisibleRow  = lastNeededRow;  m_lastVisibleColumn  = lastNeededCol; 
    
    //    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil);
    
}

#define LABEL_TAG 3

- (void)annotateTile:(UIView *)tile {
    static int totalTiles = 0;
    
    UILabel *label = (UILabel *)[tile viewWithTag:LABEL_TAG];
    if (!label) {  
        totalTiles++;  // if we haven't already added a label to this tile, it's a new tile
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(5, 0, 80, DEFAULT_TILE_HEIGHT)];
        
        [label setBackgroundColor:[UIColor clearColor]];
        [label setTag:LABEL_TAG];
        [label setTextColor:[[UIColor greenColor]colorWithAlphaComponent:0.4]];
        [label setShadowColor:[[UIColor blackColor] colorWithAlphaComponent: 0.4]];
        [label setShadowOffset:CGSizeMake(1.0, 1.0)];
        [label setFont:[UIFont boldSystemFontOfSize:40]];
        [label setText:[NSString stringWithFormat:@"%d", totalTiles]];
        [tile addSubview:label];
        [label release];
        //        [[tile layer] setBorderWidth:2];
        //        [[tile layer] setBorderColor:[[UIColor greenColor] CGColor]];
    }
    CGRect frame = [tile frame];
    int row = frame.origin.y / [self tileSize].height;
    if (row & 1)
        [label setBackgroundColor:[[UIColor blueColor] colorWithAlphaComponent:0.1]];
    else 
        [label setBackgroundColor:[[UIColor greenColor] colorWithAlphaComponent:0.1]];
    
    
    [tile bringSubviewToFront:label];
}


- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self setNeedsLayout];
    //    [self clearAE];
    if (m_controller && [m_controller respondsToSelector: @selector(scrollViewDidScroll:)]) {
        [m_controller scrollViewDidScroll:scrollView];
    }
    //    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil);
}


-(void)setFrame:(CGRect)frame {
    //    NSLog(@"rich setframe (%f,%f,%f,%f) topmarg=%d self=%x", frame.origin.x, frame.origin.y, frame.size.width, frame.size.height, m_topMargin, self);
    CGRect oldFrame = self.frame;
    if (m_freezeDisplay) {
        m_delayedFrame = frame;
        return;
    }
    if (!CGRectEqualToRect(frame, oldFrame)) {
        [super setFrame: frame];
        [m_tileContainerView setFrame: CGRectMake(0, 0, frame.size.height, frame.size.width)];
        if (oldFrame.size.width != frame.size.width) {
            [self reflowText];
            if (m_firstVisibleTextRunIndex > 0 && m_firstVisibleTextRunIndex < [m_textPos count]) {
                CGPoint pt = [[m_textPos objectAtIndex: m_firstVisibleTextRunIndex] CGPointValue];
                self.contentOffset = CGPointMake(0, pt.y+m_savedTopYOffset);
            }
        }
    }
}

-(void)prepareForKeyboardShowHide {
    m_firstVisibleTextRunIndex = 0;
}

-(void)rememberTopLineForReflow {
    int i, l = [m_textRuns count];
    CGFloat topY = self.contentOffset.y;
    
    CGPoint lastUniqPt = CGPointMake(0,0), pt;
    int lastUniqIndex = 0;
    for (i=0; i < l; ++i) {
        pt = [[m_textPos objectAtIndex: i] CGPointValue];
        if (pt.y > topY)
            break;
        if (pt.y > lastUniqPt.y)
            lastUniqIndex= i;
        lastUniqPt = pt;
    }
    m_firstVisibleTextRunIndex = lastUniqIndex;
    m_savedTopYOffset = topY - lastUniqPt.y;
}

- (BOOL)isAccessibilityElement
{
    return NO;
}
static NSString *kCommand = @"Command";

- (void)populateAccessibilityElements {
    if (!m_textRuns) return;
    if (!hasAccessibility)
        return;
    
    int count = [m_textRuns count];
    if (m_accessibilityElements)
        [m_accessibilityElements release];
    
    m_accessibilityElements = [[NSMutableArray alloc] initWithCapacity: count];
    
    int startIndex = 0, runCount = 0, i = 0, aeIndex = 0;
    for (NSString *text in m_textRuns) {
        if (i==count-1  || [text hasSuffix: @"\n\n"]) {
            runCount = i - startIndex + 1;
            RichTextAE *e = [[RichTextAE alloc] initWithAccessibilityContainer: self];
            [e setAccessibilityHint: self.accessibilityHint];
            [e setAccessibilityTraits: self.accessibilityTraits];
            NSString *text = @"";
            if ([[m_textRuns objectAtIndex: startIndex] hasPrefix: @">"])
                text = kCommand;
            text = [text stringByAppendingString:[[m_textRuns subarrayWithRange: NSMakeRange(startIndex, runCount)] componentsJoinedByString: @""]];
            [e setAccessibilityValue: text];
            [e setAeIndex: aeIndex++];
            [e setTextIndex: startIndex];
            [e setRunCount: runCount];
            
            [m_accessibilityElements addObject: e];
            [e release];
            startIndex = i+1;
        }
        ++i;
    }
    m_lastAEIndexAnnounced = aeIndex;
    m_lastAEIndexAccessed = 0;
}

-(RichTextAE*)updateAE {
    if (!m_accessibilityElements)
        return nil;
    if (!hasAccessibility)
        return nil;
    
    int count = [m_textRuns count];
    if (!count)
        return nil;
    RichTextAE *e = [m_accessibilityElements objectAtIndex: [m_accessibilityElements count]-1];
    int startIndex = e.textIndex;
    if (startIndex+ e.runCount <= count) {
        int runCount = count - startIndex;
        e.runCount = runCount;
        NSString *text = @"";
        NSString *firstText = [m_textRuns objectAtIndex: startIndex];
        if ([firstText hasPrefix: @">"])
            text = kCommand;
        else if (startIndex > 1 && [[m_textRuns objectAtIndex: startIndex-1] isEqualToString: @">"]) {
            NSRange r = [firstText rangeOfString: @"\n"];
            ++startIndex;
            --runCount;
            if (r.length == 0)
                text = [firstText stringByAppendingString: @"."];
            else {
                text = [firstText substringToIndex: r.location];
                text = [text stringByAppendingString: @"."];
                text = [text stringByAppendingString: [firstText substringFromIndex: r.location]];
            }
        }
        if (runCount > 0)
            text = [text stringByAppendingString: [[m_textRuns subarrayWithRange: NSMakeRange(startIndex, runCount)] componentsJoinedByString: @""]];
        [e setAccessibilityValue: text];
    }  
    return e;  
}

-(void)appendAE {
    if (!hasAccessibility)
        return;
    
    RichTextAE *e = [[RichTextAE alloc] initWithAccessibilityContainer: self];
    int count = [m_textRuns count];
    [e setAccessibilityHint: self.accessibilityHint];
    [e setAccessibilityTraits: self.accessibilityTraits];
    NSString *text = [m_textRuns objectAtIndex: count-1];
    if ([text hasPrefix: @">"])
        text = [kCommand stringByAppendingString: text];
    [e setAccessibilityValue: text];
    [e setAeIndex: [m_accessibilityElements count]];
    [e setTextIndex: count-1];
    [e setRunCount: 1];
    [m_accessibilityElements addObject: e];
    [e release];
}

- (void)markWaitForInput {
#if !NoAccessibility
    if (hasAccessibility && m_numLines > 1 && m_lastAEIndexAnnounced >= 0) {
        UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil);
        if (&UIAccessibilityAnnouncementNotification) {
            NSMutableString *text = [NSMutableString stringWithCapacity: 2048];
            int count = [m_accessibilityElements count];
            if (m_lastAEIndexAnnounced < count) {
                for (int i = m_lastAEIndexAnnounced; i < count; ++i) {
                    [text appendString: [[m_accessibilityElements objectAtIndex:i] accessibilityValue]];
                }
                m_lastAEIndexAnnounced = count;
                UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, text);
            }
        }
    }
#endif
    
}

/* The following methods are implementations of UIAccessibilityContainer protocol methods. */

- (NSInteger)accessibilityElementCount
{
    if (!hasAccessibility)
        return 0;
    
    if (!m_accessibilityElements)
        [self populateAccessibilityElements];
    NSInteger aeCount = [m_accessibilityElements count];
    //NSLog(@"ae count %d", aeCount);
    return aeCount;
}

-(void)clearAE {
    if (m_accessibilityElements) {
        [m_accessibilityElements release];
        m_accessibilityElements = nil;
    }
}


- (id)accessibilityElementAtIndex:(NSInteger)aeIndex
{
    if (!hasAccessibility)
        return nil;
    
    if (!m_accessibilityElements)
        [self populateAccessibilityElements];
    if (aeIndex < [m_accessibilityElements count]) {
        RichTextAE *e = [m_accessibilityElements objectAtIndex: aeIndex];
#if 0
        // update frame lazily when accessed, so we don't have to recalculate them all
        // when you reorient the device
        int startIndex = e.textIndex;
        int runCount = e.runCount;
        int count = [m_textRuns count];
        CGPoint p = [[m_textPos objectAtIndex: startIndex] CGPointValue];
        int endIndex = startIndex + runCount-1;
        CGPoint p2 = endIndex < count-1 ? [[m_textPos objectAtIndex: endIndex+1] CGPointValue] : CGPointMake(0, m_lastPt.y);
        if (p.x <= m_leftMargin)
            p.x = 0;
        CGFloat height = p2.y - p.y, width;
        if (height == 0) {
            height = m_fontHeight;
            width = p2.x - p.x;
        } else {
            p.x = 0;
            width = self.frame.size.width;
        }
        CGRect r = CGRectMake(p.x, p.y + m_topMargin, width, height);
        r = [self convertRect:r toView: self.window];
        [e setAccessibilityFrame: r];
        //NSLog(@"accElemAtIndex %d (%.0f,%.0f,%.0f,%.0f)", aeIndex, p.x, p.y+m_topMargin, width, height);
#endif
        return e;
    }
    return nil;
}

-(void) accessibilityScrollToVisible {
    if (!hasAccessibility)
        return;
    int index = m_lastAEIndexAccessed;
    RichTextAE *e = [m_accessibilityElements objectAtIndex: index];
    CGRect frame = e.accessibilityFrame;
    frame = [self.window convertRect: frame toView:self];
    [self scrollRectToVisible: frame animated:NO];
    //NSLog(@"accscrolltovis %d (%0.f,%0.f) (%0.f,%0.f,%0.f,%0.f)", index, self.contentOffset.x, self.contentOffset.y, frame.origin.x, frame.origin.y, frame.size.width, frame.size.height);
    //    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil);
}

- (NSInteger)indexOfAccessibilityElement:(id)element
{
    RichTextAE *e = element;
    //NSLog(@"index of ae: %d %@", [e textIndex], e);
    return [e textIndex];
}

- (NSArray*)getTextPos {
    return m_textPos;
}

- (void) touchesBegan:(NSSet*)touches withEvent:(UIEvent*)event
{
    
    
    UITouch* touch = [touches anyObject];
    CGPoint touchPoint = [touch locationInView: self], nextPos;
    
    int tapCount = [touch tapCount];
    if (tapCount == 1 && [touch phase]==UITouchPhaseBegan && m_selectionView && [m_selectionView superview]) {
        m_selectedRun = -1;
        m_selectedColumnRange = NSMakeRange(0, 0);
        if (m_selectionView) {
            [m_selectionView setText: @""];
            [m_selectionView removeFromSuperview];
        }
    }
    if (m_selectionDisabled || tapCount != 2 || [self isDecelerating]) {
        [super touchesBegan:touches withEvent:event];
        return;
    }
    //    NSLog(@"rich text touches began pt=(%f,%f)", touchPoint.x, touchPoint.y);
    
    int i, l = [m_textRuns count];
    CGPoint lastUniqPt = CGPointMake(0,0), pt;
    int lastUniqIndex = 0;
    for (i=0; i < l; ++i) {
        CGPoint pt = [[m_textPos objectAtIndex: i] CGPointValue];
        pt.y += m_topMargin;
        if (pt.y + m_fontHeight >= touchPoint.y)
            break;
        if (pt.y > lastUniqPt.y)
            lastUniqIndex= i;
        lastUniqPt = pt;
    }
    i = lastUniqIndex;
	
    int j = 0;
    NSString *text = nil;
    CGRect myRect = [self frame];
    BOOL found = NO;
    while (i < l) {
        pt = [[m_textPos objectAtIndex: i] CGPointValue];
        pt.y += m_topMargin;
        if (pt.y >= touchPoint.y + m_fontHeight)
            break;
        text = [m_textRuns objectAtIndex: i];
        RichTextStyle style = [[m_textStyles objectAtIndex: i] unsignedIntValue];
        UIFont *font = [self fontForStyle: style];
        
        if ((found = [self wordWrapTextSize:text atPoint:&pt font:font style:style fgColor:nil bgColor:nil withRect:myRect nextPos:&nextPos hotPoint:&touchPoint doDraw:NO]))
            break;
        i++; j++;
    }
    m_selectedRun = -1;
    if (found) {
        m_selectedRun = i;
    } else {
        m_selectedColumnRange = NSMakeRange(0, 0);
        [m_selectionView setText: @""];
        [m_selectionView removeFromSuperview];
    }
    
    [super touchesBegan:touches withEvent:event];
}

- (void) touchesMoved:(NSSet*)touches withEvent:(UIEvent*)event {
    [super touchesMoved: touches  withEvent:event];
}

- (void) touchesCancelled:(NSSet*)touches withEvent:(UIEvent*)event {
    [super touchesCancelled: touches withEvent:event];
}

//static BOOL autoprint = YES;

- (void) touchesEnded:(NSSet*)touches withEvent:(UIEvent*)event
{
#if 0
    UITouch*            touch = [touches anyObject];
    int tapCount = [touch tapCount];
    if (![self isDecelerating]) {
        if (tapCount == 3) {
            [self clear];
            autoprint = NO;
        } else if (autoprint)
            autoprint = NO;
        else {
            autoprint = YES;
            [m_controller appendText];
        }
    }
#endif
    [super touchesEnded: touches withEvent: event];
}
@end

@implementation RichTextAE

@synthesize textIndex = m_textIndex;
@synthesize aeIndex = m_aeIndex;
@synthesize runCount = m_runCount;

-(CGRect)accessibilityFrame {
    //NSLog(@"accframe %d", m_aeIndex);
    RichTextView *v = [self accessibilityContainer];
    v.lastAEIndexAccessed = m_aeIndex;
    
    // update frame lazily when accessed, so we don't have to recalculate them all
    // when you reorient the device
    int startIndex = m_textIndex;
    int runCount = m_runCount;
    NSArray *textPos = [v getTextPos];
    int count = [textPos count];
    CGPoint p = [[textPos objectAtIndex: startIndex] CGPointValue];
    int endIndex = startIndex + runCount-1;
    CGPoint p2 = endIndex < count-1 ? [[textPos objectAtIndex: endIndex+1] CGPointValue] : [v lastPt];
    if (p.x <= [v leftMargin])
        p.x = 0;
    CGFloat height = p2.y - p.y, width;
    if (height == 0) {
        height = 10;
        width = p2.x - p.x;
    } else {
        p.x = 0;
        width = v.frame.size.width;
    }
    CGRect r = CGRectMake(p.x, p.y + [v topMargin], width, height);
    
    UIWindow *window = [[self accessibilityContainer] window];
    r = [v convertRect:r toView:window];
    r = [window convertRect:r toWindow:nil];
    
    //    r = [v convertRect:r toView: v.window];    
    return r;
    
    //    return [super accessibilityFrame];
}

-(void)dealloc {
    //    NSLog(@"rtae dealloc idx=%d", m_textIndex);
    [super dealloc];
}

@end

#if 0
@interface TextController : UIViewController <UIScrollViewDelegate> {
    RichTextView *m_textView;
}
@end

@implementation TextController

-(BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return YES;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    [m_textView rememberTopLineForReflow];
    [super willRotateToInterfaceOrientation: toInterfaceOrientation duration:duration];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    [super didRotateFromInterfaceOrientation: fromInterfaceOrientation];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [m_textView setNeedsLayout];
}

- (void)loadView {
    [super loadView];
    
    
    m_textView = [[RichTextView alloc] initWithFrame: [[self view] bounds]];  // CGRectMake(0, 0, m_scrollView.frame.size.width, m_scrollView.frame.size.height)];
    [m_textView setController: self];
    [self.view addSubview: m_textView];
    
    [m_textView getOrAllocColorIndex: [UIColor redColor]];
    [m_textView getOrAllocColorIndex: [UIColor greenColor]];
    [m_textView getOrAllocColorIndex: [UIColor blueColor]];
    [m_textView getOrAllocColorIndex: [UIColor orangeColor]];
    
    [m_textView appendText: @"Tapping once in the text should bring up a test UIAlert box.\n"
     "If you build this under 3.0, it works fine. "
     "If you build it under 2.2.1 or earlier and run it on a 3.0 device, the alert doesn't happen "
     "because touchesEnded never gets called in the UITextViewClass]\n"
     "\n\nMore text follows so you can scroll; scrolling should not bring up the alert box\n"
     ];
    [self performSelector: @selector(appendText) withObject: nil afterDelay:0.1];
    
    
}

-(void)appendText {
    char *words[] = {
        "grand-father", "mooop",
        "If you build it under 2.2.1 or earlier and run it on a 3.0 device,\nthe alert doesn't happen because touchesEnded never gets\ncalled in the UITextViewClass",
        "the", "a", "cow", "enemy", "fuqua", "zifmia", "rezrov", "Barack Obama is your new bicycle", "Now is the", "antidisestablishment",
        "Saturn", "pizza", "water", "throw", "plow",
        "grand-father"
    };
    int w = random() % 18;
    int s = random() % 15;
    int c = random() % 20;
    int b = random() % 30;
    [m_textView setTextStyle: (RichTextStyle)s];
    if (c < 4)
        [m_textView setTextColorIndex: c+1];
    if (b < 4 && b!=c)
        [m_textView setBgColorIndex: b+1];
    [m_textView appendText: [NSString stringWithUTF8String: words[w]]];
    [m_textView appendText: @" "];
    [m_textView setTextColorIndex: 0];
    [m_textView setBgColorIndex: 0];
    if (autoprint)
        [self performSelector: @selector(appendText) withObject: nil afterDelay:0.002];
}

-(void)dealloc {
    [super dealloc];
}
@end
#endif
