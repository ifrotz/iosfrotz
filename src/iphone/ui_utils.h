/*
 *  ui_utils.h
 *  Frotz
 *
 *  Created by Craig Smith on 8/3/08.
 *  Copyright 2008 Craig Smith. All rights reserved.
 *
 */
#include <UIKit/UIKit.h>

UIImage *scaledUIImage(UIImage *image, size_t newWidth, size_t newHeight);
UIImage *drawUIImageInImage(UIImage *image, int x, int y, size_t scaleWidth, size_t scaleHeight, UIImage *destImage);
UIImage *drawRectInImage(unsigned int color, CGFloat x, CGFloat y, CGFloat width, CGFloat height, UIImage *destImage);
UIImage *createBlankImage(unsigned int bgColor, size_t destWidth, size_t destHeight);
NSData *imageDataFromBlorb(NSString *blorbFile);
BOOL metaDataFromBlorb(NSString *blorbFile, NSString **title, NSString **author, NSString **description, NSString **tuid);
UIColor *UIColorFromInt(unsigned int color);
