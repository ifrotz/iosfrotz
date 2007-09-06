/*

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
#import <Foundation/Foundation.h>
#import <UIKit/UIView-Geometry.h>
#import <GraphicsServices/GraphicsServices.h>
extern int GSEventGetTimestamp(GSEvent *);

#import "FrotzApplication.h"
#import "MainView.h"
#import "FrotzKeyboard.h"
#import "StoryMainView.h"

#import <UIKit/UIKeyboardLayoutQWERTY.h>
#import <UIKit/UIKeyboardLayoutQWERTYLandscape.h>

#include <pthread.h>

int iphone_textview_width = 55, iphone_textview_height = 18;
int do_autosave = 0, autosave_done = 0;
int do_filebrowser = 0;
static int filebrowser_allow_new = 0;

char iphone_filename[256];

const int kFixedFontSize = 9;
const int kFixedFontPixelHeight = 11;

// The prefs should really be in /var/root/Library/References/<NSBundlerIdentifier>.plist,
// but it makes me nervous to write anything there.
NSString *frotzPrefsPath  = @kFrotzDir @"/FrotzPrefs.plist";
NSString *storyGamePath   = @kFrotzDir @kFrotzGameDir;
NSString *storySavePath   = @kFrotzDir @kFrotzSaveDir;
NSString *storySIPPath    = @kFrotzDir @kFrotzSaveDir @"FrotzSIP.plist";
NSString *storySIPSavePath= @kFrotzDir @kFrotzSaveDir kFrotzAutoSaveFile;
const char *AUTOSAVE_FILE =  kFrotzDir  kFrotzSaveDir kFrotzAutoSaveFile;  // used by interpreter from z_save

NSMutableString *ipzBufferStr = NULL, *ipzStatusStr = NULL, *ipzInputBufferStr = NULL;
int ipzDeleteCharCount = 0;

#define kStatusLineYPos		0.0f
#define kStatusLineHeight	19.0f   // for early V3 games

float topWinSize = kStatusLineHeight;

enum { kIPZDisableInput = 0, kIPZRequestInput = 1, kIPZNoEcho = 2, kIPZAllowInput = 4 };
static int ipzAllowInput = kIPZDisableInput;

// arm-apple-darwin-cc incorrectly generates the x86-specific runtime func for sending messages that
// return floats.  The function is not implemented in the iPhone objc library.  Implement it and pretend.
OBJC_EXPORT double objc_msgSend_fpret(id self, SEL op, ...) {
  void *x = [self performSelector:op];
  return (*(float*)&x);
}

void iphone_ioinit() {
    if (!ipzBufferStr) {
	ipzBufferStr = [[NSMutableString alloc] initWithUTF8String: ""];
	ipzStatusStr = [[NSMutableString alloc] initWithUTF8String: ""];
	ipzInputBufferStr = [[NSMutableString alloc] initWithUTF8String: ""];
    }
}

void iphone_putchar(char c) {
    pthread_mutex_lock(&outputMutex);

    if (cwin == 1 || cwin == 7) {
	[ipzStatusStr appendFormat:@"%c", c];
	pthread_mutex_unlock(&outputMutex);
	return;
    }
    putchar(c);
    
    [ipzBufferStr appendFormat:@"%c", c];
    pthread_mutex_unlock(&outputMutex);
}

void iphone_puts(char *s) {
    while (*s != '\0')
        iphone_putchar(*s++);
}

int iphone_getchar() {
    while (1) {
	if ([ipzInputBufferStr length] > 0) {
	    NSString *charStr = [ipzInputBufferStr substringToIndex: 1];
	    [ipzInputBufferStr deleteCharactersInRange: NSMakeRange(0, 1)];
	    
	    const char *s = [charStr UTF8String];
	    if (s) {
		return *s;
	    }
	}
	usleep(1000000);
    }
}

void iphone_enable_input() {
    pthread_mutex_lock(&outputMutex);
    if (ipzAllowInput == kIPZDisableInput)
	ipzAllowInput = kIPZRequestInput;
    pthread_mutex_unlock(&outputMutex);
}

void iphone_enable_single_key_input() {
    pthread_mutex_lock(&outputMutex);
    if (ipzAllowInput == kIPZDisableInput)
	ipzAllowInput = kIPZRequestInput | kIPZNoEcho;
    pthread_mutex_unlock(&outputMutex);
}

void iphone_disable_input() {
    pthread_mutex_lock(&outputMutex);
    ipzAllowInput = kIPZDisableInput;
    pthread_mutex_unlock(&outputMutex);
}

void iphone_delete_chars(int n) {
    pthread_mutex_lock(&outputMutex);
    ipzDeleteCharCount += n;
    pthread_mutex_unlock(&outputMutex);
}

void iphone_more_prompt() {
// This doesn't work very well.  The text flickers when the more prompt is erased,
// and it's awkward to use the keyboard to page through when the iphone's native
// scrolling is so much more natural.
#ifdef IPHONE_MORE_PROMPT_ENABLED
    iphone_puts("[More]");
    iphone_enable_single_key_input();
    iphone_getchar();
    iphone_disable_input();
    iphone_delete_chars(6);
#endif
}

int iphone_read_file_name(char *file_name, const char *default_name, int flag) {
    do_filebrowser = 1;
    
    while (do_filebrowser) {
	usleep(100000);
    }
    if (!*iphone_filename)
	return FALSE;

    strcpy(file_name, iphone_filename);
    
    if (flag == FILE_SAVE || flag == FILE_SAVE_AUX || flag == FILE_RECORD)
	; // ask before overwriting...

    return TRUE;
}

extern int finished; // set by z_quit

void run_interp(const char *story, bool autorestore) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    char *argv[] = {"iFrotz", NULL };

    winSizeChanged = FALSE;
    finished = 0;

    NSMutableString *str = [NSMutableString stringWithUTF8String: story];
    story_name  = (char*)[str UTF8String];
    os_set_default_file_names(story_name);
    if (autorestore)
	do_autosave = 1;
    init_buffer ();
    init_err ();
    init_memory ();
    init_interpreter ();
    init_sound ();
    os_init_screen ();
    init_undo ();
    iphone_ioinit();
    z_restart ();
    if (autorestore) {
	id fileMgr = [NSFileManager defaultManager];

	z_restore ();
	do_autosave = 0;
	
	[fileMgr removeFileAtPath: storySIPSavePath handler:nil];
    }
    interpret ();
    finished = 1;
    reset_memory ();
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


@interface UITextLoupe : UIView
- (void)drawRect:(struct CGRect)rect;
@end

@implementation UITextLoupe (Black)
- (void)drawRect:(struct CGRect)rect {
}
@end

@implementation StoryMainView 
- (id)initWithFrame:(struct CGRect)rect {
    if ((self == [super initWithFrame: rect]) != nil) {
    
	m_landscape = NO;
	
	m_background = [[UIView alloc] initWithFrame: CGRectMake(0.0f, 0.0f, 480.0f, 480.0f)];
	float fgRGB[4] = {0.0, 0.0, 0.1, 1.0};
	float bgRGB[4] = {1.0, 1.0, 0.9, 1.0};
	float altRGB[4] = {0.5, 0.5, 0.6, 1.0};
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	struct CGColor *bgColor = CGColorCreate(colorSpace, bgRGB);
	struct CGColor *fgColor = CGColorCreate(colorSpace, fgRGB);
	struct CGColor *altColor = CGColorCreate(colorSpace, altRGB);
	[m_background setBackgroundColor: bgColor];
	[self addSubview: m_background];

	id fileMgr = [NSFileManager defaultManager];
	
	if (![fileMgr fileExistsAtPath: @kFrotzDir]) {
	    [fileMgr createDirectoryAtPath: @kFrotzDir attributes: nil];
	}
	if (![fileMgr fileExistsAtPath: @kFrotzDir @kFrotzSaveDir]) {
	    [fileMgr createDirectoryAtPath: @kFrotzDir @kFrotzSaveDir attributes: nil];
	}

	chdir(kFrotzDir kFrotzSaveDir);
				
	m_statusLine = [[UIStatusLine alloc] initWithFrame: CGRectMake(0.0f, kStatusLineYPos, 320.0f /*500.0f*/, kStatusLineHeight)];
	//struct CGColor *origFg = [m_statusLine textColor], *origBg = [m_statusLine backgroundColor];
	[m_statusLine setBackgroundColor: fgColor];
	[m_statusLine setTextColor: bgColor];
	[m_statusLine setTextFont: @"CourierNewBold"];
	[m_statusLine setTextSize: kFixedFontSize];
	[m_statusLine setEditable: NO];
	
	m_storyView = [[UIStoryView alloc] initWithFrame:
	    CGRectMake(0.0f, kStatusLineYPos + kStatusLineHeight,
	    rect.size.width, rect.size.height - kStatusLineYPos - kUIStatusBarHeight)];
	[m_storyView setBackgroundColor: bgColor];
	[m_storyView setTextColor: fgColor];
	[m_storyView setAllowsRubberBanding:YES];
	[m_storyView setMarginTop: 0];
	[m_storyView setBottomBufferHeight: 20.0f];
	[m_storyView displayScrollerIndicators];
	// [m_storyView setEnabledGestures: 3]; // I pinch!

	[self setFont: @"helvetica"];
	[self setFontSize: 12];
	
	[self addSubview: m_storyView];
	[self addSubview: m_statusLine];

	[self loadPrefs];
	
	m_keyb = [[FrotzKeyboard alloc] initWithFrame: CGRectMake(0.0f, rect.size.height, 320.0f, 236.0f)];
	[m_keyb show: m_storyView];
	[self addSubview: m_keyb];

	[m_storyView setKeyboard: m_keyb];
	[m_keyb setTapDelegate: m_storyView];
	
	m_currentStory = [[NSMutableString stringWithString: @""] retain];
	
	[m_storyView becomeFirstResponder];	
	
	CGColorRelease(fgColor);
	CGColorRelease(bgColor);
	CGColorRelease(altColor);
	CGColorSpaceRelease(colorSpace);
    }
    return self;
}

-(void) scrollToEnd {
    [m_storyView becomeFirstResponder];
    [[[m_storyView _webView] webView] moveToEndOfDocument:self];
}

-(void) setBackgroundColor: (CGColorRef)color {
    [m_storyView setBackgroundColor: color];
    [m_background setBackgroundColor: color]; 
    [m_statusLine setTextColor: color];
}
-(void) setTextColor: (CGColorRef)color {
    [m_storyView setTextColor: color];
    [m_statusLine setBackgroundColor: color];
}
-(CGColorRef) backgroundColor {
    return [m_storyView backgroundColor];
}
-(CGColorRef) textColor {
    return [m_storyView textColor];
}

-(BOOL) landscape {
    return m_landscape;
}

-(void) setLandscape: (BOOL)landscape {
    if (landscape != m_landscape) {
    	[m_keyb removeFromSuperview];
	[m_storyView removeFromSuperview];
	[m_statusLine removeFromSuperview];

	m_landscape = landscape;
	[m_keyb setLandscape: landscape];
	float kbdHeight = [m_keyb isVisible] ? [m_keyb keyboardHeight] : 0.0f;

	if (landscape) {
	    [self setFrame: CGRectMake(0.0f, 0.0f, 480.0f, 320.0f)];

	    [m_statusLine setFrame: CGRectMake(0.0f, kStatusLineYPos, 480.0f, topWinSize)];
	    [m_storyView setFrame: CGRectMake(0.0f, kStatusLineYPos + topWinSize,
						460.0f + (gShowStatusBarInLandscapeMode ? 0.0f: kUIStatusBarHeight),
						320.0f - kbdHeight - topWinSize)];
	    
	    [m_storyView setMarginTop: 0];
	    [m_storyView setBottomBufferHeight: 20.0f];
	    [m_storyView setNeedsLayout];
	    [m_storyView setNeedsDisplay];
	    [self addSubview: m_storyView];
	    [self addSubview: m_statusLine];

	    BOOL isVisible = [m_keyb isVisible];
	    [m_keyb setTransform: CGAffineTransformMakeTranslation(0.0f, 0.0f)];
	    if (isVisible)
		[m_keyb setFrame: CGRectMake(0.0f, 140.0f, 480.0f, 180.0f)];
	    else
		[m_keyb setFrame: CGRectMake(0.0f, 320.0f, 480.0f, 180.0f)];
	    [m_keyb showLayout:[UIKeyboardLayoutQWERTYLandscape class]];
	    if (gShowStatusBarInLandscapeMode)
		[m_keyb setTransform: CGAffineTransformMakeTranslation(-10.0f, 0.0f)];
	} else {

	    [self setFrame: CGRectMake(0.0f, 0.0f, 320.0f, 480.0f - 40.0f /* - kStatusLineHeight */)];
	    
	    [m_statusLine setFrame: CGRectMake(0.0f, kStatusLineYPos, 320.0f, topWinSize)];
	    [m_storyView setFrame: CGRectMake(0.0f, kStatusLineYPos + topWinSize, 320.0f, 440.0f - kbdHeight - topWinSize)];

	    [m_storyView setMarginTop: 1];
	    [m_storyView setBottomBufferHeight: 20.0f];
	    [m_storyView setNeedsLayout];
	    [m_storyView setNeedsDisplay];
	    [self addSubview: m_storyView];
	    [self addSubview: m_statusLine];

	    BOOL isVisible = [m_keyb isVisible];
	    [m_keyb setTransform: CGAffineTransformMakeTranslation(0.0f, 0.0f)];
	    if (isVisible)
		[m_keyb setFrame: CGRectMake(0.0f, 440.0f - 236.0f, 320.0f, 236.0f)];
	    else
		[m_keyb setFrame: CGRectMake(0.0f, 440.0f, 320.0f, 236.0f)];
	    [m_keyb showLayout:[UIKeyboardLayoutQWERTY class]];
	}

	[self addSubview: m_keyb];
	[m_storyView setKeyboard: m_keyb];
	[m_keyb setTapDelegate: m_storyView];

	[m_storyView becomeFirstResponder];
	[[[m_storyView _webView] webView] moveToEndOfDocument:self];

    }
}


-(void) setMainView: (MainView*)mainView {
    m_topView = mainView;
}

-(MainView*) mainView {
    return m_topView;
}

-(NSMutableString*) font {
    return m_fontname;
}

-(void) setFont: (NSString*) font {
    m_fontname = [[font copy] retain];
    [[self storyView] setTextFont: font];
}

-(int) fontSize {
    return m_fontSize;
}

-(void) setFontSize: (int)size {
    if (size) {
	m_fontSize = size;
	[[self storyView] setTextSize: size];
    }
}

-(UIStoryView*) storyView {
    return m_storyView;
}

-(NSString*) currentStory {
    return m_currentStory;
}

-(void) setCurrentStory: (NSString*)story {
    [m_currentStory setString: [[NSMutableString stringWithString: story] retain]];
    [m_currentStory retain];
}


static int iphone_top_win_height = 1;

char *tempScreenBuf() {
    static char buf[MAX_ROWS * MAX_COLS];
    int i, j;
    for (i=0; i < iphone_top_win_height; ++i) {
	for (j=0; j < h_screen_cols; ++j) {
	    char c = (char)screen_data[i * MAX_COLS + j];
	    if (i == cursor_row && j == cursor_col && c == ' ')
		c = '#';
	    buf[i * (h_screen_cols+1) + j] = c;
	}
	buf[i*(h_screen_cols+1) + j] = '\n';
    }	
    buf[i*(h_screen_cols+1) + j] = '\0';	
    return buf;
}

-(void)printText: (id)unused {
    static int prevTopWinHeight = 1;
    static int continuousPrintCount = 0;
    int textLen = [ipzBufferStr length];
    int statusLen = [ipzStatusStr length];
    if ((textLen > 0 || top_win_height > prevTopWinHeight) && prevTopWinHeight != top_win_height) {
	topWinSize = 8 + top_win_height * kFixedFontPixelHeight;
	if (topWinSize > 204) topWinSize = 204;
	[m_statusLine setFrame: CGRectMake(0.0f, 0.0f, 500.0f,  topWinSize)];
	[m_storyView setFrame: CGRectMake(0.0f, topWinSize, 320.0f, 480.0f - 40.0f - (topWinSize) - 236)];
	iphone_top_win_height = top_win_height;
	prevTopWinHeight = top_win_height;
    }

    pthread_mutex_lock(&winSizeMutex);
    if (winSizeChanged) {
	winSizeChanged = FALSE;
	pthread_cond_signal(&winSizeChangedCond);
    }
    pthread_mutex_unlock(&winSizeMutex);

    pthread_mutex_lock(&outputMutex);

    if (ipzDeleteCharCount) {
	NSMutableString *text = [m_storyView text];
	int len = [text length], pos;
	if (len > ipzDeleteCharCount)
	    pos = len - ipzDeleteCharCount;
	else {
	    pos = 0;
	    ipzDeleteCharCount = len;
	}
	// *sigh* The deleteBackward method in the webView doesn't seem to work
	[text deleteCharactersInRange: NSMakeRange(pos, ipzDeleteCharCount)];
	[m_storyView setText: text];
	ipzDeleteCharCount = 0;
    }

    if (textLen > 0) {
	[m_storyView insertText: ipzBufferStr];
	[ipzBufferStr setString: @""];
	continuousPrintCount++;
    } else
	continuousPrintCount = 0;

    if (statusLen > 0) {
	char * s = tempScreenBuf();
	[ipzStatusStr setString: @""];
	[ipzStatusStr appendFormat:@"%s", s];
	
    	[m_statusLine setText: ipzStatusStr];
	[ipzStatusStr setString: @""];
	//if (cursor_row < top_win_height)
	    //[m_storyView becomeFirstResponder];
    } 
    if (ipzAllowInput & kIPZRequestInput)
	ipzAllowInput |= kIPZAllowInput;
    pthread_mutex_unlock(&outputMutex);
#ifdef IPHONE_MORE_PROMPT_ENABLED
    if (continuousPrintCount)
	[m_storyView scrollToMakeCaretVisible: YES];
#endif
    if (do_filebrowser == 1) {
	do_filebrowser = 2;
	[[self mainView] openFileBrowser];
    }
    if (finished)
	[[self mainView] performSelector:@selector(abortToBrowser:) withObject:nil afterDelay:0.25];
    else
	[self performSelector:@selector(printText:) withObject:nil afterDelay:0.01];
    fflush(stdout);
    fflush(stderr);
}


-(void) savePrefs {
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity: 10];
    [dict setObject: m_fontname forKey: @"fontFamily"];
    [dict setObject: [NSNumber numberWithInt: m_fontSize] forKey: @"fontSize"];

    const float *textColorRGB = CGColorGetComponents([self textColor]);
    const float *bgColorRGB = CGColorGetComponents([self backgroundColor]);
    NSString *textColorStr = [NSString stringWithFormat: @"#%02X%02X%02X",
	    (int)(textColorRGB[0]*255), (int)(textColorRGB[1]*255),(int)(textColorRGB[2]*255)];
    NSString *bgColorStr = [NSString stringWithFormat: @"#%02X%02X%02X",
	    (int)(bgColorRGB[0]*255), (int)(bgColorRGB[1]*255),(int)(bgColorRGB[2]*255)];

    [dict setObject: textColorStr forKey: @"textColor"];
    [dict setObject: bgColorStr forKey: @"backgroundColor"];
    [dict writeToFile: frotzPrefsPath atomically: NO];
}

static struct CGColor *scanColor(NSString *colorStr) {
    unsigned int intRGB;
    float floatRGB[4] = { 0.0f, 0.0f, 0.0f, 1.0f };

    struct CGColor *color = NULL;
    if ([colorStr characterAtIndex: 0] == '#') {
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	NSScanner *scanner = [NSScanner scannerWithString: colorStr];
	[scanner setScanLocation: 1];
	[scanner scanHexInt: &intRGB];
	floatRGB[0] = (float)((intRGB & 0xff0000) >> 16) / 255.0f;
	floatRGB[1] = (float)((intRGB & 0xff00) >> 8) / 255.0f;
	floatRGB[2] = (float)((intRGB & 0xff)) / 255.0f;
	color = CGColorCreate(colorSpace, floatRGB);
	CGColorSpaceRelease(colorSpace);
    }
    return color;
}

-(void) loadPrefs {
    NSDictionary *dict = [[NSDictionary dictionaryWithContentsOfFile: frotzPrefsPath] retain];
    if (dict) {
	NSString *fontname =  [dict objectForKey: @"fontFamily"];
	int fontSize= [[dict objectForKey: @"fontSize"] longValue];
	[self setFont: fontname];
	[self setFontSize: fontSize];
	NSString *textColorStr = [dict objectForKey: @"textColor"];
	NSString *bgColorStr = [dict objectForKey: @"backgroundColor"];
	struct CGColor *textColor = scanColor(textColorStr);
	if (textColor) {
	    [self setTextColor: textColor];
	    CGColorRelease(textColor);
	}
	struct CGColor *bgColor = scanColor(bgColorStr);
	if (textColor) {
	    [self setBackgroundColor: bgColor];
	    CGColorRelease(bgColor);
	}
	[dict release];
    }
}


-(BOOL) autoRestoreSession {
    static char storyNameBuf[256];
    
    id fileMgr = [NSFileManager defaultManager];
    if ([fileMgr fileExistsAtPath: storySIPPath] && [fileMgr fileExistsAtPath: storySIPSavePath]) {
    	NSDictionary *dict = [[NSDictionary dictionaryWithContentsOfFile: storySIPPath] retain];
	NSString *statusStr = NULL;
	if (dict) {
	    [m_currentStory release];
	    m_currentStory = [[NSMutableString stringWithString: [dict objectForKey: @"storyPath"]] retain];
	    if (m_currentStory && [m_currentStory length] > 0) {
		int i, j;
		top_win_height = [[dict objectForKey: @"statusWinHeight"] longValue];
		cwin = [[dict objectForKey: @"currentWindow"] longValue];
		cursor_row = [[dict objectForKey: @"cursorRow"] longValue];
		cursor_col = [[dict objectForKey: @"cursorCol"] longValue];
		statusStr = [dict objectForKey: @"statusWinContents"];		
  		[m_storyView setText: [dict objectForKey: @"storyWinContents"]];
		[dict release];
		
		h_screen_rows = iphone_textview_height;
		h_screen_cols = iphone_textview_width;

		iphone_init_screen();
		for (i=0; i < top_win_height; ++i) {
		    for (j=0; j < h_screen_cols; ++j) {
			char c = [statusStr characterAtIndex: i * (h_screen_cols+1) + j];
			if (i == cursor_row && j == cursor_col && c == '#')
			    c = ' ';
			screen_data[i * MAX_COLS + j] = c;
		    }
		    for (; j < MAX_ROWS; ++j) {
			screen_data[i * MAX_COLS + j] = ' ';
		    }
		}
		iphone_ioinit();
		[ipzStatusStr setString: @" \b"];

		[fileMgr removeFileAtPath: storySIPPath handler:nil];
		strcpy(storyNameBuf, [m_currentStory UTF8String]);
		pthread_create(&m_storyTID, NULL, interp_cover_autorestore, (void*)storyNameBuf);
		[m_keyb show:m_storyView];
		[m_storyView becomeFirstResponder];
		[self performSelector:@selector(printText:) withObject:nil afterDelay:0.1];
		return YES;
	    }
	}
	NSLog([NSString stringWithFormat: @"autoRestoreFailed\n"]);
    }
    return NO;
}

-(void) launchStory {
    static char storyNameBuf[256];
    strcpy(storyNameBuf, [m_currentStory UTF8String]);
    pthread_create(&m_storyTID, NULL, interp_cover_normal, (void*)storyNameBuf);
//    NSLog (@"launched tid %d\n", m_storyTID);
    [m_keyb show:m_storyView];
    [self performSelector:@selector(printText:) withObject:nil afterDelay:0.1];

}

-(void) abandonStory {
    if ([m_currentStory length] > 0) {
	[ipzInputBufferStr setString: @"\n\n"];   
	do_autosave = 0;
	z_quit();
	[m_currentStory setString: @""];
	pthread_join(m_storyTID, NULL);
    }
    [ipzInputBufferStr setString: @""];
    [m_statusLine setText: @""];
    [m_storyView setText: @""];
    top_win_height = 0;
}

-(void) suspendStory {
    [ipzInputBufferStr setString: @""];   
    [ipzInputBufferStr appendFormat: @"%c", ZC_AUTOSAVE];
    if (m_currentStory && ([m_currentStory length] > 0)) {
	char *topWinString = tempScreenBuf();
	NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity: 10];
	[dict setObject: m_currentStory forKey: @"storyPath"];
	[dict setObject: [NSNumber numberWithInt: iphone_top_win_height] forKey: @"statusWinHeight"];
	[dict setObject: [NSNumber numberWithInt: cwin] forKey: @"currentWindow"];
	[dict setObject: [NSNumber numberWithInt: cursor_row] forKey: @"cursorRow"];
	[dict setObject: [NSNumber numberWithInt: cursor_col] forKey: @"cursorCol"];
	[dict setObject: [NSString stringWithUTF8String: topWinString] forKey: @"statusWinContents"];
	[dict setObject: [m_storyView text] forKey: @"storyWinContents"];
	[dict writeToFile: storySIPPath atomically: NO];
	[dict release];
		
	// need a cond var or something to synchronize this less hackishly
	int count = 30;
	while (autosave_done == 0 && count >= 0) {
	    usleep(100000);
	    --count;
	}
	sync();
    }
    autosave_done = 0;
}

@end // StoryMainView

@implementation UIStoryView

-(BOOL)canBecomeFirstResponder { return NO; }
- (void)insertText:(NSString*)text
{
#ifdef IPHONE_MORE_PROMPT_ENABLED
    [[[self _webView] webView] moveToEndOfDocument:self];
    [[self _webView] insertText:text];
    [self scrollToEnd];
#else
    [[[self _webView] webView] moveToEndOfDocument:self];
    [[self _webView] insertText:text];
#endif
}
@end

@implementation UIStatusLine
- (void)insertText:(NSString*)text
{
    [[[self _webView] webView] moveToEndOfDocument:self];
    [[self _webView] insertText:text];
    [self scrollToEnd];
}
@end

@implementation UIFrotzWinView
- (void)scrollToEnd
{
    [self setSelectionRange:NSMakeRange(9999999, 1)];
    [self scrollToMakeCaretVisible:YES];
}

- (void)setKeyboard: (FrotzKeyboard *)keyboard {
    m_keyb = keyboard;
}

static unsigned int MyGSEventGetTimestamp(GSEvent *event) {
    unsigned int *p = (unsigned int*)((char*)event + 0x20);
    // there appears to be an 8 byte little endian nanosecond counter 32 bytes into the event; convert to approx. ms
    unsigned int timeStamp = p[1] * 4295 + p[0] / 1000000; 
    return timeStamp;
}

static int lastTimestamp;

int GSEventAccelerometerAxisX(GSEvent *event);
int GSEventAccelerometerAxisY(GSEvent *event);
int GSEventAccelerometerAxisZ(GSEvent *event);


-(void)mouseDown:(GSEvent *)event {
    lastTimestamp = MyGSEventGetTimestamp(event);
    // Prevent textView from seeing the mouseDown to disallow moving the cursor
    // while still allowing typing at the end of the document.
    // Fortunately, the mouseDrag still goes through to the UIScroller parent, so
    // scrolling still works.  Allow the event through if scrolling so the
    // scrolling hysteresis can be halted.
#if 0
    int x = GSEventAccelerometerAxisX(event);
    int y = GSEventAccelerometerAxisY(event);
    int z = GSEventAccelerometerAxisZ(event);
    printf ("Accel %d %d %d\n", x, y, z);
#endif
  //  if ([self isScrolling]) {
	[super mouseDown:event];
   //  }
}

-(void)mouseUp:(GSEvent *)event
{
//  int ts = GSEventGetTimestamp(event); // return value was undeciperable as float, double, or int
#if 0
    int x = GSEventAccelerometerAxisX(event);
    int y = GSEventAccelerometerAxisY(event);
    int z = GSEventAccelerometerAxisZ(event);
    printf ("Accel %d %d %d\n", x, y, z);
#endif
    int timestamp = MyGSEventGetTimestamp(event);
    if (timestamp - lastTimestamp < 150 && ![self isScrolling])
	[m_keyb toggle: self];
    else
	[super mouseUp:event];
}

-(BOOL)webView:(id)sender shouldInsertText:(id)text replacingDOMRange:(id)range givenAction:(int)action {
    if ((ipzAllowInput & kIPZAllowInput) && ipzInputBufferStr) {
	if ([text length] > 1)  { // hack... multi-char input is hopefully always caused by keyboard autocomplete
	    [ipzInputBufferStr appendFormat: @"%c", ZC_ESCAPE];
	}
	[ipzInputBufferStr appendString: text];
	if ((ipzAllowInput & kIPZNoEcho) || cwin == 1)
	    return NO;
    }
    return [super webView:sender shouldInsertText:text replacingDOMRange:range givenAction:action];
}

-(BOOL)webView:(id)sender shouldDeleteDOMRange:(id)range {
    if ((ipzAllowInput & kIPZAllowInput) && ipzInputBufferStr) {
	[ipzInputBufferStr appendFormat: @"%c", ZC_BACKSPACE];
//	if (cwin = 1)
//	    return NO;
    }
    else
	return NO;

    return [super webView:sender shouldDeleteDOMRange:range];
}

@end

