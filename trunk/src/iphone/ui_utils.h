/*
 *  ui_utils.h
 *  Frotz
 *
 *  Created by Craig Smith on 8/3/08.
 *  Copyright 2008 Craig Smith. All rights reserved.
 *
 */
#include <UIKit/UIKit.h>

CGContextRef createBlankFilledCGContext(unsigned int bgColor, size_t destWidth, size_t destHeight);
void drawRectInCGContext(CGContextRef cgctx, unsigned int color, CGFloat x, CGFloat y, CGFloat width, CGFloat height);
void drawCGImageInCGContext(CGContextRef cgctx, CGImageRef imageRef, int x, int y, size_t scaleWidth, size_t scaleHeight);

CGImageRef drawCGImageInCGImage(CGImageRef imageRef, int x, int y, size_t scaleWidth, size_t scaleHeight, CGImageRef destImageRef);
CGImageRef createBlankCGImage(unsigned int bgColor, size_t destWidth, size_t destHeight);
CGImageRef drawRectInCGImage(unsigned int color, CGFloat x, CGFloat y, CGFloat width, CGFloat height, CGImageRef destImageRef);

UIImage *scaledUIImage(UIImage *image, size_t newWidth, size_t newHeight);
UIImage *drawUIImageInUIImage(UIImage *image, int x, int y, size_t scaleWidth, size_t scaleHeight, UIImage *destImage);
UIImage *drawRectInUIImage(unsigned int color, CGFloat x, CGFloat y, CGFloat width, CGFloat height, UIImage *destImage);
UIImage *createBlankUIImage(unsigned int bgColor, size_t destWidth, size_t destHeight);
NSData *imageDataFromBlorb(NSString *blorbFile);
BOOL metaDataFromBlorb(NSString *blorbFile, NSString **title, NSString **author, NSString **description, NSString **tuid);
BOOL readGLULheaderFromUlxOrBlorb(const char *filename, char *glulHeader);
UIColor *UIColorFromInt(unsigned int color);
