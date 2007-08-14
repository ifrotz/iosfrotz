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
#import <UIKit/UITable.h>
#import <UIKit/UIPreferencesTable.h>
#import <UIKit/UIPreferencesTableCell.h>

@protocol StorySelected
-(void)storyBrowser:browser storySelected:storyPath;
@end

@interface StoryBrowser : UIView {
    UITable *_storyTable;

    NSString *_path;
    id _delegate;

    int m_numStories;
    NSArray *m_buttons;
    NSArray *m_storyNames;
}
- (id)initWithFrame:(CGRect)rect withPath:path;
- (NSString *)path;
- (void)setPath: (NSString *)path;
- (void)tableRowSelected: (NSNotification*)notif;
- (int) numberOfGroupsInPreferencesTable: (id)sender;
- (NSString*)preferencesTable:(id)sender titleForGroup:(int)group;
- (int)preferencesTable:(id)sender numberOfRowsInGroup:(int)group;
- (id)preferencesTable:(id)sender cellForRow:(int)row inGroup:(int)group;
- (void)reloadData;
- (void)setDelegate:(id)delegate;
- (NSString *)selectedStory;
@end
