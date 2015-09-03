//
//  UIFontExt.m
//  Frotz
//
//  Created by Craig Smith on 3/13/10.
//  Copyright 2010 Craig Smith. All rights reserved.
//

#import "UIFontExt.h"


@implementation UIFont (FontExt)
-(UIFontTraits)fontTraits {
    NSString *name = [self fontName];
    int traits = UINormalFontMask;
    if ([name rangeOfString:@"bold" options: NSCaseInsensitiveSearch].length > 0)
	traits |= UIBoldFontMask;
    if ([name rangeOfString:@"italic" options: NSCaseInsensitiveSearch].length > 0
	|| [name rangeOfString:@"oblique" options: NSCaseInsensitiveSearch].length > 0)
	traits |= UIItalicFontMask;
    return traits;
}
@end
