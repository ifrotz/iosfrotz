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
#import "StoryMainView.h"
#import "MainView.h"
#include <pthread.h>

int iphone_textview_width = 54, iphone_textview_height = 18;
int do_autosave = 0, autosave_done = 1;
int do_filebrowser = 0;
static int filebrowser_allow_new = 0;

char iphone_filename[256];

const int kFixedFontSize = 9;
const int kFixedFontPixelHeight = 11;

NSString *storyGamePath   = @kFrotzDir @kFrotzGameDir;
NSString *storySavePath   = @kFrotzDir @kFrotzSaveDir;
NSString *storySIPPath    = @kFrotzDir @kFrotzSaveDir @"FrotzSIP.plist";
NSString *storySIPSavePath= @kFrotzDir @kFrotzSaveDir kFrotzAutoSaveFile;
const char *AUTOSAVE_FILE =  kFrotzDir  kFrotzSaveDir kFrotzAutoSaveFile;  // used by interpreter from z_save

NSMutableString *ipzBufferStr = NULL, *ipzStatusStr = NULL, *ipzInputBufferStr = NULL;
int ipzDeleteCharCount = 0;

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


void run_interp(const char *story, bool autorestore) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    char *argv[] = {"iFrotz", NULL };

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

@implementation StoryMainView 
- (id)initWithFrame:(struct CGRect)rect {
    const kStatusLineYPos = 0.0f;
    const kStatusLineHeight = 24.0f;
    if ((self == [super initWithFrame: rect]) != nil) {
	UIView *background = [[UIView alloc] initWithFrame: rect];
	float fgRGB[4] = {0.0, 0.0, 0.1, 1.0};
	float bgRGB[4] = {1.0, 1.0, 0.9, 1.0};
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	struct CGColor *bgColor = CGColorCreate(colorSpace, bgRGB);
	struct CGColor *fgColor = CGColorCreate(colorSpace, fgRGB);
	[background setBackgroundColor: bgColor];
	[self addSubview: background];

 	//printf ("storymainview rect: %f %f %f %f\n", rect.origin.x, rect.origin.y, rect.size.width, rect.size.height);

	id fileMgr = [NSFileManager defaultManager];
	
	if (![fileMgr fileExistsAtPath: @kFrotzDir]) {
	    [fileMgr createDirectoryAtPath: @kFrotzDir attributes: nil];
	}
	if (![fileMgr fileExistsAtPath: @kFrotzDir @kFrotzSaveDir]) {
	    [fileMgr createDirectoryAtPath: @kFrotzDir @kFrotzSaveDir attributes: nil];
	}

	chdir(kFrotzDir kFrotzSaveDir);
				
	m_statusLine = [[UIStatusLine alloc] initWithFrame: CGRectMake(0.0f, kStatusLineYPos, 500.0f, kStatusLineHeight)];
	//struct CGColor *origFg = [m_statusLine textColor], *origBg = [m_statusLine backgroundColor];
	[m_statusLine setBackgroundColor: fgColor];
	[m_statusLine setTextColor: bgColor];
	[m_statusLine setTextFont: @"CourierNewBold"];
	[m_statusLine setTextSize: kFixedFontSize];
	[m_statusLine setEditable: NO];
	
	m_storyView = [[UIStoryView alloc] initWithFrame:
	    CGRectMake(0.0f, kStatusLineYPos + kStatusLineHeight, 500.0f, rect.size.height - kStatusLineYPos /* - kStatusLineHeight */)];
	[m_storyView setBackgroundColor: bgColor];
	[m_storyView setTextColor: fgColor];
	[m_storyView setAllowsRubberBanding:YES];
	[m_storyView displayScrollerIndicators];

	[m_storyView setTextFont: @"helvetica"];
	[m_storyView setTextSize: 12];
	
	[self addSubview: m_storyView];
	[self addSubview: m_statusLine];
	
	m_keyb = [[FrotzKeyboard alloc] initWithFrame: CGRectMake(0.0f, rect.size.height, 320.0f, 236.0)];
	[self addSubview: m_keyb];
	[m_keyb setReturnKeyEnabled: YES];
	[m_storyView setKeyboard: m_keyb];
	[m_keyb setTapDelegate: m_storyView];
	
	[m_keyb activate];
	m_currentStory = [[NSMutableString stringWithString: @""] retain];
	
	[m_storyView becomeFirstResponder];
	
	[self performSelector:@selector(printText:) withObject:nil afterDelay:0.1];
	
    }
    return self;
}

-(void) setMainView: (MainView*)mainView {
    m_topView = mainView;
}

-(MainView*) mainView {
    return m_topView;
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

extern int finished; // set by z_quit

-(void)printText: (id)unused {
    static int prevTopWinHeight = 1;
    static int continuousPrintCount = 0;
    int textLen = [ipzBufferStr length];
    int statusLen = [ipzStatusStr length];
    if ((textLen > 0 || top_win_height > prevTopWinHeight) && prevTopWinHeight != top_win_height) {
	float topWinSize = 8 + top_win_height * kFixedFontPixelHeight;
	if (topWinSize > 204) topWinSize = 204;
	[m_statusLine setFrame: CGRectMake(0.0f, 0.0f, 500.0f,  topWinSize)];
	[m_storyView setFrame: CGRectMake(0.0f, topWinSize, 500.0f, 480.0f - 40.0f - (topWinSize) - 236)];
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
    if (finished) {
	[[self mainView] abortToBrowser];
    }
    else
	[self performSelector:@selector(printText:) withObject:nil afterDelay:0.01];
}


-(BOOL) autoRestoreSession {
    static char storyNameBuf[256];
    
    id fileMgr = [NSFileManager defaultManager];
    if ([fileMgr fileExistsAtPath: storySIPPath]) {
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
    printf ("launched tid %d\n", m_storyTID);
    [m_keyb show:m_storyView];
    [self performSelector:@selector(printText:) withObject:nil afterDelay:0.1];

}

-(void) abandonStory {
    [ipzInputBufferStr setString: @"\n\n"];   
    do_autosave = 0;
    z_quit();
    pthread_join(m_storyTID, NULL);
    [ipzInputBufferStr setString: @""];
    [m_currentStory setString: @""];
    [m_statusLine setText: @""];
    [m_storyView setText: @""];
    top_win_height = 0;
}

-(void) suspendStory {
    [ipzInputBufferStr setString: @""];   
    [ipzInputBufferStr appendFormat: @"%c", ZC_AUTOSAVE];

    if (m_currentStory && ([m_currentStory length] > 0)) {
	NSError *err = NULL;
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


-(void)mouseUp:(struct __GSEvent *)event
{
    if (![self isScrolling]) 
	[m_keyb toggle: self];
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

