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
#import <UIKit/UIWebView.h>

@implementation MainView 
- (id)initWithFrame:(struct CGRect)rect {
    const float kNavBarSize = 40.0f;
    if ((self == [super initWithFrame: rect]) != nil) {

    	id fileMgr = [NSFileManager defaultManager];	
	if ([fileMgr fileExistsAtPath: @kFrotzOldDir] &&
	    ![fileMgr fileExistsAtPath: @kFrotzDir]) {
	    rename(kFrotzOldDir, kFrotzDir);
	    sync();
	}
    
	_navBar = [[UINavigationBar alloc] initWithFrame:
	    CGRectMake(rect.origin.x, rect.origin.y, rect.size.width, kNavBarSize)];
	[_navBar setBarStyle: 1];
	[_navBar setDelegate: self];
	[_navBar showButtonsWithLeftTitle:nil rightTitle:@"Refresh" leftBack: YES];
	[_navBar enableAnimation];
	
	_transitionView = [[UITransitionView alloc] initWithFrame: 
	    CGRectMake(rect.origin.x, kNavBarSize, rect.size.width, rect.size.height - kNavBarSize)];

	_storyBrowser = [[StoryBrowser alloc] initWithFrame:
	    CGRectMake(0, 0, rect.size.width, rect.size.height - kNavBarSize) withPath: storyGamePath];
	_storyMainView = [[StoryMainView alloc] initWithFrame:
	    CGRectMake(0, 0, rect.size.width, rect.size.height - kNavBarSize)];
	[_storyMainView setMainView: self];
	
	[_storyBrowser setDelegate: self];
	
	[self addSubview: _navBar];
	[self addSubview: _transitionView];

	if (![_storyMainView autoRestoreSession]) {
	    _browsing = YES;
	    [_transitionView transition:1 toView:_storyBrowser];
	} else {
	    _browsing = NO;
	    [_navBar showButtonsWithLeftTitle:@"Story List" rightTitle:@"Set Font" leftBack: YES];
	    [_transitionView transition:1 toView:_storyMainView];
	}
    }
    return self;
}

-(void)storyBrowser:browser storySelected:storyPath {
    _browsing = NO;
    [_navBar showButtonsWithLeftTitle:@"Story List" rightTitle:@"Set Font" leftBack: YES];
    [_transitionView transition:1 toView:_storyMainView];
    [_storyMainView setCurrentStory: storyPath];
    [_storyMainView launchStory];
}

-(void) suspendStory {
    [_storyMainView suspendStory];
}

- (void)dealloc {
    [_storyBrowser release];
    [_storyMainView release];
    [_navBar release];
    [m_fontc release];
    [m_keyb release];
    [m_fileBrowser release];
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
    
    if (_browsing) { // browsing stories
	if (button == 0)
	    [_storyBrowser reloadData];
    }
    else if (!m_fontc) { // playing story
	if (button == 0) {
	    NSError *err;
	    m_fontc = [[UIFontChooser alloc] initWithFrame: CGRectMake(0.0f, 40.0f, 320.0f, 480.0f - 40 - 24)];
	    [_navBar showButtonsWithLeftTitle:@"Cancel" rightTitle:@"Select Font" leftBack: YES];
	    //	[m_fontc selectFamilyName: [[self textView] fontName];
	    //	[m_fontc setectSize: [[self textView] fontSize];
	    [[navbar superview] addSubview: m_fontc];
	    [m_fontc setDelegate: self];
	    [m_fontc becomeFirstResponder];
	} else {   
	    UIAlertSheet *sheet = [[UIAlertSheet alloc] initWithFrame: CGRectMake(0, 240, 320, 240)];
	    [sheet setTitle:@"Abandon Story"];
	    [sheet setBodyText:[NSString stringWithFormat:@"Do you want to quit the current story and select a new one?\n"]];
	    [sheet addButtonWithTitle:@"OK"];
	    [sheet addButtonWithTitle:@"Cancel"];
	    [sheet setDelegate: self];
	    [sheet presentSheetFromAboveView: self];
	}
    } else { // browsing fonts
	if (button == 0) {
	    //float size = [m_fontc selectedSize];
	    float size = objc_msgSend_fpret(m_fontc, @selector(selectedSize));
	    NSString *fontName = [m_fontc selectedFamilyName];
	    printf("Chose font: %s %f\n", [fontName UTF8String], size);
	    if (fontName && [fontName compare: @""]!=NSOrderedSame)
		[[_storyMainView storyView] setTextFont: [m_fontc selectedFamilyName]];
	    if (size)
		[[_storyMainView storyView] setTextSize: size];
	    [[[_storyMainView storyView] _webView] insertText: @" "];
	    [[[_storyMainView storyView] _webView] deleteBackward];
	    [[_storyMainView storyView] scrollToMakeCaretVisible: YES];
	}
	[m_fontc removeFromSuperview];
	[m_fontc release];
	[_navBar showButtonsWithLeftTitle:@"Story List" rightTitle:@"Set Font" leftBack: YES];
	m_fontc = NULL;
    }
}

- (void)abortToBrowser {
    [_storyMainView abandonStory];
    [_navBar showButtonsWithLeftTitle:nil rightTitle:@"Refresh" leftBack: YES];
    [_transitionView transition:2 toView:_storyBrowser];
    _browsing = YES;
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
    [_navBar showButtonsWithLeftTitle:nil rightTitle:nil leftBack: YES];
    
    [self addSubview: m_fileBrowser];
}

- (void)fileBrowser: (FileBrowser *)browser fileSelected:(NSString *)file {
    [m_fileBrowser removeFromSuperview];
    strcpy(iphone_filename, [file UTF8String]);
    [m_fileBrowser release];
    m_fileBrowser = NULL;
    [_navBar showButtonsWithLeftTitle:@"Story List" rightTitle:@"Set Font" leftBack: YES];
    do_filebrowser = 0;
}

@end
