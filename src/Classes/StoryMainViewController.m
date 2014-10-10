
/*
 StoryMainViewController.m
 
 This program is free software; you can redistribute it and/or
 modify it under the terms of the GNU General Public License
 as published by the Free Software Foundation; version 2
 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License
 along with this program; if not, write to the Free Software
 Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 
 */

#import <UIKit/UIKit.h>

#import "FrotzAppDelegate.h"
#import "StoryMainViewController.h"

#import "StatusLine.h"
#import "StoryInputLine.h"
#import "StoryView.h"
#import "GlkView.h"

#import "FileBrowser.h"
#import <DropboxSDK/DropboxSDK.h>

#import "ui_utils.h"

#include "glk.h"
#include "glkios.h"
#include "glulxe.h"
#include "glkstart.h"
#include "gi_blorb.h"
#include "ipw_grid.h"

#include <pthread.h>
#include <sys/time.h>
#include <unistd.h>
#include <stdlib.h>

#define kDefaultTextViewWidth ((gLargeScreenDevice || gLargeScreenPhone) ? 80 : kDefaultTextViewMinWidth)

#define kClearEscChar '\f'
#define kClearEscCode "\f"
#define kSetDefColorsChar '\007'
#define kSetDefColorsCode "\007"

#define kOutputEscCode "\033"
#define kStyleEscCode "S"
#define kZColorEscCode "z"
#define kArbColorEscCode "c"
#define kImageEscCode "I"
#define kHyperlinkEscCode "L"

int iphone_textview_width = kDefaultTextViewMinWidth;
int iphone_textview_height = kDefaultTextViewHeight;
int iphone_screenwidth = 320, iphone_screenheight = 480;
int iphone_fixed_font_width = 5, iphone_fixed_font_height = 10;

int do_autosave = 0, autosave_done = 0, refresh_savedir = 0, restore_frame_count;
int iphone_ifrotz_verbose_debug = (((!APPLE_FASCISM) << 1)|0); // 4

FileBrowserState do_filebrowser = kFBHidden;
BOOL disable_complete = NO;

int lastInputWindow = -1;
int inputsSinceSaveRestore;

char iphone_filename[MAX_FILE_NAME];
char iphone_scriptname[MAX_FILE_NAME];

StoryMainViewController *theSMVC;
StoryView *theStoryView;
StatusLine *theStatusLine;
StoryInputLine *theInputLine;

const int kDefaultFontSize = 12;
const int kDefaultPadFontSize = 18;

NSString *kFixedWidthFontName = @"Courier New";
NSString *kVariableWidthFontName = @"Helvetica";

char SAVE_PATH[MAX_FILE_NAME], AUTOSAVE_FILE[MAX_FILE_NAME];

static enum { kZStory, kGlxStory } gStoryInterp;

static int numGlkViews;

#define kLaunchMsgViewTag 100
#define kGlkImageViewTag  200

#define kStatusLineYPos		0.0f
#define kStatusLineHeight	10.0f   // for early V3 games

int ipzAllowInput = kIPZDisableInput;

static BOOL isOS30 = NO, isOS32 = NO;

static NSMutableString *ipzBufferStr = nil, *ipzStatusStr = nil, *ipzInputBufferStr = nil;
static NSMutableString *ipzLineInputStr = nil;

static pthread_mutex_t outputMutex, inputMutex, winSizeMutex;
static pthread_cond_t winSizeChangedCond;
static BOOL winSizeChanged;
static int recentScrollToVisYPos[kMaxGlkViews];
int lastVisibleYPos[kMaxGlkViews];

static NSMutableDictionary *glkImageCache, *glkViewImageCache;

volatile void *pp;

static void freeGlkViewImageCache(int vn) {
    NSNumber *viewNum = [NSNumber numberWithInt:vn];
    CGContextRef cgctx = (CGContextRef)[[glkViewImageCache objectForKey: viewNum] pointerValue];
    if (cgctx) {
        void *data = CGBitmapContextGetData(cgctx);
        
        CGContextRelease(cgctx);
        // Free image data memory for the context
        if (data)
            free(data);
    }
    [glkViewImageCache removeObjectForKey: viewNum];
    
}

static void freeGlkImageCache() {
    [glkImageCache release];
    glkImageCache = nil;
}


void iphone_ioinit() {
    static BOOL didInitIO = NO;
    if (!didInitIO) {
        pthread_mutex_init(&winSizeMutex, NULL);
        pthread_mutex_init(&outputMutex, NULL);
        pthread_mutex_init(&inputMutex, NULL);
        pthread_cond_init(&winSizeChangedCond, NULL);
        winSizeChanged = 0;
        ipzBufferStr = [[NSMutableString alloc] initWithBytes:nil length:0 encoding:NSISOLatin1StringEncoding];
        ipzStatusStr = [[NSMutableString alloc] initWithBytes:nil length:0 encoding:NSISOLatin1StringEncoding];
        ipzInputBufferStr = [[NSMutableString alloc] initWithBytes:nil length:0 encoding:NSISOLatin1StringEncoding];
        ipzLineInputStr = [[NSMutableString alloc] initWithBytes:nil length:0 encoding:NSISOLatin1StringEncoding];
        didInitIO = YES;
    }
}

int currColor = 0, currTextStyle = 0;

#define kOutputBufSize 2048
static unichar outputBuffer[2048];
static int outputBufferLen = 0;

static IPGlkGridArray glkGridArray[kMaxGlkViews];
static NSMutableArray *glkInputs;

void iphone_flush(bool lock) {
    if (lock)
        pthread_mutex_lock(&outputMutex);
    if (outputBufferLen) {
        outputBuffer[outputBufferLen] = '\0';
        if (gStoryInterp == kGlxStory) {
            NSString *tmp = [[NSString alloc] initWithBytes:outputBuffer length: outputBufferLen*sizeof(unichar) encoding:NSUTF16LittleEndianStringEncoding];
                        // CString:outputBuffer encoding:NSISOLatin1StringEncoding];
            [ipzBufferStr appendString: tmp];
            [tmp release];
        } else {
            char latinBuf[2048];
            for (int l = 0; l <= outputBufferLen; ++l)
                latinBuf[l] = (char)outputBuffer[l];
            NSString *tmp = [[NSString alloc] initWithCString:latinBuf encoding:NSISOLatin1StringEncoding];
            [ipzBufferStr appendString: tmp];
            [tmp release];
        }
        outputBufferLen = 0;
        *outputBuffer = '\0';
    }
    if (lock)
        pthread_mutex_unlock(&outputMutex);
}


static NSMutableString *getBufferStrForWin(int winNum, BOOL *isStatus) {
    NSMutableString *bufferStr = nil;
    if (gStoryInterp == kGlxStory) {
        *isStatus = (glkGridArray[winNum].win && glkGridArray[winNum].win->type == wintype_TextGrid);
        if (!glkInputs)
            glkInputs = [[NSMutableArray alloc] initWithCapacity: kMaxGlkViews];
        while (winNum >= [glkInputs count]) {
            if ([glkInputs count] == 0)
                [glkInputs addObject: ipzBufferStr];
            else
                [glkInputs addObject: [[[NSMutableString alloc] initWithBytes:nil length:0 encoding:NSISOLatin1StringEncoding] autorelease]];
        }
        bufferStr = [glkInputs objectAtIndex: winNum];
    } else {
        *isStatus = (winNum == 1 || winNum == 7);
        bufferStr = *isStatus ? ipzStatusStr : ipzBufferStr;
    }
    return bufferStr;
}


void iphone_glk_set_text_colors(int viewNum, unsigned int textColor, unsigned int bgColor) {
    pthread_mutex_lock(&outputMutex);
    
    iphone_flush(NO);
    BOOL isStatus;
    NSMutableString *bufferStr = getBufferStrForWin(viewNum, &isStatus);

    if (textColor != BAD_STYLE)
        [bufferStr appendFormat: @kOutputEscCode kArbColorEscCode "t%06x", textColor & 0xffffff];
    else
        [bufferStr appendFormat: @ kOutputEscCode kZColorEscCode "%02x", 0];
    if (bgColor != BAD_STYLE)
        [bufferStr appendFormat: @kOutputEscCode kArbColorEscCode "b%06x", bgColor & 0xffffff];
    
    pthread_mutex_unlock(&outputMutex);
}

void iphone_set_text_attribs(int viewNum, int style, int color, bool lock) {
    if (lock)
        pthread_mutex_lock(&outputMutex);
    BOOL isStatus;
    NSMutableString *bufferStr = getBufferStrForWin(viewNum, &isStatus);
    
    if (style != currTextStyle /*|| gStoryInterp==kGlxStory*/) {
        iphone_flush(NO);
        [bufferStr appendFormat: @ kOutputEscCode kStyleEscCode "%02x", style];
        currTextStyle = style;
    }
    if (color != -1 && color != currColor && gStoryInterp==kZStory) {
        iphone_flush(NO);
        // Why was this here?
    	//if (color == ((BLACK_COLOUR<<4)|WHITE_COLOUR))
        //    color = 0;
        if (color != currColor) {
            [ipzBufferStr appendFormat: @ kOutputEscCode kZColorEscCode "%02x", color & 0xff];
            currColor = color;
        }
    }
    if (lock)
        pthread_mutex_unlock(&outputMutex);
}

void iphone_set_hyperlink_value(int viewNum, int val, bool lock) {
    if (lock)
        pthread_mutex_lock(&outputMutex);
    BOOL isStatus;
    NSMutableString *bufferStr = getBufferStrForWin(viewNum, &isStatus);
    iphone_flush(NO);
    [bufferStr appendFormat: @ kOutputEscCode kHyperlinkEscCode "%08x", val];
    if (lock)
        pthread_mutex_unlock(&outputMutex);

}

void iphone_put_image(int viewNum, int imageNum, int imageAlign, bool lock) {
    if (lock)
        pthread_mutex_lock(&outputMutex);
    BOOL isStatus;
    NSMutableString *bufferStr = getBufferStrForWin(viewNum, &isStatus);
    
    iphone_flush(NO);
    [bufferStr appendFormat: @kOutputEscCode kImageEscCode "%03d%1d", imageNum, imageAlign];
    if (lock)
        pthread_mutex_unlock(&outputMutex);
}

void iphone_win_putchar(int winNum, wchar_t c) {
    pthread_mutex_lock(&outputMutex);
    BOOL isStatus;
    NSMutableString *bufferStr = getBufferStrForWin(winNum, &isStatus);
    
    if (c == kClearEscChar)
        [bufferStr setString: @""];
    
    if (isStatus && c != ' ' && c != kClearEscChar)
        [bufferStr setString: @"\n\n"];
    else if (winNum == 0) {
        if (c > 0xff || outputBufferLen >= sizeof(outputBuffer)/sizeof(outputBuffer[0])-1)
            iphone_flush(NO);
        if (c <= 0xff)
            outputBuffer[outputBufferLen++] = c;
        else
            [bufferStr appendFormat:@"%C", (unichar)c];
    }
    else
        [bufferStr appendFormat:@"%c", c];
    
    pthread_mutex_unlock(&outputMutex);
    return;
}

void iphone_putchar(wchar_t c) {
    iphone_win_putchar(cwin, c);
}

void iphone_puts(char *s) {
    while (*s != '\0')
        iphone_putchar(*s++);
}

void iphone_win_puts(int winNum, char *s) {
    while (*s != '\0')
        iphone_win_putchar(winNum, *s++);
}

void iphone_win_putwcs(int winNum, wchar_t *s, int len) {
    while (len-- > 0 && *s != 0)
        iphone_win_putchar(winNum, *s++);
}

void iphone_set_input_line(wchar_t *ws, int len) {
    int bufflen = 8 * len + 1;
    char* temp = malloc(bufflen);
    wcstombs(temp, ws, bufflen);
    NSString *str = [NSString stringWithUTF8String:temp];
    free(temp);
    [theInputLine performSelectorOnMainThread:@selector(setText:) withObject:str waitUntilDone:YES];    
}

void iphone_clear_input(NSString *initStr) {
    pthread_mutex_lock(&inputMutex);
    [ipzInputBufferStr setString: initStr ? initStr : @""];
    pthread_mutex_unlock(&inputMutex);
}

void iphone_feed_input(NSString *str) {
    pthread_mutex_lock(&inputMutex);
    [ipzInputBufferStr appendString: str];
    pthread_mutex_unlock(&inputMutex);
}

void iphone_feed_input_line(NSString *str) {
    pthread_mutex_lock(&inputMutex);
    [ipzLineInputStr setString: str ? str: @""];
    pthread_mutex_unlock(&inputMutex);
}

int iphone_peek_inputline(const wchar_t *inputbuf, int maxlen) {
    iphone_flush(YES);
    
    pthread_mutex_lock(&inputMutex);
#if 1
    int len = [ipzLineInputStr length];
    CFRange r = {0,len};
    CFIndex usedBufferLength;
    len = (int)CFStringGetBytes((CFStringRef)ipzLineInputStr, r, kCFStringEncodingUTF32, '?', FALSE,
                           (UInt8 *)inputbuf, maxlen*sizeof(wchar_t), &usedBufferLength);
#else
    [ipzLineInputStr getCString:(char*)inputbuf maxLength:maxlen encoding:NSUTF32StringEncoding];
    int len = wcslen(inputbuf);
#endif
    pthread_mutex_unlock(&inputMutex);
    return len;
}

int iphone_getchar(int timeout) {
    struct timeval now, then;
    iphone_flush(YES);
    int c = 0;
    
    if (timeout > 0) {
        gettimeofday(&then, NULL);
        then.tv_usec += timeout * 1000;
        if (then.tv_usec >= 1000000) {
            then.tv_usec -= 1000000;
            ++then.tv_sec;
        }	    
    }
    
    while (1) {
        pthread_mutex_lock(&inputMutex);
        if ([ipzInputBufferStr length] > 0) {
    	    UInt8 buf[4];
            CFRange r = {0,1}; NSRange nr = {0,1};
            CFIndex usedBufferLength;
            CFIndex numChars = CFStringGetBytes((CFStringRef)ipzInputBufferStr, r, kCFStringEncodingISOLatin1,'?',FALSE,(UInt8 *)buf,2,&usedBufferLength);
            [ipzInputBufferStr deleteCharactersInRange: nr];
            if (numChars)
                c = (int)*(unsigned char*)buf;
        }
        pthread_mutex_unlock(&inputMutex);
        if (c)
            return c;
        
        if (timeout == 0)
            break;
        else if (mouseEvent || hyperlinkEvent) {
            if (gStoryInterp == kZStory)
                mouseEvent = FALSE; // Z interp doesn't check this, ignore
            else
                break;
        }
        else if (screen_size_changed) {
            if (gStoryInterp == kZStory)
                screen_size_changed = 0; // Z interp doesn't check this, ignore
            else
                break;
        } else if (timeout > 0) {
            gettimeofday(&now, NULL);
            if (now.tv_sec > then.tv_sec || now.tv_sec == then.tv_sec && now.tv_usec > then.tv_usec)
                break;
        } 
	    
        usleep(10000);
    }
    return -1;
}

IPGlkGridArray *iphone_glk_getGridArray(int viewNum) {
    return &glkGridArray[viewNum];
}

void iphone_glk_wininit() {
    [theSMVC performSelectorOnMainThread:@selector(clearGlkViews) withObject:nil waitUntilDone:YES];
}

void iphone_glk_game_loaded() {
    [theSMVC performSelectorOnMainThread:@selector(reloadImages) withObject:nil waitUntilDone:YES];
}

static int gNewGlkWinNum = -1;

int iphone_new_glk_view(window_t *win) {
    // This is not thread safe and should only be called from the thread running glk_main()!
    if (!win || numGlkViews >= kMaxGlkViews)
        return -1;
    gNewGlkWinNum = -1;
    
    if (!finished) {
        [theSMVC performSelectorOnMainThread:@selector(newGlkViewWithWin:) withObject:[NSValue valueWithPointer: win] waitUntilDone:YES]; // will increment numGlkViews
        if (gNewGlkWinNum < 0)
            NSLog(@"error in iphone_new_glk_view!");
    }
    //    NSLog(@"new glk win %d, type=%d, win=%p", gNewGlkWinNum, win->type, win);
    if (gNewGlkWinNum >= 0) {
        glkGridArray[gNewGlkWinNum].win = win;
        glkGridArray[gNewGlkWinNum].bgColor = 0xffffff;
    }
    return gNewGlkWinNum;
}

void iphone_destroy_glk_view(int viewNum) {
    if (viewNum < 0 || viewNum > kMaxGlkViews)
        return;
    //    NSLog(@"destroy glk view %d", viewNum);
    
    glkGridArray[viewNum].pendingClose = YES;
    [theSMVC performSelectorOnMainThread:@selector(destroyGlkView:) withObject:[NSNumber numberWithInt:viewNum] waitUntilDone:YES];    
}

// delay grid allocation until here; we always call this shortly after new
void iphone_glk_view_rearrange(int viewNum, window_t *win) {
    if (viewNum >= 0 && viewNum < numGlkViews) {
        if (win != glkGridArray[viewNum].win)
            abort();
        CGRect box = CGRectMake(win->bbox.left, win->bbox.top, win->bbox.right-win->bbox.left, win->bbox.bottom-win->bbox.top);
        NSArray *a = [NSArray arrayWithObjects: [NSNumber numberWithInt:viewNum], [NSValue valueWithCGRect:box], nil];
        
        if (glkGridArray[viewNum].win->type == wintype_TextGrid) {
            pthread_mutex_lock(&outputMutex);
            if (glkGridArray[viewNum].gridArray) {
                wchar_t *ga = glkGridArray[viewNum].gridArray;
                glkGridArray[viewNum].gridArray = nil;
                free(ga);
            }
            int nRows = glkGridArray[viewNum].nRows = (int)box.size.height / iphone_fixed_font_height;
            int nCols = glkGridArray[viewNum].nCols = (int)box.size.width / iphone_fixed_font_width;
            if (nRows && nCols) {
                glkGridArray[viewNum].gridArray = malloc(nRows*nCols*sizeof(wchar_t));
                wchar_t sp = L' ';
                memset_pattern4(glkGridArray[viewNum].gridArray, &sp, nRows*nCols*sizeof(wchar_t));
            }
            pthread_mutex_unlock(&outputMutex);
        }
//        NSLog(@"glk_view_rearrange %d", viewNum);

        [theSMVC performSelectorOnMainThread:@selector(resizeGlkView:) withObject:a waitUntilDone:YES];
    }
}


void iphone_erase_screen() {
    int saved_cwin = cwin;
    iphone_flush(YES);
    //NSLog(@"erase screen\n");
    if (!finished) {
        pthread_mutex_lock(&winSizeMutex);
        cwin = 1;
        iphone_putchar(kClearEscChar);
        cwin = saved_cwin;
        winSizeChanged = YES;
        pthread_cond_wait(&winSizeChangedCond, &winSizeMutex);
        pthread_mutex_unlock(&winSizeMutex);
    }
}

void iphone_set_glk_default_colors(int winNum) {
    iphone_flush(YES);
    iphone_win_putchar(winNum, kSetDefColorsChar);
}

void iphone_erase_win(int winnum) {
    iphone_flush(YES);
    //NSLog(@"erase mainwin\n");
    
#if UseRichTextView
    // we have to wait for output to drain even though we're about to clear the screen in case
    // the output contains font changes
    while ([ipzBufferStr length])
        usleep(1000);
    
#endif
    
    int saved_cwin = cwin;
    pthread_mutex_lock(&winSizeMutex);
    cwin = winnum;
    iphone_putchar(kClearEscChar);
    cwin = saved_cwin;
    winSizeChanged = YES;
    pthread_cond_wait(&winSizeChangedCond, &winSizeMutex);
    pthread_mutex_unlock(&winSizeMutex);
}

void iphone_erase_mainwin() {
    iphone_erase_win(0);
}

void iphone_enable_tap(int viewNum) {
    [theSMVC performSelectorOnMainThread:@selector(enableTaps:) withObject:[NSNumber numberWithInt:viewNum] waitUntilDone:YES];
    glkGridArray[viewNum].tapsEnabled = YES;
}

void iphone_disable_tap(int viewNum) {
    [theSMVC performSelectorOnMainThread:@selector(disableTaps:) withObject:[NSNumber numberWithInt:viewNum] waitUntilDone:YES];
    glkGridArray[viewNum].tapsEnabled = NO;
}

void iphone_enable_input() {
    pthread_mutex_lock(&outputMutex);
    iphone_flush(NO);
    if (ipzAllowInput == kIPZDisableInput)
        ipzAllowInput = kIPZRequestInput;
    pthread_mutex_unlock(&outputMutex);
}

void iphone_enable_single_key_input() {
    pthread_mutex_lock(&outputMutex);
    iphone_flush(NO);
    if (ipzAllowInput == kIPZDisableInput)
        ipzAllowInput = kIPZRequestInput | kIPZNoEcho;
    
    pthread_mutex_unlock(&outputMutex);
}

void iphone_disable_input() {
    pthread_mutex_lock(&outputMutex);
    iphone_flush(NO);
    ipzAllowInput = kIPZDisableInput;
    pthread_mutex_unlock(&outputMutex);
}

void iphone_set_top_win_height(int height) {
    
    // wait for output to drain so size won't take effect
    // until new output in window
    iphone_flush(YES);
    
    pthread_mutex_lock(&winSizeMutex);
    top_win_height = height;
    winSizeChanged = YES;
    pthread_cond_wait(&winSizeChangedCond, &winSizeMutex);
    pthread_mutex_unlock(&winSizeMutex);
}

void iphone_mark_recent_save() {
    inputsSinceSaveRestore = 0;
}

int iphone_read_file_name(char *file_name, const char *default_name,	int flag) {
    *iphone_filename = 0;
    switch (flag) {
        case FILE_SAVE:
            do_filebrowser = kFBDoShowSave;
            break;
        case FILE_RESTORE:
            do_filebrowser = kFBDoShowRestore;
            break;
        case FILE_SCRIPT:
            do_filebrowser = kFBDoShowScript;
            strcpy(iphone_filename, default_name);
            break;
        case FILE_RECORD:
        case FILE_PLAYBACK:
            do_filebrowser = flag == FILE_RECORD? kFBDoShowRecord : kFBDoShowPlayback;
            strcpy(iphone_filename, default_name);
            break;
        default:
            do_filebrowser = kFBHidden;
            *iphone_filename = 0;
            return FALSE;
    }
    
    [theSMVC performSelectorOnMainThread:@selector(openFileBrowserWrap:) withObject:[NSNumber numberWithInt:do_filebrowser] waitUntilDone:YES];
    
    while (do_filebrowser) {
        usleep(100000);
    }
    
    if (!*iphone_filename)
        return FALSE;
    
    char *basefile = strrchr(iphone_filename, '/');
    strcpy(file_name, basefile ? basefile+1 : iphone_filename);
    
    //    if (flag == FILE_SAVE || flag == FILE_SAVE_AUX || flag == FILE_RECORD)
    //	; // ask before overwriting... // this is now done in the dialog itself
    
    return TRUE;
}



void iphone_disable_autocompletion() {
    disable_complete = YES;
}

void iphone_enable_autocompletion() {
    disable_complete = NO;
}

void iphone_start_script(char *scriptName) {
    if (scriptName)
        strcpy(iphone_scriptname, scriptName);
    else
        *iphone_scriptname = '\0';
}

void iphone_stop_script() {
    *iphone_scriptname = '\0';
}


void iphone_recompute_screensize() {
    if (!theSMVC)
        return;
    CGFloat fontwid = [theSMVC statusFixedFontPixelWidth]; // [@"x" sizeWithFont: [theStatusLine fixedFont]].width;
    FrotzView *storyView = [theSMVC storyView];
    UIView *parentView = [storyView superview];
//    CGRect frame = [storyView frame];
    CGRect pFrame = [parentView frame];
    pFrame.size.height -= [theSMVC keyboardSize].height;
    iphone_textview_width = (int)(pFrame.size.width / fontwid);
    iphone_textview_height = (int)(pFrame.size.height / [[storyView font] leading])+1;
    if (iphone_textview_width > MAX_COLS)
        iphone_textview_width = MAX_COLS;
    if (iphone_textview_height > MAX_ROWS)
        iphone_textview_height = MAX_ROWS;    
    
    iphone_screenwidth = pFrame.size.width;
    iphone_screenheight = pFrame.size.height;
    iphone_fixed_font_width = fontwid;
    iphone_fixed_font_height = [theSMVC statusFixedFontPixelHeight];
    
}

void iphone_save_glk_win_graphics_img(int ordNum, int viewNum) {
    if (viewNum < 0 || viewNum >= kMaxGlkViews)
        return;
    window_t *win = glkGridArray[viewNum].win;
    if (win->type == wintype_Graphics) {
        CGContextRef origCtx = (CGContextRef)[[glkViewImageCache objectForKey: [NSNumber numberWithInt: viewNum]] pointerValue];
        if (origCtx) {
            CGImageRef imgRef = CGBitmapContextCreateImage(origCtx);
            UIImage *img = [UIImage imageWithCGImage: imgRef];
            NSString *pngPath = [NSString stringWithFormat: @"%s/glkwingfx-%d.png", SAVE_PATH, ordNum];
            NSError *error;
            NSFileManager *fileMgr = [NSFileManager defaultManager];
            [fileMgr removeItemAtPath: pngPath error:&error];
            [UIImagePNGRepresentation(img) writeToFile:pngPath atomically:YES];
            CGImageRelease(imgRef);
        }
    }
}

void iphone_restore_glk_win_graphics_img(int ordNum, int viewNum) {
    if (viewNum < 0 || viewNum >= kMaxGlkViews)
        return;
    window_t *win = glkGridArray[viewNum].win;
    if (win->type == wintype_Graphics) {
        CGRect r = CGRectMake(win->bbox.left, win->bbox.top, win->bbox.right-win->bbox.left, win->bbox.bottom-win->bbox.top);
        CGContextRef cgctx = (CGContextRef)[[glkViewImageCache objectForKey: [NSNumber numberWithInt: viewNum]] pointerValue];
        if (!cgctx)
            cgctx = createBlankFilledCGContext(glkGridArray[viewNum].bgColor, r.size.width, r.size.height);
        if (cgctx) {
            NSString *pngPath = [NSString stringWithFormat: @"%s/%s-%d.png", SAVE_PATH, kFrotzAutoSaveGlkImgPrefix, ordNum];
            UIImage *img = [UIImage imageWithContentsOfFile: pngPath];
            if (img) {
                CGFloat width = img.size.width;
                CGFloat height = img.size.height;
                if (!glkViewImageCache)
                    glkViewImageCache = [[NSMutableDictionary alloc] initWithCapacity: 100];
                drawCGImageInCGContext(cgctx, [img CGImage], 0, 0, width, height);
            }
            [glkViewImageCache setObject: [NSValue valueWithPointer: cgctx] forKey: [NSNumber numberWithInt: viewNum]];
            NSError *error;
            NSFileManager *fileMgr = [NSFileManager defaultManager];
            [fileMgr removeItemAtPath: pngPath error:&error];
        }
    }
}


void iphone_set_background_color(int viewNum, glui32 color) {
    if (viewNum > kMaxGlkViews)
        return;
    glkGridArray[viewNum].bgColor = color;
    //NSLog(@"glk_set_bg_color %d %06x", viewNum, color);
    
    [theSMVC performSelectorOnMainThread:@selector(setGlkBGColor:) withObject:[NSNumber numberWithInt:viewNum] waitUntilDone:YES];
}

glui32 iphone_glk_image_get_info(glui32 image, glui32 *width, glui32 *height) {
    giblorb_map_t *map;
    giblorb_err_t err;
    giblorb_result_t blorbres;
    
    map = giblorb_get_resource_map();
    if (!map)
        return FALSE;
    
    err = giblorb_load_resource(map, giblorb_method_Memory, &blorbres, giblorb_ID_Pict, image);
    if (!err) {
        NSData *data = nil;
        if (blorbres.chunktype == giblorb_make_id('J', 'P', 'E', 'G') || blorbres.chunktype == giblorb_make_id('P', 'N', 'G', ' '))
            data = [NSData dataWithBytesNoCopy: blorbres.data.ptr length:blorbres.length freeWhenDone:NO];
        if (data) {
            UIImage *img = [UIImage imageWithData: data];
            if (img) {
                if (width)
                    *width = gLargeScreenDevice ? img.size.width : img.size.width / 2;
                if (height)
                    *height = gLargeScreenDevice ? img.size.height : img.size.height / 2;
                return TRUE;
            }
        }
    }
    *width = *height = 0;
    return FALSE;
}

typedef struct glkImageDrawArgs {
    int viewNum;
    glui32 image;
    glsi32 val1, val2;
    glui32 width, height;
    glui32 retVal;
    giblorb_result_t blorbres;
} GlkImageDrawArgs;

typedef struct glkRectDrawArgs {
    int viewNum;
    glui32 color;
    glsi32 left, top;
    glui32 width, height;
} GlkRectDrawArgs;

void iphone_glk_window_graphics_update(int viewNum) {
    [theSMVC performSelectorOnMainThread:@selector(updateGlkWin:) withObject:[NSNumber numberWithInt: viewNum] waitUntilDone:NO];
}

void iphone_glk_window_erase_rect(int viewNum, glsi32 left, glsi32 top, glui32 width, glui32 height) {
//    NSLog(@"glk_window_erase_rect %d %dx%d", viewNum, width, height);
    GlkRectDrawArgs args = { viewNum, 0, left, top, width, height };
//    [theSMVC performSelectorOnMainThread:@selector(drawGlkRect:) withObject:[NSValue valueWithPointer:&args] waitUntilDone:YES];
    [theSMVC performSelector:@selector(drawGlkRect:) withObject:[NSValue valueWithPointer:&args]];
}

void iphone_glk_window_fill_rect(int viewNum, glui32 color, glsi32 left, glsi32 top, glui32 width, glui32 height) {
//    NSLog(@"glk_window_fill_rect %d %dx%d", viewNum, width, height);
    GlkRectDrawArgs args = { viewNum, color, left, top, width, height };
//    [theSMVC performSelectorOnMainThread:@selector(drawGlkRect:) withObject:[NSValue valueWithPointer:&args] waitUntilDone:YES];
    [theSMVC performSelector:@selector(drawGlkRect:) withObject:[NSValue valueWithPointer:&args]];

}

extern int gLastGlkEventWasArrange;

glui32 iphone_glk_image_draw(int viewNum, glui32 image, glsi32 val1, glsi32 val2, glui32 width, glui32 height) {
    giblorb_map_t *map;
    giblorb_err_t err;
    
//    NSLog(@"glk_image_draw %d %d", viewNum, image);
    map = giblorb_get_resource_map();
    if (!map) {
        return FALSE;
    }
    
    GlkImageDrawArgs args = { viewNum, image, val1, val2, width, height, 0 };
    err = giblorb_load_resource(map, giblorb_method_Memory, &args.blorbres, giblorb_ID_Pict, image);
    if (err)
        return FALSE;
    if (!finished) {
        if (glkGridArray[viewNum].win->type == wintype_TextBuffer) {
            if (!gLastGlkEventWasArrange) // work around Diana bug
                [theSMVC performSelectorOnMainThread:@selector(drawGlkImage:) withObject:[NSValue valueWithPointer:&args] waitUntilDone:YES];
        }
        else
            [theSMVC performSelector:@selector(drawGlkImage:) withObject:[NSValue valueWithPointer:&args]];
    }
    return TRUE;
}

int hflagsRestore = 0;

void run_zinterp(bool autorestore) {
    gStoryInterp = kZStory;
    os_set_default_file_names(story_name);
    if (autorestore)
        do_autosave = 1;
    init_buffer ();
    init_err ();
    if (init_memory () == 0) {
        init_screen();
        script_reset(iphone_scriptname);
        init_interpreter ();
        iphone_ioinit();
        init_sound ();
        os_init_screen ();
        init_undo ();
        z_restart ();
        if (autorestore) {
            refresh_cwin();
            frame_count = restore_frame_count;
            split_window(h_version > 3 ? top_win_height : top_win_height-1);
            
            z_restore ();

            h_flags |= hflagsRestore;
            hflagsRestore = 0;
            do_autosave = 0;
        }
        interpret ();
        finished = -1;
    } else
        finished = 2;
    
    reset_memory ();
}

BOOL gForceUseGlulxe = NO;

void glk_main_glulxe();

void run_glxinterp(const char *story, bool autorestore) {
    char glulHeader[48];

    BOOL useGlulxe = gForceUseGlulxe;
    
    if (readGLULheaderFromUlxOrBlorb(story, glulHeader)) {
        // Inform-created stories have 'INFO' at offset 36.
        if (glulHeader[36]!='I' && glulHeader[4]==0 && glulHeader[5]==2) // glulxa-asssembled, probably SuperGLUS?
            useGlulxe = YES;
    }

    
    gStoryInterp = kGlxStory;
    
    char *argv[] = { "frotz", (char*)story };
    glkunix_startup_t  glkunix_startup = { 2,  argv };
    iphone_ioinit();
    
    h_default_foreground = BLACK_COLOUR;
    h_default_background = WHITE_COLOUR;
    
    iphone_recompute_screensize();
    
    gli_initialize_misc();
    gli_initialize_windows();
    gli_initialize_events();
    
    if (useGlulxe)
        glkunix_startup_code_glulxe(&glkunix_startup);
    else
        glkunix_startup_code(&glkunix_startup);

    if (autorestore)
        do_autosave = 1;
    
    if (useGlulxe)
        glk_main_glulxe();
    else
        glk_main();

    freeGlkImageCache();

//    glk_window_close(gli_rootwin, NULL); // now done at end of glk_main so it can shutdown dispatch
    
    finished = -1;
}

void run_interp(const char *story, bool autorestore) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    winSizeChanged = NO;
    finished = 0;
    
    NSMutableString *str = [NSMutableString stringWithUTF8String: story];
    story_name  = (char*)[str UTF8String];
    
    if ([[str pathExtension] isEqualToString: @"blb"]
        || [[str pathExtension] isEqualToString: @"gblorb"]
        || [[str pathExtension] isEqualToString: @"ulx"])
        run_glxinterp(story, autorestore);
    else
        run_zinterp(autorestore);
    
    [pool release];
}

void *interp_cover_normal(void *arg) {
    const char *story = (const char*)arg;
    run_interp(story, false);
    return NULL;
}

void *interp_cover_autorestore(void *arg) {
    const char *story = (const char*)arg;
    run_interp(story, true);
    return NULL;
}

@interface UIBarButtonItem (Ext) 
-(UIView*)view;
@end


static void setColorTable(RichTextView *v) {
    [v resetColors];
    [v getOrAllocColorIndex: [UIColor brownColor]];
    [v getOrAllocColorIndex: [UIColor blackColor]];
    [v getOrAllocColorIndex: [UIColor redColor]];
    [v getOrAllocColorIndex: [UIColor greenColor]];
    [v getOrAllocColorIndex: [UIColor yellowColor]];
    [v getOrAllocColorIndex: [UIColor blueColor]];
    [v getOrAllocColorIndex: [UIColor magentaColor]];
    [v getOrAllocColorIndex: [UIColor cyanColor]];
    [v getOrAllocColorIndex: [UIColor whiteColor]];
    [v getOrAllocColorIndex: [UIColor grayColor]];
    [v getOrAllocColorIndex: [UIColor lightGrayColor]];
    [v getOrAllocColorIndex: [UIColor grayColor]];
    [v getOrAllocColorIndex: [UIColor darkGrayColor]];
    [v getOrAllocColorIndex: [UIColor orangeColor]];
}


@implementation StoryMainViewController 

- (StoryMainViewController*)init {
    self = [super init];
    if (self)
    {
        NSString *osVersStr = [[UIDevice currentDevice] systemVersion];
        if (osVersStr && [osVersStr characterAtIndex: 0] >= '3') {
            isOS30 = YES;
            if ([osVersStr characterAtIndex: 0] >= '4' || [osVersStr characterAtIndex: 2] >= '2')
                isOS32 = YES;
        }
        
        // this title will appear in the navigation bar
        //	self.title = NSLocalizedString(@"Frotz", @"");
        [self resetSettingsToDefault];
        
        id fileMgr = [NSFileManager defaultManager];
        
        NSArray *array = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, true);
        docPath = [[array objectAtIndex: 0] copy];
        chdir([docPath UTF8String]);
        
        storyGamePath = [[docPath stringByAppendingPathComponent: @kFrotzGameDir] retain];
        storyTopSavePath = [[docPath stringByAppendingPathComponent: @kFrotzSaveDir] retain];
        
        
        if (![fileMgr fileExistsAtPath: storyGamePath]) {
            [fileMgr createDirectoryAtPath: storyGamePath attributes: nil];
        }
        if (![fileMgr fileExistsAtPath: storyTopSavePath]) {
            [fileMgr createDirectoryAtPath: storyTopSavePath attributes: nil];
        }
        
        NSString *resourcePath = [[NSBundle mainBundle] resourcePath];
        resourceGamePath = [resourcePath stringByAppendingPathComponent: @kFrotzGameDir];
        
        frotzPrefsPath  = nil;
        storySIPPath    = [[storyTopSavePath stringByAppendingPathComponent: @kFrotzAutoSavePListFile] retain];
        storySIPPathOld = [storySIPPath retain];
        storySIPSavePath= [[storyTopSavePath stringByAppendingPathComponent: @kFrotzOldAutoSaveFile] retain];
        activeStoryPath = [[storyTopSavePath stringByAppendingPathComponent: @kFrotzAutoSaveActiveFile] retain];
        
        strcpy(SAVE_PATH, [storyTopSavePath UTF8String]);
        
        strcpy(AUTOSAVE_FILE,  [storySIPSavePath UTF8String]);  // used by interpreter from z_save
        
        m_currentStory = [[NSMutableString stringWithString: @""] retain];
        
        inputsSinceSaveRestore = 0;
        
        [self loadPrefs];
        
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        
//       [center addObserver:self selector:@selector(allNotif:) name:nil object:nil];
//       [center addObserver:self selector:@selector(keyboardWillChangeFrame:) name:UIKeyboardWillChangeFrameNotification object:nil];

        [center addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
        [center addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
        [center addObserver:self selector:@selector(keyboardDidShow:) name:UIKeyboardDidShowNotification object:nil];
        [center addObserver:self selector:@selector(keyboardDidHide:) name:UIKeyboardDidHideNotification object:nil];
        
        // Stupidly, there is no notification sent when accessibllity is turned on and off with triple-home
        // Check for the loading of the accessibility bundle to detect this instead.
        // Calls to setAccessibilityLabel:, etc. do nothing unless Accessibility is on, so if we don't do this,
        // the names we set for controls, etc. during launch won't get used.
        [center addObserver:self selector:@selector(handleAccessibilityLoad:) name:NSBundleDidLoadNotification object:nil];
        
    }
    return self;
}

-(void)clearGlkViews {
    NSNull *null = [NSNull null];
    for (RichTextView *v in m_glkViews)
        if (v != m_storyView && (NSNull*)v != null)
            [v removeFromSuperview];
    
    [m_glkViews release];
    for (int i=0; i < kMaxGlkViews; ++i)
        recentScrollToVisYPos[i] = 0;
    m_glkViews = nil;
    numGlkViews = 0;
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return [[scrollView subviews] objectAtIndex:0];
}
- (void)scrollViewDidEndZooming:(UIScrollView *)scrollView withView:(UIView *)view atScale:(CGFloat)scale { // scale between minimum and maximum. called after any 'bounce' animations
}

-(void)glkGraphicsWinTap:(UITapGestureRecognizer *) recognizer {
    CGPoint pt = [recognizer locationInView: [recognizer view]];
    if (![self tapInView:[recognizer view] atPoint: pt]) {
        if ((ipzAllowInput & kIPZNoEcho) || cwin == 1) { // single key input
            iphone_feed_input(@" "); // press 'space'
        }
    }
}

-(void)newGlkViewWithWin:(NSValue*)winVal {
    window_t *win = [winVal pointerValue];
    int winType = win->type;
    if (!m_glkViews) {
        m_glkViews = [[NSMutableArray alloc] initWithCapacity: 8];
        [m_glkViews addObject: m_storyView];
        glkGridArray[0].win = NULL;
        glkGridArray[0].pendingClose = NO;
        glkGridArray[0].tapsEnabled = NO;
        glkGridArray[0].nRows = glkGridArray[gNewGlkWinNum].nCols = 0;
        numGlkViews++;
    }
    if (winType == wintype_TextBuffer) {
        if (!glkGridArray[0].win) {
            glkGridArray[0].win = win;
            gNewGlkWinNum = 0;
            winType = -1;
        }
    }
    if (winType > 0)
    {
        BOOL useBorder = win->parent && win->parent->type==wintype_Pair ? ((window_pair_t*)win->parent->data)->hasborder : NO;
        GlkView *newView = (GlkView*)[[GlkView alloc] initWithFrame: CGRectZero border:useBorder]; //pref_window_borders?YES:NO;
        [newView setTextColor:m_defaultFGColor];
        if (winType == wintype_TextGrid || winType == wintype_Graphics) {
            newView.tapInputEnabled = NO;
            if (winType == wintype_Graphics) {
                [newView setBackgroundColor: [UIColor whiteColor]];
                
                UIView *gfxView = [[UIView alloc] initWithFrame: CGRectZero];
                [gfxView setTag: kGlkImageViewTag];

                /// scrollable/zoomable glk graphics windows support, #if 0 to disable
#if 1
                UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame: CGRectZero];
                [scrollView setDelegate: self];
                [scrollView setMinimumZoomScale: 1.0];
                [scrollView setMaximumZoomScale: 2.0];
                [scrollView setAutoresizingMask:UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight];
                
                if (isOS32) {
                    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(glkGraphicsWinTap:)] autorelease];
                    tap.numberOfTapsRequired = 1;
                    [newView addGestureRecognizer:tap];
                }
                [scrollView addSubview: gfxView];
                [newView addSubview: scrollView];
#else
                [newView addSubview: gfxView];
#endif
                [newView setAutoresizesSubviews:YES];

                [newView setAutoresizingMask: 0];
            } else {
                [newView setBackgroundColor: m_defaultBGColor];
                [newView setAutoresizingMask: UIViewAutoresizingFlexibleWidth];
            }
            [newView setNoMargins];
            [newView setBounces: NO];
            [newView setFont: [m_statusLine fixedFont]];
            [newView setFixedFont: [m_statusLine fixedFont]];
        } else {
            [newView setBackgroundColor: m_defaultBGColor];
            [newView setAutoresizingMask: UIViewAutoresizingFlexibleWidth];
            [newView setFont: [m_storyView font]];
            [newView setFixedFont: [m_storyView fixedFont]];
        }
        [newView reflowText];
        setColorTable(newView);
        [newView setDelegate: self];
        
        NSUInteger holeIndex = [m_glkViews indexOfObject: [NSNull null]];
        if (holeIndex != NSNotFound) {
            gNewGlkWinNum = holeIndex;
            glkGridArray[gNewGlkWinNum].win = win;
            glkGridArray[gNewGlkWinNum].pendingClose = NO;
            glkGridArray[gNewGlkWinNum].tapsEnabled = NO;
            glkGridArray[gNewGlkWinNum].nRows = glkGridArray[gNewGlkWinNum].nCols = 0;
            [m_glkViews replaceObjectAtIndex: holeIndex withObject: newView];
        }
        else {
            gNewGlkWinNum = [m_glkViews count];
            glkGridArray[gNewGlkWinNum].win = win;
            glkGridArray[gNewGlkWinNum].pendingClose = NO;
            glkGridArray[gNewGlkWinNum].tapsEnabled = NO;
            glkGridArray[gNewGlkWinNum].nRows = glkGridArray[gNewGlkWinNum].nCols = 0;
            [m_glkViews addObject: newView];
        }
        [m_background addSubview: newView];
        
        UIView *launchMsgView = [self.view viewWithTag:kLaunchMsgViewTag];
        if (launchMsgView)
            [m_background bringSubviewToFront: launchMsgView];
        ++numGlkViews;
    }
}

-(void)resizeGlkView:(NSArray*)arg {
    int viewNum = [[arg objectAtIndex:0] intValue];
    CGRect r = [[arg objectAtIndex: 1] CGRectValue];
    RichTextView *v = [m_glkViews objectAtIndex: viewNum];
    //NSLog(@"resizeglk: %d : (%f,%f,%f,%f)", viewNum, r.origin.x, r.origin.y, r.size.width, r.size.height);
    if (v) {
        r.origin.x /= kIOSGlkScaleFactor;
        r.origin.y /= kIOSGlkScaleFactor;
        r.size.width /= kIOSGlkScaleFactor;
        r.size.height /= kIOSGlkScaleFactor;
        if (viewNum > 0) {
            if (glkGridArray[viewNum].win->type == wintype_Graphics) {
                window_t *parent = glkGridArray[viewNum].win->parent;
                if (!parent || parent->type != wintype_Pair || ((window_pair_t*)parent->data)->division != winmethod_Fixed
                    || v.frame.size.height != r.size.height) {
                    // kludge for games which don't resize on events like Beyond; if height doesn't change, don't clear
                    UIView *imgv = [v viewWithTag: kGlkImageViewTag];
                    if (imgv) {
                        [imgv layer].contents = nil;
                    }
                }
                {
                    CGContextRef origCtx = (CGContextRef)[[glkViewImageCache objectForKey: [NSNumber numberWithInt: viewNum]] pointerValue];
                    if (origCtx) {
                        CGContextRef cgctx = createBlankFilledCGContext(glkGridArray[viewNum].bgColor, r.size.width, r.size.height);
                        CGImageRef imgRef = CGBitmapContextCreateImage(origCtx);
                        CGFloat origWidth = CGBitmapContextGetWidth(origCtx);
                        CGFloat origHeight = CGBitmapContextGetHeight(origCtx);
                        drawCGImageInCGContext(cgctx, imgRef,0, 0, origWidth, origHeight);
                        CGImageRelease(imgRef);
                        freeGlkViewImageCache(viewNum);
                        [glkViewImageCache setObject: [NSValue valueWithPointer: cgctx] forKey: [NSNumber numberWithInt: viewNum]];
                    }
                }
            }
            if (glkGridArray[viewNum].win->type == wintype_TextBuffer) {
                if (r.size.height > 64)
                    [v resetMargins];
                else
                    [v setNoMargins];
            }
            [v setFrame: r];
        } else if (viewNum == 0) {
            [v setFrame: r];
        }
    }
}

-(void)destroyGlkView:(NSNumber*)arg {
    int viewNum = [arg intValue];
    if (viewNum >= 0) {
        if (glkGridArray[viewNum].win->type == wintype_Graphics)
            freeGlkViewImageCache(viewNum);

        glkGridArray[viewNum].win = NULL;
        glkGridArray[viewNum].bgColor = 0xffffff;
        glkGridArray[viewNum].nRows = 0;
        glkGridArray[viewNum].nCols = 0;
        if (glkGridArray[viewNum].gridArray) {
            wchar_t *ga = glkGridArray[viewNum].gridArray;
            glkGridArray[viewNum].gridArray = nil;
            free(ga);
        }
        UIView *v = [m_glkViews objectAtIndex: viewNum];
        if (v != m_storyView) {
            --numGlkViews;
            [v removeFromSuperview];
            if (viewNum == [m_glkViews count]-1)
                [m_glkViews removeLastObject];
            else
                [m_glkViews replaceObjectAtIndex:viewNum withObject:[NSNull null]];
        }        
    }
}

-(void)setGlkBGColor:(NSNumber*)arg {
    int winNum = [arg intValue];
    if (winNum > 0 && winNum < [m_glkViews count]) {
        unsigned int color = glkGridArray[winNum].bgColor;
        CGFloat red = ((color >> 16) & 0xff) / 255.0;
        CGFloat green = ((color >> 8) & 0xff) / 255.0;
        CGFloat blue = (color & 0xff) / 255.0;
        UIColor *bgColor = [UIColor colorWithRed:red green:green blue:blue alpha:1.0];
        [[m_glkViews objectAtIndex: winNum] setBackgroundColor: bgColor];
    }
}

-(void)updateGlkWin:(NSNumber*)viewNum {
    int vn = [viewNum intValue];
    if (glkGridArray[vn].win->type != wintype_Graphics)
        return;
    UIView *v = [theSMVC glkView: vn];
    if (v && glkViewImageCache) {
        UIView *imgView = [v viewWithTag: kGlkImageViewTag];
#if 0
        CGImageRef imgRef = (CGImageRef)[glkViewImageCache objectForKey: viewNum];
        if (imgView && imgRef) {
            NSLog(@"updateglkwin: %p %p %p", imgView, [imgView layer], imgRef);
            imgView.frame = CGRectMake(0, 0, v.bounds.size.width, v.bounds.size.height);
            [imgView layer].contents = (id)imgRef;
            [glkViewImageCache removeObjectForKey: viewNum];
        }
#else
        CGContextRef cgctx = (CGContextRef)[[glkViewImageCache objectForKey: viewNum] pointerValue];
        if (imgView && cgctx) {
            //NSLog(@"updateglkwin: %p %p %p", imgView, [imgView layer], cgctx);
            if ([imgView superview] && [[imgView superview] respondsToSelector:@selector(setZoomScale:animated:)])
                [(UIScrollView*)[imgView superview] setZoomScale: 1.0 animated:NO];
            imgView.frame = CGRectMake(0, 0, v.bounds.size.width, v.bounds.size.height);
            
            CGImageRef imgRef = CGBitmapContextCreateImage(cgctx);
            [imgView layer].contents = (id)imgRef;
            CGImageRelease(imgRef);

#if 0
            void *data = CGBitmapContextGetData(cgctx);

            CGContextRelease(cgctx);
            // Free image data memory for the context
            if (data)
                free(data);
            [glkViewImageCache removeObjectForKey: viewNum];
#endif
        }
#endif
    }
}

-(void)drawGlkRect:(NSValue*)argsVal {
    GlkRectDrawArgs *args = [argsVal pointerValue];
    if (!args)
        return;
    int viewNum = args->viewNum;
    glui32 color = args->color;
    glsi32 left = args->left, top = args->top;
    glui32 width = args->width, height = args->height;
    left /= kIOSGlkScaleFactor;
    top /= kIOSGlkScaleFactor;
    width /= kIOSGlkScaleFactor;
    height /= kIOSGlkScaleFactor;
    UIView *v = [theSMVC glkView: viewNum];
    if (v) {
        if (!glkViewImageCache)
            glkViewImageCache = [[NSMutableDictionary alloc] initWithCapacity: 100];
        CGContextRef cgctx = (CGContextRef)[[glkViewImageCache objectForKey: [NSNumber numberWithInt: viewNum]] pointerValue];
        if (!cgctx)
            cgctx = createBlankFilledCGContext(glkGridArray[viewNum].bgColor, v.bounds.size.width/kIOSGlkScaleFactor, v.bounds.size.height/kIOSGlkScaleFactor);
        drawRectInCGContext(cgctx, color, left, top, width, height);
        [glkViewImageCache setObject: [NSValue valueWithPointer: cgctx] forKey: [NSNumber numberWithInt: viewNum]];
    }
    
}

-(void)drawGlkImage:(NSValue*)argsVal {
    GlkImageDrawArgs *args = [argsVal pointerValue];
    if (!args)
        return;
    int viewNum = args->viewNum;
    glui32 image = args->image;
    glsi32 val1 = args->val1, val2 = args->val2;
    glui32 width = args->width, height = args->height;
    giblorb_result_t *blorbres = &args->blorbres;
    
    glui32 retval = FALSE;

    if (!glkImageCache)
        glkImageCache = [[NSMutableDictionary alloc] initWithCapacity: 100];
    UIView *v = [theSMVC glkView: viewNum];
    NSNumber *imgKey = [NSNumber numberWithInt: image];
    UIImage *img = [glkImageCache objectForKey: imgKey];
    if (!img) {
        NSData *data = nil;
        if (blorbres && (blorbres->chunktype == giblorb_make_id('J', 'P', 'E', 'G') || blorbres->chunktype == giblorb_make_id('P', 'N', 'G', ' ')))
            data = [NSData dataWithBytesNoCopy: blorbres->data.ptr length:blorbres->length freeWhenDone:NO];
        
        if (data) {
            img = scaledUIImage([UIImage imageWithData: data], 0, 0); // scales down too screen size if too big, else leaves alone
            //img = [UIImage imageWithData: data];
            [glkImageCache setObject: img forKey: imgKey];
        }
    }
    if (img) {
        if (glkGridArray[viewNum].win->type == wintype_TextBuffer) {
//            [[m_glkViews objectAtIndex: viewNum] appendImage: image];
            iphone_put_image(viewNum, image, val1, NO);

        } else if (glkGridArray[viewNum].win->type == wintype_Graphics) {
            if (!width)
                width = img.size.width;
            if (!height)
                height = img.size.height;
            val1 /= kIOSGlkScaleFactor;
            val2 /= kIOSGlkScaleFactor;
            width /= kIOSGlkScaleFactor;
            height /= kIOSGlkScaleFactor;
           //NSLog(@"image draw view %d, img %d v1 %d v2 %d w %d h %d", viewNum, image, val1,  val2, width, height);
            if (!glkViewImageCache)
                glkViewImageCache = [[NSMutableDictionary alloc] initWithCapacity: 100];
            CGContextRef cgctx = (CGContextRef)[[glkViewImageCache objectForKey: [NSNumber numberWithInt: viewNum]] pointerValue];
            if (!cgctx)
                cgctx = createBlankFilledCGContext(glkGridArray[viewNum].bgColor, v.bounds.size.width, v.bounds.size.height);
            drawCGImageInCGContext(cgctx, [img CGImage],val1, val2, width, height);
            [glkViewImageCache setObject: [NSValue valueWithPointer: cgctx] forKey: [NSNumber numberWithInt: viewNum]];
        }
        retval = TRUE;
    }
    out:
    args->retVal = retval;
}


extern void gli_iphone_set_focus(window_t *winNum);

-(BOOL)tapInView:(UIView*)view atPoint:(CGPoint)pt {
    if (m_glkViews) {
        int winNum = [m_glkViews indexOfObject: view];
        if (winNum != NSNotFound) {
            iosEventWin = glkGridArray[winNum].win;
            RichTextView *rtv = (RichTextView*)view;
            if (iosEventWin->hyper_request) {
                int hyperlink = [rtv hyperlinkAtPoint: pt];
                if (hyperlink) {
                    hyperlinkEvent = TRUE;
                    iosEventX = hyperlink;
                    iosEventY = 0;
                    [self rememberLastContentOffsetAndAutoSave: m_storyView];
                    iphone_feed_input(@"");
                    return YES;
                }
            } else if (iosEventWin->mouse_request) {
                mouseEvent = TRUE;
                iosEventX = (int)pt.x;
                iosEventY = (int)pt.y;
                if (iosEventWin->type == wintype_TextGrid) {
                    CGSize sz = [rtv fixedFontSize];
                    iosEventX /= sz.width;
                    iosEventY /= sz.height;
                }
                [self rememberLastContentOffsetAndAutoSave: m_storyView];
                iphone_feed_input(@"");
                return YES;
            }
        }
    }
    return NO;
}

-(void)enableTaps:(NSNumber*)viewNum {
    int vn = [viewNum intValue];
    GlkView *v = [m_glkViews objectAtIndex: vn];
    v.tapInputEnabled = YES;
}

-(void)disableTaps:(NSNumber*)viewNum {
    int vn = [viewNum intValue];
    GlkView *v = [m_glkViews objectAtIndex: vn];
    v.tapInputEnabled = NO;
}


-(void)focusGlkView:(UIView*)view {
    if (m_glkViews) {
        int winNum = [m_glkViews indexOfObject: view];
        if (winNum != NSNotFound) {
            window_t *win = glkGridArray[winNum].win;
            if (win && (win->char_request || win->line_request)) {
                gli_iphone_set_focus(win); 	// bcs??? cross-thread unsafe
                cwin = winNum;
                [m_inputLine updatePosition];
            }
        }
    }
}

-(FrotzView*)glkView:(int)viewNum {
    if (gStoryInterp != kGlxStory)
        return nil;
    if (viewNum >= [m_glkViews count])
        return nil;
    FrotzView *v = [m_glkViews objectAtIndex: viewNum];
    if ((NSNull*)v == [NSNull null]) 
        return nil;
    return v;
}

-(BOOL)glkViewTypeIsGrid:(int)viewNum {
    return glkGridArray[viewNum].win->type == wintype_TextGrid;
}

-(NotesViewController*)notesController {
    return m_notesController;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    
    if (!gLargeScreenDevice && interfaceOrientation == UIInterfaceOrientationPortraitUpsideDown)
        return NO;
    
    if (m_storyView) {
        [[self view] setTransform: CGAffineTransformIdentity];
        [self hideInputHelper];
    }
    
    return YES;
}


-(NSString*)storyGamePath {
    return storyGamePath;
}

-(NSString*)resourceGamePath {
    return resourceGamePath;
}

-(NSString*)rootPath { // root directory for FTP transfers
    return docPath;
}


-(void)storyDidPressBackButton:(id)sender {
    [self.navigationController popViewControllerAnimated: YES];
}

- (void)abortToBrowser {
    [self abandonStory: YES];
    if (gUseSplitVC)
        [m_storyBrowser didPressModalStoryListButton];
    else
        [self.navigationController popViewControllerAnimated: YES];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == 0) {
        [self abortToBrowser];
    }
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == 1) {
        [self abortToBrowser];
    }
}

-(void)setNavBarTint {
#ifdef NSFoundationVersionNumber_iOS_6_1
    if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1) {
        [self.navigationController.navigationBar setBarStyle: UIBarStyleBlackOpaque];
        CGColorRef cgColor = [m_defaultBGColor CGColor];
        CGFloat max;
        const CGFloat *components = CGColorGetComponents(cgColor);
        size_t nComponents = CGColorGetNumberOfComponents(cgColor), i;
        max = components[0];
        for (i=1; i < nComponents-1; ++i)
            if (components[i] > max)
                max = components[i];
        if (max < 0.5) {
            [self.navigationController.navigationBar  setBarTintColor:  m_defaultBGColor];
            [self.navigationController.navigationBar  setTintColor: m_defaultFGColor];
            m_inputLine.keyboardAppearance = UIKeyboardAppearanceDark;
        }
        else {
            [self.navigationController.navigationBar  setBarTintColor:  m_defaultFGColor];
            [self.navigationController.navigationBar  setTintColor: m_defaultBGColor];
            m_inputLine.keyboardAppearance = UIKeyboardAppearanceLight;
        }
    } else
#endif
    {
        m_inputLine.keyboardAppearance = UIKeyboardAppearanceAlert;
    }
}

-(void)showKeyboardLockStateInView:(UIView*)kbdToggleItemView {
    BOOL notesVisible = (m_notesController && [m_notesController isVisible]);
        
    if (m_kbLocked && !notesVisible && ![m_inputLine isFirstResponder])
        [m_kbdToggleItem setImage: [UIImage imageNamed:@"icon-keyboard-locked.png"]];
    else
        [m_kbdToggleItem setImage: [UIImage imageNamed:@"icon-keyboard.png"]];
    if ([kbdToggleItemView respondsToSelector: @selector(setTintColor:)])
        [kbdToggleItemView setTintColor: m_kbLocked  && !notesVisible ? [UIColor colorWithRed:0.75 green:0.10 blue:0.25 alpha:1.0] : nil];
}

-(void)showKeyboardLockState {
    UIView *kbdToggleItemView = [m_kbdToggleItem valueForKey:@"view"];
    [self showKeyboardLockStateInView: kbdToggleItemView];
}

-(void)addKeyBoardLockGesture {
    [self view];
    UIBarButtonItem *kbdToggleItem = m_kbdToggleItem;
    UIView *kbdToggleItemView = [kbdToggleItem valueForKey:@"view"];
    Class UILongPressGestureRecognizerClass = NSClassFromString(@"UILongPressGestureRecognizer");
    if (kbdToggleItemView && UILongPressGestureRecognizerClass) {
        if ([[kbdToggleItemView gestureRecognizers] count] == 0) {
            UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc]
                                                              initWithTarget:self
                                                              action:@selector(toggleKeyboardLongPress:)];
            //Broken because there is no customView in a UIBarButtonSystemItemUndo item
            [kbdToggleItemView addGestureRecognizer:longPressGesture];
            [longPressGesture release];
            [self showKeyboardLockStateInView: kbdToggleItemView];
        }
    }

}

-(void)viewDidDisappear:(BOOL)animated {
}

-(void)viewDidAppear:(BOOL)animated {
    [self checkAccessibility];
    
    self.navigationItem.titleView = [m_frotzInfoController view];
    
    [self autosize];
    [self addKeyBoardLockGesture];
    
    if (m_kbShown)
        [m_inputLine becomeFirstResponder];
    
    //    if (m_autoRestoreDict)
    //	[self autoRestoreSession];
}

-(void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
  
    if (!m_frotzInfoController)
        m_frotzInfoController = [[FrotzInfo alloc] initWithSettingsController:[m_storyBrowser settings] navController:[self navigationController] navItem:self.navigationItem];
    
    [m_frotzInfoController setKeyboardOwner: self];

    disable_complete = !m_completionEnabled;
    refresh_savedir = 1;

    [self setNavBarTint];
    [m_frotzInfoController updateTitle];
    if (UIInterfaceOrientationIsLandscape([self interfaceOrientation])) {
        m_landscape = YES;
    }
    else {
        m_landscape = NO;
    }

    if (m_notesController) {
        [m_notesController hide];
        [m_notesController viewWillAppear:animated];
    }
}

-(void)viewWillDisappear:(BOOL)animated {
    disable_complete = YES;
    [super viewWillDisappear:animated];
    [[self view] setTransform: CGAffineTransformIdentity];
    if ([self.navigationController.navigationBar respondsToSelector:@selector(setBarTintColor:)]) {
        [self.navigationController.navigationBar setBarStyle: UIBarStyleDefault];
        [self.navigationController.navigationBar  setBarTintColor: [UIColor whiteColor]];
        [self.navigationController.navigationBar  setTintColor:  [UIColor darkGrayColor]];
    }
    
    [self.navigationItem.rightBarButtonItem setEnabled: YES];
    [self dismissKeyboard];
    if ([self inputHelperShown])
        [self hideInputHelper];
    if (m_notesController)
        [m_notesController viewWillDisappear:animated];
}

- (id)dismissKeyboard
{
    BOOL kbdWasShown = m_kbShown;
//    [self unlockKeyboard]; // allow staying locked if hiding by triple-tap
    [m_inputLine resignFirstResponder];
    [self showKeyboardLockState];
    return kbdWasShown ? m_inputLine : nil;
}

-(void)activateKeyboard {
    [m_inputLine resetState];
    [m_notesController workaroundFirstResponderBug]; // in iOS 6 on iPad, for some reason the notes controller keeps us from getting first responder after a modal dialog is dismissed (e.g. after 'restore' command)
    [self hideNotes];
    if (!m_kbLocked) {
        if (m_inputLine.window)
            [m_inputLine becomeFirstResponder];
        else
            m_kbShown = YES; // will becomeFirsResponder in viewDidAppear
    }
}

-(void)hideNotes {
    if (m_notesController)
        [m_notesController hide];
}

-(void)unlockKeyboard {
    if (m_kbLocked) {
        m_kbLocked = NO;
        [self showKeyboardLockState];
    }
}

- (void)toggleKeyboard
{
    if (m_notesController) {
        if ([m_notesController isVisible]) {
            [m_notesController toggleKeyboard];
            return;
        }
    }
    if (!m_kbShown)
        [self unlockKeyboard];
    if (m_kbShown)
        [m_inputLine resignFirstResponder];
    else
        [m_inputLine becomeFirstResponder];
    [self showKeyboardLockState];
}

- (void)forceToggleKeyboard {
    BOOL wasLocked = m_kbLocked;
    [self toggleKeyboard];
    m_kbLocked = wasLocked;
    [self showKeyboardLockState];
}

- (void) toggleKeyboardLongPress:(UILongPressGestureRecognizer*)sender {
    if ([sender respondsToSelector:@selector(view)]) {
        UIView *view = [sender view];
        [self showKeyboardLockStateInView: view];
    }
    if (m_notesController && [m_notesController isVisible])
        return;

    if (m_kbShown)
        [self dismissKeyboard];
    m_kbLocked = YES;
    [m_inputLine setClearButtonMode];
}

static BOOL checkedAccessibility = NO, hasAccessibility = NO;

static UIImage *GlkGetImageCallback(int imageNum) {
    if (!glkImageCache)
        glkImageCache = [[NSMutableDictionary alloc] initWithCapacity: 100];
    UIImage *image = [glkImageCache objectForKey: [NSNumber numberWithInt: imageNum]];
    if (image)
        return image;

    giblorb_map_t *map = giblorb_get_resource_map();
    if (!map)
        return nil;
    
    giblorb_result_t blorbres;
    giblorb_err_t err = giblorb_load_resource(map, giblorb_method_Memory, &blorbres, giblorb_ID_Pict, imageNum);
    if (!err) {
        NSData *data = nil;
        if (blorbres.chunktype == giblorb_make_id('J', 'P', 'E', 'G') || blorbres.chunktype == giblorb_make_id('P', 'N', 'G', ' '))
            data = [NSData dataWithBytesNoCopy: blorbres.data.ptr length:blorbres.length freeWhenDone:NO];
        if (data) {
            NSNumber *imgKey = [NSNumber numberWithInt: imageNum];
            image = scaledUIImage([UIImage imageWithData: data], 0, 0); // scales down too screen size if too big, else leaves alone
            [glkImageCache setObject: image forKey: imgKey];
        }
    }
    return image;
}
    
- (void)loadView {
    
    if (m_background) {
        self.view = m_background;
        return;
    }
    
    CGRect frame = [[UIScreen mainScreen] applicationFrame];
    if (UIInterfaceOrientationIsLandscape([self interfaceOrientation])) {
        CGFloat t = frame.size.width;
        frame.size.width = frame.size.height;
        frame.size.height = t;
        t = frame.origin.x; frame.origin.x = frame.origin.y; frame.origin.y = t;
    }
    frame.origin.x = 0;  // in left orientation on iPad, this is passed in as 20 for unknown reason
    float navHeight;
#ifdef NSFoundationVersionNumber_iOS_6_1
    if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1) {
        self.automaticallyAdjustsScrollViewInsets = NO;
        self.view = [[UIView alloc] initWithFrame:CGRectMake(frame.origin.x, frame.origin.y, frame.size.width, frame.size.height)];
        navHeight = 64.0;
        frame.origin.y = navHeight;
        frame.size.height -= navHeight;
    } else
#endif
    {
        navHeight = 44.0; //[self.navigationController.navigationBar bounds].size.height;
        frame.origin.y += navHeight;
        frame.size.height -= navHeight;
        self.view = [[UIView alloc] initWithFrame:CGRectMake(frame.origin.x, frame.origin.y, frame.size.width, frame.size.height)];
        frame.origin.y = 0;
    }

    [self.view setBackgroundColor: m_defaultBGColor];

#if 1
    //notes page support
    if (!m_notesController) {
        m_notesController = [[NotesViewController alloc] initWithFrame: frame];
        [m_notesController setDelegate: self];
        
        if ([self respondsToSelector:@selector(automaticallyForwardAppearanceAndRotationMethodsToChildViewControllers:)])
            [self addChildViewController:m_notesController]; // this was private but worked in 4.3, so check for another method added in 5.0
        // (Yes, this is hacky, but not as hacky as doing string compares on systemVersion)
    }
    m_background = [m_notesController containerScrollView];
    [m_background addSubview: m_notesController.view];
#endif
    [m_background setBackgroundColor: m_defaultBGColor];
 //   self.view = m_background;
   [self.view addSubview: m_background];

    [m_background addSubview: m_notesController.view];
    
    [m_background setAutoresizesSubviews: YES];
    [m_background setAutoresizingMask: UIViewAutoresizingFlexibleTopMargin|
    UIViewAutoresizingFlexibleBottomMargin|UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth];
    
    topWinSize = kStatusLineHeight;

    m_statusLine = [[StatusLine alloc] initWithFrame: CGRectMake(0.0f, 0.0f,  frame.size.width, kStatusLineHeight)];
    m_inputLine = [[StoryInputLine alloc] initWithFrame:  CGRectMake(0.0f, frame.size.height-236-2*kStatusLineHeight, frame.size.width, 2*kStatusLineHeight)];
    if (m_notesController)
        [m_notesController setChainResponder: m_inputLine];
    
    [m_statusLine setScrollsToTop: NO];
#if UseRichTextView
    [m_statusLine setLeftMargin: 0];
    [m_statusLine setRightMargin: 0];
    [m_statusLine setTopMargin: 0];
    [m_statusLine setBottomMargin: 0];
    [m_statusLine setBounces: NO];
#endif
    
    [m_inputLine setAutocapitalizationType: UITextAutocapitalizationTypeNone];
    
    const NSString *fixedFontName;
    NSArray *fontArray = [UIFont fontNamesForFamilyName: kFixedWidthFontName];
    for (fixedFontName in fontArray) {
        if ([fixedFontName rangeOfString: @"bold" options: NSCaseInsensitiveSearch].length > 0)
            break;
    }
#if !UseRichTextView
    if (!fixedFontName)
        fixedFontName = kFixedWidthFontName;
    m_statusLine.editable = NO;
#endif
    [m_statusLine setDelegate: self];
    [m_statusLine setAutoresizingMask: UIViewAutoresizingFlexibleWidth];
    
#if !UseRichTextView
    [m_statusLine setAutocapitalizationType: UITextAutocapitalizationTypeNone];
    [m_statusLine setAutocorrectionType: UITextAutocorrectionTypeNo];
    frame.origin.y = kStatusLineHeight;
    frame.size.height -= kStatusLineHeight;
#else
    CGFloat fudge = 1; // 1
    frame.origin.y = fudge;  // avoids richtext tile drawing glitch
    frame.size.height -= fudge;
#endif
    
    m_storyView = [[StoryView alloc] initWithFrame:frame];
    [m_storyView setScrollsToTop: YES];
    
    [m_storyView setDelegate: self];
#if !UseRichTextView
    m_storyView.editable = NO;
#endif
    UIEdgeInsets edgeInsets = [m_storyView contentInset];
    //    edgeInsets.right = 8;
    edgeInsets.bottom = 8;
    [m_storyView setContentInset: edgeInsets];
    
    m_fontSize = gLargeScreenDevice ? kDefaultPadFontSize : kDefaultFontSize;
    [self loadPrefs];
    
    [m_storyView setAutoresizingMask: /*UIViewAutoresizingFlexibleTopMargin|*/UIViewAutoresizingFlexibleBottomMargin|UIViewAutoresizingFlexibleRightMargin|
     UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight];
#if !UseRichTextView
    [m_storyView setAutocapitalizationType: UITextAutocapitalizationTypeNone];
    [m_storyView setAutocorrectionType: UITextAutocorrectionTypeNo];
#else
    setColorTable(m_storyView);
    setColorTable(m_statusLine);
    
    [m_storyView setSelectionDelegate: self];
#endif
    
    [m_background addSubview: m_storyView];
    [m_background addSubview: m_statusLine];
    [m_background addSubview: m_inputLine];
    [m_inputLine setStoryView: m_storyView];
    [m_inputLine setStatusLine: m_statusLine];
    [m_background bringSubviewToFront: m_inputLine];
    
    [m_inputLine setAutocorrectionType: UITextAutocorrectionTypeNo];
    [m_inputLine setDelegate: self];
    [m_storyView setDelegate: self];
    
//    m_kbdToggleItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose target:self action:@selector(toggleKeyboard)];
    m_kbdToggleItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"icon-keyboard.png"] style:UIBarButtonItemStylePlain target:self action:@selector(toggleKeyboard)];
    [m_kbdToggleItem setStyle: UIBarButtonItemStylePlain];
    self.navigationItem.rightBarButtonItem = m_kbdToggleItem;
    
    // Allocate in viewWillAppear instead
    //m_frotzInfoController = [[FrotzInfo alloc] initWithSettingsController:[m_storyBrowser settings] navController:[self navigationController] navItem:self.navigationItem];
    
    theSMVC = self;
    theStoryView = m_storyView;
    theStatusLine = m_statusLine;
    theInputLine = m_inputLine;
    
    m_storyView.richDataGetImageCallback = GlkGetImageCallback;
    [self setBackgroundColor: m_defaultBGColor makeDefault: NO];
    [self setTextColor: m_defaultFGColor makeDefault: NO];
    
    [self checkAccessibility];
    if (hasAccessibility) {
        [m_storyView setAccessibilityValue: nil];
        [m_inputLine setAccessibilityValue: nil];
    }
    
}
- (void) setIgnoreWordSelection:(BOOL)ignore {
    m_ignoreWordSelection = ignore;
}

-(void)textSelectedAnimDidFinish:(NSString *)animationID finished:(NSNumber *)finished context:(void *)context {
    NSString *origText = [m_inputLine text];
    NSString *text = (NSString*)context;
    [UIView setAnimationDelegate: nil];
    m_animDuration = 0;
    //NSLog(@"textsel did fin: %@ %@", text, finished);
    if (!m_ignoreWordSelection) { // finished && [finished boolValue]) {
        if ([[m_inputLine text] length]) {
            if (![origText hasSuffix: @" "])
                origText = [origText stringByAppendingString: @" "];
            [m_inputLine setText: [origText stringByAppendingString: text]];
        }
        else
            [m_inputLine setText: text];
    }
    m_ignoreWordSelection = NO;
    [text release];
    [m_storyView clearSelection];
}

-(void)textSelected:(NSString*)text animDuration:(CGFloat)animDuration hilightView:(UIView <WordSelection>*)view {
    m_ignoreWordSelection = NO;
    if (/*m_kbShown && */!(ipzAllowInput & kIPZNoEcho)) {
        // m_kbShown commented out so this still works with paired hardware keyboards
        NSString *origText = [m_inputLine text];
        //NSLog(@"textsel: %@", text);
        [text retain];
        [UIView beginAnimations: @"tsel" context: text];
        [UIView setAnimationDelay: 0.1];
        CGRect frame = [m_inputLine frame];
        CGRect origViewFrame = [view frame];
        CGFloat inputLineWidth = frame.size.width;
        frame.size = origViewFrame.size;
        frame = [m_inputLine.superview convertRect:frame toView:view.superview];
        CGFloat maxDist = [[UIScreen mainScreen] applicationFrame].size.height;
        if (frame.origin.y - origViewFrame.origin.y > maxDist)
            frame.origin.y = origViewFrame.origin.y + maxDist;
        CGFloat duration = animDuration;
        if (duration < 0) {
            duration = 1.0*(frame.origin.y - origViewFrame.origin.y)/maxDist;
            if (duration < 0.2)
                duration = 0.2;
        }
        m_animDuration = duration;
        [UIView setAnimationDuration: duration];
        [view setFont: [m_inputLine font]];
        if (origText && [origText length]) {
            if (![origText hasSuffix: @" "])
                origText = [origText stringByAppendingString: @" "];
            CGFloat clearButtonWidth = [m_inputLine clearButtonRectForBounds: [m_inputLine bounds]].size.width+1;
            CGFloat textWidth = [origText sizeWithFont: [m_inputLine font]].width;
            if (textWidth + frame.size.width < inputLineWidth - clearButtonWidth)
                frame.origin.x += textWidth;
            else 
                frame.origin.x = inputLineWidth - frame.size.width - clearButtonWidth;
        }
        [UIView setAnimationDelegate: self];
        [UIView setAnimationDidStopSelector: @selector(textSelectedAnimDidFinish:finished:context:)];
        [view setFrame: frame];
        
        [UIView commitAnimations];
    }
}

-(void)handleAccessibilityLoad:(NSNotification*)aNotification {
    if ([[(NSObject*)aNotification.object description] rangeOfString: @"UIAccessibility"].length > 0) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSBundleDidLoadNotification object:nil];
        checkedAccessibility = NO;
        [self performSelector: @selector(checkAccessibility) withObject:nil afterDelay:0.01];
    }
}

-(void)checkAccessibility {
    static BOOL hadAccessibility = NO;
    if (hadAccessibility)
        return;
    hasAccessibility = [m_inputLine respondsToSelector: @selector(setAccessibilityLabel:)];
    if (hasAccessibility) {
        [m_statusLine setAccessibilityLabel: NSLocalizedString(@"Status line",nil)];
        [m_statusLine setAccessibilityHint: nil];
        [m_statusLine setAccessibilityTraits: UIAccessibilityTraitNotEnabled]; //256,128
        [m_storyView setAccessibilityLabel: NSLocalizedString(@"Story output",nil)];
        [m_storyView setAccessibilityHint: nil];
        // [m_storyView setAccessibilityTraits: UIAccessibilityTraitNotEnabled|UIAccessibilityTraitStaticText]; //256,64
        [m_storyView setAccessibilityTraits: UIAccessibilityTraitSummaryElement];
        
#if UseRichTextView
        [m_statusLine setIsAccessibilityElement: YES];
        [m_storyView setIsAccessibilityElement: YES];
#endif
        [m_inputLine setAccessibilityLabel: NSLocalizedString(@"Input command",nil)];
        [m_inputLine setAccessibilityHint: nil];
        [m_inputLine setAccessibilityTraits: UIAccessibilityTraitStaticText]; //64
        
        UIBarButtonItem *shkb = self.navigationItem.rightBarButtonItem;
        if ([shkb respondsToSelector: @selector(view)])
            [(UIView*)[shkb view] setAccessibilityLabel: NSLocalizedString(@"Show/Hide Keyboard",nil)];
        [m_frotzInfoController updateAccessibility];
        [m_storyBrowser updateAccessibility];
        hadAccessibility = YES;
    }
}

-(void)dealloc {
    [m_kbdToggleItem release];

    [m_storyView release];
    [m_statusLine release];
    [m_inputLine release];
    [m_background release];
    m_background = nil;
    if (m_notesController)
        [m_notesController release];
    m_notesController = nil;
    
    [m_currentStory release];
    [m_fontname release];
    
    [storyGamePath release];
    [resourceGamePath release];
    [storyTopSavePath release];
    [storySavePath release];
    [storySIPPath release];
    [activeStoryPath release];
    [storySIPSavePath release];
    [m_defaultBGColor release];
    [m_defaultFGColor release];
    [super dealloc];
}

-(StoryBrowser*)storyBrowser {
    return m_storyBrowser;
}

-(void)setStoryBrowser:(StoryBrowser*)browser {
    m_storyBrowser = browser;
}


-(void)setupFadeWithDuration:(float)duration {
    CATransition *animation = [CATransition animation];
    [animation setType:kCATransitionFade];
    [animation setDuration: duration];
    [animation setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];	
    [[m_background layer] addAnimation:animation forKey:@"storyfade"];
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    m_rotationInProgress = YES;
    if (!self.navigationController.modalViewController)
        [m_frotzInfoController dismissInfo];
    if (m_storyView)
        [self hideInputHelper];
    
    if (m_notesController)
        [m_notesController willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
}

- (BOOL)prefersStatusBarHidden {
    return m_landscape && !gLargeScreenDevice;
}

- (void)autosize {
    if (UIDeviceOrientationIsLandscape([self interfaceOrientation])) {
        m_landscape = YES;
        if (!gLargeScreenDevice) {
            if (isOS32)
                [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation: UIStatusBarAnimationSlide];
            else if (isOS30)
                [[UIApplication sharedApplication] setStatusBarHidden:YES animated:YES];
        }
        [self.navigationController setNavigationBarHidden:gLargeScreenDevice?NO:YES animated:YES];
    } else {
        if (!gLargeScreenDevice) {
            if (isOS32)
                [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation: UIStatusBarAnimationSlide];
            else if (isOS30)
                [[UIApplication sharedApplication] setStatusBarHidden:NO animated:YES];
        }
        m_landscape = NO;
        [self.navigationController setNavigationBarHidden:NO animated:YES];
    }
    [self performSelector: @selector(_clearRotationInProgress) withObject: nil afterDelay:0.05];

    CGRect frame = [self storyViewFullFrame];

    // Work around weird bug where the owning NotesVC scrollview resizes the view 20
    // pixels smaller when presentModalViewController shows the view.  Dunno why, but this
    // compensates for it.
    if (gUseSplitVC && m_landscape && m_autoRestoreDict!=nil)
        frame.size.height += 20;

#ifdef NSFoundationVersionNumber_iOS_6_1
    if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1)
    {
        CGRect applicationFrame = [[UIScreen mainScreen] applicationFrame], bgRect;
        BOOL swap = m_landscape;
#if defined(__IPHONE_8_0)
		if ([[[UIDevice currentDevice] systemVersion] compare:@"8.0" options:NSNumericSearch] != NSOrderedAscending)
			swap = NO;
#endif
        CGFloat height = swap ? applicationFrame.size.width : applicationFrame.size.height;
        CGFloat width = !swap ? applicationFrame.size.width : applicationFrame.size.height;
        CGFloat statusHeight = 20;
        // storyViewFullFrame subtracts off original origin, which we don't want, so add it back in here
        if (m_landscape)
            bgRect = CGRectMake(0, height-frame.size.height-frame.origin.y + (gLargeScreenDevice?20:0), width, frame.size.height+frame.origin.y);
        else
            bgRect = CGRectMake(0, height-frame.size.height-frame.origin.y+statusHeight, width, frame.size.height+frame.origin.y);
        m_background.frame = bgRect;
    }
#endif
    
    // iOS 8 seems to be auto-restoring the first responder and bringing the keyboard back when you return to the story from the
    // story list, which we never had to deal with before.  Worse, sometimes keyboardDidShow notification happens after viewDidAppear,
    // and sometimes BEFORE, so we have to handle it here as well. If KB is already shown, adjust frame accordingly.
    if (m_kbShown)
        frame.size.height -= m_kbdSize.height;
    [m_storyView setFrame: frame];
    CGRect statusFrame = [m_statusLine frame];
    statusFrame.size.width = frame.size.width;
    [m_statusLine setFrame: statusFrame];
    [m_statusLine setNeedsDisplay];

    if (m_notesController)
        [m_notesController autosize];
    [self resizeStatusWindow];

}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {    // Notification of rotation ending.
    [self autosize];
	[m_inputLine updatePosition];
    [self addKeyBoardLockGesture];
    [[m_storyBrowser detailsController] refresh];
}

-(void)_clearRotationInProgress {
    m_rotationInProgress = NO;
}

-(CGRect) storyViewFullFrame {
    CGRect applicationFrame = [[UIScreen mainScreen] applicationFrame];
    CGRect frame = CGRectMake(0, 0, 0, 0);
	if (applicationFrame.size.height < applicationFrame.size.width) { // iOS 8, AppFrame is rotated in landscape mode, detect and undo
		CGFloat t = applicationFrame.size.height;
		applicationFrame.size.height = applicationFrame.size.width;
		applicationFrame.size.width = t;
	}
    float navHeight = [self.navigationController.navigationBar bounds].size.height;
#if UseRichTextView
    float statusHeight = 0;
    frame.origin.y = 0;
#else
    float statusHeight = [m_statusLine frame].size.height;
    frame.origin.y = statusHeight;
#endif
    BOOL navHidden = [self.navigationController isNavigationBarHidden];
    //    if (UIDeviceOrientationIsLandscape([[UIDevice currentDevice] orientation]) || !m_rotationInProgress && m_landscape) { // m_landscape
    if (UIDeviceOrientationIsLandscape([self interfaceOrientation])) {
        if (navHidden)
            frame.size.height = applicationFrame.size.width - statusHeight;
        else
            frame.size.height = applicationFrame.size.width - (gLargeScreenDevice?navHeight:navHeight /2) - statusHeight;
        frame.size.width = applicationFrame.size.height;
    } else {
        if (navHidden)
            frame.size.height = applicationFrame.size.height - (gLargeScreenDevice?0:navHeight/2) - statusHeight;
        else
            frame.size.height = applicationFrame.size.height - navHeight - statusHeight;
        frame.size.width = applicationFrame.size.width;
    }
    
    //    frame.size.width = m_storyView.frame.size.width; ??? why was this here
    
    //    NSLog(@"sv full frame nav=%d dev=%d frame +%.0f,%.0f,%.0fx%.0f", navHidden, UIDeviceOrientationIsLandscape([[UIDevice currentDevice] orientation]),
    //	    frame.origin.x, frame.origin.y,frame.size.width, frame.size.height);
    CGPoint origin = m_storyView.frame.origin;
    frame.origin.x += origin.x;
    frame.origin.y += origin.y;
    frame.size.width -= origin.x;
    frame.size.height -= origin.y;
    return frame;
}

//-(void) allNotif:(NSNotification*)notif  {
//    NSString *name = [notif name];
//    if (![name hasPrefix:@"UIViewAnim"])
//        NSLog(@"Notification %@", notif);
//}

//-(void) keyboardWillChangeFrame:(NSNotification*)notif  {
//    NSLog(@"kb will change frame %@", notif);
//}

-(void) keyboardDidShow:(NSNotification*)notif {
//    NSLog(@"kb did show: %@", notif);
    // Even though we already did this in keyboardWillShow, we do it again here
    // so the animation of the storyview resizing will sync up with the keyboard
    // appearing, to make sure the size is correct for whether the
    // the nav bar and device status line are visible.
    // The storyViewFullFrame call cannot tell if these items are visible or not
    // during a rotation because the show/hide hasn't taken effect yet,
    // so resizing again here will be correct.
    NSDictionary *userInfo = [notif userInfo];
    NSValue *boundsValue = [userInfo objectForKey: UIKeyboardBoundsUserInfoKey];
    if (!boundsValue) // sometimes nil in ios 8???
        return;
    CGRect bounds = [boundsValue CGRectValue];

#ifdef NSFoundationVersionNumber_iOS_6_1
    if (floor(NSFoundationVersionNumber) >= 1133.0) { // iOS 8.0 doesn't sent hide notifications for undocked kbd
        // and instead sends another show notification with smaller frame height
        NSValue *frameUserInfoValue = [userInfo objectForKey: UIKeyboardFrameEndUserInfoKey];
        if (gLargeScreenDevice && frameUserInfoValue) {
            CGRect frameEnd = [frameUserInfoValue CGRectValue];
            CGFloat height = frameEnd.size.width > frameEnd.size.height ? frameEnd.size.height : frameEnd.size.width;
            if (height <= 216 || height == 267) { // hackish check for known undocked kb sizes; hopefully iOS 8 will fix this before release
                if (m_kbShown) // do our own hide notification
                    [self keyboardWillHide:notif];
                return;
            }
        }
    }
#endif
    m_kbShown = YES;
    
    // workaround ios 8 beta bug, where bounds width & height are swapped in landscape
    if (bounds.size.height > bounds.size.width) {
        CGFloat h = bounds.size.height;
        bounds.size.height = bounds.size.width;
        bounds.size.width = h;
    }

    m_kbdSize = bounds.size;
    CGRect frame = [self storyViewFullFrame];
    frame.size.height -= bounds.size.height;
    
    [UIView beginAnimations: @"kbd" context: 0];
    [UIView setAnimationBeginsFromCurrentState:YES];

    //NSLog(@"keyboarddidshow storyview frame=(%f,%f,%f,%f) boundssize=%f boundsVal=%@", frame.origin.x, frame.origin.y, frame.size.width, frame.size.height, bounds.size.height, boundsValue);
    [m_storyView setFrame: frame];

    CGRect statusFrame = [m_statusLine frame];
    statusFrame.size.width = frame.size.width;
    [m_statusLine setFrame: statusFrame];
    [UIView commitAnimations];
    
    if (m_rotationInProgress)
        [self performSelector: @selector(scrollStoryViewToEnd) withObject:nil afterDelay:0.2];

    [m_inputLine updatePosition];
    
    if (gStoryInterp == kGlxStory) {
        iphone_recompute_screensize();
        screen_size_changed = 1;
    }
}

-(void) keyboardDidHide:(NSNotification*)notif {
    m_kbShown = NO;
    m_kbdSize = CGSizeZero;
    if (gStoryInterp == kGlxStory) {
        iphone_recompute_screensize();
        screen_size_changed = 1;
    }
}

-(CGSize) keyboardSize {
    return m_kbdSize;
}

-(void) keyboardWillShow:(NSNotification*)notif {
    NSDictionary *userInfo = [notif userInfo];
    NSValue *boundsValue = [userInfo objectForKey: UIKeyboardBoundsUserInfoKey];
    CGRect bounds = [boundsValue CGRectValue];
    CGRect frame = [self storyViewFullFrame];

    // workaround ios 8 beta bug, where bounds width & height are swapped in landscape
    if (bounds.size.height > bounds.size.width) {
        CGFloat h = bounds.size.height;
        bounds.size.height = bounds.size.width;
        bounds.size.width = h;
    }
#if UseRichTextView
    [m_storyView prepareForKeyboardShowHide];
#endif
    CGFloat botMargin = [m_storyView bottomMargin];
    if (botMargin > 0) {
        bounds.size.height -= botMargin;
        if (bounds.size.height < 0)
            bounds.size.height = 0;
    }
    if (m_notesController)
        [m_notesController keyboardWillShow: bounds];
    
    frame.size.height -= bounds.size.height;
    
    [UIView beginAnimations: @"kbd" context: 0];
    [UIView setAnimationDuration: 0.3];
    [UIView setAnimationBeginsFromCurrentState:YES];

#if 1
    if (!m_rotationInProgress) {
        CGPoint cofst = [m_storyView contentOffset];
        cofst.y += bounds.size.height;
        [m_storyView setContentOffset: cofst];
    }
#endif
    [m_storyView setFrame: frame];
    //NSLog(@"keyboardwillshow storyview frame=(%f,%f,%f,%f) boundssize=%f boundsVal=%@", frame.origin.x, frame.origin.y, frame.size.width, frame.size.height, bounds.size.height, boundsValue);
    CGRect statusFrame = [m_statusLine frame];
    statusFrame.size.width = frame.size.width;
    [m_statusLine setFrame: statusFrame];
    
    [UIView commitAnimations];
    
    if (!m_rotationInProgress)
        [self scrollStoryViewToEnd: YES];
    
    [m_inputLine updatePosition];
    
    //NSLog(@"kbd will show notif frame height=%f kbbh=%f", frame.size.height, bounds.size.height);
}


-(void) keyboardWillHide:(NSNotification*)notif {
    CGRect frame = [self storyViewFullFrame];
#if UseRichTextView
    [m_storyView prepareForKeyboardShowHide];
#endif
    if (m_notesController)
        [m_notesController keyboardWillHide];
    
    [UIView beginAnimations: @"kbd" context: 0];
    [UIView setAnimationDuration: 0.3];
    [UIView setAnimationBeginsFromCurrentState:YES];
    
    [m_storyView setFrame: frame];
    
    CGRect statusFrame = [m_statusLine frame];
    statusFrame.size.width = frame.size.width;
    [m_statusLine setFrame: statusFrame];
    [UIView commitAnimations];
    m_kbShown = NO;
}

-(BOOL) isKBShown {
    return m_kbShown;
}

-(BOOL) isKBLocked {
    return m_kbLocked;
}

-(void) scrollStoryViewToEnd {
    [self scrollStoryViewToEnd: YES];
}

-(void) scrollStoryViewToEnd:(BOOL)animated {
    FrotzView *storyView = m_storyView;
    if (gStoryInterp == kGlxStory && cwin > 0 && cwin < [m_glkViews count] && glkGridArray[cwin].win->type == wintype_TextBuffer) {
        storyView = [m_glkViews objectAtIndex: cwin];
    }
    CGSize contentSize = [storyView contentSize];
    float height = contentSize.height-[storyView visibleRect].size.height;
    if (height < 0)
        height = 0;
    CGPoint contentOffset = CGPointMake(0, height);
    removeAnim(storyView);
    [storyView setContentOffset: contentOffset animated: animated];
}

-(BOOL) scrollStoryViewOnePage:(FrotzView*)view fraction:(float)fraction {
    CGRect visRect = [view visibleRect];
    //    visRect.size.height += [view bottomMargin]; // bcs
    CGFloat topMargin = [view topMargin];
    CGPoint contentOffset = [view contentOffset];
    CGSize contentSize = [view contentSize];
    float height = visRect.size.height/fraction;
    if (contentOffset.y < contentSize.height - 2*height + topMargin) {
        contentOffset.y += height - topMargin - 16;
    } else if (contentOffset.y <  contentSize.height - height) {
        contentOffset.y = contentSize.height - height;
    } else {
        int viewNum = [m_glkViews indexOfObject:view];
        if (viewNum == NSNotFound)
            viewNum = 0;
        if (lastVisibleYPos[viewNum] < contentOffset.y)
            lastVisibleYPos[viewNum] = contentOffset.y;
        return NO;
    }
    
    [view setContentOffset: contentOffset animated: YES];
    return YES;
}

-(BOOL) scrollStoryViewUpOnePage:(FrotzView*)view fraction:(float)fraction {
    CGRect visRect = [view visibleRect];
    CGPoint contentOffset = [view contentOffset];
    float height = visRect.size.height/fraction;
    if (contentOffset.y == 0)
        return NO;
    else if (contentOffset.y < height)
        contentOffset.y = 0;
    else
        contentOffset.y -= height;
    [view setContentOffset: contentOffset animated: YES];
    return YES;
}

-(void) openFileBrowserWrap:(NSNumber*)dialogType {
    [self openFileBrowser: (FileBrowserState)[dialogType intValue]];
}

-(void) openFileBrowser:(FileBrowserState)dialogType {
    FileBrowser *fileBrowser = [[FileBrowser alloc] initWithDialogType:dialogType];
    
    [fileBrowser setPath: storySavePath];
    
    [fileBrowser setDelegate: self];
    [fileBrowser reloadData];
    
    if (gUseSplitVC) {
        UINavigationController *nc = [[UINavigationController alloc] initWithRootViewController: fileBrowser];
        [nc.navigationBar setBarStyle: UIBarStyleBlackOpaque];   
        nc.modalPresentationStyle = UIModalPresentationFormSheet;
        [self.navigationController presentModalViewController: nc animated: YES];
    } else {
        if (!gLargeScreenDevice)
            [self.navigationController setNavigationBarHidden:NO animated:YES];
        [self.navigationController pushViewController: fileBrowser animated: YES];
    }
    
    [fileBrowser release];
}

-(void) fileBrowser: (FileBrowser *)browser fileSelected:(NSString *)file {
    if (gUseSplitVC) {
        UINavigationController *nc = browser.navigationController;
        [self.navigationController dismissModalViewControllerAnimated:YES];
        [nc release];
    }
    else {
        [self.navigationController popViewControllerAnimated: YES];
        if (!gLargeScreenDevice)
            [self.navigationController setNavigationBarHidden:m_landscape ? YES:NO animated:YES];
    }
    if (file)
        strcpy(iphone_filename, [file UTF8String]);
    else
        *iphone_filename = '\0';
    [self activateKeyboard];
    do_filebrowser = kFBHidden;
}

-(void) fileBrowser: (FileBrowser *)browser deleteFile: (NSString*)filePath {
    id fileMgr = [NSFileManager defaultManager];
    NSError *error;
    [fileMgr removeItemAtPath: filePath error: &error];
    if ([[DBSession sharedSession] isLinked]) {
        NSString *subPath = [filePath stringByReplacingOccurrencesOfString:storyTopSavePath withString:@"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, filePath.length)];
        NSString *dbPath = [[self dbSavePath] stringByAppendingPathComponent: subPath];
        [self.restClient deletePath: dbPath];
        [self cacheTimestamp:nil forSaveFile: [self metadataSubPath: dbPath]];
    }
}

-(void) setBackgroundColor: (UIColor*)color makeDefault:(BOOL)makeDefault {
    if (makeDefault && color != m_defaultBGColor) {
        [m_defaultBGColor release];
        m_defaultBGColor = [color retain];
    }
    if (!m_storyView)
        return;

    [m_storyView setBackgroundColor: color];
    
    [m_background setBackgroundColor: m_defaultBGColor];

    if (gLargeScreenDevice)
        [self setNavBarTint];
    
#if UseRichTextView
    [m_statusLine setBackgroundColor: color];
#else
    [m_statusLine setTextColor: color];
#endif
    //    [m_inputLine setBackgroundColor: color];
}

-(void) setTextColor: (UIColor*)color makeDefault:(BOOL)makeDefault {
    if (makeDefault && color != m_defaultFGColor) {
        [m_defaultFGColor release];
        m_defaultFGColor = [color retain];
    }
    if (!m_storyView)
        return;
    [self.view setBackgroundColor: m_defaultFGColor];
    if (gLargeScreenDevice)
        [self setNavBarTint];
    //    if (makeDefault && currColor != 0 && currColor != 0x29)
    //	return;
    [m_storyView setTextColor: color];
#if UseRichTextView
    [m_statusLine setTextColor: color];
#else
    [m_statusLine setBackgroundColor: color];
#endif
    [m_inputLine setTextColor: color];
    [m_storyView setNeedsLayout];
    [m_statusLine setNeedsLayout];
}

-(UIColor*) backgroundColor {
    return m_defaultBGColor;
}

-(UIColor*) textColor {
    return m_defaultFGColor;
}

-(BOOL) isLandscape {
    return m_landscape;
}

-(void)setLandscape:(BOOL)landscape {
    m_landscape = landscape;
}

-(void) setFont: (NSString*) fontname withSize:(int)size {
    if (fontname) {
        [m_fontname release];
        m_fontname = [fontname copy];
    } // else keep existing font, just change size
    if (size)
        m_fontSize = size;
    if (m_fontSize < 1)
        m_fontSize = gLargeScreenDevice ? kDefaultPadFontSize : kDefaultFontSize;
    else if (m_fontSize < 8)
        m_fontSize = 8;
    else if (m_fontSize > (gLargeScreenDevice ? 32 : 24))
        m_fontSize = gLargeScreenDevice ? 32 : 24;
    UIFont *font = [UIFont fontWithName:m_fontname  size:m_fontSize];
#if UseRichTextView
    bool normalSizedStatusFont = UseFullSizeStatusLineFont && isOS32;
	bool normalSizeFixedFont = normalSizedStatusFont || gLargeScreenDevice || gLargeScreenPhone>1;
    [m_storyView setFontFamily: [font familyName] size: m_fontSize];
    int fixedFontSize = normalSizeFixedFont ? m_fontSize : (m_fontSize > 12 ? (m_fontSize+5)/2:8);
    [m_storyView setFixedFontFamily: [[m_storyView fixedFont] familyName] size: fixedFontSize];
    [m_storyView reflowText];
    if (normalSizedStatusFont) {
        int lowRange = gLargeScreenDevice ? 12 : 8;
        int hiRange = gLargeScreenDevice ? 20 : 16;
        m_statusFixedFontSize = fixedFontSize > hiRange ? hiRange : fixedFontSize < lowRange ? lowRange : fixedFontSize;
    }
    else if (gLargeScreenDevice)
        m_statusFixedFontSize = 15;
    else
        m_statusFixedFontSize = normalSizeFixedFont ? 9 : 8;
    NSString *statusFixedFontFamily = [[m_statusLine fixedFont] familyName];
    [m_statusLine setFontFamily: statusFixedFontFamily size: m_statusFixedFontSize];
    [m_statusLine setFixedFontFamily: statusFixedFontFamily size: m_statusFixedFontSize];
    UIFont *fixedFont = [m_statusLine fixedFont];
    m_statusFixedFontWidth = !normalSizeFixedFont ? 5.0 : (int)[@"WWWW" sizeWithFont: fixedFont].width/4.0;
    m_statusFixedFontPixelHeight = !normalSizeFixedFont ? 9 : [fixedFont leading];
    [m_statusLine reflowText];
    
    if (gStoryInterp == kGlxStory) {
        int c = [m_glkViews count];
        for (int k = 0; k < c; ++k) {
            RichTextView *rtv = [m_glkViews objectAtIndex:k];
            if (glkGridArray[k].win->type == wintype_TextGrid) {
                [rtv setFixedFontFamily: statusFixedFontFamily size:m_statusFixedFontSize];
                [rtv setFontFamily: statusFixedFontFamily size:m_statusFixedFontSize];
            } else {
                [rtv setFontFamily: [font familyName] size:m_fontSize];
                [rtv setFixedFontFamily: [[m_storyView fixedFont] familyName] size: fixedFontSize];
            }
            [rtv reflowText];
        }
        screen_size_changed = 1;
    }
#else
    m_statusFixedFontSize = 8;
    m_statusFixedFontWidth = 5.0;
    m_statusFixedFontPixelHeight = 10;
    [m_storyView setFont: font];
    UIFont *fixedFont = [UIFont fontWithName:fixedFontName size:m_statusFixedFontSize];
    [m_statusLine setFont: fixedFont];
#endif
    [m_inputLine setFont: font];
}

-(NSString*) font {
    return m_fontname;
}

-(void) setFixedFont: (NSString*)font {
    int fixedFontSize = gLargeScreenDevice ? m_fontSize : (m_fontSize > 12 ? (m_fontSize+5)/2:8);
    [m_storyView setFixedFont: [UIFont fontWithName: font size: fixedFontSize]];
}

-(NSString*) fixedFont {
    return [[m_storyView fixedFont] fontName];
}

-(int) fontSize {
    return m_fontSize;
}

-(StoryView*) storyView {
    return m_storyView;
}

-(NSString*) currentStory {
    return m_currentStory;
}

-(NSString*) saveSubFolderForStory:(NSString*)storyPath {
    return [[storyPath lastPathComponent] stringByAppendingString: @".d"];
}

-(BOOL)autoSaveExistsForStory:(NSString*)storyPath {
    NSString *aStorySavePath = [storyTopSavePath stringByAppendingPathComponent: [self saveSubFolderForStory: storyPath]];
    NSString *sipPath = [aStorySavePath stringByAppendingPathComponent: @kFrotzAutoSavePListFile];
    if ([[NSFileManager defaultManager] fileExistsAtPath: sipPath])
        return YES;
    return NO;
}

-(void)deleteAutoSaveForStory:(NSString*)storyPath {
    NSString *aStorySavePath = [storyTopSavePath stringByAppendingPathComponent: [self saveSubFolderForStory: storyPath]];
    NSString *sipPath = [aStorySavePath stringByAppendingPathComponent: @kFrotzAutoSavePListFile];
    NSError *error = nil;
    [[NSFileManager defaultManager] removeItemAtPath: sipPath error: &error];
    NSString *savePath= [aStorySavePath stringByAppendingPathComponent: @kFrotzAutoSaveFile];
    [[NSFileManager defaultManager] removeItemAtPath: savePath error: &error];
    
    if (m_currentStory && [m_currentStory isEqualToString: storyPath]) {
        [self forceAbandonStory];
    }
}

-(void)updateAutosavePaths {
    if (storySIPPath)
        [storySIPPath release];
    storySIPPath    = [[storySavePath stringByAppendingPathComponent: @kFrotzAutoSavePListFile] retain];
    if (storySIPSavePath) {
        [storySIPSavePath release];
        storySIPSavePath = nil;
    }
    if (storySavePath) {
        storySIPSavePath= [[storySavePath stringByAppendingPathComponent: @kFrotzAutoSaveFile] retain];
        strcpy(AUTOSAVE_FILE,  [storySIPSavePath UTF8String]);  // used by interpreter from z_save
    }
}

-(NSString*)currentStorySavePath {
    return storySavePath;
}

-(NSString*)textFileBrowserPath {
    return storySavePath;
}

-(void) setCurrentStory: (NSString*)storyPath {
    id fileMgr = [NSFileManager defaultManager];
    if (m_currentStory != storyPath) {
        [m_currentStory release];
        m_currentStory = nil;
        BOOL isDir = NO;
        if (storyPath && [storyPath length] > 0) {
            if ([fileMgr fileExistsAtPath: storyPath isDirectory:&isDir] && !isDir)
                m_currentStory = [[NSMutableString stringWithString: storyPath] retain];
            else {
                NSString *altPath = [storyGamePath stringByAppendingPathComponent: [storyPath lastPathComponent]];
                if ([fileMgr fileExistsAtPath: altPath isDirectory:&isDir] && !isDir)
                    m_currentStory = [[NSMutableString stringWithString: altPath] retain];
                else {
                    altPath = [resourceGamePath stringByAppendingPathComponent: [storyPath lastPathComponent]];
                    if ([fileMgr fileExistsAtPath: altPath isDirectory:&isDir] && !isDir)
                        m_currentStory = [[NSMutableString stringWithString: altPath] retain];
                }
            }
        }
    }
    if (m_currentStory) {
        if (storySavePath)
            [storySavePath release];
        storySavePath = [[storyTopSavePath stringByAppendingPathComponent: [self saveSubFolderForStory: m_currentStory]] retain];
        if (![fileMgr fileExistsAtPath: storySavePath])
            [fileMgr createDirectoryAtPath: storySavePath attributes: nil];
    	strcpy(SAVE_PATH, [storySavePath UTF8String]);
        
        if (![fileMgr fileExistsAtPath: storySIPPathOld]) {
            [self updateAutosavePaths];
        }
    }
}


static int iphone_top_win_height = 1;
-(CGPoint)cursorOffset {
    return m_cursorOffset;
}

#if UseRichTextView
-(void) updateStatusLine:(RichTextView*)view {
    int slStyle = kFTFixedWidth|kFTNoWrap|kFTBold;
    int i, j=0, prevSlStyle=slStyle, isReverse=0, prevColor=0;
    int prevHyperlink=0, hyperlink=0;
    int off = 0;
    int maxPossCols = MAX_COLS;
    int numRows = iphone_top_win_height;
    int maxCols = 80; //h_screen_cols;
    window_textgrid_t *dwin = NULL;
    NSUInteger viewNum = [m_glkViews indexOfObject: view];
    if (!screen_colors || gStoryInterp == kGlxStory) {
        if (viewNum == NSNotFound) 
            return;
        maxCols = maxPossCols = glkGridArray[viewNum].nCols;
        numRows = glkGridArray[viewNum].nRows;
        dwin = glkGridArray[viewNum].win ? glkGridArray[viewNum].win->data : NULL;
    }
    NSMutableString *buf = [[NSMutableString alloc] init];
    int color = gStoryInterp == kGlxStory ? 0 : screen_colors[0];
    [view setTextColorIndex: color >> 4];
    [view setBgColorIndex: color & 0xf];
    [view clear];
    [view setTextStyle: slStyle];
    m_cursorOffset = CGPointMake(0, 0);
    for (i=0; i < numRows; ++i) {
#if UseFullSizeStatusLineFont
        int needCols = 0;
        int skipCol = -1, skipCount = 0, skipCol2 = -1, skipCount2 = 0;
        if (isOS32 && gStoryInterp==kZStory) {
            CGFloat charWidth = m_statusFixedFontWidth;
            int displayCols = (int)(view.frame.size.width / charWidth + 0.5);
            int firstNonReversedRow = 0;
            if (displayCols < h_screen_cols) {
                needCols = h_screen_cols - displayCols;
                for (j=0; j < numRows; ++j) {
                    isReverse = (screen_data[j * maxPossCols] >> 8) & REVERSE_STYLE;
                    if (!isReverse)
                        break;
                }
                firstNonReversedRow = j;
                if (i < firstNonReversedRow) {
                    int consecSpaces = 0, maxConsecSpaces = 0, maxConsecSpaces2 = 0, spaceIndex = -1, spaceIndex2 = -1;
                    for (j=0; j < h_screen_cols; ++j) {
                        wchar_t c = (unsigned char)screen_data[i * maxPossCols + j];
                        if (c == ' ') {
                            consecSpaces++;
                            if (consecSpaces > 1) {
                                if (consecSpaces > maxConsecSpaces) {
                                    if (maxConsecSpaces2 > 0 && skipCol!=j-consecSpaces+1) {
                                        maxConsecSpaces2 = maxConsecSpaces;
                                        spaceIndex2 = spaceIndex;
                                        skipCol2 = skipCol; skipCount2 = skipCount;
                                    }
                                    maxConsecSpaces = consecSpaces;
                                    spaceIndex = j;
                                    skipCol = spaceIndex-consecSpaces+1;
                                    skipCount = consecSpaces-1;
                                } else if (consecSpaces > maxConsecSpaces2) {
                                    maxConsecSpaces2 = consecSpaces;
                                    spaceIndex2 = j;
                                    skipCol2 = spaceIndex2-consecSpaces+1;
                                    skipCount2 = consecSpaces-1;
                                }
                            }
                        } else
                            consecSpaces = 0;
                    }
                    if (skipCount + skipCount2 > needCols) {
                        skipCount2 = (int)(1.0*skipCount2/(skipCount+skipCount2)*needCols);
                        skipCount = needCols - skipCount2;
                    }
                    if (skipCol2 >= 0 && skipCol2 < skipCol) {
                        int t = skipCol; skipCol = skipCol2; skipCol2 = t;
                        t = skipCount; skipCount = skipCount2; skipCount2 = t;
                    }
                    //NSLog(@"row=%d n=%d skip1=%d %d, skip2=%d %d", i, needCols, skipCol, skipCount, skipCol2, skipCount2);
                    if (skipCount + skipCount2 < needCols) {
                        int diff = needCols - skipCount - skipCount2;
                        if (diff > skipCol)
                            diff = skipCol;
                        skipCol -= diff;
                        skipCount += diff-1;
                    }
                } else {
                    for (j=h_screen_cols-1; j > 0; --j) {
                        isReverse = (screen_data[i * maxPossCols + j] >> 8) & REVERSE_STYLE;
                        if (isReverse)
                            break;
                    }
                    int maxc = j;
                    int trailingSpace = (h_screen_cols - maxc);
                    if (needCols > 0 && trailingSpace > 0) {
                        needCols -= trailingSpace-trailingSpace/2;
                        if (needCols < 0)
                            needCols = 0;
                    }
                    for (j=0; j < maxc; ++j) {
                        isReverse = (screen_data[i * maxPossCols + j] >> 8) & REVERSE_STYLE;
                        if (isReverse)
                            break;
                    }
                    if (j > 0 && j < h_screen_cols) {
                        skipCol = 0;
                        if (j > needCols)
                            skipCount = (needCols+j)/2;
                        else
                            skipCount = j;
                    }
                }
            }
        }
#endif
        
        int firstColStyle = (gStoryInterp == kGlxStory) ? 0 : (screen_data[i * maxPossCols] >> 8) & REVERSE_STYLE;
        tgline_t *ln = dwin && dwin->lines && i < dwin->height ? &(dwin->lines[i]) : NULL;
        for (j=0; j < maxCols; ++j) {
            wchar_t c = 0;
            if (j == skipCol) {
                j += skipCount;
                if (skipCol > 0 && skipCount == needCols-skipCount2-1)
                    c = 0x2026;
            } else if (j == skipCol2) {
                j += skipCount2;
            }
            if (gStoryInterp == kGlxStory) {
                if (!c)
                    c = glkGridArray[viewNum].gridArray[i * maxPossCols + j];
                if (ln && j < ln->size) {
                    int s = ln->attrs[j];
                    isReverse = ((dwin->hints[s].styleSetMask & kGlKStyleRevertColorMask) && dwin->hints[s].reverseColor!=0);
                    slStyle &= ~(kFTItalic|kFTReverse); //|kFTBold
                    if (s==style_Header || s==style_Subheader)
                        slStyle |= kFTBold;
                    else if (s==style_Emphasized)
                        slStyle |= kFTItalic;
                    else if (s==style_Alert)
                        isReverse = 1;
                    hyperlink = ln->hyperlink[j];
                }
                color = 0;
            } else {
                if (!c)
                    c = (unsigned char)screen_data[i * maxPossCols + j];
                color = screen_colors[i * maxPossCols + j];
                isReverse = (screen_data[i * maxPossCols + j] >> 8) & REVERSE_STYLE;
                if (currColor==0x22 || j >= h_screen_cols-1 && iphone_top_win_height <= 4 && firstColStyle) {
                    isReverse = REVERSE_STYLE;
                    color = prevColor;
                }
            }
            if (color != prevColor) {
                if ([buf length]) {
                    [view appendText: buf];
                    [buf setString: @""];
                }
                [view setTextColorIndex: color >> 4];
                [view setBgColorIndex: color & 0xf];
                prevColor = color;
            }
            slStyle &= ~kFTReverse;
            slStyle |= (isReverse & REVERSE_STYLE) ? kFTReverse : 0;
            if (slStyle != prevSlStyle) {
                if ([buf length]) {
                    [view appendText: buf];
                    [buf setString: @""];
                }
                [view setTextStyle: slStyle];
                prevSlStyle = slStyle;
            }
            if (prevHyperlink != hyperlink) {
                if ([buf length]) {
                    [view appendText: buf];
                    [buf setString: @""];
                }
                [view setHyperlinkIndex: hyperlink];
                prevHyperlink = hyperlink;
            }
            if (i == cursor_row && j == cursor_col) {
                if ([buf length]) {
                    [view appendText: buf];
                    [buf setString: @""];
                }
                m_cursorOffset = [m_statusLine lastPt];
            }
            if (c==' ')
                [buf appendString: @" "];
            else if (c==kClearEscChar) {
                [buf release];
                [view clear];
                return;
            }		
            else {
                NSString *uniFmt = @"%C"; // moved out of line to suppress incorrect warning
                [buf appendFormat: uniFmt, c];
            }
            ++off;
        }
        if (h_screen_cols == maxCols) {
            [buf appendString: @"             "];
            off += 15;
        }
        [buf appendString: @"                      "];
        off += 20;
        if (1 || i < iphone_top_win_height-1) {
            [buf appendString: @"\n"];
            ++off;
        }
    }
    [view appendText: buf];
    [view setTextStyle: slStyle];
    if (hasAccessibility)
        [view setAccessibilityValue: view.text];
    [buf release];
    if (cwin==1)
        [m_inputLine updatePosition];
}
#else
char *tempStatusLineScreenBuf() {
    static char buf[MAX_ROWS * MAX_COLS];
    int i, j=0;
    for (i=0; i < iphone_top_win_height; ++i) {
        for (j=0; j < h_screen_cols; ++j) {
            char c = (char)screen_data[i * MAX_COLS + j];
            buf[i * (h_screen_cols+1) + j] = c;
        }
        buf[i*(h_screen_cols+1) + j] = '\n';
    }
    
    buf[i*(h_screen_cols+1)] = '\0';	
    return buf;
}
#endif

-(void)reloadImages {
    for (RichTextView *v in m_glkViews) {
        [v reloadImages];
    }
}

-(void)printText: (id)unused {
    static int prevTopWinHeight = 1;
    static int continuousPrintCount = 0;
    static int grewStatus = 0;
    int textLen;
    CGRect viewFrame = [m_storyView frame];
    BOOL fast = NO;
    RichTextView *storyView = nil;
    RichTextView *statusLine = nil;
    NSMutableString *inputStatusStr = ipzStatusStr;
    NSMutableString *inputBufferStr = ipzBufferStr;
    
    pthread_mutex_lock(&winSizeMutex);
    
    int viewNum = 0;
    BOOL glkViewIsGrid = NO;
    if (gStoryInterp == kGlxStory && [m_glkViews count] > 1) {
        int glkInputsCount = glkInputs ? [glkInputs count] : 0;
        
        int vn = 0;
        for (RichTextView *v in m_glkViews) {
            if (glkInputsCount <= vn)
                break;
            if ((NSNull*)v == [NSNull null])
                ;
            else if (!statusLine && glkGridArray[vn].win && glkGridArray[vn].win->type == wintype_TextGrid && [[glkInputs objectAtIndex:vn] length] > 0) {
                statusLine = v;
                inputStatusStr = [glkInputs objectAtIndex:vn];
                glkViewIsGrid = YES;
            }
            else if (!storyView && glkGridArray[vn].win && glkGridArray[vn].win->type == wintype_TextBuffer && [[glkInputs objectAtIndex:vn] length] > 0) {
                storyView = v;
                inputBufferStr = [glkInputs objectAtIndex:vn];
                viewNum = vn;
            }
            ++vn;
        }
        if (!storyView) {
            storyView = m_storyView;
        }
        if (!statusLine)
            statusLine = m_statusLine;
    } else {
        storyView = m_storyView;
        statusLine = m_statusLine;
    }
    int statusLen = [inputStatusStr length];

    if (iphone_top_win_height == -2) {
        topWinSize = prevTopWinHeight * (m_statusFixedFontPixelHeight+1);
        [statusLine setFrame: CGRectMake(0.0f, 0.0f, viewFrame.size.width,  topWinSize)];
        iphone_top_win_height = prevTopWinHeight;
        [storyView setTopMargin: topWinSize];
        grewStatus = 1;
    }

    if (iphone_top_win_height < 0)
        prevTopWinHeight = -1;
    
    BOOL frozeDisplay = NO;
    
    if (statusLen > 1 && top_win_height <=1 && prevTopWinHeight>=3) { // && [storyView textStyle]==kFTFixedWidth) {
        [storyView setFreezeDisplay: YES];
        [statusLine setFreezeDisplay: YES];
        frozeDisplay = YES;
    }
    
    if (iphone_top_win_height < 0 || prevTopWinHeight != top_win_height
                && (grewStatus==2 || statusLen > 1 && !grewStatus || top_win_height==0 || top_win_height > prevTopWinHeight)) {
        
        if (top_win_height > 1 && top_win_height > prevTopWinHeight)
            grewStatus = 1;
        else
            grewStatus = 0;
        fast = YES;
        topWinSize = top_win_height * (m_statusFixedFontPixelHeight+1) + 0; // was 3 in 1.3, was 6 in 1.2
        
        if (!frozeDisplay && (prevTopWinHeight - top_win_height > 1 || top_win_height - prevTopWinHeight > 1))
            [self setupFadeWithDuration: 0.08];
        
        [statusLine setFrame: CGRectMake(0.0f, 0.0f, viewFrame.size.width,  topWinSize)];
        
        iphone_top_win_height = top_win_height;
        [storyView setTopMargin: topWinSize+0];
        prevTopWinHeight = top_win_height;
        //NSLog(@"set topwinheight %d", top_win_height);
    }
    
    if (winSizeChanged) {
        winSizeChanged = NO;
        pthread_cond_signal(&winSizeChangedCond);
    }
    pthread_mutex_unlock(&winSizeMutex);
    
    pthread_mutex_lock(&outputMutex);
    if (finished)
        iphone_flush(NO);
    textLen = [inputBufferStr length];
    
    BOOL clearStory = ([inputBufferStr hasPrefix: @kClearEscCode]);
    BOOL setDefColors = ([inputBufferStr hasPrefix: @kSetDefColorsCode]);
    if (textLen > 0) {
        if (!clearStory && !setDefColors) {
#if UseRichTextView
            NSRange escCodeRange = [inputBufferStr rangeOfString: @kOutputEscCode];
            while (escCodeRange.length > 0) {
                if (escCodeRange.location > 0)
                    [storyView appendText: [inputBufferStr substringToIndex: escCodeRange.location]];
                NSString *subEscCode = [inputBufferStr substringFromIndex: escCodeRange.location+1];
                if ([subEscCode hasPrefix: @kStyleEscCode]) {
                    RichTextStyle style = kFTNormal;
                    int fstyle = 0;
                    for (int i = 0; i < 2; ++i) {
                        char c = [inputBufferStr characterAtIndex: escCodeRange.location+i+2];
                        fstyle <<= 4;
                        if (c >= '0' && c <='9')
                            fstyle |= (c - '0');
                        else if (c >='a')
                            fstyle |= (c - 'a'+10);
                        else
                            fstyle |= c - 'A'+10;
                    }
                    style |= fstyle;
                    if (fstyle & kFTReverse)
                        style |= ((fstyle & kFTFixedWidth) ? (kFTBold|kFTNoWrap) : 0);
                    [storyView setTextStyle: style];
                    [inputBufferStr setString: [inputBufferStr substringFromIndex: escCodeRange.location+4]];
                } else if ([subEscCode hasPrefix: @ kArbColorEscCode]) {
                    NSString *colorStr = [inputBufferStr substringWithRange: NSMakeRange(escCodeRange.location+2,7)];
                    unsigned int intRGB;
                    float floatRGB[4] = { 0.0f, 0.0f, 0.0f, 1.0f };
                    UIColor *color = nil;
                    int skip = escCodeRange.location+2;
                    NSScanner *scanner = [NSScanner scannerWithString: colorStr];
                    BOOL isBGColor = ([colorStr characterAtIndex:0] == 'b');
                    [scanner setScanLocation: 1];
                    if ([scanner scanHexInt: &intRGB]) {
                        floatRGB[0] = (float)((intRGB & 0xff0000) >> 16) / 255.0f;
                        floatRGB[1] = (float)((intRGB & 0xff00) >> 8) / 255.0f;
                        floatRGB[2] = (float)((intRGB & 0xff)) / 255.0f;
                        color = [UIColor colorWithRed: floatRGB[0] green:floatRGB[1] blue:floatRGB[2] alpha:1.0];
                        int colIndex = [storyView getOrAllocColorIndex: color];
                        if (isBGColor)
                            [storyView setBgColorIndex: colIndex];
                        else {
                            [storyView setTextColorIndex: colIndex];
                            [m_inputLine setTextColor: color];
                        }
                        skip += [scanner scanLocation];
                    }
                    [inputBufferStr setString: [inputBufferStr substringFromIndex: skip]];
                    
                } else if ([subEscCode hasPrefix: @kZColorEscCode])  {
                    int col[2];
                    for (int i=0; i < 2; ++i) {
                        char c = [inputBufferStr characterAtIndex: escCodeRange.location+i+2];
                        col[i] = 0;
                        if (c >= '0' && c <='9')
                            col[i] = c - '0';
                        else if (c >='a')
                            col[i] = c - 'a'+10;
                        else
                            col[i] = c - 'A'+10;
                        if (i==0) {
                            [storyView setTextColorIndex: col[i]];
                            [statusLine setTextColorIndex: col[i]];
                            if (col[i]<=1)
                                [m_inputLine setTextColor: m_defaultFGColor];
                        } else {
                            [storyView setBgColorIndex: col[i]];
                            [statusLine setBgColorIndex: col[i]];
                        }
                    }
                    [inputBufferStr setString: [inputBufferStr substringFromIndex: escCodeRange.location+4]];
                } else if ([subEscCode hasPrefix: @ kImageEscCode])  {
                    NSString *imageNumStr = [inputBufferStr substringWithRange: NSMakeRange(escCodeRange.location+2,3)];
                    int imageNum = atoi([imageNumStr UTF8String]);
                    int imageAlign = [inputBufferStr characterAtIndex: escCodeRange.location+5] - '0';
                    int rtImageAlign = kFTImage;
                    switch (imageAlign) {
                        case imagealign_InlineCenter:
                            rtImageAlign |= kFTCentered;
                            break;
                        case imagealign_InlineDown:
                            rtImageAlign |= kFTRightJust;
                            break;
                        case imagealign_InlineUp:
                            break;
                        case imagealign_MarginRight:
                            rtImageAlign |= kFTRightJust;
                            // fall thru
                        case imagealign_MarginLeft:
                            rtImageAlign |= kFTInMargin;
                            break;
                        default:
                            break;
                    }
                    [storyView appendImage: imageNum withAlignment: rtImageAlign];
                    [inputBufferStr setString: [inputBufferStr substringFromIndex: escCodeRange.location+6]];

                } else if ([subEscCode hasPrefix: @ kHyperlinkEscCode]) {
                    int val = 0;
                    for (int i=0; i < 8; ++i) {
                        char c = [inputBufferStr characterAtIndex: escCodeRange.location+i+2];
                        if (c >= '0' && c <='9')
                            val = val*16 + (c - '0');
                        else if (c >='a')
                            val = val*16 + (c - 'a'+10);
                        else
                            val = val*16 + (c - 'A'+10);
                    }
                    [storyView setHyperlinkIndex: val];
                    [inputBufferStr setString: [inputBufferStr substringFromIndex: escCodeRange.location+10]];
                }
                escCodeRange = [inputBufferStr rangeOfString: @kOutputEscCode];
            }
#endif
            int iBufLen = [inputBufferStr length];
            if (iBufLen < 256)
                [storyView appendText: inputBufferStr];
            else {
                NSRange nlr = [inputBufferStr rangeOfString: @"\n"];
                NSString *substr = inputBufferStr;
                while (nlr.length > 0) {
                    [storyView appendText: [substr substringToIndex:nlr.location+1]];
                    substr = [substr substringFromIndex: nlr.location+1];
                    nlr = [substr rangeOfString: @"\n"];
                }
                if ([substr length] > 0)
                    [storyView appendText: substr];
            }
            [inputBufferStr setString: @""];
        } else {
            [inputBufferStr setString: [inputBufferStr substringFromIndex: 1]];
        }	
        continuousPrintCount++;
    } else
        continuousPrintCount = 0;
    
    if (statusLen > 0 || clearStory || setDefColors) {
        if (statusLen == 1 && [inputStatusStr isEqualToString: @kClearEscCode] || clearStory || setDefColors) {
            int color, j;
            if (gStoryInterp == kZStory) {
                [storyView setFreezeDisplay: YES];
                [statusLine setFreezeDisplay: YES];
                
                UIColor *uicol[2] = { nil, nil };
                for (j=0; j < 2; ++j) {
                    if (j==0)
                        color = (currColor & 0xF);
                    else
                        color = currColor >> 4;
                    if (j==0 && (!color || color == h_default_background))
                        uicol[j] = m_defaultBGColor;
                    else if (j==1 && (!color || color == h_default_foreground)) {
                        if ((currColor & 0xF) == h_default_foreground) { // if fg same color as bg because of defaults, cheat
                            if (color == BLACK_COLOUR)
                                uicol[j] = [UIColor whiteColor];
                            else
                                uicol[j] = [UIColor blackColor];
                        }
                        else
                            uicol[j] = m_defaultFGColor;
                    }
                    else
                        switch (color) {
                            case 0:
                                //uicol[j] = [m_background backgroundColor];
                                break;
                            case BLACK_COLOUR:
                                uicol[j] = [UIColor blackColor];
                                break;
                            case RED_COLOUR:
                                uicol[j] = [UIColor redColor];
                                break;
                            case GREEN_COLOUR:
                                uicol[j] = [UIColor greenColor];
                                break;
                            case YELLOW_COLOUR:
                                uicol[j] = [UIColor yellowColor];
                                break;
                            case BLUE_COLOUR:
                                uicol[j] = [UIColor blueColor];
                                break;
                            case MAGENTA_COLOUR:
                                uicol[j] = [UIColor magentaColor];
                                break;
                            case CYAN_COLOUR:
                                uicol[j] = [UIColor cyanColor];
                                break;
                            case WHITE_COLOUR:
                                uicol[j] = [UIColor whiteColor];
                                break;
                            case LIGHTGREY_COLOUR:
                                uicol[j] = [UIColor lightGrayColor];
                                break;
                            case MEDIUMGREY_COLOUR:
                                uicol[j] = [UIColor grayColor];
                                break;
                            case DARKGREY_COLOUR:
                                uicol[j] = [UIColor darkGrayColor];
                                break;
                            default:
                                break;
                        }
                    if (j) {
                        if (uicol[j]) {
                            if (color && color != DEFAULT_COLOUR)
                                [m_inputLine setTextColor: uicol[j]];
                            //[self setTextColor: uicol[j] makeDefault:NO];
                        }
                        if (clearStory || gStoryInterp==kZStory)
                            [storyView setTextColorIndex: color];
                        else if (statusLen==1) // kGlxStory
                            [statusLine setTextColorIndex: color];
                    }
                    else {
                        if (uicol[j])
                            [self setBackgroundColor: uicol[j] makeDefault:NO];
                        if (clearStory || gStoryInterp==kZStory)
                            [storyView setBgColorIndex: color];
                        else if (statusLen==1) // kGlxStory
                            [statusLine setBgColorIndex: color];
                    }
                }
            }
            if (statusLen == 1) {
                [statusLine setContentOffset: CGPointMake(0,0) animated: NO];
                [statusLine setText: @""];
                [inputStatusStr setString: @""];
            }
            [storyView setContentOffset: CGPointMake(0,0) animated: NO];
            if (gStoryInterp == kGlxStory) {
                if (viewNum >= 0 && viewNum < [m_glkViews count] ) {
                    glui32 bgColor = gli_stylehint_get(glkGridArray[viewNum].win, style_Normal, stylehint_BackColor);
                    glui32 textColor = gli_stylehint_get(glkGridArray[viewNum].win, style_Normal, stylehint_TextColor);

                    if (bgColor != BAD_STYLE) {
                        UIColor *bcolor = UIColorFromInt(bgColor);
                        if (viewNum == 0)
                            [self setBackgroundColor: bcolor makeDefault:NO];
                        if (glkViewIsGrid)
                            [statusLine setBackgroundColor: bcolor];
                        else
                            [storyView setBackgroundColor: bcolor];
                    }
                    if (textColor != BAD_STYLE) {
                        UIColor *tcolor = UIColorFromInt(textColor);
                        if (glkViewIsGrid)
                            [statusLine setTextColor: tcolor];
                        else {
                            [storyView setTextColor: tcolor];
                            [m_inputLine setTextColor: tcolor];
                        }
                    }
                }
            }
            if (clearStory || gStoryInterp != kGlxStory && !setDefColors) {
                [storyView clear];
                lastVisibleYPos[viewNum] = 0;
            }
        } else {
            [statusLine setContentOffset: CGPointMake(0, 0) animated: NO];
            [self updateStatusLine: statusLine];
            [inputStatusStr setString: @""];
        }
    } 
    if (ipzAllowInput & kIPZRequestInput) {
            grewStatus = 0;
        CGSize sz = [storyView contentSize];
        float viewWidth = viewFrame.size.width;
        if (!(ipzAllowInput & kIPZNoEcho) && sz.width != viewWidth) { // && prevTopWinHeight == top_win_height) {
            sz.width = viewWidth;
            [storyView setContentSize: sz];
        }
        
        if (textLen > 0 || !(ipzAllowInput & kIPZAllowInput) && recentScrollToVisYPos[cwin]!=lastVisibleYPos[cwin]) {
            CGSize contentSz = [storyView contentSize];
            CGSize viewSz = [storyView frame].size;
            if (contentSz.height > viewSz.height) {
                float visHeight = contentSz.height - lastVisibleYPos[cwin];
                if (visHeight > viewSz.height - topWinSize - m_fontSize)
                    visHeight = viewSz.height - topWinSize - m_fontSize;
                CGRect visrect = CGRectMake(0, lastVisibleYPos[cwin], viewSz.width, visHeight);
                if ([storyView contentOffset].y < lastVisibleYPos[cwin]) {
                    //NSLog(@"scrrecttovis cwin=%d y=%d h=%f", cwin, lastVisibleYPos[cwin], visHeight);
                    [storyView scrollRectToVisible:visrect  animated:YES];
                }
                recentScrollToVisYPos[cwin] = lastVisibleYPos[cwin];
            }
        }
        if ([storyView displayFrozen]) {
            [storyView setFreezeDisplay: NO];
            [statusLine setFreezeDisplay: NO];
        }
        if (!(ipzAllowInput & kIPZAllowInput)) {
            if (gStoryInterp == kGlxStory)
                [m_inputLine setFont: ([storyView textStyle] & kFTFixedWidth) ? [storyView fixedFont] : [storyView font]];
            else if (cwin != lastInputWindow || (ipzAllowInput & kIPZNoEcho)) {
                [m_inputLine setFont: (top_win_height > 0 && cursor_row <= top_win_height) ? [statusLine fixedFont] :
                     ([storyView textStyle] & kFTFixedWidth) ? [storyView fixedFont] : [storyView font]];
                NSString *t = m_inputLine.text; [m_inputLine setTextKeepCompletion: @" "]; [m_inputLine setTextKeepCompletion: t]; // *sigh* needed to force cursor to resize
                lastInputWindow = cwin;
            }
            [storyView markWaitForInput];
            [m_inputLine performSelector: @selector(updatePosition) withObject:nil afterDelay: 0.08];
            ipzAllowInput |= kIPZAllowInput;
        }
    }
    pthread_mutex_unlock(&outputMutex);
    
    if (finished && finished != 1) {
        if ([m_currentStory length] > 0) {
            if (finished == 2) {
                finished = -1;
                UIAlertView *dialog = [[UIAlertView alloc] initWithTitle:@"Unreadable story file" message: @"Frotz doesn't understand the format of this file" delegate:self cancelButtonTitle:@"Drat" otherButtonTitles:nil];
                [dialog show];
                [dialog release];
            }
            [storyView setFreezeDisplay:NO];
            [storyView setTextStyle: kFTBold];
            if (viewFrame.size.height < statusLine.frame.size.height) {
                viewFrame.size.height = statusLine.frame.size.height + 24;
                [storyView setFrame: viewFrame];
                [storyView appendText: @"\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n"];
            }
            [storyView appendText: @"\n\n[End of story. Tap 'Story List' to exit.]\n\n"];
            [storyView scrollRectToVisible:CGRectMake(0, lastVisibleYPos[0]+50, viewFrame.size.width, 24) animated:YES];
            [self abandonStory: YES];
        }
    } else {
        [self performSelector:@selector(printText:) withObject:nil afterDelay:clearStory||fast ? 0.0 : 0.03];
    }
    if (refresh_savedir) {
        refresh_savedir = 0;
        if ([[DBSession sharedSession] isLinked])
            [self.restClient loadMetadata: [[self dbSavePath] stringByAppendingPathComponent: [self saveSubFolderForStory: m_currentStory]]];	
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {               // any offset changes
    [m_inputLine updatePosition];
}

-(void) savePrefs {
    if (gUseSplitVC)
        [[m_storyBrowser detailsController] refresh];
    
    NSUserDefaults *dict = [NSUserDefaults standardUserDefaults];
    
    if (m_fontname) {
        [dict setObject: m_fontname forKey: @"font"];
        if (m_fontSize)
            [dict setObject: [NSNumber numberWithInt: m_fontSize] forKey: @"fontSize"];
    }
    CGColorRef textColor = [[self textColor] CGColor];
    CGColorRef bgColor = [[self backgroundColor] CGColor];
    const CGFloat *textColorRGB = CGColorGetComponents(textColor);
    const CGFloat *bgColorRGB = CGColorGetComponents(bgColor);
    size_t tnc = CGColorGetNumberOfComponents(textColor), bnc = CGColorGetNumberOfComponents(bgColor);
    NSString *textColorStr = [NSString stringWithFormat:  @"#%02X%02X%02X",
                              (int)(textColorRGB[0]*255),
                              (int)(textColorRGB[tnc >=3 ? 1 : 0]*255),
                              (int)(textColorRGB[tnc >=3 ? 2 : 0]*255)];
    NSString *bgColorStr = [NSString stringWithFormat: @"#%02X%02X%02X",
                            (int)(bgColorRGB[0]*255),
                            (int)(bgColorRGB[bnc >=3 ? 1 : 0]*255),
                            (int)(bgColorRGB[bnc >=3 ? 2 : 0]*255)];
    [dict setObject: textColorStr forKey: @"textColor"];
    [dict setObject: bgColorStr forKey: @"backgroundColor"];
    [dict setObject: [NSNumber numberWithBool: !m_completionEnabled] forKey: @"completionDisabled"];
    [dict setObject: [NSNumber numberWithBool: m_canEditStoryInfo] forKey: @"canEditStoryInfo"];
    [dict setObject: [NSNumber numberWithInt: iphone_ifrotz_verbose_debug] forKey: @"debug_flags_" IPHONE_FROTZ_VERS];
    [dict setObject: [NSNumber numberWithBool: m_autoRestoreEnabled] forKey:@"autorestore_preference"];
    
    [dict synchronize];    
}

static UIColor *scanColor(NSString *colorStr) {
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
    }
    return color;
}

-(void) loadPrefs {
    NSUserDefaults *dict = [NSUserDefaults standardUserDefaults];
    
    if (dict) {
        NSString *fontname =  [dict objectForKey: @"font"];
        int fontSize= [[dict objectForKey: @"fontSize"] longValue];
        if (!fontSize)
            fontSize = m_fontSize;
        iphone_ifrotz_verbose_debug = [[dict objectForKey: @"debug_flags_" IPHONE_FROTZ_VERS ] longValue];
        if (fontname)
            [self setFont: fontname withSize: fontSize];
        else
            [self setFont: kVariableWidthFontName withSize: fontSize];

        NSString *textColorStr = [dict objectForKey: @"textColor"];
        NSString *bgColorStr = [dict objectForKey: @"backgroundColor"];
        UIColor *textColor = scanColor(textColorStr);
        if (textColor) {
            [self setTextColor: textColor makeDefault:YES];
        }
        if (![textColorStr isEqualToString: bgColorStr]) {
            UIColor *bgColor = scanColor(bgColorStr);
            if (bgColor) {
                [self setBackgroundColor: bgColor makeDefault:YES];
            }
        }
        m_completionEnabled = ![[dict objectForKey: @"completionDisabled"] boolValue];
        m_canEditStoryInfo = [[dict objectForKey: @"canEditStoryInfo"] boolValue];
        id arp = [dict objectForKey: @"autorestore_preference"];
        if (arp)
            m_autoRestoreEnabled = [arp boolValue];
        else
            m_autoRestoreEnabled = YES;
    }
}

-(void)rememberActiveStory {
    if (m_currentStory && [m_currentStory length] > 0) {
        NSDictionary *storyLocDict  = [[NSDictionary alloc] initWithObjectsAndKeys:
                                       [self pathToAppRelativePath: m_currentStory], @"storyPath", nil];
        if (storyLocDict) {
            NSString *errString = nil;
            NSData *slData = [NSPropertyListSerialization dataFromPropertyList:storyLocDict format:NSPropertyListBinaryFormat_v1_0
                                                              errorDescription:&errString];
            [slData writeToFile:activeStoryPath atomically:NO];
            [storyLocDict release];
        }
    }
}

-(BOOL) willAutoRestoreSession:(BOOL)isFirstLaunch {
    NSFileManager *fileMgr = [NSFileManager defaultManager];
    NSString *storyPath = nil;
    if ((!m_currentStory || [m_currentStory length]==0) && [fileMgr fileExistsAtPath: activeStoryPath]) {
        NSDictionary *storyLocDict  = [NSDictionary dictionaryWithContentsOfFile: activeStoryPath];
        if (storyLocDict) {
            storyPath = [storyLocDict objectForKey: @"storyPath"];
            storyPath = [self relativePathToAppAbsolutePath: storyPath];
            [self setCurrentStory: storyPath];
            if (gUseSplitVC) {
                StoryInfo *si = [[StoryInfo alloc] initWithPath: storyPath browser:m_storyBrowser];
                [m_storyBrowser setStoryDetails: si];	
                [si release];
            }
        }
    }
    if (isFirstLaunch) {
        if (!m_autoRestoreEnabled && ![m_storyBrowser launchPath]) {
            [self setCurrentStory: nil];
            return NO;
        }
    }
    
    if ([fileMgr fileExistsAtPath: storySIPPath] && [fileMgr fileExistsAtPath: storySIPSavePath]) {
    	NSDictionary *dict = [[NSDictionary dictionaryWithContentsOfFile: storySIPPath] retain];
        if (dict) {
            storyPath = [dict objectForKey: @"storyPath"];
            storyPath = [self relativePathToAppAbsolutePath: storyPath];
            [self setCurrentStory: storyPath];
            if (m_currentStory && [fileMgr fileExistsAtPath: m_currentStory]) {
                m_autoRestoreDict = dict;
                return YES;
            }
            [dict release];
        }
    }
    if (storyPath) { //  save file not found
        NSError *error = nil;
        [fileMgr removeItemAtPath: activeStoryPath error:&error];
        [self setCurrentStory: nil];
    }
    return NO;
}

static void setScreenDims(char *storyNameBuf) {
    iphone_textview_width = kDefaultTextViewWidth;
    iphone_textview_height = kDefaultTextViewHeight;
    
    if (gStoryInterp == kZStory) {
        char *s = strrchr(storyNameBuf, '/');
        if (s)
            s++;
        else
            s = storyNameBuf;
        // Hack alert - pretend to be 80 cols for these games because they fail or display poorly with fewer.
        // Should detect this in a cleaner way (at least)
        if (iphone_textview_width < 80 && (strncasecmp(s, "trinity", 7) == 0 || strncasecmp(s, "amfv", 4) == 0
                                           || strncasecmp(s, "vgame", 5) == 0))
            iphone_textview_width = 80;
    } else 
        iphone_recompute_screensize();
}

-(void)setLaunchMessage:(NSString*)msg clear:(BOOL)clear {
    if (clear) {
        [m_storyView clear];
        [m_statusLine clear];
    }
    m_launchMessage = [msg retain];
}

-(void)launchMessageAnimDidFinish:(NSString *)animationID finished:(NSNumber *)finished context:(void *)context {
    [UIView setAnimationDelegate: nil];
    UIView *msgView = [m_storyView.superview viewWithTag: kLaunchMsgViewTag];
    if (msgView)
        [msgView removeFromSuperview];
}

-(void)displayLaunchMessageWithDelay: (CGFloat)delay duration:(CGFloat)duration alpha:(CGFloat)alpha {
    if (m_launchMessage) {
        CGRect frame = [[[m_storyView superview] superview] frame];
#ifdef NSFoundationVersionNumber_iOS_6_1
        if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1) {
            frame.size.height -= 64;
        }
#endif
        UILabel *msgView = [[UILabel alloc] initWithFrame: CGRectMake(0, 0, frame.size.width, 60)];
        [msgView setText: m_launchMessage];
        [msgView setTextAlignment: UITextAlignmentCenter];
        [msgView setLineBreakMode: UILineBreakModeTailTruncation];
        [msgView setNumberOfLines: 0];
        [msgView setAutoresizingMask: UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleRightMargin];
        [msgView sizeToFit];
        CGRect msgFrame = [msgView frame];
        msgFrame.size.height += 20;
        msgFrame.origin.y = frame.size.height - msgFrame.size.height + 2;
        msgFrame.size.width = frame.size.width;
        [msgView setFrame: msgFrame];
        [msgView setBackgroundColor: [UIColor blackColor]];
        [msgView setTextColor: [UIColor whiteColor]];
        [msgView setAlpha: alpha];
        [msgView setAutoresizingMask: UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleRightMargin];
        [m_background addSubview: msgView];
        [msgView setTag: kLaunchMsgViewTag];
        [UIView beginAnimations: @"asmsg" context:0];
        [UIView setAnimationDelay: delay];
        [UIView setAnimationDuration: duration];
        [msgView setAlpha: 0.0];
        [msgView release];
        [UIView setAnimationDelegate: self];
        [UIView setAnimationDidStopSelector: @selector(launchMessageAnimDidFinish:finished:context:)];
        [UIView commitAnimations];
        [m_launchMessage release];
        m_launchMessage = nil;
    }
}

// Mutate old HTML buffer from UITextView-based save game to plain text
-(NSMutableString*)convertHTML:(NSString*)htmlString {
#define hgetchar() ((i < len) ? ([htmlString characterAtIndex: i++]) : 0)
    
    NSMutableString *text = [[NSMutableString alloc] initWithCapacity: 10240];
    NSString *tag = nil;
    int len = [htmlString length], i = 0, j, k;
    unichar c;
    NSRange r = [htmlString rangeOfString: @"</style>"];
    if (r.length)
        i = r.location + r.length;
    while ((c = hgetchar()) != 0) {
        switch (c) {
            case '&':
                j = i;
                while ((c = hgetchar()) != ';')
                    ;
                if (i > j) {
                    tag = [htmlString substringWithRange: NSMakeRange(j, i-1-j)];
                    if ([tag isEqualToString: @"nbsp"])
                        [text appendString: @" "];
                    else if ([tag isEqualToString: @"gt"])
                        [text appendString: @">"];
                    else if ([tag isEqualToString: @"lt"])
                        [text appendString: @"<"];
                    else if ([tag isEqualToString: @"amp"])
                        [text appendString: @"&"];
                    else
                        [text appendFormat: @"&%@;", tag];
                }
                break;
            case '<':
                j = i;
                BOOL openTag = ((c = hgetchar()) != '/');
                if (!openTag)
                    ++j;
                k = j;
                unichar prevc = 0;
                while ((c = hgetchar()) != '>') {
                    prevc = c;
                    if (c == ' ' && j==k)
                        k = i;
                }
                if (j==k)
                    k = i;
                if (prevc == '/')
                    openTag = NO;
                if (j < k) {
                    tag = [htmlString substringWithRange: NSMakeRange(j, k-1-j)];
                    if ([tag isEqualToString: @"br"])
                        [text appendString: @"\n"];
                }
            case '\n':
            case '\r':
                break;
            case 0x2013:
                [text appendString: @"-"];
                break;
            default:
                [text appendFormat: @"%c", c];
                break;
        }
        
    }
    
    return text;
#undef hgetchar
}

-(void) resizeStatusWindow {
    if (gStoryInterp == kZStory) {
        iphone_top_win_height = -2;
        iphone_win_puts(1, "\n\n");
    } else if (gStoryInterp == kGlxStory) {
        iphone_recompute_screensize();
        screen_size_changed = 1;
    }
    [m_inputLine updatePosition];
}

-(BOOL) autoRestoreSession {
    static char storyNameBuf[MAX_FILE_NAME];
    
    id fileMgr = [NSFileManager defaultManager];
    NSError *error = nil;
    [self displayLaunchMessageWithDelay: 3.0 duration:1.0 alpha:0.85];
    if (m_splashImageView) { // stale
        [m_splashImageView removeFromSuperview];
        [m_splashImageView release];
        m_splashImageView = nil;
    }
    if ([fileMgr fileExistsAtPath: storySIPPath] && [fileMgr fileExistsAtPath: storySIPSavePath]) {
    	NSDictionary *dict = m_autoRestoreDict;
        NSData *statusScreenData = NULL, *statusScreenColors = NULL;
        if (dict) {
            (void)[self view];  // ensure storyView is loaded so we can restore its text contents
            
            NSString *storyPath = m_currentStory;
            if (!storyPath) {
                storyPath = [dict objectForKey: @"storyPath"];
                storyPath = [self relativePathToAppAbsolutePath: storyPath];
                [self setCurrentStory: storyPath];
            }
            if (m_currentStory) {
                NSString *story = [m_currentStory storyKey];
                if (m_notesController) {
                    NSString *notesText = [m_storyBrowser getNotesForStory:story];
                    [m_notesController setTitle: [m_storyBrowser fullTitleForStory: story]];
                    [m_notesController setText: notesText];
                }
                
                if ([[m_currentStory pathExtension] isEqualToString: @"blb"]
                    || [[m_currentStory pathExtension] isEqualToString: @"gblorb"]
                    || [[m_currentStory pathExtension] isEqualToString: @"ulx"])
                    gStoryInterp = kGlxStory;
                else
                    gStoryInterp = kZStory;
                
                inputsSinceSaveRestore = 1;
                int hvers = 0;
                strcpy(storyNameBuf, [m_currentStory UTF8String]);
                FILE *sf = fopen(storyNameBuf, "r");
                if (sf) hvers = fgetc(sf);
                fclose(sf);
                if ((hvers < 2 || hvers > 8) && hvers != 'F' && hvers != 'G') { // F for zblorb, G for glulx
                    NSLog(@"autoRestoreFailed");
                    [fileMgr removeItemAtPath: storySIPPath error:&error];
                    return NO;
                }
                
                h_version = hvers;
                iphone_top_win_height = -1;
                top_win_height = [[dict objectForKey: @"statusWinHeight"] longValue];
                cwin = [[dict objectForKey: @"currentWindow"] longValue];
                cursor_row = [[dict objectForKey: @"cursorRow"] longValue];
                cursor_col = [[dict objectForKey: @"cursorCol"] longValue];
                restore_frame_count = [[dict objectForKey: @"frameCount"] longValue];
                
                NSString *savedScriptname = [dict objectForKey: @"scriptname"];
                if (savedScriptname) {
                    savedScriptname = [self relativePathToAppAbsolutePath: savedScriptname];
                    iphone_start_script((char*)[savedScriptname UTF8String]);
                } else
                    iphone_stop_script();
                
                int color = [[dict objectForKey: @"textColors"] longValue] & 0xff;
                if (color == 0x21)
                    color = 0x11; // fix corrupt autosave
                if (color && color != 0x11 && (color & 0xf) == (color >> 4)) { // don't allow fg same as bg
                    if ((color & 0xf) == BLACK_COLOUR)
                        color = BLACK_COLOUR | (WHITE_COLOUR<<4);
                    else
                        color = (color & 0xf) | (BLACK_COLOUR<<4);
                    currColor = u_setup.current_color = color;
                } else 	if (color > 0x11) //  && (color != 0x29)
                    currColor = u_setup.current_color = color;
                NSNumber *currStyle = [dict objectForKey: @"currTextStyle"];
                if (currStyle)
                    currTextStyle = u_setup.current_text_style = [currStyle integerValue];

                statusScreenData = [dict objectForKey: @"statusWinData"];
                statusScreenColors = [dict objectForKey: @"statusWinColors"];
                setScreenDims(storyNameBuf);
                h_screen_rows = kDefaultTextViewHeight; // iphone_textview_height;
                h_screen_cols = iphone_textview_width;
                h_screen_width = h_screen_cols;
                h_screen_height = h_screen_rows;
                
                do_autosave = 0;
                iphone_init_screen();
                do_autosave = 1;
                resize_screen();
                iphone_ioinit();
                [m_statusLine reset];
                [m_storyView reset];
                [m_storyView resetMargins];
                [self clearGlkViews];
                
                iphone_flush(NO);
                if (!statusScreenData) {
                    [fileMgr removeItemAtPath: storySIPPath error:&error];
                    [dict release];
                    m_autoRestoreDict = nil;
                    return NO;
                }
                [ipzStatusStr setString: @kClearEscCode];
                [ipzBufferStr setString: @""];
                iphone_clear_input(NULL);
                [self printText: nil];
                int len = [statusScreenData length], maxLen = h_screen_rows * MAX_COLS * sizeof(*screen_data);
                if (len > h_screen_rows * MAX_COLS * sizeof(*screen_data))
                    len = maxLen;
                memcpy(screen_data, (char*)[statusScreenData bytes], len);
                if (statusScreenColors) {
                    len = [statusScreenColors length];
                    if (len > maxLen)
                        len = maxLen;
                    memcpy(screen_colors, (char*)[statusScreenColors bytes], len);
                }
                [m_statusLine setBgColorIndex: currColor & 0xf];
                [m_statusLine setTextColorIndex: currColor >> 4];
                [ipzStatusStr setString: @"i\n"];
                
#if UseRichTextView
                NSDictionary *storyTextSaveDict = [dict objectForKey: @"storyRichWinContents"];
                if (storyTextSaveDict) {
                    [m_storyView restoreFromSaveDataDict: storyTextSaveDict];
                    [self scrollStoryViewToEnd: NO];
                } else {
                    NSMutableString *newText = nil;
                    NSString *storyText = [dict objectForKey: @"storyWinContents"];
                    if (storyText) {
                        NSRange r = [storyText rangeOfString: @"<style type="];
                        if (r.length == 0)
                            r = [storyText rangeOfString: @"<br"];
                        if (r.length > 0 && r.length < 1024) {
                            newText = [self convertHTML: storyText];
                            storyText = newText;
                        }
                    } else
                        storyText = @"";
                    [m_storyView setText: storyText];
                    if (newText)
                        [newText release];
                }
#else
                [m_storyView setText: [dict objectForKey: @"storyWinContents"]];
#endif
                NSNumber *hFlagsNum = [dict objectForKey: @"hflags"];
                if (hFlagsNum) {
                    hflagsRestore =  [hFlagsNum integerValue] & FIXED_FONT_FLAG;
                } else
                    hflagsRestore = 0;
                
                [dict release];
                m_autoRestoreDict = nil;
                
                if ([storySIPPath isEqualToString: storySIPPathOld]) {
                    [fileMgr removeItemAtPath: storySIPPath error:&error];
                    if (color == 0x29)
                        color = 0;
                }
                [m_inputLine setTextColor: [m_storyView getCurrentTextColor]];
                if (color)
                    currColor = u_setup.current_color = color;
                
                [self rememberActiveStory];

                screen_size_changed = 1;
                
                m_storyTID = 0;
                pthread_create(&m_storyTID, NULL, interp_cover_autorestore, (void*)storyNameBuf);
                CGSize sz = [m_storyView contentSize];
                CGRect rect = CGRectMake(0, sz.height, 1, 1);
                lastVisibleYPos[cwin] = sz.height-1;
                [m_storyView scrollRectToVisible: rect animated:YES];
                [self performSelector:@selector(printText:) withObject:nil afterDelay:0.1];
                return YES;
            }
            [dict release];
            m_autoRestoreDict = nil;
        }
        NSLog(@"autoRestoreFailed");
    }
    return NO;
}

- (void)transitionViewDidFinish:(TransitionView *)transitionView {
    if (m_splashImageView) {
        [m_splashImageView removeFromSuperview];
        [m_splashImageView release];
        m_splashImageView = nil;
    }
    [transitionView removeFromSuperview];
}

- (void)transitionViewDidCancel:(TransitionView *)transitionView {
    if ([[transitionView subviews] count] > 0)
        [transitionView replaceSubview: m_splashImageView withSubview:nil transition:kCATransitionFade  direction:kCATransitionFromTop duration:0.4];
    else
        [self transitionViewDidFinish: transitionView];
    [m_storyView skipNextTap];
}

-(BOOL) splashVisible {
    return m_splashImageView != nil;
}

-(void)fadeSplashScreen:(TransitionView*)transitionView  {
    if ([transitionView superview])
        [transitionView replaceSubview: m_splashImageView withSubview:nil transition:kCATransitionFade  direction:kCATransitionFromTop duration:2.0];
}

-(void) launchStory {
    static char storyNameBuf[MAX_FILE_NAME];
    iphone_top_win_height = -1;
    
    strcpy(storyNameBuf, [m_currentStory UTF8String]);
    if (strlen(storyNameBuf) == 0)
        return;
    
    iphone_stop_script();

    // Make sure pending performSelector calls are cancelled
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(printText:) object:nil];
    
    NSString *story = [[self currentStory] storyKey];
    StoryBrowser *storyBrowser = [self storyBrowser];
    
    if (m_notesController) {
        NSString *notesText = [storyBrowser getNotesForStory:story];
        [m_notesController setTitle: [storyBrowser fullTitleForStory: story]];
        [m_notesController setText: notesText];
    }
    
    [self displayLaunchMessageWithDelay: 2.5 duration:1.0  alpha:0.85];
    
    [self rememberActiveStory];
    
    if (m_splashImageView) { // stale
        [m_splashImageView removeFromSuperview];
        [m_splashImageView release];
        m_splashImageView = nil;
    }
    
    if (1 || ![storyBrowser lowMemory]) {
        NSString *pathExt = [[self currentStory] pathExtension];
        BOOL isZblorb = ([pathExt isEqualToString:@"zblorb"] || [pathExt isEqualToString:@"gblorb"]);
        NSData *data = nil;
        if (!isZblorb || !gLargeScreenDevice)
            data = [storyBrowser splashDataForStory: story];
        if (!data && isZblorb)
            data = [imageDataFromBlorb([self currentStory]) autorelease];
        
        if (data) {
            UIImage *timg = [[UIImage alloc] initWithData: data];
            UIImage *splashImage = scaledUIImage(timg, 0, 0);
            m_splashImageView = [[UIImageView alloc] initWithImage: splashImage];
            [timg release];

            UIImage *thumb = scaledUIImage(splashImage, 40, 32);
            if (thumb) {
                [storyBrowser addThumbData: UIImagePNGRepresentation(thumb) forStory:story];
                [storyBrowser saveMetaData];
            }

            CGRect rect = [m_splashImageView bounds];
            
            CGSize mySize = [self view].frame.size;	    
            if (gLargeScreenDevice || rect.size.width > 320 || rect.size.height > 320) {
                float scale = 1.0f;
                if (gLargeScreenDevice && rect.size.height <= 512 && rect.size.width <= 512) {
                    scale = (rect.size.height <= 320 && rect.size.width <= 320) ? 2.0f : 1.5f;
                } else if (rect.size.height > mySize.height-40 || rect.size.width > mySize.width) {
                    scale = mySize.height / rect.size.height;
                    CGFloat scale2 = mySize.width / rect.size.width;
                    if (scale2 < scale)
                        scale = scale2;
                    scale *= 0.9;
                }
                rect.size.height *= scale;
                rect.size.width *= scale;
            }
            rect.origin.x += mySize.width/2 - rect.size.width/2.0;
            rect.origin.y += mySize.height/2 - rect.size.height/2.0 - 20;
            [m_splashImageView setFrame: rect];
            
            TransitionView *transitionView = [[TransitionView alloc] initWithFrame: [[self view] bounds]];
            [transitionView setAutoresizingMask: UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth];
            [m_splashImageView setAutoresizingMask: UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleLeftMargin|
             UIViewAutoresizingFlexibleBottomMargin|UIViewAutoresizingFlexibleRightMargin];
            [transitionView setDelegate: self];
            [transitionView addSubview: m_splashImageView];
            [transitionView setContentMode:UIViewContentModeScaleAspectFit];
            [transitionView bringSubviewToFront: m_splashImageView];
            
            [[self view] addSubview: transitionView];
            [[self view] bringSubviewToFront: transitionView];
            [self performSelector: @selector(fadeSplashScreen:) withObject: transitionView afterDelay: 6.0];
        }
    }
    
    inputsSinceSaveRestore = 0;
    finished = 0;
    
    setScreenDims(storyNameBuf);
    [m_statusLine reset];
    [m_storyView reset];
    [m_storyView resetMargins];
    [self clearGlkViews];
    
    disable_complete = NO;
    
    iphone_textview_height = (int)([self storyViewFullFrame].size.height / [[m_storyView font] leading]);
    
    m_storyTID = 0;
    pthread_create(&m_storyTID, NULL, interp_cover_normal, (void*)storyNameBuf);
    //NSLog (@"launched tid %p\n", m_storyTID);
    [self performSelector:@selector(printText:) withObject:nil afterDelay:0.1];
    
}

-(void) forceAbandonStory {
    [self abandonStory: YES];
}

-(void) abandonStory:(BOOL)deleteAutoSave {
   // NSLog(@"abandon story %p %@\n", m_storyTID, m_currentStory);
    if ([m_currentStory length] > 0) {
        NSError *error = nil;
        iphone_stop_script();
        script_reset(NULL);
        NSFileManager *fileManager = [NSFileManager defaultManager];
        [fileManager removeItemAtPath: activeStoryPath error:&error];
        
        if (deleteAutoSave) {
            [fileManager removeItemAtPath: storySIPPath error:&error];
            int imgnum = 0;
            while ([fileManager removeItemAtPath: [storySavePath stringByAppendingPathComponent:
                                            [NSString stringWithFormat: @"%s-%d.png", kFrotzAutoSaveGlkImgPrefix, 0]] error: &error])
                ++imgnum;
        }
        [self savePrefs];
        [m_statusLine setBgColorIndex: 0];
        [m_statusLine setTextColorIndex: 0];
        [m_storyView setBgColorIndex: 0];
        [m_storyView setTextColorIndex: 0];
        [self setBackgroundColor: m_defaultBGColor makeDefault: NO];
        [self setTextColor: m_defaultFGColor makeDefault: NO];
        currColor = 0;
        os_set_colour (DEFAULT_COLOUR, DEFAULT_COLOUR);
        
        //NSLog(@"abandon story clr inp %p\n", m_storyTID);
        iphone_clear_input(@"\n\n");
        [m_currentStory setString: @""];
        [self clearGlkViews];
        do_autosave = 0;
        
        // if story thread is blocked waiting on window size change, wake it up
        pthread_mutex_lock(&winSizeMutex);
        if (finished == 0) // else interp already finished
            finished = 1;

        winSizeChanged = NO;
        pthread_cond_signal(&winSizeChangedCond);
        pthread_mutex_unlock(&winSizeMutex);
        for (int k = 0; k < 32; ++k)
            lastVisibleYPos[k] = 0;
        
        if (m_storyTID) {
            while (finished == 1) {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]]; 
            }
            //NSLog(@"joining thread %p", m_storyTID);
            pthread_join(m_storyTID, NULL);
        }
        m_storyTID = 0;
    }
    
    iphone_clear_input(NULL);
    [m_inputLine setText: @""];
    top_win_height = 0;
    [self dismissKeyboard];
    finished = 0;
}

-(NSString*)pathToAppRelativePath:(NSString*)path {
    NSString *rootPath = [[self rootPath] stringByDeletingLastPathComponent];
    if ([path hasPrefix: rootPath]) {
        NSUInteger len = [rootPath length]+1;
        path = [path substringWithRange: NSMakeRange(len, [path length]-len)];
    }
    return path;
}

-(NSString*)relativePathToAppAbsolutePath:(NSString*)path {
    if ([path isAbsolutePath]) {
        // mutate saved paths that should have been made relative when saved to relative paths
        NSRange r = [path rangeOfString: @"/Documents/"];
        if (r.length)
            path = [path substringFromIndex: r.location+1];
        else {
            r = [path rangeOfString: @"/Frotz.app/"];
            if (r.length)
                path = [path substringFromIndex: r.location+1];
        }
    }
    if (![path isAbsolutePath])
        path = [[[self rootPath] stringByDeletingLastPathComponent] stringByAppendingPathComponent: path];
    return path;
}

-(void) autoSaveStory {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(autoSaveCallback) object:nil];
    
    [self updateAutosavePaths];
    
    iphone_clear_input([NSString stringWithFormat:@"%c", ZC_AUTOSAVE]);
    
    if (m_currentStory && ([m_currentStory length] > 0)) {
        NSString *story = [m_currentStory storyKey];
        NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithCapacity:10];
        [dict setObject: [self pathToAppRelativePath: m_currentStory] forKey: @"storyPath"];
        [dict setObject: [NSNumber numberWithInt: iphone_top_win_height] forKey: @"statusWinHeight"];
        [dict setObject: [NSNumber numberWithInt: cwin] forKey: @"currentWindow"];
        [dict setObject: [NSNumber numberWithInt: cursor_row] forKey: @"cursorRow"];
        [dict setObject: [NSNumber numberWithInt: cursor_col] forKey: @"cursorCol"];
        [dict setObject: [NSNumber numberWithInt: frame_count] forKey: @"frameCount"];
        [dict setObject: [NSNumber numberWithInt: currColor] forKey: @"textColors"];
        [dict setObject: [NSNumber numberWithInt: currTextStyle] forKey: @"currTextStyle"];
        [dict setObject: [NSNumber numberWithInt: (h_flags & FIXED_FONT_FLAG)] forKey: @"hflags"];
        
        if (*iphone_scriptname) {
            NSString *scriptPath = [self pathToAppRelativePath: [NSString stringWithUTF8String: iphone_scriptname]];
            [dict setObject: scriptPath forKey: @"scriptname"];
        }
        
        NSData *statusData = [NSData dataWithBytes: screen_data length: h_screen_rows * MAX_COLS * sizeof(*screen_data)];
        NSData *statusColors = [NSData dataWithBytes: screen_colors length: h_screen_rows * MAX_COLS * sizeof(*screen_colors)];
        [dict setObject: statusData  forKey: @"statusWinData"];
        [dict setObject: statusColors forKey: @"statusWinColors"];
        
#if UseRichTextView
        NSDictionary *storyTextSaveDict = [m_storyView getSaveDataDict];
        [dict setObject: storyTextSaveDict forKey: @"storyRichWinContents"];
#else
        NSString *storyText;
        storyText = [m_storyView text];
        [dict setObject: storyText forKey: @"storyWinContents"];
#endif
        
        NSString *errString = nil;
        NSData *scData = [NSPropertyListSerialization dataFromPropertyList:dict format:NSPropertyListBinaryFormat_v1_0
                                                          errorDescription:&errString];
        [scData writeToFile:storySIPPath atomically:NO];
        
        [dict release];
        
        if (m_notesController) {
            NSString *notesText = [m_notesController text];
            if (notesText)
                [m_storyBrowser saveNotes:notesText forStory:story];
        }
        
        // !!! need a cond var to synchronize this less hackishly
        int count = 30;
        while (autosave_done == 0 && count >= 0) {
            usleep(100000);
            --count;
        }
        sync();
    }
    autosave_done = 0;
}

-(void) suspendStory {
    [self autoSaveStory];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(printText:) object:nil];
    //    [[NSRunLoop currentRunLoop] cancelPerformSelector:@selector(printText:) target:self argument:nil];
}

-(BOOL) possibleUnsavedProgress {
    if (m_notesController && [[m_notesController text] length] > 0)
        return YES;
    return inputsSinceSaveRestore != 0;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    
    //NSLog(@"runloopmode %@", [[NSRunLoop currentRunLoop] currentMode]);
    if ((ipzAllowInput & kIPZNoEcho) || cwin == 1)
        return NO;
    
    // If we accept the input here, word completion from a return key won't get entered.
    // If we call endEditing, then the text is right when we get to the textFieldDidEndEditing callback,
    // but we lose firstResponder and the keyboard goes away.
    // It seems to work best if we just invoke the callback here with a perform/delay, so the
    // autocorrection, if any, has time to take effect
    NSTimeInterval duration = 0.02;
    if (m_animDuration)
        duration = m_animDuration;
    [self performSelector: @selector(textFieldFakeDidEndEditing:) withObject: textField afterDelay: duration];
    
    [self checkAccessibility];
    return YES;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    if (textField == m_inputLine)
        iphone_feed_input_line([textField.text stringByReplacingCharactersInRange:range withString:string]);
    return YES;
}

- (BOOL)textFieldShouldClear:(UITextField *)textField {
    if (textField == m_inputLine) {
        iphone_feed_input_line(@"");
        [m_inputLine hideEnterKey];
        [self hideInputHelper];
    }
    return  YES;
}

-(void)autoSaveCallback {
    if ([self possibleUnsavedProgress]) {
        if (!do_autosave && (ipzAllowInput & kIPZAllowInput) && [[m_inputLine text] length]==0 && [ipzInputBufferStr length] == 0) {
            [self setLaunchMessage: @"Autosaving..." clear:NO];
            [self displayLaunchMessageWithDelay: 0.8 duration:0.5 alpha:0.4];
            [self autoSaveStory];
        }
    }
}

-(void)autoplay {
    [m_inputLine setText: @"look"];
    [self textFieldFakeDidEndEditing: m_inputLine];
}

-(void)rememberLastContentOffsetAndAutoSave:(UIScrollView*)textView {
    ++inputsSinceSaveRestore;
    CGSize sz1 = [textView contentSize];
    CGPoint contentOffset = [textView contentOffset];
    CGSize sz2 = [textView contentSize];
    contentOffset.y +=  sz2.height - sz1.height + 8;
    [textView setContentOffset: contentOffset animated:YES];
    lastVisibleYPos[cwin] = sz2.height;
    
    [self performSelector: @selector(autoSaveCallback) withObject:nil afterDelay: 30.0];
}

- (void)textFieldFakeDidEndEditing:(UITextField *)textField {
    NSString *inputText = [textField text];
    //    NSLog(@"input str:'%@' len:%d", inputText, [inputText length]);
    BOOL autoplay = [inputText isEqualToString: @"$autoplay"];
    static BOOL doAutoplay = NO;
    if (autoplay)
        doAutoplay = !doAutoplay;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(autoSaveCallback) object:nil];
    
    FrotzView *textView = m_storyView;
    if (gStoryInterp == kGlxStory && cwin >= 0)
        textView = [m_glkViews objectAtIndex:cwin];
    
    iphone_feed_input(inputText);
    iphone_feed_input(@"\n");
    iphone_feed_input_line(@"");
    [m_inputLine addHistoryItem: inputText];
    
    CGRect textFieldFrame = [textField frame];
    textFieldFrame.origin.x = 0;
    textFieldFrame.origin.y = [textView frame].size.height;
    [textField setFrame: textFieldFrame];
    XYZZY();
    if (!(gStoryInterp == kGlxStory && (cwin >= 0 && glkGridArray[cwin].win && !glkGridArray[cwin].win->echo_line_input)))
        [textView appendText: inputText];
    [textField setText: @""];
    
    [self rememberLastContentOffsetAndAutoSave: textView];
#if 1
    if (doAutoplay) {
        [self performSelector: @selector(autoplay) withObject: nil afterDelay: 0.25];
    }
#endif
    
}

-(BOOL)isCompletionEnabled {
    return m_completionEnabled;
}

-(void)setCompletionEnabled:(BOOL)on {
    m_completionEnabled = on;
}

-(BOOL)canEditStoryInfo {
    return m_canEditStoryInfo;
}

-(void)setCanEditStoryInfo: (BOOL)on {
    m_canEditStoryInfo = on;
}

-(StoryInputLine*)inputLine {
    return m_inputLine;
}

//- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
//    [m_inputLine updatePosition];
//}

-(void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView { // called when setContentOffset/scrollRectVisible:animated: finishes. not called if not animating
    [m_inputLine updatePosition];
}

-(void)hideInputHelper {
    [m_inputLine hideInputHelper];
}

-(BOOL)inputHelperShown {
    return [[m_inputLine inputHelperView] superview] != nil;
}

-(UIView*) inputHelperView {
    return [m_inputLine inputHelperView];
}


-(void)resetSettingsToDefault {
    if (m_defaultBGColor)
        [m_defaultBGColor release];
    if (m_defaultFGColor)
        [m_defaultFGColor release];
    m_defaultBGColor = [[UIColor alloc] initWithRed: 1.0 green:1.0 blue:0.9 alpha:1.0];
    m_defaultFGColor = [[UIColor alloc] initWithRed: 0.0 green:0.0 blue:0.1 alpha:1.0];
    if (currColor == 0 || currColor == 0x11 || currColor == 0x29) // don't override current game's custom colors
    {
        [self setTextColor: m_defaultFGColor makeDefault:NO];
        [self setBackgroundColor: m_defaultBGColor makeDefault:NO];
    }
    m_fontSize = gLargeScreenDevice ? kDefaultPadFontSize : kDefaultFontSize;
    [self setFont: kVariableWidthFontName withSize: m_fontSize];
    m_completionEnabled = YES;
    m_canEditStoryInfo = NO;
    [m_storyBrowser unHideAll];
}

-(int)statusFixedFontPixelWidth {
    return (int)m_statusFixedFontWidth;
}

-(int)statusFixedFontPixelHeight {
    return m_statusFixedFontPixelHeight+1;
}


static int matchWord(NSString *str, NSString *wordArray[]) {
    int i;
    for (i=0; wordArray[i]; ++i) {
        if ([wordArray[i] hasPrefix: str]) {
            return i;
        }
    }
    return -1;
}

extern int completion (const zchar *buffer, zchar *result);
extern int glulxCompleteWord(const char *word, char *result);


-(NSString*)completeWord:(NSString*)str prevString:(NSString*)prevString isAmbiguous:(BOOL*)isAmbiguous {
    *isAmbiguous = NO;
    static NSString *wordArray[] = { @"look", @"read", @"restore", @"take", @"get", @"p",
        @"put", @"quit", @"throw", @"tell", @"open", @"pick",
        @"up", @"i", @"out", @"it", @"in", @"id", @"iv", @"xi", @"is", @"on", @"of", nil };
    // removed 'inventory' because some games choke on the full spelling (HHGTTG)
    static NSString *rareWordArray[] = { @"examine", @"do", @"down", @"diagnose", @"say", @"save", @"to", @"no", @"yes",
        @"all", @"but", @"from", @"with", @"about", @"close", @"climb", @"north", @"east", @"south", @"west", @"talk",
        @"ask", @"se", @"sw", @"sb", @"port", @"drop", @"dig", @"door", @"me", @"memo", @"move", @"press", @"push", @"pull", @"show", @"stand",
        @"star", @"starboard", @"switch", @"turn", @"sit", @"kill", @"search", @"kick", @"jump",  @"go", @"lock", @"unlock", @"give",
        @"learn", @"disrobe", @"help", @"hear", @"hint", @"wear", @"remove", @"window", nil };
    static NSString *veryRareWordArray[] = { @"attack", @"answer", @"diagnose", @"verbose", @"brief", @"superbrief",
        @"score", @"restart", @"script", @"drink", @"unscript", @"listen", @"table", @"touch", @"smell", @"taste", @"feel", @"under",
        @"untie", @"inventory",	@"memorize", @"follow", @"light", @"knock", @"lantern", @"northwest", @"northeast",
        @"southeast", @"southwest",
        nil };
    static NSString *nonVerbsOnlyArray[] = { @"out", @"up", @"in", @"me", @"to", @"no", @"it", @"on", @"of", @"yes", @"all", @"down", @"off", @"but", @"from", @"with", @"about", @"door", @"memo", @"star",
        @"lock", @"window", @"score", @"switch", @"table", @"under", @"light", @"lantern", nil };
    int len = [str length], match;
    BOOL startsWithPunct = NO;

    char resultbuf[32] = { 0 };
    int status = 2;

    if (len > 0) {
        char c = [str characterAtIndex: 0];
        if (ispunct(c)) {
            startsWithPunct = YES;
            do {
                str = [str substringFromIndex: 1];
                --len;
            } while (len > 0 && [str characterAtIndex: 0]==' ');
        }
    }
    NSString *candString = nil;
    int prevlen = prevString ? [prevString length] : 0;
    if (prevlen) {
        NSRange r = [prevString rangeOfString:@"." options:NSBackwardsSearch];
        if (r.length > 0 && r.location >= prevlen-3)
            prevlen = 0;
    }
    if (len == 0)
        return nil;

    if (gStoryInterp==kZStory)
        status = completion((const zchar*)"examine", (zchar*)resultbuf);
    else
        status = glulxCompleteWord("examine", resultbuf);
    if (status != 0)
        ; // don't match built-ins, game is non-English
    else if ([str isEqualToString: @"x"])  // 1-letter shortcuts
        candString = startsWithPunct || prevlen ? nil : @"examine";
    else if ([str isEqualToString: @"z"])
        candString = startsWithPunct || prevlen ? nil : @"wait. ";
    else if ([str isEqualToString: @"g"])
        candString= startsWithPunct || prevlen ? nil : @"again. ";
    else if ([str isEqualToString: @"mem"])
        candString= startsWithPunct || prevlen ? @"memo" : @"memorize ";
    else if ([str isEqualToString: @"d"])
        candString= startsWithPunct ? nil : @"down";
    else if ([str isEqualToString: @"do"])
        candString= startsWithPunct || !prevlen ? nil : @"down";
    else {
        if ((match = matchWord(str, wordArray)) >= 0)
            candString = wordArray[match];
        else if (len > 1 && (match = matchWord(str, rareWordArray)) >= 0)
            candString = rareWordArray[match];
        else if (len > 2 && (match = matchWord(str, veryRareWordArray)) >= 0)
            candString= veryRareWordArray[match];
        if (candString && [candString length] >= 2 && (startsWithPunct || prevlen)
            && matchWord(candString, nonVerbsOnlyArray)<0)
            candString = nil;
    }
    if (!candString) {
        *resultbuf = '\0';
        status = 2;
        if (gStoryInterp==kZStory)
            status = completion((const zchar*)[str UTF8String], (zchar*)resultbuf);
        else
            status = glulxCompleteWord((const char*)[str UTF8String], resultbuf);
        if (status != 2 && strlen(resultbuf) > 0) {
            if (gStoryInterp==kZStory)
                candString = [str stringByAppendingString: [NSString stringWithUTF8String: resultbuf]];
            else
                candString = [NSString stringWithUTF8String: resultbuf];
            if (candString && [str rangeOfString:@"-"].length==0 && [candString rangeOfString:@"-"].length!=0) {
                // some games (Alabaster) seem to have hyphenated debugging commands in the dictionary; don't complete
                // hyphenated words unless the user has actually typed a hyphen
                status = 2;
                candString = nil;
            }
            if (status == 1)
                *isAmbiguous = YES;
            if (status == 0 && ([candString length] == 9 || gStoryInterp==kZStory && h_version==3 && [candString length]==6)) { // possibly truncated
                NSString *fullword = [m_storyView lookForTruncatedWord: candString];
                if (fullword)
                    candString = fullword;
            }
        }
    }
    
    if (candString && [candString isEqualToString: str])
        return nil;
    return candString;
}


/////// Dropbox Support

static NSString *kDBCFilename = @"dbcache.plist";
static NSString *kTimestampKey = @"timestamps";
static NSString *kHashKey = @"hash";
static NSString *kActiveKey = @"active";
static NSString *kDBTopPath = @"topPath";

static NSString *kDefaultDBTopPath = @"/Frotz";

-(void) initializeDropbox {
#ifdef FROTZ_DB_APP_KEY
    DBSession* session = [[DBSession alloc] initWithAppKey:@FROTZ_DB_APP_KEY  appSecret:@FROTZ_DB_APP_SECRET root:kDBRootDropbox];

    session.delegate = self; // DBSessionDelegate methods allow you to handle re-authenticating
    [DBSession setSharedSession:session];
    [session release];
    
    NSString *dbcPath = [docPath stringByAppendingPathComponent: kDBCFilename];
    
    m_dbCachedMetadata = [[NSMutableDictionary dictionaryWithContentsOfFile: dbcPath] retain];
    if (!m_dbCachedMetadata)
        m_dbCachedMetadata = [[NSMutableDictionary alloc] initWithCapacity: 4];
    m_dbTopPath = [m_dbCachedMetadata objectForKey: kDBTopPath];
    
    m_dbActive = [[m_dbCachedMetadata objectForKey: kActiveKey] boolValue];
    if ([[DBSession sharedSession] isLinked]) {
        [self.restClient loadMetadata: [self dbTopPath]];
    }
#endif
}


-(BOOL)dbIsActive {
    return m_dbActive;
}

- (void)saveDBCacheDict {
    if (!m_dbCachedMetadata)
        return;
    NSString *dbcPath = [docPath stringByAppendingPathComponent: kDBCFilename];
    NSString *error;
    
    NSData *plistData = [NSPropertyListSerialization dataFromPropertyList:m_dbCachedMetadata
                                                                   format:NSPropertyListBinaryFormat_v1_0
                                                         errorDescription:&error];
    if(plistData)
        [plistData writeToFile:dbcPath atomically:YES];
    else
    {
        NSLog(@"savedbc: err %@", error);
        [error release];
    }
}

-(NSDate*)getCachedTimestampForSaveFile:(NSString*)saveFile {
    NSMutableDictionary *timeStampDict = [m_dbCachedMetadata objectForKey: kTimestampKey];
    if (!timeStampDict) 
        return nil;
    
    return (NSDate*)[timeStampDict objectForKey: saveFile];
}

-(void)cacheTimestamp:(NSDate*)timeStamp forSaveFile:(NSString*)saveFile {
    NSMutableDictionary *timeStampDict = [m_dbCachedMetadata objectForKey: kTimestampKey];
    if (!timeStampDict) {
        timeStampDict = [[[NSMutableDictionary alloc] initWithCapacity:32] autorelease];
        [m_dbCachedMetadata setValue: timeStampDict forKey: kTimestampKey];
    }
    if (timeStamp)
        [timeStampDict setValue: timeStamp forKey:saveFile];
    else 
        [timeStampDict removeObjectForKey: saveFile];
}

-(NSString*)getHashForDBPath:(NSString*)path {
    NSMutableDictionary *hashDict = [m_dbCachedMetadata objectForKey: kHashKey];
    if (!hashDict) 
        return nil;
    
    return (NSString*)[hashDict objectForKey: path];
}

-(void)cacheHash:(NSString*)hash forDBPath:(NSString*)path {
    if (!hash || !path)
        return;
    NSMutableDictionary *hashDict = [m_dbCachedMetadata objectForKey: kHashKey];
    if (!hashDict) {
        hashDict = [[[NSMutableDictionary alloc] initWithCapacity:32] autorelease];
        [m_dbCachedMetadata setValue: hashDict forKey: kHashKey];
    }
    [hashDict setValue: hash forKey:path];
}

- (DBRestClient*)restClient {
    if (!m_restClient) {
        m_restClient = [[DBRestClient alloc] initWithSession:[DBSession sharedSession]];
        m_restClient.delegate = self;
    }
    return m_restClient;
}

- (void)sessionDidReceiveAuthorizationFailure:(DBSession*)session {
}

- (void)sessionDidReceiveAuthorizationFailure:(DBSession *)session userId:(NSString *)userId {
}

- (void)dropboxDidLinkAccount {
    if ([[DBSession sharedSession] isLinked]) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Account linked"
                                                        message: 
                              [NSString stringWithFormat:
                               @"All saved game files will now be synchronized with the '%@' folder in your Dropbox, "
                               "with separate subfolders per story.  You can access this area from Frotz on other "
                               "devices, or using any compatible Interactive Fiction program on other computers.", [self dbTopPath]]
                                                       delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [alert show];
        [alert release];
        
        [self.restClient loadMetadata: [self dbTopPath]];
    }
}


-(NSString*)metadataSubPath:(NSString*)path {
    NSString *dbTopPathT = [self dbTopPathT];
    return [path stringByReplacingOccurrencesOfString:dbTopPathT withString:@"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, path.length)];
}

- (void)restClient:(DBRestClient*)client loadedMetadata:(DBMetadata*)metadata {
    NSLog(@"Loaded metadata! %@ (%@)", metadata.path, metadata.hash);
    NSString *dbTopPath = [self dbTopPath];
    NSString *dbGamePath = [self dbGamePath];
    NSString *dbSavePath = [self dbSavePath];
    NSString *dbSavePathT = [dbSavePath stringByAppendingString: @"/"];
    
    BOOL foundGames = NO, foundSaves = NO;
    if ([metadata.path isEqualToString: dbTopPath]) {
        for (DBMetadata* child in metadata.contents) {
            if (child.isDirectory) {
                if ([child.path isEqualToString: dbGamePath])
                    foundGames = YES;
                else if ([child.path isEqualToString: dbSavePath])
                    foundSaves = YES;
            }
        }
#if 0 // creating this if we're not going to populate it will mislead people...
        if (!foundGames) {
            NSLog(@"creating dbgamepath");
            [self.restClient createFolder: dbGamePath];
        }
#endif
        if (!foundSaves) {
            NSLog(@"creating dbsavepath");
            [self.restClient createFolder: dbSavePath];
        }
        if (!m_dbActive) {
            m_dbActive = YES;
            [m_dbCachedMetadata setValue: [NSNumber numberWithBool: m_dbActive] forKey: kActiveKey];
            [self saveDBCacheDict];
        }
        //	[self.restClient performSelector:@selector(loadMetadata:) withObject:dbGamePath afterDelay:0.2];
        [self.restClient performSelector:@selector(loadMetadata:) withObject:dbSavePath afterDelay:0.3];
    } else if ([metadata.path isEqualToString: dbGamePath]) {
    } else if ([metadata.path isEqualToString: dbSavePath]) {
        [self dbCheckSaveDirs:metadata];
    } else if ([metadata.path hasPrefix: dbSavePathT]) {
        [self dbSyncSingleSaveDir: metadata];
    }
    
}

-(void)dbUploadSaveGameFile:(NSString*)saveGameSubPath { // includes game subfolder, e.g. 905.z5.d/foo.sav
    
    if ([saveGameSubPath hasSuffix: @kFrotzAutoSaveFile] || [saveGameSubPath hasSuffix: @kFrotzAutoSavePListFile]
        || [saveGameSubPath hasSuffix: @kFrotzOldAutoSaveFile]
        || [[saveGameSubPath lastPathComponent] hasPrefix: @kFrotzAutoSaveGlkImgPrefix])
        return;
    NSLog(@"Uploading to DB: %@", saveGameSubPath);
    
    NSString *saveGameFile = [saveGameSubPath lastPathComponent];
    NSString *localSavePath = [storyTopSavePath stringByAppendingPathComponent: saveGameSubPath];
    NSString *dbSGPath = [[self dbSavePath] stringByAppendingPathComponent: [saveGameSubPath stringByDeletingLastPathComponent]];
    [self.restClient deletePath: [[self dbSavePath] stringByAppendingPathComponent: saveGameSubPath]]; // delete to force upload (& timestamp update!) even if file is same
    [self.restClient uploadFile:saveGameFile toPath:dbSGPath fromPath:localSavePath];
}

-(void)dbDownloadSaveGameFile:(NSString*)saveGameSubPath { // includes game subfolder, e.g. 905.z5.d/foo.sav
    NSLog(@"Downloading from DB: %@", saveGameSubPath);
    
    NSString *localSavePath = [storyTopSavePath stringByAppendingPathComponent: saveGameSubPath];
    NSString *dbSGPath = [[self dbSavePath] stringByAppendingPathComponent: saveGameSubPath];
    [self.restClient loadFile:dbSGPath intoPath:localSavePath];
}



-(void)dbSyncSingleSaveDir:(DBMetadata*)metadata {
    NSString *dbSavePath = [self dbSavePath];
    NSString *dbSavePathT = [dbSavePath stringByAppendingString: @"/"];
    NSString *subSavePath = [metadata.path stringByReplacingOccurrencesOfString: dbSavePathT withString:@"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, metadata.path.length)];
    
    NSMutableArray *dbSaveFiles = [NSMutableArray arrayWithCapacity:metadata.contents.count];
    
    NSString *dbSavePathWithSubT = [metadata.path stringByAppendingString: @"/"];
    for (DBMetadata* child in metadata.contents) {
        if (!child.isDirectory)
            [dbSaveFiles addObject: child]; // [child.path stringByReplacingOccurrencesOfString:dbSavePathWithSubT withString:@""]];
    }
    [dbSaveFiles sortUsingSelector: @selector(caseInsensitiveCompare:)];
    
    //    NSLog(@"SingleSaveDir: %@: %@", subSavePath, dbSaveFiles);
    
    NSString *localSavePath = [storyTopSavePath stringByAppendingPathComponent: subSavePath];
    NSFileManager *defaultManager = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray *localSaveFiles = [[defaultManager contentsOfDirectoryAtPath:localSavePath error:&error] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    
    int localCount = [localSaveFiles count];
    int dbCount = [dbSaveFiles count];
    int localIndex = 0, dbIndex = 0, i = 0;
    NSString *locSF, *dbSF;
    while (localIndex < localCount && dbIndex < dbCount) {
        locSF = [localSaveFiles objectAtIndex: localIndex];
        DBMetadata *md = [dbSaveFiles objectAtIndex: dbIndex];
        dbSF = [md.path stringByReplacingOccurrencesOfString:dbSavePathWithSubT withString:@"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, md.path.length)];
        NSDate *dbModDate = md.lastModifiedDate;
        NSComparisonResult cr = [locSF caseInsensitiveCompare: dbSF];
        if (cr == NSOrderedSame) {
            NSDictionary *fileAttribs = [defaultManager fileAttributesAtPath:[localSavePath stringByAppendingPathComponent:locSF] traverseLink:NO];
            NSDate *locModDate = [fileAttribs objectForKey: NSFileModificationDate];
            NSString *sfPath = [subSavePath stringByAppendingPathComponent: locSF];
            NSDate *cachedDBModDate = [self getCachedTimestampForSaveFile: [NSString stringWithFormat: @"%@/%@", @kFrotzSaveDir, sfPath]];
            //	    NSLog(@"file %@/%@ cachedmd %@ dbmodd %@ locmd %@", subSavePath, locSF, cachedDBModDate, dbModDate, locModDate);
            
            // oldest             newest    | result
            // cache      db       local    | upload
            // db         cache    local    | upload
            // local      cache    db       | download
            // cache      local    db       | conflict  
            // db         local    cache    | no-op
            // local      db       cache    | no-op
            
            if ([locModDate compare: dbModDate] == NSOrderedDescending && [locModDate compare: cachedDBModDate] == NSOrderedDescending) {
                // If filesystem mod date is newer than db (and cache is same or older than db), upload new file
                [self dbUploadSaveGameFile: sfPath];
            } else if ([dbModDate compare: cachedDBModDate] == NSOrderedDescending) {
                if ([locModDate compare: cachedDBModDate] == NSOrderedDescending)
                    ; // conflict; ignore
                else
                    [self dbDownloadSaveGameFile: sfPath];
            }
            ++localIndex;
            ++dbIndex;
        } else if (cr == NSOrderedAscending) { // local, not in db
            NSString *sfPath = [subSavePath stringByAppendingPathComponent: locSF];
            // If we don't have the file but do have a cached timestamp, the file was deleted in DB.
            // We won't delete it locally; the user must delete it by hand, but we won't auto-reupload it either.
            // When they delete it locally, we'll also delete the cache, so if the file is recreated it will be uploaded.
            if (![self getCachedTimestampForSaveFile: [NSString stringWithFormat: @"%@/%@", @kFrotzSaveDir, sfPath]])
                [self dbUploadSaveGameFile: sfPath];
            ++localIndex;
        } else { // cr == NSOrderDescending, db, not in local
            
            NSString *sfPath = [subSavePath stringByAppendingPathComponent: dbSF];
            [self cacheTimestamp:dbModDate forSaveFile: [NSString stringWithFormat: @"%@/%@", @kFrotzSaveDir,sfPath]];
            [self dbDownloadSaveGameFile: sfPath];
            ++dbIndex;
        }
        ++i;
    }
    while (localIndex < localCount) {
        locSF = [localSaveFiles objectAtIndex: localIndex];
        [self dbUploadSaveGameFile: [subSavePath stringByAppendingPathComponent: locSF]];
        ++localIndex;
    }
    while (dbIndex < dbCount) {
    	DBMetadata *md = [dbSaveFiles objectAtIndex: dbIndex];
        dbSF = [md.path stringByReplacingOccurrencesOfString:dbSavePathWithSubT withString:@"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, md.path.length)];
        NSDate *dbModDate = md.lastModifiedDate;
        NSString *sfPath = [subSavePath stringByAppendingPathComponent: dbSF];
        [self cacheTimestamp:dbModDate forSaveFile: [NSString stringWithFormat: @"%@/%@", @kFrotzSaveDir,sfPath]];
        [self dbDownloadSaveGameFile: sfPath];
        ++dbIndex;
    }
    [self cacheHash:metadata.hash forDBPath:[self metadataSubPath: metadata.path]];
    [self saveDBCacheDict];    
}

-(void)dbCheckSaveDirs:(DBMetadata*)metadata {
    NSString *dbSavePath = [self dbSavePath];
    NSString *dbSavePathT = [dbSavePath stringByAppendingString: @"/"];
    
    NSArray *storyNames = [m_storyBrowser storyNames];
    NSMutableArray *dbSaveDirs = [NSMutableArray arrayWithCapacity:32];
    NSMutableArray *localSaveDirs = [NSMutableArray arrayWithCapacity:32];
    for (StoryInfo *si in storyNames) {
        NSString *story = [si path];
        [localSaveDirs addObject: [self saveSubFolderForStory: story]];
    }	
    for (DBMetadata* child in metadata.contents) {
        if (child.isDirectory)
            [dbSaveDirs addObject: [child.path stringByReplacingOccurrencesOfString:dbSavePathT withString:@""  options:NSCaseInsensitiveSearch range:NSMakeRange(0, child.path.length)]];
    }
    [localSaveDirs sortUsingSelector: @selector(caseInsensitiveCompare:)];
    [dbSaveDirs sortUsingSelector: @selector(caseInsensitiveCompare:)];
    
    int localCount = [localSaveDirs count];
    int dbCount = [dbSaveDirs count];
    int localIndex = 0, dbIndex = 0, i = 0;
    NSString *locSD, *dbSD;
    while (localIndex < localCount && dbIndex < dbCount) {
        locSD = [localSaveDirs objectAtIndex: localIndex];
        dbSD = [dbSaveDirs objectAtIndex: dbIndex];
        NSComparisonResult cr = [locSD caseInsensitiveCompare: dbSD];
        NSString *subPath = [dbSavePath stringByAppendingPathComponent: locSD];
        if (cr == NSOrderedSame) {
            ++localIndex;
            ++dbIndex;
            [self.restClient loadMetadata: subPath withHash:[self getHashForDBPath: [self metadataSubPath: subPath]]];
        } else if (cr == NSOrderedAscending) { // local, not in db
            NSLog(@"create folder in db: %@", locSD);
            [self.restClient createFolder: subPath];
            [self.restClient performSelector:@selector(loadMetadata:) withObject:subPath afterDelay:0.5];
            ++localIndex;
        } else { // cr == NSOrderDescending, db, not in local
            // if the dir isn't in the local list, the game isn't installed, don't create a dir for it.
            //NSLog(@"create folder local: %@", dbSD);	    
            ++dbIndex;
        }
        ++i;
    }
    while (localIndex < localCount) {
        locSD = [localSaveDirs objectAtIndex: localIndex];
        NSString *subPath = [dbSavePath stringByAppendingPathComponent: locSD];
        NSLog(@"create folder in db: %@", locSD);
        [self.restClient createFolder: subPath];
        [self.restClient performSelector:@selector(loadMetadata:) withObject:subPath afterDelay:0.5];
        ++localIndex;
    }
    while (dbIndex < dbCount) {
        // if the dir isn't in the local list, the game isn't installed, don't create a dir for it.
        //NSLog(@"create folder local: %@", dbSD);
        //dbSD = [dbSaveDirs objectAtIndex: dbIndex];
        ++dbIndex;
    }
    if (localCount > 0 || dbCount > 0)
        [self saveDBCacheDict];
}

- (void)restClient:(DBRestClient*)client loadedFile:(NSString*)destPath {
    NSLog(@"db downloaded %@", destPath);
    [self cacheTimestamp:[NSDate date] forSaveFile:
     [@kFrotzSaveDir stringByAppendingPathComponent:[destPath stringByReplacingOccurrencesOfString:storyTopSavePath withString:@"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, destPath.length)]]];
    [self saveDBCacheDict];
}

- (void)restClient:(DBRestClient*)client loadProgress:(CGFloat)progress forFile:(NSString*)destPath {
    //    NSLog(@"db download progress : %f : %@", progress, destPath);
}

- (void)restClient:(DBRestClient*)client loadFileFailedWithError:(NSError*)error {
    NSLog(@"db download failed %@ : %@", error.userInfo, error);
}

- (void)restClient:(DBRestClient*)client uploadedFile:(NSString*)destPath from:(NSString*)srcPath {
    NSLog(@"db uploadedFile: %@ from %@", destPath, srcPath);
    [self cacheTimestamp:[NSDate date] forSaveFile: [destPath stringByReplacingOccurrencesOfString:[self dbTopPathT] withString:@"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, destPath.length)]];
    [self saveDBCacheDict];
}

- (void)restClient:(DBRestClient*)client uploadProgress:(CGFloat)progress forFile:(NSString*)destPath from:(NSString*)srcPath {
    //    NSLog(@"db uploadProg: %f : %@ from %@", progress, destPath, srcPath);
}

- (void)restClient:(DBRestClient*)client uploadFileFailedWithError:(NSError*)error {
    NSLog(@"Error uploading file: %@ : %@", error.userInfo, error);
}

-(void)restClient:(DBRestClient*)client metadataUnchangedAtPath:(NSString*)path {
    //    NSLog(@"Metadata unchanged for path %@!", path);
}

-(NSString*)dbTopPath {
    if (m_dbTopPath)
        return m_dbTopPath;
    return kDefaultDBTopPath;
}

-(void)dbRecursiveMakeParents:(NSString*)path {
    if (![path hasPrefix: @"/"] || [path isEqualToString: @"/"])
        return;
    [self dbRecursiveMakeParents: [path stringByDeletingLastPathComponent]];
    [self.restClient createFolder: path];
}

-(void)setDBTopPath:(NSString*)path {
    if (m_dbTopPath != path) {
        if (![path hasPrefix: @"/"] || [path hasSuffix: @"/"])
            return;
        if (m_dbActive && [[DBSession sharedSession] isLinked]) {
            [self dbRecursiveMakeParents: [path stringByDeletingLastPathComponent]];
            
            // NOTE: this doesn't work if they try something like move /Frotz -> /Frotz/foo/bar.
            // For that to work we'd have to move each top-level subfolder individually.  Oh well.
            [self.restClient moveFrom: [self dbTopPath] toPath: path];
        }
        [m_dbTopPath release];
        m_dbTopPath = [path retain];
    	[m_dbCachedMetadata setObject:m_dbTopPath forKey:kDBTopPath];
        [self saveDBCacheDict];
        if ([[DBSession sharedSession] isLinked])
            [self.restClient performSelector:@selector(loadMetadata:) withObject:m_dbTopPath afterDelay:1.0];
    }
}

-(NSString*)dbTopPathT {
    return [self.dbTopPath stringByAppendingString: @"/"];
}

-(NSString*)dbGamePath {
    return [self.dbTopPath stringByAppendingFormat: @"/" kFrotzGameDir];
}

-(NSString*)dbSavePath {
    return [self.dbTopPath stringByAppendingFormat: @"/" kFrotzSaveDir];
}

- (void)restClient:(DBRestClient*)client loadMetadataFailedWithError:(NSError*)error {
    NSLog(@"Error loading metadata: %@ : %@", error.userInfo, error);
    int errCode = [error code];
    if (errCode == 404) {
        NSString *topPath = [self dbTopPath];
        NSString *path = [error.userInfo objectForKey: @"path"];
        if (path && [path isEqualToString: topPath]) {
            NSLog(@"creating dbtoppath");
    	    [self dbRecursiveMakeParents: [topPath stringByDeletingLastPathComponent]];
            [self.restClient createFolder: topPath];
            [self.restClient loadMetadata: topPath];
        }
    }
}


@end // StoryMainViewController

@implementation UINavigationController (OrientationSettings_IOS6)

-(BOOL)shouldAutorotate {
    return [[self.viewControllers lastObject] shouldAutorotate];
}

-(NSUInteger)supportedInterfaceOrientations {
    return [[self.viewControllers lastObject] supportedInterfaceOrientations];
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return [[self.viewControllers lastObject] preferredInterfaceOrientationForPresentation];
}

@end


@implementation DBMetadata (MySort)

-(NSComparisonResult)caseInsensitiveCompare:(DBMetadata*)other {
    return [self.path caseInsensitiveCompare: other.path];
}
@end

void removeAnim(UIView *view) {
    //    [[UIAnimator sharedAnimator] removeAnimationsForTarget:view];
    static id c;
    static SEL s,r;
    if (!c) {
        c = NSClassFromString(@"UIAnimator");
        NSString *sa = [@"shared" stringByAppendingString: @"Animator"];
        NSString *rt = [@"remove" stringByAppendingString: @"AnimationsForTarget:"];
        s = NSSelectorFromString(sa);
        r = NSSelectorFromString(rt);
    }
    if (c && [c respondsToSelector: s])
        [[c performSelector: s] performSelector:r withObject:view];
}

