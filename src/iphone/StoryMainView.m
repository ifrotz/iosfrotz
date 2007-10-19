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

BOOL gUseHTML = YES;

NSString *htmlPreamble = @"<html><body>\n";
NSMutableString *htmlBuf = NULL;

NSString *htmlColorTable[] = {
  NULL,	      // unused
  @"",        // default
  @"#000000", // black
  @"#ff0000", // red
  @"#00ff00", // green
  @"#ffff00", // yellow
  @"#0000ff", // blue
  @"#ff00ff", // magenta
  @"#00ffff", // cyan
  @"#ffffff", // white
  @"#555555", // grey
  @"#cccccc", // light grey
  @"#808080", // medium grey
  @"#333333"  // dark grey
};

int iphone_textview_width = 61, iphone_textview_height = 24;
int do_autosave = 0, autosave_done = 0;
int do_filebrowser = 0;
static int filebrowser_allow_new = 0;

char iphone_filename[256];

const int kFixedFontSize = 8;
const int kFixedFontWidth = 5;
const int kFixedFontPixelHeight = 9;

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

int currColor = 0, currTextStyle = 0;

void iphone_set_text_attribs(int style, int color) {
    if (!gUseHTML)
	return;
    
    pthread_mutex_lock(&outputMutex);

    if (style != currTextStyle || color != currColor) {
	NSString *fontWtStr = @"", *fontStyleStr = @"", *fontFixedStr = @"", *fgStr= @"", *bgStr = @"";
	if (style & BOLDFACE_STYLE)
	    fontWtStr = [NSString stringWithFormat: @"font-weight:bold;"];
	if (style & EMPHASIS_STYLE)
	    fontStyleStr = [NSString stringWithFormat: @"font-style:italic;"];
	if (style & FIXED_WIDTH_STYLE)
	    fontStyleStr = [NSString stringWithFormat: @"font-family:courier;"];
	if (style & REVERSE_STYLE) {
	    fgStr = [NSString stringWithFormat: @"color:%@;", htmlColorTable[(color & 0xF)]];
	    bgStr = [NSString stringWithFormat: @"background-color:%@;", htmlColorTable[(color >> 4)]];
	} else {
	    if ((color >> 4) != h_default_foreground)
		fgStr = [NSString stringWithFormat: @"color:%@;", htmlColorTable[(color >> 4)]];
	    if ((color & 0xF) != h_default_background)
		bgStr = [NSString stringWithFormat: @"background-color:%@;", htmlColorTable[(color & 0xF)]];
	}
	if (fontWtStr || fontStyleStr || fontFixedStr || fgStr || bgStr) {
	    NSString *ts = [NSString stringWithFormat: @"</span><span style=\"%@%@%@%@%@\">", fontWtStr, fontStyleStr, fontFixedStr, fgStr, bgStr];
	    [ipzBufferStr appendString: ts];
//	    NSLog(ts);
	}

	currTextStyle = style;
	currColor = color;
    }
    pthread_mutex_unlock(&outputMutex);
}


void iphone_putchar(char c) {
    char *s = NULL;
    pthread_mutex_lock(&outputMutex);
    BOOL isStatus = (cwin == 1 || cwin == 7);
    NSMutableString *bufferStr = isStatus ? ipzStatusStr : ipzBufferStr;

    if (isStatus) {
	if (!gUseHTML) {
	    [bufferStr appendFormat:@"%c", c];
	    pthread_mutex_unlock(&outputMutex);
	    return;
	}
    }
    else
	putchar(c);
    
    if (gUseHTML) {
	switch (c) {
	    case ' ':
		s = "&nbsp;";
		break;
	    case '\n':
		s = "<br>"; // breaks end the current span as well
		currColor = 0;
		currTextStyle = 0;
		break;
	    case '<':
		s = "&lt;";
		break;
	    case '>':
		s = "&gt;";
		break;
	    case '&':
		s = "&amp;";
		break;
	    default:
		break;
	}
    }
    if (s)
	[bufferStr appendFormat:@"%s", s];
    else
	[bufferStr appendFormat:@"%c", c];
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

@interface Foo : NSObject {
id m_delegate;
}
-(BOOL)respondsToSelector:(SEL)sel;
- (void)forwardInvocation:(NSInvocation *)anInvocation;
@end

@implementation Foo
-(BOOL)respondsToSelector:(SEL)sel {
    printf("FOO respoondsToSel:%s\n", sel);
    return YES;
}
- (void)forwardInvocation:(NSInvocation *)anInvocation {
  [m_delegate forwardInvocation:anInvocation];
  return;
}
- (void)setDelegate:(id)del {
NSLog(@"setdel %@\n", del);
    m_delegate = del;
}
#if 0
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
NSLog(@"msfs: sel: %s %@\n", aSelector, m_delegate);
    if ([[self class] instancesRespondToSelector:aSelector])
	return [[self class] instanceMethodSignatureForSelector:aSelector];
 //   if ([[m_delegate class] instancesRespondToSelector:aSelector])
	return [[m_delegate class] instanceMethodSignatureForSelector:aSelector];
    return nil;
}
#endif
-(BOOL)shouldSuggestUserEnteredString: (NSString*)str {
NSLog(@"ssss");
    return YES;
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
	if (gUseHTML) {
	    [m_statusLine setBackgroundColor: bgColor];
	    [m_statusLine setTextColor: fgColor];
	} else {
	    [m_statusLine setBackgroundColor: fgColor];
	    [m_statusLine setTextColor: bgColor];
	}
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
	[self setFont: @"helvetica"];
	[self setFontSize: 12];
	if (gUseHTML) {
	    [m_storyView setHTML: htmlPreamble];
	    }

	// [m_storyView setEnabledGestures: 3]; // I pinch!
	
	[self addSubview: m_storyView];
	[self addSubview: m_statusLine];

	[self loadPrefs];
	
	[FrotzKeyboard initImplementationNow];
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
    if (!gUseHTML)
	[m_storyView becomeFirstResponder];
    [[[m_storyView _webView] webView] moveToEndOfDocument:self];
}

-(void) setBackgroundColor: (CGColorRef)color {
    [m_storyView setBackgroundColor: color];
    [m_background setBackgroundColor: color];
    if (gUseHTML) 
	[m_statusLine setBackgroundColor: color];
    else
	[m_statusLine setTextColor: color];
}
-(void) setTextColor: (CGColorRef)color {
    [m_storyView setTextColor: color];
    if (gUseHTML)
	[m_statusLine setTextColor: color];
    else
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
	    //[[m_keyb sharedInstance] showLayout:[UIKeyboardLayoutQWERTYLandscape class]];
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
	    //[[m_keyb sharedInstance] showLayout:[UIKeyboardLayoutQWERTY class]];
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

char *tempStatusLineScreenBuf() {
    static char buf[MAX_ROWS * MAX_COLS];
    int i, j=0;
    for (i=0; i < iphone_top_win_height; ++i) {
	for (j=0; j < h_screen_cols; ++j) {
	    char c = (char)screen_data[i * MAX_COLS + j];
	    if (i == cursor_row && j == cursor_col && c == ' ')
		c = '#';
	    buf[i * (h_screen_cols+1) + j] = c;
	}
	buf[i*(h_screen_cols+1) + j] = '\n';
    }
    
    buf[i*(h_screen_cols+1)] = '\0';	
    return buf;
}

NSMutableString *tempStatusLineHTMLScreenBuf() {
    NSMutableString *buf = [[NSMutableString alloc] init];
    [buf setString: @""];
    int i, j=0, prevStyle=(screen_data[0] >> 8) & REVERSE_STYLE, style=0;
    char *elem;
    elem = "span";
    for (i=0; i < iphone_top_win_height; ++i) {
	if (prevStyle & REVERSE_STYLE) {
	    [buf appendFormat: @"<%s style=\"color:%@; background-color:%@; position:absolute; left:%dpx; top:%dpx; \">", elem,
		htmlColorTable[(currColor & 0xF)], htmlColorTable[(currColor >> 4)], 0, i*kFixedFontPixelHeight];
	}
	for (j=0; j < h_screen_cols; ++j) {
	    char c = (char)screen_data[i * MAX_COLS + j];
	    
	    style = (screen_data[i * MAX_COLS + j] >> 8) & REVERSE_STYLE;
	    putchar(c);
	    if (style != prevStyle) {
		// the position: absolute crap is to work around an annoying kerning bug where fixed width fonts
		// on the phone don't actually seem to be fixed width.  We reset the position to where it should
		// be anytime we enter reverse style, or when we display a space when already in reverse style.
		if (style & REVERSE_STYLE) {
		    [buf appendFormat: @"<%s style=\"color:%@; background-color:%@; position:absolute; left:%dpx; top:%dpx;\">", elem,
		     htmlColorTable[(currColor & 0xF)], htmlColorTable[(currColor >> 4)], (j) * kFixedFontWidth, i*kFixedFontPixelHeight];
		} else {
		    [buf appendFormat: @"</%s>", elem];
		}
		prevStyle = style;
	    } else if (c==' ') {
		// first space after non-space when in reverse mode, reset pos
		if ((style & REVERSE_STYLE) && j > 1 && (char)screen_data[i * MAX_COLS + j-1]!=' ') {
		    [buf appendFormat: @"&nbsp;&nbsp;</%s><%s style=\"color:%@; background-color:%@; position:absolute;left:%dpx; top:%dpx;\">", elem, elem,
		     htmlColorTable[(currColor & 0xF)], htmlColorTable[(currColor >> 4)], (j) * kFixedFontWidth, i*kFixedFontPixelHeight];
		}
	    }
	    if (i == cursor_row && j == cursor_col && c == ' ')
		c = '#';
	    if (c==' ')
		[buf appendString: @"&nbsp;"];
	    else if (c=='>')
		[buf appendString: @"&gt;"];
	    else if (c=='<')
		[buf appendString: @"&lt;"];
	    else if (c=='&')
		[buf appendString: @"&amp;"];
	    else
		[buf appendFormat: @"%c", c];
	}
	[buf appendString: @"&nbsp;&nbsp;&nbsp;&nbsp;"];
	[buf appendString: @"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"];
	if (i < iphone_top_win_height-1)
	    [buf appendString: @"<br>"];
	putchar('\n');
	if (style & REVERSE_STYLE)
	    [buf appendFormat: @"</%s>", elem];
    }
    return buf;
}

-(void)printText: (id)unused {
    static int prevTopWinHeight = 1;
    static int continuousPrintCount = 0;
    static int grewStatus = 0;
    int textLen = [ipzBufferStr length];
    int statusLen = [ipzStatusStr length];

    if (iphone_top_win_height<0 || (textLen > 1 && !grewStatus || top_win_height > prevTopWinHeight) && prevTopWinHeight != top_win_height) {
	if (top_win_height > 1 && top_win_height > prevTopWinHeight)
	    grewStatus = 1;
	else
	    grewStatus = 0;
	topWinSize = 1 + top_win_height * kFixedFontPixelHeight;
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
    textLen = [ipzBufferStr length];
    if (ipzDeleteCharCount) { // !!! won't work in html mode
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
	if (gUseHTML) {
	    [m_statusLine setMarginTop: 0];
	    [m_statusLine setHTML: tempStatusLineHTMLScreenBuf()];
	}
	else {
	    char * s = tempStatusLineScreenBuf();
	    [ipzStatusStr setString: @""];
	    [ipzStatusStr appendFormat:@"%s", s];
	    [m_statusLine setText: ipzStatusStr];
	}
	[ipzStatusStr setString: @""];
    } 
    if (ipzAllowInput & kIPZRequestInput) {
	grewStatus = 0;
	ipzAllowInput |= kIPZAllowInput;
    }
    pthread_mutex_unlock(&outputMutex);
#ifdef IPHONE_MORE_PROMPT_ENABLED
    if (continuousPrintCount)
	[m_storyView scrollToMakeCaretVisible: YES];
#endif
    if (do_filebrowser == 1) {
	do_filebrowser = 2;
	[[self mainView] openFileBrowser];
    }
    if (finished) {
	[[self mainView] performSelector:@selector(abortToBrowser:) withObject:nil afterDelay:0.25];
	}
    else
	[self performSelector:@selector(printText:) withObject:nil afterDelay:0.05];
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
		iphone_top_win_height = -1;
		top_win_height = [[dict objectForKey: @"statusWinHeight"] longValue];
		cwin = [[dict objectForKey: @"currentWindow"] longValue];
		cursor_row = [[dict objectForKey: @"cursorRow"] longValue];
		cursor_col = [[dict objectForKey: @"cursorCol"] longValue];
		statusStr = [dict objectForKey: @"statusWinContents"];		
		if (gUseHTML)  {
		    [m_storyView setHTML: @""];
		    [m_storyView setText: [dict objectForKey: @"storyWinContents"]];
		    if (htmlBuf)
			[htmlBuf release];
		    htmlBuf = [[NSMutableString alloc] initWithString: htmlPreamble];
		    [htmlBuf appendFormat: @"%@", [m_storyView HTML]];
		    [m_storyView setHTML: htmlBuf];
		    }
		else
		    [m_storyView setText: [dict objectForKey: @"storyWinContents"]];
		[dict release];
		
		h_screen_rows = iphone_textview_height;
		h_screen_cols = iphone_textview_width;
		h_screen_width = h_screen_cols;
		h_screen_height = h_screen_rows;

		do_autosave = 0;
		iphone_init_screen();
		do_autosave = 1;
		resize_screen();
		restart_screen();
		split_window(top_win_height-1);

		int l = [statusStr length], off;
		int style = (top_win_height <= 2) ? (REVERSE_STYLE << 8) : 0;
		i = j = 0;
		for (off = 0; off < l; ++off) {
		    char c = [statusStr characterAtIndex: off];
		    if (c=='\n') {
			for (; j < MAX_COLS; ++j)
			    screen_data[i * MAX_COLS + j] = ' ' | style;
			j = 0;
			++i;
			continue;
		    } else if (i == cursor_row && j == cursor_col && c == '#')
			c = ' ';
		    screen_data[i * MAX_COLS + j] = c | style;
		    ++j;
		}
		for (; i < MAX_ROWS; ++i) {
		    for (j=0; j < MAX_COLS; ++j)
			screen_data[i * MAX_COLS + j] = ' ';
		}
		iphone_ioinit();
		[ipzStatusStr setString: @" \b"];

		[fileMgr removeFileAtPath: storySIPPath handler:nil];
		strcpy(storyNameBuf, [m_currentStory UTF8String]);
		pthread_create(&m_storyTID, NULL, interp_cover_autorestore, (void*)storyNameBuf);
		[m_keyb show:m_storyView];
		[m_storyView becomeFirstResponder];
		CGSize sz = [m_storyView contentSize];
		CGRect rect = CGRectMake(0, sz.height, 1, 1);
		[m_storyView scrollRectToVisible: rect animated:YES];
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
    if (gUseHTML) {
	if (htmlBuf) {
	    [htmlBuf release];
	    htmlBuf = NULL;
	}
	[m_storyView setHTML: htmlPreamble];
    }
    else
	[m_storyView setText: @""];
    top_win_height = 0;
}

-(void) suspendStory {
    [ipzInputBufferStr setString: @""];   
    [ipzInputBufferStr appendFormat: @"%c", ZC_AUTOSAVE];
    if (m_currentStory && ([m_currentStory length] > 0)) {
	NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity: 10];
	[dict setObject: m_currentStory forKey: @"storyPath"];
	[dict setObject: [NSNumber numberWithInt: iphone_top_win_height] forKey: @"statusWinHeight"];
	[dict setObject: [NSNumber numberWithInt: cwin] forKey: @"currentWindow"];
	[dict setObject: [NSNumber numberWithInt: cursor_row] forKey: @"cursorRow"];
	[dict setObject: [NSNumber numberWithInt: cursor_col] forKey: @"cursorCol"];
	char *statusBuf = tempStatusLineScreenBuf();
	[dict setObject: [NSString stringWithUTF8String: statusBuf]  forKey: @"statusWinContents"];
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
    if (gUseHTML) {
	//_scrollerFlags.scrollingDisabled = 1;
	if (!htmlBuf)
	    htmlBuf = [[NSMutableString alloc] initWithString: htmlPreamble];

	[htmlBuf appendString: text];
	[m_body setInnerHTML: htmlBuf];
	[m_bridge updateLayout];
	[self webViewDidChange: nil];
	//NSLog(@"%@", text);
	typedef id DOMRange;
	DOMRange *range = [[[[[self _webView] webView] selectedFrame] DOMDocument] createRange];
	[range setStartAfter: [[[[[self _webView] webView] selectedFrame] DOMDocument] body]];
	[range setEndAfter: [[[[[self _webView] webView] selectedFrame] DOMDocument] body]];
	[m_bridge setSelectedDOMRange: range affinity:0 closeTyping: NO];
	[self setEditable: YES];
	[m_bridge setCaretVisible: YES];
	[[[self _webView] webView] moveToEndOfDocument:self];
    } else {
	[[[self _webView] webView] moveToEndOfDocument:self];
	[[self _webView] insertText:text];
    }
#endif
}
@end

@implementation UIStatusLine
- (void)insertText:(NSString*)text
{
    if (0 && gUseHTML) {
    } else {
	[[[self _webView] webView] moveToEndOfDocument:self];
	[[self _webView] insertText:text];
	[self scrollToEnd];
    }
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
	if ([text isEqualToString: @"\n"])
	    [htmlBuf setString: [self HTML]];
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

