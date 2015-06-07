//
//  RichTextStyle.h
//  Frotz
//
//  Created by Craig Smith on 6/1/11.
//  Copyright 2011 Craig Smith. All rights reserved.
//
typedef enum { kFTNormal=0, kFTBold=1, kFTItalic=2, kFTFixedWidth=4, kFTFontStyleMask=7, kFTReverse=8, kFTNoWrap=16,
    kFTRightJust=32, kFTCentered=64, kFTImage=512, kFTInMargin=1024 } RichTextStyle;
enum { kFTImageNumShift = 20 };

