/*
 *  ui_utils.c
 *  Frotz
 *
 *  Created by Craig Smith on 8/3/08.
 *  Copyright 2008 Craig Smith. All rights reserved.
 *
 */

#include "iphone_frotz.h"
#include "ui_utils.h"

static CGContextRef CreateARGBBitmapContext (size_t pixelsWide, size_t pixelsHigh);

UIImage *scaledUIImage(UIImage *image, size_t newWidth, size_t newHeight)
{
    if (!image)
        return nil;
    CGImageRef inImage = [image CGImage];
    if (!inImage)
        return nil;
	
    CGSize screenSize = [[UIScreen mainScreen] applicationFrame].size;
    
    int origWidth = CGImageGetWidth(inImage);
    int origHeight = CGImageGetHeight(inImage);
    UIImage *img = nil;
    if (newWidth == 0 && newHeight == 0) {
        if (!gLargeScreenDevice &&
            (origHeight <= screenSize.height*2 && origWidth <= screenSize.width*2)
            && [image respondsToSelector:@selector(scale)]) {
            // ??? can we also check if the device actually supports scale > 1.0?
            if ([image scale] < 2.0 && (origHeight > screenSize.height || origWidth > screenSize.width))
                img = [UIImage imageWithCGImage:inImage scale:2.0 orientation:UIImageOrientationUp];
            else
                img = image;
            return img;
        }
        
        newWidth = newHeight = screenSize.width; // fall thru...
    }
    
    if (origWidth < newWidth || origHeight < newHeight) {
        newWidth = origWidth;
        newHeight = origHeight;
    } else if (origWidth >= origHeight) {
        newHeight = (int)(origHeight * ((double)newWidth / origWidth));    
    } else {
        newWidth = (int)(origWidth * ((double)newHeight / origHeight));    
    }
    if (origWidth==newWidth && origHeight==newHeight)
        return image;

    CGFloat scale = 1.0;
    if ([[UIScreen mainScreen] respondsToSelector:@selector(scale)])
        scale = [[UIScreen mainScreen] scale];
    
    if (scale > 1.0) {
        newWidth *= scale;
        newHeight *= scale;
    }
    // Create the bitmap context
    CGContextRef cgctx = CreateARGBBitmapContext(newWidth, newHeight);
    if (cgctx == NULL)     // error creating context
        return nil;
    
    // Get image width, height. We'll use the entire image.
    CGRect rect = {{0,0},{newWidth,newHeight}};
    
    // Draw the image to the bitmap context. Once we draw, the memory
    // allocated for the context for rendering will then contain the
    // raw image data in the specified color space.
    CGContextSetRGBFillColor(cgctx, 1.0, 1.0, 1.0, 1.0);
    CGContextFillRect(cgctx, rect);
    CGContextDrawImage(cgctx, rect, inImage);
    
    CGImageRef newRef = CGBitmapContextCreateImage(cgctx);
    
    void *data = CGBitmapContextGetData(cgctx);
    
    // When finished, release the context
    CGContextRelease(cgctx);
    if (scale > 1.0)
        img = [UIImage imageWithCGImage: newRef scale:scale orientation:UIImageOrientationUp];
    else
        img= [UIImage imageWithCGImage: newRef];

    CGImageRelease(newRef);
    // Free image data memory for the context
    if (data)
        free(data);
    
    return img;
}

UIImage *drawUIImageInImage(UIImage *image, int x, int y, size_t scaleWidth, size_t scaleHeight, UIImage *destImage) {

    if (!image || !destImage)
        return nil;
    CGImageRef imageRef = [image CGImage];
    CGImageRef destImageRef = [destImage CGImage];
    destImageRef = drawCGImageInCGImage(imageRef, x, y, scaleWidth, scaleHeight, destImageRef);
    UIImage *img= [UIImage imageWithCGImage: destImageRef];
    CGImageRelease(destImageRef);
    return  img;
}

void drawCGImageInCGContext(CGContextRef cgctx, CGImageRef imageRef, int x, int y, size_t scaleWidth, size_t scaleHeight)
{
    int destHeight = CGBitmapContextGetHeight(cgctx);
    CGImageRef inImage = imageRef;
    if (!inImage)
        return;
//    NSLog(@"draw img %p +%d+%d %dx%d", imageRef, x, y, scaleWidth, scaleHeight);
    CGRect rect = {{x, (int)destHeight-y-(int)scaleHeight},{scaleWidth,scaleHeight}};

    CGContextDrawImage(cgctx, rect, inImage);

}

CGImageRef drawCGImageInCGImage(CGImageRef imageRef, int x, int y, size_t scaleWidth, size_t scaleHeight, CGImageRef destImageRef)
{
    if (!imageRef || !destImageRef)
        return nil;
    CGImageRef inImage = imageRef;
    CGImageRef origImage = destImageRef;
    
    if (!inImage || !origImage)
        return nil;
    
    size_t destWidth = CGImageGetWidth(destImageRef);
    size_t destHeight = CGImageGetHeight(destImageRef);
    
    if (scaleHeight > destHeight) {
        scaleHeight /= 2; 
    }
    if (scaleWidth > destWidth) {
        scaleWidth /= 2;
    }
    
    // Create the bitmap context
    CGContextRef cgctx = CreateARGBBitmapContext(destWidth, destHeight);
    if (cgctx == NULL)     // error creating context
        return nil;
    
    // Get image width, height. We'll use the entire image.
    CGRect destRect = {{0,0},{destWidth,destHeight}};
    
    CGContextDrawImage(cgctx, destRect, origImage);
    
    CGRect rect = {{x, destHeight-y-scaleHeight},{scaleWidth,scaleHeight}};
    
    // Draw the image to the bitmap context. Once we draw, the memory
    // allocated for the context for rendering will then contain the
    // raw image data in the specified color space.
    CGContextDrawImage(cgctx, rect, inImage);
    
    CGImageRef newRef = CGBitmapContextCreateImage(cgctx);
    
    void *data = CGBitmapContextGetData(cgctx);
    
    // When finished, release the context
    CGContextRelease(cgctx);
    // Free image data memory for the context
    if (data)
        free(data);
    
    return newRef;
}

UIImage *drawRectInUIImage(unsigned int color, CGFloat x, CGFloat y, CGFloat width, CGFloat height, UIImage *destImage) {
    if (!destImage)
        return nil;
    CGImageRef origImage = [destImage CGImage];
    CGImageRef newRef = drawRectInCGImage(color, x, y, width, height, origImage);
    UIImage *img= [UIImage imageWithCGImage: newRef];
    CGImageRelease(newRef);
    return img;

}

void drawRectInCGContext(CGContextRef cgctx, unsigned int color, CGFloat x, CGFloat y, CGFloat width, CGFloat height) {
    //size_t destWidth = CGBitmapContextGetHeight(cgctx);
    size_t destHeight = CGBitmapContextGetHeight(cgctx);
    //CGRect destRect = {{0,0},{destWidth,destHeight}};

    CGFloat red = ((color >> 16) & 0xff) / 255.0;
    CGFloat green = ((color >> 8) & 0xff) / 255.0;
    CGFloat blue = (color & 0xff) / 255.0;
    CGContextSetRGBFillColor(cgctx, red, green, blue, 1.0);
    CGContextFillRect(cgctx, CGRectMake(x, destHeight-y-height, width, height));
    
}

CGImageRef drawRectInCGImage(unsigned int color, CGFloat x, CGFloat y, CGFloat width, CGFloat height, CGImageRef destImageRef)
{
    if (!destImageRef)
        return nil;
    CGImageRef origImage = destImageRef;

    size_t destWidth = CGImageGetWidth(origImage);
    size_t destHeight = CGImageGetHeight(origImage);
    
    // Create the bitmap context
    CGContextRef cgctx = CreateARGBBitmapContext(destWidth, destHeight);
    if (cgctx == NULL)     // error creating context
        return nil;
    
    CGRect destRect = {{0,0},{destWidth,destHeight}};
    
    CGContextDrawImage(cgctx, destRect, origImage);
    
    CGFloat red = ((color >> 16) & 0xff) / 255.0;
    CGFloat green = ((color >> 8) & 0xff) / 255.0;
    CGFloat blue = (color & 0xff) / 255.0;
    CGContextSetRGBFillColor(cgctx, red, green, blue, 1.0);
    CGContextFillRect(cgctx, CGRectMake(x, destHeight-y-height, width, height));
    
    CGImageRef newRef = CGBitmapContextCreateImage(cgctx);
    
    void *data = CGBitmapContextGetData(cgctx);
    
    // When finished, release the context
    CGContextRelease(cgctx);
    
    // Free image data memory for the context
    if (data)
        free(data);
    
    return newRef;
}

UIColor *UIColorFromInt(unsigned int color) {
    CGFloat red = ((color >> 16) & 0xff) / 255.0;
    CGFloat green = ((color >> 8) & 0xff) / 255.0;
    CGFloat blue = (color & 0xff) / 255.0;
    return [UIColor colorWithRed:red green:green blue:blue alpha:1.0];
}


CGContextRef createBlankFilledCGContext(unsigned int bgColor, size_t destWidth, size_t destHeight) {
    CGContextRef cgctx = CreateARGBBitmapContext(destWidth, destHeight);
    
    CGFloat red = ((bgColor >> 16) & 0xff) / 255.0;
    CGFloat green = ((bgColor >> 8) & 0xff) / 255.0;
    CGFloat blue = (bgColor & 0xff) / 255.0;
    CGContextSetRGBFillColor(cgctx, red, green, blue, 1.0);
    CGContextFillRect(cgctx, CGRectMake(0, 0, destWidth, destHeight));
//`    NSLog(@"new cgctx %p", cgctx);
    return cgctx;
}

CGImageRef createBlankCGImage(unsigned int bgColor, size_t destWidth, size_t destHeight) {
    CGContextRef cgctx = createBlankFilledCGContext(bgColor, destWidth, destHeight);
    CGImageRef newRef = CGBitmapContextCreateImage(cgctx);
    
    void *data = CGBitmapContextGetData(cgctx);
    
    // When finished, release the context
    CGContextRelease(cgctx);
    
    // Free image data memory for the context
    if (data)
        free(data);
    
    return newRef;
}

UIImage *createBlankUIImage(unsigned int bgColor, size_t destWidth, size_t destHeight) {
    // Free image data memory for the context
    CGImageRef imgRef = createBlankCGImage(bgColor, destWidth, destHeight);
    UIImage *img= [UIImage imageWithCGImage: imgRef];
    CGImageRelease(imgRef);
    return img;
}

CGContextRef CreateARGBBitmapContext (size_t pixelsWide, size_t pixelsHigh)
{
    CGContextRef    context = NULL;
    CGColorSpaceRef colorSpace;
    void *          bitmapData;
    int             bitmapByteCount;
    int             bitmapBytesPerRow;
    
    // Declare the number of bytes per row. Each pixel in the bitmap in this
    // example is represented by 4 bytes; 8 bits each of red, green, blue, and
    // alpha.
    bitmapBytesPerRow   = (pixelsWide * 4);
    bitmapByteCount     = (bitmapBytesPerRow * pixelsHigh);
    
    // Use the generic RGB color space.
    colorSpace = CGColorSpaceCreateDeviceRGB();
    if (colorSpace == NULL)
    {
        NSLog(@"Error allocating color space\n");
        return NULL;
    }
    
    // Allocate memory for image data. This is the destination in memory
    // where any drawing to the bitmap context will be rendered.
    bitmapData = malloc( bitmapByteCount );
    if (bitmapData == NULL)
    {
        NSLog(@"BitmapContext memory not allocated!");
        CGColorSpaceRelease( colorSpace );
        return NULL;
    }
    
    // Create the bitmap context. We want pre-multiplied ARGB, 8-bits
    // per component. Regardless of what the source image format is
    // (CMYK, Grayscale, and so on) it will be converted over to the format
    // specified here by CGBitmapContextCreate.
    context = CGBitmapContextCreate (bitmapData,
                                     pixelsWide,
                                     pixelsHigh,
                                     8,      // bits per component
                                     bitmapBytesPerRow,
                                     colorSpace,
                                     kCGImageAlphaPremultipliedFirst);
    if (context == NULL)
    {
        free (bitmapData);
        NSLog(@"Context not created!");
    }
    
    // Make sure and release colorspace before returning
    CGColorSpaceRelease( colorSpace );
    
    return context;
}

BOOL readGLULheaderFromUlxOrBlorb(const char *filename, char *glulHeader) {
    BOOL found = NO;
    FILE *fp;
    if ((fp = os_path_open(filename, "rb")) == NULL)
        return NO;
    unsigned char zblorbbuf[48];
    unsigned char *z;
    unsigned int fileSize=0, chunkSize=0, pos;
    while (1) {
        if (fread(zblorbbuf, 1, 12, fp)!=12)
            break;
        z = zblorbbuf;
        if (z[0]=='G' && z[1]=='l' && z[2]=='u' && z[3]=='l')
            goto foundGLUL;
        if (*z++ != 'F') break;
        if (*z++ != 'O') break;
        if (*z++ != 'R') break;
        if (*z++ != 'M') break;
        fileSize = (z[0]<<24)|(z[1]<<16)|(z[2]<<8)|z[3];
        z += 4;
        if (*z++ != 'I') break;
        if (*z++ != 'F') break;
        if (*z++ != 'R') break;
        if (*z   != 'S') break;
        pos = 12;
        while (pos < fileSize) {
            if (fread(zblorbbuf, 1, 8, fp) != 8)
                break;
            pos += 8;
            z = zblorbbuf+4;
            chunkSize = (z[0]<<24)|(z[1]<<16)|(z[2]<<8)|z[3];
            if (chunkSize % 1 == 1)
                chunkSize++;
            z = zblorbbuf;
            if (chunkSize >= 48 && z[0]=='G' && z[1]=='L' && z[2]=='U' && z[3]=='L') {
                if (fread(zblorbbuf, 1, 48, fp)!=48)
                    break;
                if (z[0]=='G' && z[1]=='l' && z[2]=='u' && z[3]=='l') {
                foundGLUL:
                    found = YES;
                    if (glulHeader)
                        memcpy(glulHeader, z, 48);
                }
                break;
            } else {
                pos += chunkSize;
                fseek (fp, pos, SEEK_SET);
            }
        }
        break;
    }
    fclose(fp);
    return found;
}


BOOL metaDataFromBlorb(NSString *blorbFile, NSString **title, NSString **author, NSString **description, NSString **tuid) {
    const char *filename = [blorbFile UTF8String];
    BOOL found = NO;
    FILE *fp;
    if ((fp = os_path_open(filename, "rb")) == NULL)
        return NO;
    unsigned char zblorbbuf[16];
    unsigned char *z;
    unsigned int fileSize=0, chunkSize=0, pos;
    while (1) {
        if (fread(zblorbbuf, 1, 12, fp)!=12)
            break;
        z = zblorbbuf;
        if (*z++ != 'F') break;
        if (*z++ != 'O') break;
        if (*z++ != 'R') break;
        if (*z++ != 'M') break;
        fileSize = (z[0]<<24)|(z[1]<<16)|(z[2]<<8)|z[3];
        z += 4;
        if (*z++ != 'I') break;
        if (*z++ != 'F') break;
        if (*z++ != 'R') break;
        if (*z   != 'S') break;
        pos = 12;
        while (pos < fileSize) {
            if (fread(zblorbbuf, 1, 8, fp) != 8)
                break;
            pos += 8;
            z = zblorbbuf+4;
            chunkSize = (z[0]<<24)|(z[1]<<16)|(z[2]<<8)|z[3];
            if (chunkSize % 1 == 1)
                chunkSize++;
            z = zblorbbuf;
            if (z[0]=='I' && z[1]=='F' && z[2]=='m' && z[3]=='d') {
                char *buf = malloc(chunkSize+1);
                if (!buf)
                    break;
                buf[chunkSize] = 0;
                if (fread(buf, 1, chunkSize, fp) != chunkSize) {
                    free(buf);
                    break;
                }
                NSString *xmlString = [NSString stringWithCString: buf encoding: NSUTF8StringEncoding];
                NSRange r = [xmlString rangeOfString: @"<identification>"], r2 = [xmlString rangeOfString: @"</identification>"];
                if (r.length && r2.length) {
                    NSRange r3 = [xmlString rangeOfString:@"<tuid>" options:0 range: NSMakeRange(r.location+r.length, r2.location-(r.location+r.length))];
                    if (r3.length) {
                        NSRange r4 = [xmlString rangeOfString:@"</tuid>" options:0 range: NSMakeRange(r3.location+r3.length, r2.location-(r3.location+r3.length))];
                        if (r4.length) {
                            NSString *xtuid = [xmlString substringWithRange: NSMakeRange(r3.location+r3.length, r4.location-(r3.location+r3.length))];
                            if (tuid)
                                *tuid = xtuid;
                        }
                    }
                }
                r = [xmlString rangeOfString: @"<bibliographic>"]; r2 = [xmlString rangeOfString: @"</bibliographic>"];
                if (r.length && r2.length) {
                    NSRange r3 = [xmlString rangeOfString:@"<title>" options:0 range: NSMakeRange(r.location+r.length, r2.location-(r.location+r.length))];
                    if (r3.length) {
                        NSRange r4 = [xmlString rangeOfString:@"</title>" options:0 range: NSMakeRange(r3.location+r3.length, r2.location-(r3.location+r3.length))];
                        if (r4.length) {
                            found = YES;
                            NSString *xtitle = [xmlString substringWithRange: NSMakeRange(r3.location+r3.length, r4.location-(r3.location+r3.length))];
                            if (title) {
                                xtitle = [xtitle stringByReplacingOccurrencesOfString: @"&amp;" withString:@"&"];
                                xtitle = [xtitle stringByReplacingOccurrencesOfString: @"&lt;" withString:@"<"];
                                xtitle = [xtitle stringByReplacingOccurrencesOfString: @"&gt;" withString:@">"];                                         
                                *title = xtitle;
                            }
                        }
                    }
                    r3 = [xmlString rangeOfString:@"<author>" options:0 range: NSMakeRange(r.location+r.length, r2.location-(r.location+r.length))];
                    if (r3.length) {
                        found = YES;
                        NSRange r4 = [xmlString rangeOfString:@"</author>" options:0 range: NSMakeRange(r3.location+r3.length, r2.location-(r3.location+r3.length))];
                        if (r4.length) {
                            NSString *xauthor = [xmlString substringWithRange: NSMakeRange(r3.location+r3.length, r4.location-(r3.location+r3.length))];
                            if (author) {
                                xauthor = [xauthor stringByReplacingOccurrencesOfString: @"&amp;" withString:@"&"];
                                xauthor = [xauthor stringByReplacingOccurrencesOfString: @"&lt;" withString:@"<"];
                                xauthor = [xauthor stringByReplacingOccurrencesOfString: @"&gt;" withString:@">"];                                         
                                *author = xauthor;
                            }
                        }
                    }
                    r3 = [xmlString rangeOfString:@"<description>" options:0 range: NSMakeRange(r.location+r.length, r2.location-(r.location+r.length))];
                    if (r3.length) {
                        found = YES;
                        NSRange r4 = [xmlString rangeOfString:@"</description>" options:0 range: NSMakeRange(r3.location+r3.length, r2.location-(r3.location+r3.length))];
                        if (r4.length) {
                            NSString *xdescript = [xmlString substringWithRange: NSMakeRange(r3.location+r3.length, r4.location-(r3.location+r3.length))];
                            if (xdescript) {
                                // descript should already have &,<,> encoded in HTML, and no other tags but <br/>
                                *description = xdescript;
                            }
                        }
                    }
                }
                free(buf);
            } else
                ;//printf("Skipping chunk '%c%c%c%c'\n", z[0],z[1],z[2],z[3]);
            pos += chunkSize;
            fseek (fp, pos, SEEK_SET);
        }
        break;
    }
    fclose(fp);
    return found;

}

NSData *imageDataFromBlorb(NSString *blorbFile) {
    const char *filename = [blorbFile UTF8String];
    NSData *data = nil;
    FILE *fp;
    if ((fp = os_path_open(filename, "rb")) == NULL)
        return nil;
    unsigned char zblorbbuf[16];
    unsigned char *z;
    unsigned int fileSize=0, chunkSize=0, numEntries=0, pictOffset=0, pos,i;
    while (1) {
        if (fread(zblorbbuf, 1, 12, fp)!=12)
            break;
        z = zblorbbuf;
        if (*z++ != 'F') break;
        if (*z++ != 'O') break;
        if (*z++ != 'R') break;
        if (*z++ != 'M') break;
        fileSize = (z[0]<<24)|(z[1]<<16)|(z[2]<<8)|z[3];
        z += 4;
        if (*z++ != 'I') break;
        if (*z++ != 'F') break;
        if (*z++ != 'R') break;
        if (*z   != 'S') break;
        pos = 12;
        while (pos < fileSize) {
            if (fread(zblorbbuf, 1, 8, fp) != 8)
                break;
            pos += 8;
            z = zblorbbuf+4;
            chunkSize = (z[0]<<24)|(z[1]<<16)|(z[2]<<8)|z[3];
            if (chunkSize % 1 == 1)
                chunkSize++;
            z = zblorbbuf;
            if (z[0]=='R' && z[1]=='I' && z[2]=='d' && z[3]=='x') {
                if (fread(zblorbbuf, 1, 4, fp) != 4)
                    break;
                pos += 4;
                numEntries = (z[0]<<24)|(z[1]<<16)|(z[2]<<8)|z[3];
                printf("Found Ridx chunk of size %d with %d entries at pos %d\n", chunkSize, numEntries, pos);
                for (i=0; i < numEntries; ++i) {		
                    if (fread(zblorbbuf, 1, 12, fp) != 12)
                        break;
                    if (z[0]=='P' && z[1]=='i' && z[2]=='c' && z[3]=='t') {
                        pictOffset = (z[8]<<24)|(z[9]<<16)|(z[10]<<8)|z[11];
                        break;
                    }
                    if (pictOffset)
                        break;
                }
                if (pictOffset) {
                    pos = pictOffset;
                    fseek(fp, pos, SEEK_SET);
                    continue;
                }
            } else if (z[0]=='J' && z[1]=='P' && z[2]=='E' && z[3]=='G'
                       || z[0]=='P' && z[1]=='N' && z[2]=='G' && z[3]==' ') {
                printf ("Found pict resource\n");
                char *buf = malloc(chunkSize);
                int sizePerRead = 0x2000;
                int size=0,  sizeLeft = chunkSize;
                while (sizeLeft > 0) {
                    if (sizePerRead > sizeLeft)
                        sizePerRead = sizeLeft;
                    if (fread(buf + size, 1, sizePerRead, fp) != sizePerRead)
                        break;
                    size += sizePerRead;
                    sizeLeft -= sizePerRead;
                }
                if (sizeLeft == 0)
                    data = [[NSData alloc] initWithBytesNoCopy: buf length:chunkSize freeWhenDone:YES];
                else
                    free(buf);
                break;
            } else
                ; //printf("Skipping chunk '%c%c%c%c'\n", z[0],z[1],z[2],z[3]);
            pos += chunkSize;
            fseek (fp, pos, SEEK_SET);
        }
        break;
    }
    fclose(fp);
    return data;
}





