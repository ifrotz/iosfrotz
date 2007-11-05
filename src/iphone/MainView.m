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

#import "MainView.h"
#import "FrotzApplication.h"
#import <UIKit/UIAnimator.h>
#import <UIKit/UITransformAnimation.h>
#import <UIKit/UIView-Geometry.h>
#import <UIKit/UINavigationItem.h>
//#import <UIKit/UIWebView.h>

const float kNavBarSize = 40.0f;

@implementation MainView 
- (id)initWithFrame:(struct CGRect)rect {
    if ((self == [super initWithFrame: rect]) != nil) {
    	id fileMgr = [NSFileManager defaultManager];	
	if ([fileMgr fileExistsAtPath: @kFrotzOldDir] &&
	    ![fileMgr fileExistsAtPath: @kFrotzDir]) {
	    rename(kFrotzOldDir, kFrotzDir);
	    sync();
	}
     	m_background = [[UIView alloc] initWithFrame: CGRectMake(0.0f, 0.0f, 480.0f, 480.0f)];
	float bgRGB[4] = {0.0, 0.0, 0.0, 1.0};
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	struct CGColor *bgColor = CGColorCreate(colorSpace, bgRGB);
	[m_background setBackgroundColor: bgColor];
	[self addSubview: m_background];
   
	rect.origin.y = 0.0f; // UI Status bar
	m_navBar = [[UINavigationBar alloc] initWithFrame:
	    CGRectMake(rect.origin.x, rect.origin.y, rect.size.width, kNavBarSize)];
	[m_navBar setBarStyle: 1];
	[m_navBar setDelegate: self];
	[m_navBar enableAnimation];
	
	CGRect r2 = rect;
//	r2.size.width = r2.size.height;
	m_transitionView = [[UITransitionView alloc] initWithFrame: 
	    CGRectMake(rect.origin.x, kNavBarSize, r2.size.width, rect.size.height - kNavBarSize)];

	m_storyBrowser = [[StoryBrowser alloc] initWithFrame:
	    CGRectMake(0, 0, rect.size.width, rect.size.height - kNavBarSize) withPath: storyGamePath];
	m_storyMainView = [[StoryMainView alloc] initWithFrame:
	    CGRectMake(0, 0, rect.size.width, rect.size.height - kNavBarSize)];
	[m_storyMainView setMainView: self];
	
	[m_storyBrowser setDelegate: self];
	
	m_mode = kModeUninit;
	[self addSubview: m_navBar];
	[self addSubview: m_transitionView];
        [self updateNavBarButtons: kModeSelectStory];

	if (![m_storyMainView autoRestoreSession]) {
	    [m_transitionView transition:1 toView:m_storyBrowser];
	} else {
	    [self updateNavBarButtons: kModePlayStory];
	    [m_transitionView transition:1 toView:m_storyMainView];
	}
	CGColorRelease(bgColor);
	CGColorSpaceRelease(colorSpace);
    }
    return self;
}

-(int) orientation {
    return m_orient;
}

-(void) updateOrientation: (int)orient {
    if (m_mode != kModePlayStory)
	return;
    switch (orient)
    {
	    case 1:
		    orient = 0;
		    break;
	    case 3:
		    orient = 90;
		    break;
	    case 4:
		    orient = -90;
		    break;
	    case 2:
		    //orient = 180;
		    //break;
	    default: 
		    return;
    }
    if (orient != m_orient) {
	printf ("device orientation changed %d\n", orient);
	fflush(stdout);
	if (orient != m_orient) {
	    BOOL landscape = (orient == 90 || orient == -90);
	#if 0
	    UITransformAnimation *translate = [[UITransformAnimation alloc] initWithTarget: self];
	    [translate setStartTransform: CGAffineTransformMakeRotation(m_orient * M_PI / 180.0)];
	    [translate setEndTransform: CGAffineTransformMakeRotation(orient * M_PI / 180.0)];
	    [translate setDelegate: self];
	    UIAnimator *anim = [[UIAnimator alloc] init];
	    [anim addAnimation:translate withDuration:0.25 start:YES];
	#else
	    float statusBarShownAdjust = gShowStatusBarInLandscapeMode ? kUIStatusBarHeight : 0.0f;
	    float screenHeight = 480.0f - statusBarShownAdjust;
	    // show/hide the status bar
	    if (!gShowStatusBarInLandscapeMode)
		[theApp setStatusBarMode:landscape ? 2 : 1 duration:0.0f];
	    if (!landscape || orient == -m_orient) {
		[self setTransform: CGAffineTransformMakeRotation(0.0f)];
		[self setFrame: CGRectMake(0.0f, kUIStatusBarHeight, 320.0f, 480.0f)];
		[self setTransform: CGAffineTransformMakeRotation(0.0f)];
		if (!landscape)
		    [self addSubview: m_navBar];
	    }
	    if (landscape) {
		float landScreenHeight = 320.0f + kNavBarSize;
		[self setFrame: CGRectMake(gShowStatusBarInLandscapeMode ? kUIStatusBarHeight : 0.0f, 0.0f,
					   screenHeight, landScreenHeight)];
		if (orient == 90)
		    [self setTransform: CGAffineTransformRotate(
			CGAffineTransformMakeTranslation(-60.0 - statusBarShownAdjust/2, 60.0 + statusBarShownAdjust/2), orient * M_PI / 180.0f)];
		else {
		    [self setTransform: CGAffineTransformRotate(
			CGAffineTransformMakeTranslation(-100.0f - statusBarShownAdjust/2, 60.0f + statusBarShownAdjust/2), orient * M_PI / 180.0f)];
		}

		[m_navBar removeFromSuperview];
	    } 
	#endif
	    m_orient = orient;
	    if (landscape)
		[m_transitionView setFrame: CGRectMake(0,40,480,480)];
	    else
		[m_transitionView setFrame: CGRectMake(0,40,320,480)];

	    [m_transitionView transition:6 toView:m_storyMainView];
	    [m_storyMainView setLandscape: (m_orient == 90 || m_orient == -90)];
	}
    }
}

-(void)updateNavBarButtons: (int)newMode {

    switch (newMode) {
	case kModeSelectStory:
	    if (m_mode == kModeUninit)
		[m_navBar pushNavigationItem: [[UINavigationItem alloc] initWithTitle: @"Story List"]];
	    else if (newMode != m_mode)
		[m_navBar popNavigationItem];
	    [m_navBar showButtonsWithLeftTitle:nil rightTitle:@"Refresh" leftBack: NO];
	    break;
	case kModeSelectColor:
	    if (newMode != m_mode)
		[m_navBar pushNavigationItem: [[UINavigationItem alloc] initWithTitle:
		    m_whichColor ? @"Background " : @"Text Color"]];
	    [m_navBar showButtonsWithLeftTitle:@"Cancel" rightTitle:@"Select" leftBack: YES];
	    break;
	case kModeSelectFont:
	    if (newMode != m_mode)
		[m_navBar pushNavigationItem: [[UINavigationItem alloc] initWithTitle: @"Choose Font"]];
	    [m_navBar showButtonsWithLeftTitle:@"Cancel" rightTitle:@"Select" leftBack: YES];
	    break;
	case kModePrefs:
	    if (m_mode == kModePlayStory)
		[m_navBar pushNavigationItem: [[UINavigationItem alloc] initWithTitle: @"Settings"]];
	    else if (newMode != m_mode)
		[m_navBar popNavigationItem];
	    [m_navBar showButtonsWithLeftTitle:@"Back" rightTitle:nil leftBack: YES];
	    break;
	case kModeResumeStory:
	case kModePlayStory:
	    if (m_mode != kModePlayStory) {
		if (newMode == kModeResumeStory) {
		    [m_navBar popNavigationItem];
		    newMode = kModePlayStory;
		} else
		    [m_navBar pushNavigationItem: [[UINavigationItem alloc] initWithTitle: @"Frotz"]];
	    }
	    [m_navBar showButtonsWithLeftTitle:@"Story List" rightTitle:@"Settings" leftBack: YES];
	    break;
	case kModeSelectFile:
	    if (newMode != m_mode)
		[m_navBar pushNavigationItem: [[UINavigationItem alloc] initWithTitle: @"Saved Games"]];
	    [m_navBar showButtonsWithLeftTitle:@"Cancel" rightTitle:nil leftBack: YES];
	    break;
	default:
	    [m_navBar showButtonsWithLeftTitle:nil rightTitle:nil leftBack: YES];
	    break;
    }
    m_mode = newMode;
}

-(void)storyBrowser:browser storySelected:storyPath {
    [self updateNavBarButtons: kModePlayStory];
    [m_transitionView transition:1 toView:m_storyMainView];
    [m_storyMainView setCurrentStory: storyPath];
    [m_storyMainView launchStory];
}

-(void) suspendStory {
    [m_storyMainView suspendStory];
}

- (void)dealloc {
    [m_storyBrowser release];
    [m_storyMainView release];
    [m_navBar release];
    [m_fontc release];
    [m_keyb release];
    [m_fileBrowser release];
    [m_colorPicker release];
    [m_prefTable release];
    [m_background release];
    [super dealloc];
}


-(void)showKeyboardForFontChooser:(id)sender
{
    m_keyb = [[UIKeyboard alloc] initWithFrame: CGRectMake(0.0f, 204.0f, 320.0f, 276.0f)];
    [sender addSubview: m_keyb];
    [m_keyb activate]; 
}

-(void)hideKeyboardForFontChooser:(id)sender
{
    if (m_keyb) {
	[m_keyb deactivate]; 
	[m_keyb removeFromSuperview];
	[m_keyb release];
	m_keyb = NULL;
    }
}

OBJC_EXPORT double objc_msgSend_fpret(id self, SEL op, ...);

-(void)navigationBar:(UINavigationBar *)navbar buttonClicked:(int)button {
    // right button=0, left=1
 
    switch (m_mode) {
	case kModeSelectStory:
	    if (button == 0) // refresh
		[m_storyBrowser reloadData];
	    break;
	case kModeSelectColor:
	    if (button == 0 && m_selectedColor) {
	        CGColorRef color = CGColorCreateCopy(m_selectedColor);
		if (m_whichColor)
		    [m_storyMainView setBackgroundColor: color];
		else
		    [m_storyMainView setTextColor: color];
	    }
	    [m_transitionView transition:2 toView :m_prefTable];

	    [self updateNavBarButtons: kModePrefs];
	    break;
	case kModeSelectFont:
	    if (button == 0) {
		//float size = [m_fontc selectedSize];
		float size = objc_msgSend_fpret(m_fontc, @selector(selectedSize));
		NSString *fontName = [m_fontc selectedFamilyName];
		printf("Chose font: %s %f\n", [fontName UTF8String], size);
		
		if (fontName && [fontName compare: @""]!=NSOrderedSame)
		    [m_storyMainView setFont: [m_fontc selectedFamilyName]];
		if (size)
		    [m_storyMainView setFontSize: size];
		    
		[[[m_storyMainView storyView] _webView] insertText: @" "];
		[[[m_storyMainView storyView] _webView] deleteBackward];
		[[m_storyMainView storyView] scrollToMakeCaretVisible: YES];
	    }
	    [m_transitionView transition:2 toView: m_prefTable];
	    [self updateNavBarButtons: kModePrefs];
	    break;
	case kModePrefs:
	    [m_storyMainView savePrefs];
	    [m_transitionView transition:2 toView:m_storyMainView];
	    [m_storyMainView scrollToEnd];
	    [self updateNavBarButtons: kModeResumeStory];
	    break;
	case kModePlayStory:
	    if (button == 0) {
		if (!m_prefTable) {
		    m_prefTable = [[UIPreferencesTable alloc] initWithFrame: CGRectMake(0.0f, 20.0f, 320.0f, 480.0f)];
		    m_prefButton[0] = [[[UIPreferencesTableCell alloc] init] retain];
		    [m_prefButton[0] setTitle: @"Font"];
		    [m_prefButton[0] setTarget: self];
		    m_prefButton[1] = [[[UIPreferencesTableCell alloc] init] retain];
		    [m_prefButton[1] setTitle: @"Text Color"]; 
		    m_prefButton[2] = [[[UIPreferencesTableCell alloc] init] retain];
		    [m_prefButton[2] setTitle: @"Background Color"]; 

		    [m_prefTable setDelegate: self];
		    [m_prefTable setDataSource: self];
		    [m_prefTable reloadData];
		}
		[m_transitionView transition:1 toView:m_prefTable];
		[self updateNavBarButtons: kModePrefs];
	    } else {   
		UIAlertSheet *sheet = [[UIAlertSheet alloc] initWithFrame: CGRectMake(0, 240, 320, 240)];
		[sheet setTitle:@"Abandon Story"];
		[sheet setBodyText:[NSString stringWithFormat:@"Do you want to quit the current story and select a new one?\n"]];
		[sheet addButtonWithTitle:@"OK"];
		[sheet addButtonWithTitle:@"Cancel"];
		[sheet setDelegate: self];
		[sheet presentSheetFromAboveView: self];
	    }
	    break;
	case kModeSelectFile:
	    if (button == 1)
		[self fileBrowser: m_fileBrowser fileSelected: nil];
	    break;
	default:
	    [navbar removeFromSuperview];
	    break;
    }
}

- (void)abortToBrowser {
    if (m_mode == kModePlayStory) {
	[m_storyMainView abandonStory];
	[[NSRunLoop currentRunLoop] cancelPerformSelectorsWithTarget: self];

	[self updateNavBarButtons: kModeSelectStory];

	[m_transitionView transition:2 toView:m_storyBrowser];
    } else
	NSLog(@"Ignore abortTobrowser async call\n");
}

- (void)abortToBrowser : (id)unused {
    [self abortToBrowser];
}

- (void)alertSheet:(UIAlertSheet *)sheet buttonClicked:(int)button {
    [sheet dismiss];
    if (button == 1) {
	[self abortToBrowser];
    }
}

extern int do_filebrowser;
extern NSString *storySavePath;
extern char iphone_filename[];

-(void) openFileBrowser {
    m_fileBrowser = [[FileBrowser alloc] initWithFrame: CGRectMake(0, 40, 320, 440)];

    [m_fileBrowser setPath: storySavePath];
    [m_fileBrowser setDelegate: self];    
    [m_fileBrowser reloadData];

    [self updateNavBarButtons: kModeSelectFile];
    
    [self addSubview: m_fileBrowser];
}

#if 0
- (BOOL)respondsToSelector:(SEL)aSelector {
    NSLog(@"Request for selector: %@\n", NSStringFromSelector(aSelector)); fflush(stdout);
    return [super respondsToSelector:aSelector];
}
#endif

- (void)fileBrowser: (FileBrowser *)browser fileSelected:(NSString *)file {
    [m_fileBrowser removeFromSuperview];
    if (file)
	strcpy(iphone_filename, [file UTF8String]);
    else
	*iphone_filename = '\0';
    [m_fileBrowser release];
    m_fileBrowser = NULL;
    [self updateNavBarButtons: kModeResumeStory];
    do_filebrowser = 0;
}

- (BOOL) table:(id)sender showDisclosureForRow:(int)row {
    return (row > 0);
}
- (BOOL) table:(id)sender disclosureClickableForRow:(int)row {
    return (row > 0);
}

- (void)tableRowSelected: (NSNotification*)notif {
    int row = [m_prefTable selectedRow];
    if (row && m_prefButton[row])
	[m_prefButton[row] setSelected: NO withFade: NO];
    switch (row) {
	case 1: {
	    if (!m_fontc)
		m_fontc = [[UIFontChooser alloc] initWithFrame: CGRectMake(0.0f, 40.0f, 320.0f, 480.0f - 40 - 24)];
	    [self updateNavBarButtons: kModeSelectFont];

	    [m_fontc selectFamilyName: [m_storyMainView font]];
	    [m_fontc selectSize: [m_storyMainView fontSize]];
	    [m_transitionView transition:1 toView:m_fontc];
	    [m_fontc setDelegate: self];
	    [m_fontc becomeFirstResponder];
	} break;
	case 2:
	case 3: {
	    if (!m_colorPicker)
		m_colorPicker = [[ColorPicker alloc] initWithFrame: CGRectMake(0.0f, 0.0f, 320.0f, 480.0f)];
	    [m_colorPicker setDelegate: self];
	    struct CGColor *color;

	    m_whichColor = row-2;
	    if (m_whichColor)
		color = [m_storyMainView backgroundColor];
	    else
		color = [m_storyMainView textColor];
	    [m_colorPicker setColor: color];
	    [m_transitionView transition:1 toView:m_colorPicker];

	    [self updateNavBarButtons: kModeSelectColor];
	} break;
    }
}

- (int) numberOfGroupsInPreferencesTable: (id)sender {
    return 1;
}
- (NSString*)preferencesTable:(id)sender titleForGroup:(int)group {
    return @"Frotz Settings (Version " @IPHONE_FROTZ_VERS @")";
}
- (int)preferencesTable:(id)sender numberOfRowsInGroup:(int)group {
    return 3;
}
- (id)preferencesTable:(id)sender cellForRow:(int)row inGroup:(int)group {
    return m_prefButton[row];
}

- (void)colorPicker:(id)sender selectedColor:(CGColorRef)color {
    if (m_selectedColor)
	CGColorRelease(m_selectedColor);
    m_selectedColor = CGColorCreateCopy(color);
}

@end
