//
//  UIFontExt.h
//  Frotz
//
//  Created by Craig Smith on 3/13/10.
//  Copyright 2010 Craig Smith. All rights reserved.
//

#import <UIKit/UIKit.h>

// these masks are returned by the private UIFont fontTraits method, which we can't use for the
// app store.  The font trait method lamely just looks for substrings in the font name to
// identify bold, italic, etc. and returns those bits, so if Apple ever makes this
// method available again, I can switch back to using it with no effort.
typedef NS_OPTIONS(unsigned int, UIFontTraits) {
    UINormalFontMask = 0,
    UIItalicFontMask = 0x00000001, 
    UIBoldFontMask = 0x00000002, 
    UIUnboldFontMask = 0x00000004, 
    UINonStandardCharacterSetFontMask = 0x00000008, 
    UINarrowFontMask = 0x00000010, 
    UIExpandedFontMask = 0x00000020, 
    UICondensedFontMask = 0x00000040, 
    UISmallCapsFontMask = 0x00000080, 
    UIPosterFontMask = 0x00000100, 
    UICompressedFontMask = 0x00000200, 
    UIFixedPitchFontMask = 0x00000400, 
    UIUnitalicFontMask = 0x01000000 
}; 


@interface UIFont (FontExt) 
-(UIFontTraits)fontTraits;
@end
