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
// Pilfered from NES.app.
// Many thanks to its authors.

#import <UIKit/UIKit.h>


typedef enum  { kFBHidden, kFBShown, kFBDoShowRestore, kFBDoShowSave, kFBDoShowScript, kFBDoShowViewScripts  } FileBrowserState;

@protocol TextFileBrowser
-(NSString*)textFileBrowserPath;
@end


@protocol FileSelected
@optional
-(void)fileBrowser:(id)browser fileSelected: (NSString*)filePath;
-(void)fileBrowser:(id)browser deleteFile: (NSString*)filePath;
@end

@interface FileBrowser : UIViewController <UITextFieldDelegate, UITableViewDataSource, UITableViewDelegate>
{
	UITableViewController *m_tableViewController;
	NSMutableArray *m_extensions;
	NSMutableArray *m_files;
	NSString *m_path;
	int m_rowCount;
	id m_delegate;
	FileBrowserState m_dialogType;
	UIView *m_backgroundView;
	UITableView *m_tableView;
	UITextField *m_textField;
	UIButton *m_saveButton;
	int m_textFileCount;
}
- (id)initWithDialogType:(FileBrowserState)dialogType;
- (NSString *)path;
- (void)setPath: (NSString *)path;
- (void)reloadData;
- (void)setDelegate:(id<FileSelected>)delegate;
- (id<FileSelected>)delegate;
- (NSInteger) tableView:(UITableView*)tableView numberOfRowsInSection: (NSInteger)section;
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView;
- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath;
- (NSString *)selectedFile;
- (void)commit:(id)sender;
- (void)doneWithTextFile:(id)sender;
- (void)addExtension: (NSString *)extension;
- (int)textFileCount;
@end
