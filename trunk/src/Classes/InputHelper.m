//
//  InputHelper.m
//  Frotz
//
//  Created by Craig Smith on 9/6/08.
//  Copyright 2008 Craig Smith. All rights reserved.
//

#import "iphone_frotz.h"
#import "InputHelper.h"

const CGFloat kHistoryLineHeight = 20.0;

@implementation FrotzInputHelper

- (id)init {
    if (self = [super initWithStyle:UITableViewStylePlain]) {
	m_history = [[NSMutableArray alloc] initWithCapacity: 2];
	m_commonCommands = [NSArray arrayWithObjects: 
	    @"about ", @"all ", @"ask ", @"at ", @"attack ", @"behind ", @"but ", @"climb ", @"door ", @"down ", @"from ", @"give ", @"help ",
	    @"in ",@"jump ", @"kick ", @"kill ", @"no", @"on ", @"push ", @"pull ", @"read ", @"remove ", @"say ", @"switch ",  @"take ", @"tell ",
	    @"through ", @"throw ", @"tie ", @"touch ", @"turn", @"under ", @"untie ", @"up ", @"wait ", @"wear ",@"window ", @"with ", @"quit ", @"yes",
	    @"brief", @"diagnose", @"save", @"score", @"restart", @"restore", @"undo", @"verbose ", nil];
	[m_commonCommands retain];
	m_mode = 0;
	m_lastCommonWordPicked = 0;
    }
    return self;
}

- (UIView*)helperView {
    if (m_mode == FrotzInputHelperModeNone)
	return nil;
    else if (m_mode == FrotzInputHelperModeWords)
	return m_wordPicker;
    return [self tableView];
}


-(void)loadView {
    [super loadView];
    UITableView *tableView = [self tableView];
    [tableView setFrame: CGRectMake(0.0, 0.0, 240.0, 72.0)];
    [tableView setShowsVerticalScrollIndicator: YES];
    [tableView setBounces: NO];
    [tableView setBackgroundColor: [UIColor darkGrayColor]];
    [tableView setAlpha: 0.9];
    [tableView setUserInteractionEnabled: YES];
    
    NSArray* nibViews =  [[NSBundle mainBundle] loadNibNamed:@"FrotzWordPicker" owner:self options:nil];
    m_wordPicker = [nibViews objectAtIndex: 0];
    [m_wordPicker retain];
    
    NSArray *subViews = [m_wordPicker subviews];
    UIButton *b;
    for (b in subViews) {
	[b addTarget:self action:@selector(butttonPressed:) forControlEvents:UIControlEventTouchUpInside];
    }

}

- (void)butttonPressed:(UIButton*)button {
    NSString *string = [button currentTitle];
    if ([string isEqualToString: @"..."]) {
	CGPoint pt = m_wordPicker.frame.origin;
	pt.y += m_wordPicker.frame.size.height;
	pt.x += 20;
	[self showInputHelperInView: [m_wordPicker superview] atPoint:pt withMode: FrotzInputHelperModeMoreWords];
    }
    else if (isupper([string characterAtIndex: 0]))
	[m_delegate inputHelperString: [string stringByAppendingString: @"\n"]];
    else
	[m_delegate inputHelperString: [string stringByAppendingString: @" "]];
}

- (FrotzInputHelperMode)mode {
    return m_mode;
}

-(void)hideInputHelper {
    m_mode = FrotzInputHelperModeNone;
    if (m_wordPicker) {
	[self.view removeFromSuperview];
	[m_wordPicker removeFromSuperview];
    }
}

-(void)showInputHelperInView:(UIView*)parentView atPoint:(CGPoint)pt withMode:(FrotzInputHelperMode)mode {

    UITableView *tableView = [self tableView];
    m_mode = mode;
    if (m_mode == FrotzInputHelperModeNone) {
	[self hideInputHelper];
    } else if (m_mode == FrotzInputHelperModeWords) {
       CGRect wpFrame = [m_wordPicker frame];
	wpFrame.origin = pt;
	wpFrame.origin.y -= wpFrame.size.height;
	[tableView removeFromSuperview];
	[m_wordPicker setFrame: wpFrame];
	float alpha = [m_wordPicker alpha];
	[m_wordPicker setAlpha: 0.0];
	[UIView beginAnimations:nil context:NULL];
	[UIView setAnimationDuration:0.15];
	[parentView addSubview: m_wordPicker];
	[m_wordPicker setAlpha: alpha];
	[UIView commitAnimations];

    } else {
	CGRect frame = [tableView frame];
	int nLines;
	int maxLines = gLargeScreenDevice ? 14 : 6;
    
	if (m_mode == FrotzInputHelperModeMoreWords)
	    nLines = maxLines;
	else {
	    nLines = [m_history count];
	    if (nLines > maxLines)
		nLines = maxLines;
	}
	if (nLines > 0) {
	    [tableView reloadData];
	    
	    NSIndexPath	*idx = [tableView indexPathForSelectedRow];
	    if (idx)
		[tableView deselectRowAtIndexPath: idx animated:NO];

	    frame.size.height = 8;
	    frame.origin = pt;
	    [tableView setFrame: frame];
	    [m_wordPicker removeFromSuperview];
	    [parentView addSubview: tableView];

	    [UIView beginAnimations:nil context:NULL];

	    [UIView setAnimationDuration:0.1];
	 
	    frame.size.height = kHistoryLineHeight * (nLines+1) + 2;
	    pt.y -= frame.size.height;
	    frame.origin = pt;
	    [tableView setFrame: frame];

	    int scrollTo = m_mode == FrotzInputHelperModeMoreWords ? m_lastCommonWordPicked : [self historyCount] - 1;
	    if (scrollTo >= 0)
		[tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow: scrollTo inSection:0] 
		    atScrollPosition: m_mode == FrotzInputHelperModeMoreWords ? UITableViewScrollPositionMiddle:UITableViewScrollPositionBottom animated:NO];
	    [UIView commitAnimations];
	} else
	    [self hideInputHelper];
    }
}

-(NSObject<FrotzInputDelegate>*)delegate {
    return m_delegate;
}

-(void)setDelegate:(NSObject<FrotzInputDelegate>*)delegate {
    m_delegate = delegate;
}

- (void)clearHistory {
    [m_history removeAllObjects];
}

- (int)historyCount {
    return [m_history count];
}

- (int)menuCount {
    return m_mode == FrotzInputHelperModeMoreWords ? [m_commonCommands count] : [m_history count];
}

- (NSString*)historyItem:(int)item {
    if (m_mode == FrotzInputHelperModeMoreWords) {
	if (item < [m_commonCommands count])
	    return [m_commonCommands objectAtIndex: item];
    } else if (item < [m_history count])
	return [m_history objectAtIndex: item];
    return nil;
}

- (int)addHistoryItem:(NSString*)historyItem; {
    int idx;
    NSString *hItem = historyItem;
    while ([hItem hasPrefix: @" "])
	hItem = [hItem stringByReplacingCharactersInRange: NSMakeRange(0,1) withString: @""];
    while ([hItem hasSuffix: @" "])
	hItem = [hItem stringByReplacingCharactersInRange: NSMakeRange([hItem length]-1,1) withString: @""];

    if ([hItem isEqualToString: @""])
	return -1;
	
    if ([m_history count] > 0) {
	idx = [m_history indexOfObject:hItem];
	if (idx != NSNotFound)
	    [m_history removeObjectAtIndex: idx];
    }

    [m_history addObject: hItem];
    [[self tableView] reloadData];
    return [m_history count]-1;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return kHistoryLineHeight;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return m_mode == FrotzInputHelperModeMoreWords ? @"More words" : @"Command History";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return m_mode == FrotzInputHelperModeMoreWords ? [m_commonCommands count] : [m_history count];
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	
    static NSString *MyIdentifier = @"inputnamecell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:MyIdentifier];
    if (cell == nil) {
	cell = [[[UITableViewCell alloc] initWithFrame:CGRectZero reuseIdentifier:MyIdentifier] autorelease];
    }
    // Configure the cell
    NSString *item = m_mode == FrotzInputHelperModeMoreWords ? [m_commonCommands objectAtIndex: indexPath.row] : [m_history objectAtIndex: indexPath.row];
    cell.text = item;
    cell.textColor = m_mode == FrotzInputHelperModeMoreWords && indexPath.row > [m_commonCommands count] - 9 ? [UIColor yellowColor] : [UIColor whiteColor];
    cell.backgroundColor = [UIColor darkGrayColor];

    return cell;
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (m_delegate && [m_delegate respondsToSelector: @selector(inputHelperString:)]) {
	if (m_mode == FrotzInputHelperModeMoreWords)
	    m_lastCommonWordPicked = indexPath.row;
	    
	NSString *item = m_mode == FrotzInputHelperModeMoreWords ?
		    [m_commonCommands objectAtIndex: indexPath.row] : [m_history objectAtIndex: indexPath.row];
	[m_delegate inputHelperString: item];
    }
}

/*
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
	
	if (editingStyle == UITableViewCellEditingStyleDelete) {
	}
	if (editingStyle == UITableViewCellEditingStyleInsert) {
	}
}
*/
/*
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	return YES;
}
*/
/*
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath {
}
*/
/*
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
	return YES;
}
*/


- (void)dealloc {
    [m_history release];
    [m_commonCommands release];
    [super dealloc];
}


- (void)viewDidLoad {
    [super viewDidLoad];
}


- (void)viewWillAppear:(BOOL)animated {

    self.title = NSLocalizedString(@"Input history", @"");

    [super viewWillAppear:animated];
    [[self tableView] reloadData];
    if (m_delegate && [m_delegate respondsToSelector: @selector(historyItem)]) {
    }
}

-(void)viewWillDisappear:(BOOL)animated {
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
}

- (void)viewDidDisappear:(BOOL)animated {
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}


@end

