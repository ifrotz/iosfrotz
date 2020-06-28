//
//  InputHelper.m
//  Frotz
//
//  Created by Craig Smith on 9/6/08.
//  Copyright 2008 Craig Smith. All rights reserved.
//

#import "iosfrotz.h"
#import "InputHelper.h"

const CGFloat kHistoryLineHeight = 20.0;

@implementation FrotzInputHelper
@synthesize delegate = m_delegate;

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        m_history = [[NSMutableArray alloc] initWithCapacity: 2];
        m_commonCommands = @[@"about ", @"all ", @"and ", @"ask ", @"at ", @"attack ", @"behind ", @"but ", @"cast ", @"climb ", @"door ", @"down ", @"from ", @"get ", @"give ", @"help ",
                            @"in ",@"jump ", @"kick ", @"kill ", @"learn ", @"leave ", @"memorize ", @"no", @"off ", @"on ", @"push ", @"pull ", @"put ", @"read ", @"remove ", @"say ", @"search ", @"switch ",  @"take ", @"talk ", @"tell ", @"then ",
                            @"through ", @"throw ", @"tie ", @"to ", @"touch ", @"turn", @"under ", @"untie ", @"up ", @"wait ", @"wear ",@"window ", @"with ", @"quit ", @"yes", @", ", @". ", @"\"",
                            @"brief", @"diagnose", @"save", @"score", @"restart", @"restore", @"undo", @"verbose"];
        m_mode = 0;
        m_lastCommonWordPicked = 0;
        m_currHistoryItem = 0;
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
    [tableView setBackgroundColor: [UIColor blackColor]]; //[UIColor darkGrayColor]];
    [tableView setAlpha: 0.75];
    [tableView setUserInteractionEnabled: YES];
    [tableView setContentInset: UIEdgeInsetsMake(0, 0, 0, 0)];
    
    NSArray* nibViews =  [[NSBundle mainBundle] loadNibNamed:@"FrotzWordPicker" owner:self options:nil];
    m_wordPicker = nibViews[0];
    
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
        NSUInteger nLines;
        BOOL isLandscape = UIInterfaceOrientationIsLandscape([self interfaceOrientation]);
        int maxLines = gLargeScreenDevice ? (isLandscape ? 14 : 24) : (isLandscape ? 6 : 7);
        if (![m_delegate isFirstResponder])
            maxLines += gLargeScreenDevice ? 10 : 6;
        
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
            [tableView setContentInset: UIEdgeInsetsMake(0, 0, 0, 0)];

            NSInteger scrollTo = m_mode == FrotzInputHelperModeMoreWords ? m_lastCommonWordPicked : [self historyCount] - 1;
            if (scrollTo >= 0)
                [tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow: scrollTo inSection:0] 
                                 atScrollPosition: m_mode == FrotzInputHelperModeMoreWords ? UITableViewScrollPositionMiddle:UITableViewScrollPositionBottom animated:NO];
            [UIView commitAnimations];
        } else
            [self hideInputHelper];
    }
}

- (void)clearHistory {
    [m_history removeAllObjects];
    m_currHistoryItem = 0;
}

- (NSUInteger)historyCount {
    return [m_history count];
}

- (NSUInteger)menuCount {
    return m_mode == FrotzInputHelperModeMoreWords ? [m_commonCommands count] : [m_history count];
}

- (NSString*)historyItem:(int)item {
    if (m_mode == FrotzInputHelperModeMoreWords) {
        if (item < [m_commonCommands count])
            return m_commonCommands[item];
    } else if (item < [m_history count])
        return m_history[item];
    return nil;
}

- (NSUInteger)addHistoryItem:(NSString*)historyItem; {
    NSUInteger idx;
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
    m_currHistoryItem = [m_history count];
    return [m_history count]-1;
}

- (NSString*)getNextHistoryItem {
    NSUInteger count = [m_history count];
    if (!count)
        return @"";
    if (m_currHistoryItem < count-1) {
        ++m_currHistoryItem;
        return m_history[m_currHistoryItem];
    } else
        m_currHistoryItem = count;
    return @"";
}

- (NSString*)getPrevHistoryItem {
    NSUInteger count = [m_history count];
    if (!count)
        return @"";
    if (m_currHistoryItem > 0) {
        --m_currHistoryItem;
        return m_history[m_currHistoryItem];
    } else
        m_currHistoryItem = 0;
    return @"";
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

#if __IPHONE_5_1 < __IPHONE_OS_VERSION_MAX_ALLOWED

// iOS 6 and later
- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section
{
    // Background color
    view.tintColor = [UIColor blackColor];
    
    // Text Color
    UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)view;
    [header.textLabel setTextColor:[UIColor whiteColor]];
}
#endif

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	
    static NSString *MyIdentifier = @"inputnamecell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:MyIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithFrame:CGRectZero reuseIdentifier:MyIdentifier];
    }
    // Configure the cell
    NSString *item = m_mode == FrotzInputHelperModeMoreWords ? m_commonCommands[indexPath.row] : m_history[indexPath.row];
    cell.text = item;
    cell.textColor = m_mode == FrotzInputHelperModeMoreWords && indexPath.row > [m_commonCommands count] - 9 ? [UIColor yellowColor] : [UIColor whiteColor];
    cell.backgroundColor = [UIColor blackColor]; // [UIColor darkGrayColor];
    
    return cell;
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (m_delegate && [m_delegate respondsToSelector: @selector(inputHelperString:)]) {
        if (m_mode == FrotzInputHelperModeMoreWords)
            m_lastCommonWordPicked = indexPath.row;
	    
        NSString *item = m_mode == FrotzInputHelperModeMoreWords ?
        m_commonCommands[indexPath.row] : m_history[indexPath.row];
        [m_delegate inputHelperString: item];
    }
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
    
    self.title = NSLocalizedString(@"Input history", @"");
    
    [super viewWillAppear:animated];
    [[self tableView] reloadData];
}

-(void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
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

