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
        if (!gLargeScreenDevice
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
    // Create the bitmap context
    CGContextRef cgctx = CreateARGBBitmapContext(newWidth, newHeight);
    if (cgctx == NULL)     // error creating context
        return nil;
    
    // Get image width, height. We'll use the entire image.
    CGRect rect = {{0,0},{newWidth,newHeight}};
    
    // Draw the image to the bitmap context. Once we draw, the memory
    // allocated for the context for rendering will then contain the
    // raw image data in the specified color space.
    CGContextDrawImage(cgctx, rect, inImage);
    
    CGImageRef newRef = CGBitmapContextCreateImage(cgctx);
    
    void *data = CGBitmapContextGetData(cgctx);
    
    // When finished, release the context
    CGContextRelease(cgctx);
    img= [UIImage imageWithCGImage: newRef];
    CGImageRelease(newRef);
    // Free image data memory for the context
    if (data)
        free(data);
    
    return img;
}


UIImage *drawUIImageInImage(UIImage *image, int x, int y, size_t scaleWidth, size_t scaleHeight, UIImage *destImage)
{
    if (!image || !destImage)
        return nil;
    CGImageRef inImage = [image CGImage];
    CGImageRef origImage = [destImage CGImage];
    
    if (!inImage || !origImage)
        return nil;
    
    size_t destWidth = destImage.size.width;
    size_t destHeight = destImage.size.height;
    
#if 1
    if (scaleHeight > destHeight) {
        scaleHeight /= 2; 
        //	y /= 2;
    }
    if (scaleWidth > destWidth) {
        scaleWidth /= 2;
        //	x /= 2;
    }
#endif
    
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
    
    UIImage *img= [UIImage imageWithCGImage: newRef];
    CGImageRelease(newRef);
    // Free image data memory for the context
    if (data)
        free(data);
    
    return img;
}

UIImage *drawRectInImage(unsigned int color, CGFloat x, CGFloat y, CGFloat width, CGFloat height, UIImage *destImage)
{
    if (!destImage)
        return nil;
    CGImageRef origImage = [destImage CGImage];
    
    if (!origImage)
        return nil;
    
    size_t destWidth = destImage.size.width;
    size_t destHeight = destImage.size.height;
    
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
    
    UIImage *img= [UIImage imageWithCGImage: newRef];
    CGImageRelease(newRef);
    
    // Free image data memory for the context
    if (data)
        free(data);
    
    return img;
}

UIColor *UIColorFromInt(unsigned int color) {
    CGFloat red = ((color >> 16) & 0xff) / 255.0;
    CGFloat green = ((color >> 8) & 0xff) / 255.0;
    CGFloat blue = (color & 0xff) / 255.0;
    return [UIColor colorWithRed:red green:green blue:blue alpha:1.0];
}


UIImage *createBlankImage(unsigned int bgColor, size_t destWidth, size_t destHeight) {
    CGContextRef cgctx = CreateARGBBitmapContext(destWidth, destHeight);
    
    CGFloat red = ((bgColor >> 16) & 0xff) / 255.0;
    CGFloat green = ((bgColor >> 8) & 0xff) / 255.0;
    CGFloat blue = (bgColor & 0xff) / 255.0;
    CGContextSetRGBFillColor(cgctx, red, green, blue, 1.0);
    CGContextFillRect(cgctx, CGRectMake(0, 0, destWidth, destHeight));
    
    CGImageRef newRef = CGBitmapContextCreateImage(cgctx);
    
    void *data = CGBitmapContextGetData(cgctx);
    
    // When finished, release the context
    CGContextRelease(cgctx);
    // Free image data memory for the context
    UIImage *img= [UIImage imageWithCGImage: newRef];
    CGImageRelease(newRef);
    
    // Free image data memory for the context
    if (data)
        free(data);
    
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
                char *buf = malloc(chunkSize);
                if (fread(buf, 1, chunkSize, fp) != chunkSize) {
                    free(buf);
                    break;
                }
                NSString *xmlString = [NSString stringWithCString: buf encoding:NSISOLatin1StringEncoding];
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
            } else
                printf("Skipping chunk '%c%c%c%c'\n", z[0],z[1],z[2],z[3]);
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
                printf("Skipping chunk '%c%c%c%c'\n", z[0],z[1],z[2],z[3]);
            pos += chunkSize;
            fseek (fp, pos, SEEK_SET);
        }
        break;
    }
    fclose(fp);
    return data;
}





