//
//  BookmarkList.m
//  Frotz
//
//  Created by Craig Smith on 8/6/08.
//  Copyright 2008 Craig Smith. All rights reserved.
//

#import "BookmarkListController.h"

static const CGFloat kBookmarkToolbarHeight = 44;

@implementation BookmarkListController
@synthesize delegate = m_delegate;

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
    [self.view setAutoresizingMask: UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleRightMargin|UIViewAutoresizingFlexibleBottomMargin];
    [self.view addSubview: m_tableView];
    [m_tableView setFrame: frame];

    // placed over the bottom of the table in viewWillLayoutSubviews
    frame.size.height = kBookmarkToolbarHeight;
    UIToolbar *toolBar = m_toolBar = [[UIToolbar alloc] initWithFrame: frame];

    [toolBar setBarStyle: UIBarStyleBlackOpaque];
    
    UIBarButtonItem *addButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(add)];
    UIBarButtonItem *spaceButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *editButtonItem =  [self editButtonItem];
    UIBarButtonItem *cancelButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    [addButtonItem setTintColor: [UIColor whiteColor]];
    [editButtonItem setTintColor: [UIColor whiteColor]];
    [cancelButtonItem setTintColor: [UIColor whiteColor]];
    [toolBar setItems: @[spaceButtonItem, addButtonItem, spaceButtonItem, editButtonItem, spaceButtonItem, cancelButtonItem, spaceButtonItem]];
    
    [self.view addSubview: toolBar];
    [self.view bringSubviewToFront: toolBar];
}

-(UITableView*)tableView {
    if (m_tableView)
        return m_tableView;
    return [super tableView];
}

// The table fills the view and the toolbar floats over its bottom edge, above any bottom safe-area
// inset (home indicator, and the browser's translucent toolbar that this view extends under).
// The table's bottom content inset lets the last bookmarks scroll up from under the toolbar; the
// safe-area part of the inset is added by the table itself. Done here rather than with
// autoresizing so the layout follows both frame and safe-area changes (this view is placed in the
// web browser's view by hand).
- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    CGRect bounds = self.view.bounds;
    CGFloat toolbarTop = CGRectGetMaxY(bounds) - self.view.safeAreaInsets.bottom - kBookmarkToolbarHeight;
    [m_toolBar setFrame: CGRectMake(0, toolbarTop, bounds.size.width, kBookmarkToolbarHeight)];
    [m_tableView setFrame: bounds];
    UIEdgeInsets inset = m_tableView.contentInset;
    inset.bottom = kBookmarkToolbarHeight;
    m_tableView.contentInset = inset;
    m_tableView.verticalScrollIndicatorInsets = inset;
}

- (void)add {
    [self setEditing:NO];
    if (m_delegate) {
        NSString *currentURL = [[[m_delegate currentURL] stringByReplacingOccurrencesOfString:@"http://" withString:@""] stringByReplacingOccurrencesOfString:@"https://" withString:@""];
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
        cell.detailTextLabel.text = m_sites[row];
        if (row < [m_titles count])
            cell.textLabel.text = m_titles[row];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else {
        // the blank trailing row; nothing to select
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger row = [indexPath row];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (row < [m_sites count]) // not the blank trailing row
        [m_delegate enterURL: m_sites[row]];
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
    self.edgesForExtendedLayout=UIRectEdgeNone;
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

