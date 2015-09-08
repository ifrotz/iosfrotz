//
//  RichTextStyle.h
//  Frotz
//
//  Created by Craig Smith on 6/1/11.
//  Copyright 2011 Craig Smith. All rights reserved.
//

#include <CoreFoundation/CFBase.h>


typedef CF_OPTIONS(unsigned int, RichTextStyle) { RichTextStyleNormal=0, RichTextStyleBold=1,
    RichTextStyleItalic=2, RichTextStyleFixedWidth=4, RichTextStyleFontStyleMask=7,
    RichTextStyleReverse=8, RichTextStyleNoWrap=16, RichTextStyleRightJustification=32,
    RichTextStyleCentered=64, RichTextStyleImage=512, RichTextStyleInMargin=1024 };
enum { kFTImageNumShift = 20 };

#pragma mark compatibility macros
#define kFTNormal RichTextStyleNormal
#define kFTBold RichTextStyleBold
#define kFTItalic RichTextStyleItalic
#define kFTFixedWidth RichTextStyleFixedWidth
#define kFTFontStyleMask RichTextStyleFontStyleMask
#define kFTReverse RichTextStyleReverse
#define kFTNoWrap RichTextStyleNoWrap
#define kFTRightJust RichTextStyleRightJustification
#define kFTCentered RichTextStyleCentered
#define kFTImage RichTextStyleImage
#define kFTInMargin RichTextStyleInMargin
