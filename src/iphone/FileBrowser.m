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
#include "iphone_frotz.h"

@implementation FileBrowser 
- (id)initWithFrame:(struct CGRect)frame{
    if ((self == [super initWithFrame: frame]) != nil) {
	UITableColumn *col = [[UITableColumn alloc]
			initWithTitle: @"FileName"
			   identifier:@"filename"
				width: frame.size.width
	    ];
	
	m_table = [[UITable alloc] initWithFrame: CGRectMake(0, 0, frame.size.width, frame.size.height)];
	[ m_table addTableColumn: col ];
	[ m_table setSeparatorStyle: 1 ];
	[ m_table setDelegate: self ];
	[ m_table setDataSource: self ];
	
	m_extensions = [[NSMutableArray alloc] init];
	m_files = [[NSMutableArray alloc] init];
	m_rowCount = 0;
	
	m_delegate = nil;
	
	[self addSubview: m_table];
    }
    return self;
}

- (void)dealloc {
    [m_path release];
    [m_files release];
    [m_extensions release];
    [m_table release];
    m_delegate = nil;
    [super dealloc];
}

- (NSString *)path {
    return [[m_path retain] autorelease];
}

- (void)setPath: (NSString *)path {
    [m_path release];
    m_path = [path copy];
    
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
    while (file = [dirEnum nextObject]) {
	const char *fn = [file cStringUsingEncoding: NSASCIIStringEncoding];
	if (strcasecmp(fn, kFrotzAutoSaveFile) != 0) 
	    [m_files addObject: file];
    }
    
    //[_files sortUsingSelector:@selector(caseInsensitiveCompare:)];
    m_rowCount = [m_files count];
    [m_table reloadData];
}

- (void)setDelegate:(id)delegate {
    m_delegate = delegate;
}

- (int)numberOfRowsInTable:(UITable *)table {
    return m_rowCount;
}

- (UITableCell *)table:(UITable *)table cellForRow:(int)row column:(UITableColumn *)col {
    UITableCell *cell = [[UITableCell alloc] init];
    
    UITextLabel *descriptionLabel = [[UITextLabel alloc] 
            initWithFrame:CGRectMake(5.0f, 3.0f, 210.0f, 40.0f)];
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    float whiteComponents[4] = {1, 1, 1, 1};
    float transparentComponents[4] = {0, 0, 0, 0};
    
    [ descriptionLabel setText:[m_files objectAtIndex: row] ];   // stringByDeletingPathExtension
    [ descriptionLabel setWrapsText: YES ];
    [ descriptionLabel setBackgroundColor:CGColorCreate(colorSpace, transparentComponents) ];
    
    [ cell addSubview: descriptionLabel ];
    
    return cell;
}

- (void)tableRowSelected:(NSNotification *)notification {
    if( [m_delegate respondsToSelector:@selector( fileBrowser:fileSelected: )] )
	[m_delegate fileBrowser:self fileSelected:[self selectedFile]];
}

- (NSString *)selectedFile {
    if ([m_table selectedRow] == -1)
	return nil;
    
    return [m_path stringByAppendingPathComponent: [m_files objectAtIndex: [m_table selectedRow]]];
}

@end
