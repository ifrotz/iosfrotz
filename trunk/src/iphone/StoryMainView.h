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
#import <UIKit/UIKit.h>
#import <UIKit/UIView.h>
#import <UIKit/UIKeyboard.h>
#import <UIKit/UIFontChooser.h>
#import <UIKit/UITextView.h>
#import "Cleanup.h" // header fixups borrowed from MobileTerminal

#include "iphone_frotz.h"

@class MainView;
@class FrotzTextSuggestionDelegate;
@class FrotzKeyboard;

@interface UIFrotzWinView : UITextView {
    FrotzKeyboard *m_keyb;
}
- (void)setKeyboard: (FrotzKeyboard*)keyboard;
- (void)scrollToEnd;
-(BOOL)webView:(id)sender shouldInsertText:(id)text replacingDOMRange:(id)range givenAction:(int)action;
-(BOOL)webView:(id)sender shouldDeleteDOMRange:(id)range;
@end

@interface UIStoryView : UIFrotzWinView
@end

@interface UIStatusLine : UIFrotzWinView
@end

@interface StoryMainView : UIView {
    MainView	*m_topView;

    UIStoryView *m_storyView;
    UIStatusLine *m_statusLine;
    UIView *m_background;
    FrotzKeyboard *m_keyb;
   
    NSMutableString *m_currentStory;
    
    NSMutableString *m_fontname;
    int m_fontSize;

    pthread_t m_storyTID;
    BOOL m_landscape;
}

-(UIStoryView*) storyView;
-(NSString*) currentStory;
-(void) setMainView: (MainView*)mainView;
-(MainView*) mainView;
-(void) setCurrentStory: (NSString*)story;
-(void) launchStory;
-(void) abandonStory;
-(BOOL) autoRestoreSession;
-(void) suspendStory;
-(void) savePrefs;
-(void) loadPrefs;
-(BOOL) landscape;
-(void) setLandscape: (BOOL)landscape;
-(NSMutableString*) font;
-(void) setFont: (NSString*)font;
-(int) fontSize;
-(void) setFontSize: (int)size;
-(void) setBackgroundColor: (CGColorRef)color;
-(void) setTextColor: (CGColorRef)color;
-(CGColorRef) backgroundColor;
-(CGColorRef) textColor;
-(void) scrollToEnd;
@end

extern const int kFixedFontSize;
extern const int kFixedFontPixelHeight;

extern NSString *storyGamePath;
extern NSString *storySIPPath;  // SIP == Story In Progress

