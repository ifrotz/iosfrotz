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

#import "FileBrowser.h"
#include "iosfrotz.h"

static NSString *kSaveExt = @".sav", *kAltSaveExt = @".qut";

@interface FileInfo : NSObject
{
    NSString *path;
    NSDate *modDate;
}
@property(nonatomic,strong) NSString *path;
@property(nonatomic,strong) NSDate *modDate;
-(NSComparisonResult)compare:(FileInfo*)other;
-(instancetype)initWithPath:(NSString*)path NS_DESIGNATED_INITIALIZER;
@end

@implementation FileInfo
@synthesize path;
@synthesize modDate;

-(instancetype)initWithPath:(NSString*)aPath {
    if ((self = [super init])) {
        self.path = aPath;
        NSDictionary *fileAttribs = [[NSFileManager defaultManager] fileAttributesAtPath: aPath traverseLink:NO];
        if (fileAttribs)
            self.modDate = fileAttribs[NSFileModificationDate];
    }
    return self;
}

-(NSComparisonResult)compare:(FileInfo*)other {
    return -[self.modDate compare: other.modDate];
}

@end


@implementation FileBrowser 
- (instancetype)initWithDialogType:(FileBrowserState)dialogType {
    if ((self = [super init]) != nil) {
        m_tableViewController = [[UITableViewController alloc] init];
        m_dialogType = dialogType;
        NSString *title = @"";
        switch (m_dialogType) {
            case kFBDoShowSave:
                title = @"Save Game";
                break;
            case kFBDoShowRestore:
                title = @"Restore Game";
                break;
            case kFBDoShowScript:
                title = @"Save Transcript";
                break;
            case kFBDoShowViewScripts:
                title = @"View Transcript";
                break;
            case kFBDoShowRecord:
                title = @"Save Recording";
                break;
            case kFBDoShowPlayback:
                title = @"Playback Recording";
                break;
            default:
                break;
        }
        if (title)
            self.title = NSLocalizedString(title, @"");

        m_extensions = [[NSMutableArray alloc] init];
        m_files = [[NSMutableArray alloc] initWithCapacity: 32];
        m_rowCount = 0;
        [self setEditing: NO];
    }
    return self;
}

#define ShowSaveButton 0 // keyboard Done button is sufficient

- (void)loadView {
    m_tableView = m_tableViewController.tableView;
    [m_tableView setAutoresizingMask: UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleRightMargin];
    [m_tableView setDelegate: self];
    [m_tableView setDataSource: self];
    CGRect origFrame = [[UIScreen mainScreen] applicationFrame];
    if (UIDeviceOrientationIsLandscape([self interfaceOrientation])) {
        CGFloat t = origFrame.size.width; origFrame.size.width = origFrame.size.height; origFrame.size.height = t;
        t = origFrame.origin.x; origFrame.origin.x = origFrame.origin.y; origFrame.origin.y = t;
    }

    m_backgroundView = [[UIView alloc] initWithFrame: origFrame]; // CGRectMake(0, 0, origFrame.size.width, origFrame.size.height)]; //34)];
    [m_backgroundView setBackgroundColor: [UIColor blackColor]];
    [m_backgroundView setAutoresizingMask:UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleBottomMargin];
    [m_backgroundView setAutoresizesSubviews: YES];
    self.view = m_backgroundView;
    if (m_dialogType != kFBDoShowRestore && m_dialogType != kFBDoShowViewScripts && m_dialogType != kFBDoShowPlayback) {
        BOOL isLandscape = UIDeviceOrientationIsLandscape([self interfaceOrientation]);

        m_textField = [[UITextField alloc] initWithFrame: CGRectMake(0, 0, origFrame.size.width - (ShowSaveButton ? 56: 0), 30)];
        
        [m_tableView setFrame: CGRectMake(0, m_textField.bounds.size.height /*28*/,
                                          origFrame.size.width,
                                          origFrame.size.height-m_textField.bounds.size.height -
                                          (gUseSplitVC ? 70: isLandscape ? 160 : 216))];
        [m_textField setReturnKeyType: UIReturnKeyDone];
        [m_textField setBackgroundColor: [UIColor whiteColor]];
        [m_textField setBorderStyle: UITextBorderStyleRoundedRect];
        [m_textField setPlaceholder: @"filename"];
        [m_textField setDelegate: self];
        [m_textField setClearButtonMode:UITextFieldViewModeWhileEditing];
        [m_textField setAutocorrectionType: UITextAutocorrectionTypeNo];
        [m_textField setAutoresizingMask: UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleRightMargin];
        
        m_textField.text = @(iosif_filename);
        
        //	[m_tableView setBounces: NO];
        
#if ShowSaveButton
        m_saveButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        [m_saveButton setImage:[UIImage imageNamed: @"save.png"] forState:UIControlStateNormal];
        m_saveButton.frame = CGRectMake(origFrame.size.width-55, 2, 54, 30);
        [m_saveButton setAutoresizingMask: UIViewAutoresizingFlexibleLeftMargin];
        [m_saveButton setBackgroundColor: [UIColor darkGrayColor]];
        [m_saveButton addTarget:self action:@selector(commit:) forControlEvents:UIControlEventTouchUpInside];
        [m_saveButton setEnabled: NO];
#endif
        [m_backgroundView addSubview: m_saveButton];
		
        [m_backgroundView addSubview: m_textField];
        [m_textField becomeFirstResponder];
        [m_backgroundView setNeedsLayout];
    } else
    	[m_tableView setFrame: CGRectMake(0, 00 /*28*/, origFrame.size.width, origFrame.size.height)];
    [m_backgroundView addSubview: m_tableView];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing: editing animated:animated];
    [m_tableViewController setEditing: editing animated:animated];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return gLargeScreenDevice ? YES : interfaceOrientation == UIInterfaceOrientationPortrait;
}

-(void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    if (m_dialogType != kFBDoShowRestore && m_dialogType != kFBDoShowViewScripts && m_dialogType != kFBDoShowPlayback) {
        BOOL isLandscape = UIDeviceOrientationIsLandscape(toInterfaceOrientation);
        [m_tableView setFrame: CGRectMake(0, m_textField.bounds.size.height,
                                          m_backgroundView.frame.size.width,
                                          m_backgroundView.frame.size.height-m_textField.bounds.size.height - (gUseSplitVC ? (isLandscape ? 220 : 70): (isLandscape ? 160 : 216)))];
    }
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    NSIndexPath *indexPath = [m_tableView indexPathForSelectedRow];
    if (indexPath != nil)
        [m_tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSMutableString *newFilename = [NSMutableString stringWithString: [textField text]];
    [newFilename replaceCharactersInRange: range withString:string];
    if ([newFilename length] == 0) {
        [m_saveButton setEnabled: NO];
        return YES;
    }
    [m_saveButton setEnabled: YES];
    int row = 0;
    for (FileInfo *fi in m_files) {
        NSString *file = [fi.path lastPathComponent];
        if ([file caseInsensitiveCompare: newFilename] == NSOrderedSame
            || [file caseInsensitiveCompare: [newFilename stringByAppendingString: kSaveExt]] == NSOrderedSame
            || [file caseInsensitiveCompare: [newFilename stringByAppendingString: kAltSaveExt]] == NSOrderedSame) {
            indexPath = [NSIndexPath indexPathForRow: row inSection:0];
            [m_tableView selectRowAtIndexPath:indexPath animated:YES scrollPosition:UITableViewScrollPositionMiddle];
            break;
        }
        row++;
    }
    return YES;
}

- (BOOL)textFieldShouldClear:(UITextField *)textField {
    NSIndexPath *indexPath = [m_tableView indexPathForSelectedRow];
    if (indexPath != nil)
        [m_tableView deselectRowAtIndexPath:indexPath animated:YES];
    [m_saveButton setEnabled: NO];
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if ([[textField text] length] > 0) {
        [self commit: textField];
        return YES;
    }
    return NO;
}

- (void)commit:(id)sender {
    if ([[m_textField text] length] > 0) {
        NSString *selFile = [self selectedFile];
        BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath: selFile];
        if (m_dialogType==kFBDoShowScript) {
            if (!exists) {
                exists = [[NSFileManager defaultManager] fileExistsAtPath: [selFile stringByAppendingString: kSaveExt]];
                if (exists)
                    m_textField.text = [m_textField.text stringByAppendingString: @".txt"];
            }
        } else {
            if (!exists) {
                exists = [[NSFileManager defaultManager] fileExistsAtPath: [selFile stringByAppendingString: kSaveExt]];
                if (exists)
                    m_textField.text = [m_textField.text stringByAppendingString: kSaveExt];
            }
            if (!exists) {
                exists = [[NSFileManager defaultManager] fileExistsAtPath: [selFile stringByAppendingString: kAltSaveExt]];
                if (exists)
                    m_textField.text = [m_textField.text stringByAppendingString: kAltSaveExt];
            }
        }
        if (exists && m_dialogType != kFBDoShowScript) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Overwrite File" message:@"Do you want to save over this file?"
                                                           delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles: @"Save", nil];
            [alert show];
            return;
        }
        [m_textField endEditing: YES];
    }
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    NSString *file = [textField text];
    
    if ([file length] > 0)
    	[m_delegate fileBrowser:self fileSelected: [self selectedFile]];
    else
    	[m_delegate fileBrowser:self fileSelected:nil];
}

-(void)viewDidLoad {
#ifdef NSFoundationVersionNumber_iOS_6_1
    if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1)
    {
        self.edgesForExtendedLayout=UIRectEdgeNone;
    }
#endif
}

-(void)viewDidAppear:(BOOL)animated {
    UIBarButtonItem* backItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:UIBarButtonItemStylePlain target:self action:@selector(didPressCancel:)];
    self.navigationItem.leftBarButtonItem = backItem;
    
    UIBarButtonItem* editItem = [self editButtonItem];
    [editItem setStyle: UIBarButtonItemStylePlain];
    self.navigationItem.rightBarButtonItem = editItem;
    [editItem setEnabled: (m_rowCount > 0)];
    
#ifdef NSFoundationVersionNumber_iOS_6_1
    if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1) {
        if ([self.navigationController.navigationBar respondsToSelector:@selector(setBarTintColor:)]) {
            [self.navigationController.navigationBar setBarStyle: UIBarStyleDefault];
            [self.navigationController.navigationBar  setBarTintColor: [UIColor whiteColor]];
            [self.navigationController.navigationBar  setTintColor:  [UIColor darkGrayColor]];
        }
    }
#endif

}

-(void)viewWillDisappear:(BOOL)animated {
    // since the save dialog and parent vc both have the keyboard showing and there's not much vertical space,
    // the normal dismissal animation looks stuttery.  It's better just to fade out in this case.
    [super viewWillDisappear:animated];
    if (gUseSplitVC && animated && UIDeviceOrientationIsLandscape([self interfaceOrientation]) && m_dialogType != kFBDoShowRestore && m_dialogType != kFBDoShowViewScripts && m_dialogType != kFBDoShowPlayback)
        [self.navigationController.view.superview setHidden: YES];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSInteger row = indexPath.row;
        if (row < [m_files count]) {
            if ([m_delegate respondsToSelector: @selector(fileBrowser:deleteFile:)])
                [m_delegate fileBrowser:self deleteFile: [m_files[row] path]];
            [m_files removeObjectAtIndex: row];
            m_rowCount = [m_files count];
            NSArray *indexPaths = @[indexPath];
            [m_tableView deleteRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationFade];
            [self reloadData];
            [[self editButtonItem] setEnabled: (m_rowCount > 0)];
        }
    }
}


-(void)didPressCancel:(id)sender {
    if (m_textField) {
        [m_textField setText: nil];
        NSIndexPath *indexPath = [m_tableView indexPathForSelectedRow];
        if (indexPath)
            [m_tableView  deselectRowAtIndexPath:indexPath animated:NO];
        [m_textField endEditing: YES];
    } else if( [m_delegate respondsToSelector:@selector( fileBrowser:fileSelected: )] )
        [m_delegate fileBrowser:self fileSelected: nil];
}

-(void)setDelegate:(id<FileSelected>)delegate {
    m_delegate = delegate;
}

- (id<FileSelected>)delegate {
    return m_delegate;
}


- (NSString *)path {
    return m_path;
}

- (void)setPath: (NSString *)path {
    if (m_path != path) {
        m_path = [path copy];
    }
    
    [self reloadData];
}

- (void)addExtension: (NSString *)extension {
    if (![m_extensions containsObject:[extension lowercaseString]]) {
        [m_extensions addObject: [extension lowercaseString]];
    }
}

- (void)setExtensions: (NSArray *)extensions {
    [m_extensions setArray: extensions];
}

- (void)reloadData {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath: m_path] == NO) {
        return;
    }
    
    [m_files removeAllObjects];
    
    NSString *file;
    NSDirectoryEnumerator *dirEnum = [[NSFileManager defaultManager] enumeratorAtPath: m_path];
    while ((file = [dirEnum nextObject])) {
        BOOL isDir;
        NSString *path = [m_path stringByAppendingPathComponent: file];
        if ([fileManager fileExistsAtPath: path isDirectory: &isDir] && !isDir) {
            const char *fn = [file cStringUsingEncoding: NSUTF8StringEncoding];
            if (fn && strcasecmp(fn, kFrotzAutoSaveFile) != 0 && strcasecmp(fn, kFrotzAutoSavePListFile) != 0
                && strcasecmp(fn, kFrotzAutoSaveFileGlkWin) != 0) {
                if ([file hasSuffix: @".png"] || [file hasSuffix: @".jpg"])
                    continue;
                if (m_dialogType==kFBDoShowRecord || m_dialogType==kFBDoShowPlayback) {
                    if (![file hasSuffix:@".rec"])
                        continue;
                } else if (m_dialogType==kFBDoShowScript || m_dialogType==kFBDoShowViewScripts) {
                    if (([file hasSuffix: kSaveExt] || [file hasSuffix: kAltSaveExt]))
                        continue;
                    ++m_textFileCount;
                } else if ([file hasSuffix: @".scr"] || [file hasSuffix: @".txt"] || [file hasSuffix: @".rec"])
                    continue;
                FileInfo *fi = [[FileInfo alloc] initWithPath: path];
                [m_files addObject: fi];
            }
        }
    }
    
    [m_files sortUsingSelector:@selector(compare:)];
    m_rowCount = [m_files count];
    [m_tableView reloadData];
}

- (int)textFileCount {
    return m_textFileCount;
}

- (NSString*)tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section {
    if (m_dialogType==kFBDoShowScript || m_dialogType==kFBDoShowViewScripts || m_dialogType==kFBDoShowRecord || m_dialogType == kFBDoShowPlayback)
        return nil;
    if (section == 0 && m_rowCount > 0)
        return @"Previously saved games";
    else
        return @"No saved games";
}

- (NSInteger) tableView:(UITableView*)tableView numberOfRowsInSection: (NSInteger)section {
    return m_rowCount;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView  {
    return 1;
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"saveGameCell"];
    if (cell == nil) {
        cell = [UITableViewCell alloc];
        if ([cell respondsToSelector: @selector(initWithStyle:reuseIdentifier:)])
            cell = [cell initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"saveGameCell"];
        else
            cell = [cell initWithFrame:CGRectZero reuseIdentifier:@"saveGameCell"];
    }
    
    NSString *file = [[m_files[indexPath.row] path] lastPathComponent], *cellText = nil;
    if ([file hasSuffix: kSaveExt] || [file hasSuffix: kAltSaveExt]) {
        cellText = [file stringByDeletingPathExtension];
        if (indexPath.row > 0 && [[[m_files[indexPath.row-1] path] lastPathComponent] isEqual: cellText])
            cellText = file;
	}
    else
        cellText = file;
    cell.text = cellText;
    if ([cell respondsToSelector: @selector(detailTextLabel)]) {
        NSDate *moddate = [m_files[indexPath.row] modDate];
        
        if (moddate)
            cell.detailTextLabel.text = [NSString stringWithFormat: @"%@; .%@", [moddate description], [[file pathExtension] lowercaseString]];
        else
            cell.detailTextLabel.text = nil;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [self setEditing: NO];
    if (m_textField) {
        if (indexPath != nil) {
            NSString *file = [[m_files[indexPath.row] path] lastPathComponent];
            if ([file hasSuffix: kSaveExt] || [file hasSuffix: kAltSaveExt])
                [m_textField setText:[file stringByDeletingPathExtension]];
            else
                [m_textField setText: file];
            [m_saveButton setEnabled: YES];
        }
    }
    else {
        if( [m_delegate respondsToSelector:@selector( fileBrowser:fileSelected: )] ) {
            
            if (m_dialogType == kFBDoShowViewScripts) {
                UITextView *textView = [[UITextView alloc] initWithFrame: self.view.bounds];
                NSString *text = [[NSString alloc] initWithData: [[NSFileManager defaultManager] contentsAtPath: [self selectedFile]] encoding:NSUTF8StringEncoding];
                textView.text = text;
                textView.editable = NO;
                [self.view addSubview: textView];
                self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem: UIBarButtonSystemItemDone
                                                                                                       target:self action:@selector(doneWithTextFile:)];
                self.navigationItem.rightBarButtonItem = nil;
                return;
            }
            
            [m_delegate fileBrowser:self fileSelected:[self selectedFile]];
        }
    }
}

-(void)doneWithTextFile:(id)sender {
    [m_delegate fileBrowser:self fileSelected:[self selectedFile]];
}    

// Called when a button is clicked. The view will be automatically dismissed after this call returns
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == 1) { 
        [m_textField endEditing: YES];
    }
}

- (NSString *)selectedFile {
    if (m_textField && [[m_textField text] length] > 0)
        return [m_path stringByAppendingPathComponent: [m_textField text]];    
    NSIndexPath *indexPath = [m_tableView indexPathForSelectedRow];
    if (indexPath == nil || indexPath.row == -1) {
        return nil;
    }
    return [m_files[indexPath.row] path];
}

@end
