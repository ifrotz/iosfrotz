//
//  BookmarkList.m
//  Frotz
//
//  Created by Craig Smith on 8/6/08.
//  Copyright 2008 Craig Smith. All rights reserved.
//

#import "BookmarkListController.h"

@implementation BookmarkListController

-(void)setDelegate:(id<BookmarkDelegate>)del {
    m_delegate = del;
}

-(id<BookmarkDelegate>)delegate {
    return m_delegate;
}

- (instancetype)initWithStyle:(UITableViewStyle)style {
    if ((self = [super initWithStyle:style])) {

    }
    return self;
}

- (void)loadView {
    [super loadView];
    m_tableView = self.tableView;
    CGRect frame = [self.view bounds];

    if (m_delegate) {
	NSArray *urls = nil, *titles = nil;
	[m_delegate loadBookmarksWithURLs:&urls andTitles:&titles];
	m_sites = [[NSMutableArray alloc] initWithArray: urls];
	m_titles = [[NSMutableArray alloc] initWithArray: titles];
    }
    else {
	m_sites = [[NSMutableArray alloc] init];
	m_titles = [[NSMutableArray alloc] init];
    }
    self.view = [[UIView alloc] initWithFrame: frame];
    [self.view setAutoresizesSubviews: YES];
    [self.view setAutoresizingMask: UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight];
    [m_tableView setAutoresizingMask: UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight];
    [self.view addSubview: m_tableView];
    [m_tableView setFrame: CGRectOffset(frame, 0, -frame.origin.y)];

    frame.origin.y = frame.size.height - 44;
    frame.size.height = 44;
    UIToolbar *toolBar = [[UIToolbar alloc] initWithFrame: frame];
    
    [toolBar setAutoresizingMask: UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleWidth];

    [toolBar setBarStyle: UIBarStyleBlackOpaque];
    
    UIBarButtonItem *addButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(add)];
    UIBarButtonItem *spaceButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *editButtonItem =  [self editButtonItem]; //[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemEdit target:self action:@selector(edit)];
    UIBarButtonItem *cancelButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    [toolBar setItems: @[addButtonItem, spaceButtonItem, editButtonItem, spaceButtonItem, cancelButtonItem]];
    
    [self.view addSubview: toolBar];
    [self.view bringSubviewToFront: toolBar];
}

-(UITableView*)tableView {
    if (m_tableView)
	return m_tableView;
    return [super tableView];
}

- (void)add {
    [self setEditing:NO];
    if (m_delegate) {
	NSString *currentURL = [[m_delegate currentURL] stringByReplacingOccurrencesOfString:@"http://" withString:@""];
	NSString *currentTitle = [m_delegate currentURLTitle];

	if (currentURL) {
	    UITableView *tableView = self.tableView;
	    [tableView beginUpdates];
	    [m_sites addObject: currentURL];
	    [m_titles addObject: currentTitle ? currentTitle : @"(untitled)"];
	    [m_delegate saveBookmarksWithURLs:m_sites andTitles:m_titles];
	    NSUInteger indexes[] = { 0, [m_sites count] };
	    NSIndexPath *indexPath = [NSIndexPath indexPathWithIndexes: indexes length:2];
	    NSArray *indexPaths = @[indexPath];
	    [tableView insertRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationBottom];
	    [tableView reloadData];
	    [tableView endUpdates];
	    [tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionBottom animated:YES];
	}
    }
}

- (void)cancel {
    [self setEditing:NO];
    [m_delegate hideBookmarks];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}


- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [m_sites count]+1;
}

- (NSString*)tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section {
    return @"Interactive Fiction Resouces";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *myID = @"IFBookmarks";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:myID];
    if (cell == nil) {
	cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:myID];
    }
    // Configure the cell
    cell.textLabel.text = nil;
    cell.detailTextLabel.text = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    NSInteger row = [indexPath row];
    if (row < [m_sites count]) {
	cell.textLabel.text = m_sites[row];
	if (row < [m_titles count])
	    cell.detailTextLabel.text = m_titles[row];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [m_delegate enterURL: m_sites[[indexPath row]]];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return (indexPath.row < [m_sites count]);
}


- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger row = indexPath.row;
    if (row < [m_sites count] && editingStyle == UITableViewCellEditingStyleDelete) {
	[m_sites removeObjectAtIndex: row];
	if (row < [m_titles count])
	    [m_titles removeObjectAtIndex: row];
	if (m_delegate)
	    [m_delegate saveBookmarksWithURLs:m_sites andTitles:m_titles];
	[tableView reloadData];
    }
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath {
    NSInteger fromRow = fromIndexPath.row;
    NSInteger toRow = toIndexPath.row;
    NSUInteger count = [m_sites count];
    if (fromRow < count && toRow < count) {
	NSString *url = m_sites[fromRow];
	NSString *title = (fromRow < [m_titles count]) ? m_titles[fromRow] : nil;
	[m_sites removeObjectAtIndex: fromRow];
	if (title)
	    [m_titles removeObjectAtIndex: fromRow];
	if (toRow > fromRow)
	    --toRow;
	[m_sites insertObject:url atIndex:toRow];
	if (title)
	    [m_titles insertObject: title atIndex:toRow];
	if (m_delegate)
	    [m_delegate saveBookmarksWithURLs:m_sites andTitles:m_titles];
    }
}


- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return (indexPath.row < [m_sites count]);
}



- (void)viewDidLoad {
#ifdef NSFoundationVersionNumber_iOS_6_1
    if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1)
    {
        self.edgesForExtendedLayout=UIRectEdgeNone;
    }
#endif
    [super viewDidLoad];
}


- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated {
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

@end

