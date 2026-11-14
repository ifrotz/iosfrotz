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

// Layout of the popup: the tab control across the top, then the content (the word picker grid,
// or the table, with the back-to-grid button above the table for the long word list).
static const CGFloat kTabBarHeight = 32.0;     // the segmented control and its padding
static const CGFloat kTabControlHeight = 26.0;
static const CGFloat kTabCornerRadius = 6.0;
static const CGFloat kTabIndicatorInset = 2.0;   // the pill sits inside the selected tab's bounds
static const CGFloat kTabPadding = 3.0;
static const CGFloat kBackBarHeight = 24.0;
static const NSUInteger kMinTableLines = 3;    // the table never shrinks below this when space is short
static const CGFloat kPopupCornerRadius = 8.0;
static const CGFloat kPopupAlpha = 0.92;         // the picker nib's 0.85 let the story show through too much
static const CGFloat kPopupBorderWidth = 1.0;

@implementation FrotzInputHelper
@synthesize delegate = m_delegate;

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        m_history = [[NSMutableArray alloc] initWithCapacity: 2];
        m_commonCommands = @[@"about ", @"all ", @"and ", @"ask ", @"at ", @"attack ", @"behind ", @"but ", @"cast ", @"climb ", @"door ", @"down ", @"from ", @"get ", @"give ", @"help ",
                            @"in ",@"jump ", @"kick ", @"kill ", @"learn ", @"leave ", @"memorize ", @"no", @"off ", @"on ", @"push ", @"pull ", @"put ", @"read ", @"remove ", @"say ", @"search ", @"switch ",  @"take ", @"talk ", @"tell ", @"then ",
                            @"through ", @"throw ", @"tie ", @"to ", @"touch ", @"turn", @"under ", @"untie ", @"up ", @"wait ", @"wear ",@"window ", @"with ", @"quit ", @"yes", @", ", @". ", @"\"",
                            @"brief", @"diagnose", @"save", @"score", @"restart", @"restore", @"undo", @"verbose"];
        m_mode = FrotzInputHelperModeNone;
        m_lastTabMode = FrotzInputHelperModeWords;
        m_lastCommonWordPicked = 0;
        m_currHistoryItem = 0;
    }
    return self;
}

- (UIView*)helperView {
    if (m_mode == FrotzInputHelperModeNone)
        return nil;
    return m_popupView;
}

- (FrotzInputHelperMode)lastTabMode {
    return m_lastTabMode;
}

-(void)loadView {
    [super loadView];
    UITableView *tableView = [self tableView];
    [tableView setShowsVerticalScrollIndicator: YES];
    [tableView setBounces: NO];
    [tableView setBackgroundColor: [UIColor clearColor]];
    [tableView setSeparatorStyle: UITableViewCellSeparatorStyleNone];
    [tableView setContentInset: UIEdgeInsetsMake(0, 0, 0, 0)];
    if (@available(iOS 15.0, *))
        tableView.sectionHeaderTopPadding = 0;

    NSArray* nibViews =  [[NSBundle mainBundle] loadNibNamed:@"FrotzWordPicker" owner:self options:nil];
    m_wordPicker = nibViews[0];

    NSArray *subViews = [m_wordPicker subviews];
    UIButton *b;
    for (b in subViews) {
        [b addTarget:self action:@selector(butttonPressed:) forControlEvents:UIControlEventTouchUpInside];
    }

    // The popup takes the picker's look (its nib has the system background) so that the picker,
    // the tabs and the table read as one panel; the picker itself goes transparent. A gray border
    // sets the panel off from a light story background, where the edge was otherwise lost.
    CGRect pickerFrame = m_wordPicker.frame;
    m_pickerSize = pickerFrame.size; // kept apart from the frame, which layout stretches for the table
    m_popupView = [[UIView alloc] initWithFrame: CGRectMake(0, 0, pickerFrame.size.width, kTabBarHeight + pickerFrame.size.height)];
    m_popupView.backgroundColor = m_wordPicker.backgroundColor;
    m_popupView.alpha = kPopupAlpha;
    m_popupView.layer.cornerRadius = kPopupCornerRadius;
    m_popupView.layer.borderWidth = kPopupBorderWidth;
    m_popupView.layer.borderColor = [UIColor systemGrayColor].CGColor;
    m_popupView.clipsToBounds = YES;
    m_wordPicker.backgroundColor = [UIColor clearColor];
    m_wordPicker.alpha = 1.0;

    // A plain tab bar rather than a UISegmentedControl: on iOS 26 the segmented control's glass
    // selection indicator swells past the control while it slides, and magnifying the panel's edge
    // and border looked wrong at this size. The highlight here is a flat pill that slides, quickly,
    // within the bar.
    m_tabBar = [[UIView alloc] initWithFrame: CGRectZero];
    m_tabBar.backgroundColor = [UIColor clearColor];
    m_tabIndicator = [[UIView alloc] initWithFrame: CGRectZero];
    m_tabIndicator.backgroundColor = [UIColor secondarySystemFillColor];
    m_tabIndicator.layer.cornerRadius = kTabCornerRadius;
    m_tabIndicator.userInteractionEnabled = NO;
    [m_tabBar addSubview: m_tabIndicator];
    NSArray<NSString*> *tabTitles = @[NSLocalizedString(@"Commands", @""), NSLocalizedString(@"History", @"")];
    for (NSInteger i = 0; i < 2; i++) {
        UIButton *tab = [UIButton buttonWithType: UIButtonTypeSystem];
        tab.tag = i;
        [tab setTitle: tabTitles[i] forState: UIControlStateNormal];
        [tab setTitleColor: [UIColor labelColor] forState: UIControlStateNormal];
        [tab addTarget: self action: @selector(tabTapped:) forControlEvents: UIControlEventTouchUpInside];
        [m_tabBar addSubview: tab];
        m_tabButtons[i] = tab;
    }
    [self setSelectedTab: 0 animated: NO];
    [m_popupView addSubview: m_tabBar];

    // Everything but the tab control, so a switch can crossfade the content without touching the
    // segmented control's own selection animation.
    m_contentView = [[UIView alloc] initWithFrame: CGRectMake(0, kTabBarHeight, pickerFrame.size.width, pickerFrame.size.height)];
    m_contentView.backgroundColor = [UIColor clearColor];
    [m_popupView addSubview: m_contentView];

    UIButtonConfiguration *backConfig = [UIButtonConfiguration plainButtonConfiguration];
    backConfig.image = [UIImage systemImageNamed: @"chevron.left"];
    backConfig.title = NSLocalizedString(@"Commands", @"");
    backConfig.imagePadding = 4;
    backConfig.contentInsets = NSDirectionalEdgeInsetsMake(0, 6, 0, 6);
    backConfig.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithPointSize: 12 weight: UIImageSymbolWeightSemibold];
    backConfig.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey,id> *(NSDictionary<NSAttributedStringKey,id> *attrs) {
        NSMutableDictionary *out = [attrs mutableCopy];
        out[NSFontAttributeName] = [UIFont systemFontOfSize: 14];
        return out;
    };
    m_backButton = [UIButton buttonWithConfiguration: backConfig primaryAction: nil];
    m_backButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    [m_backButton addTarget: self action: @selector(backToWords) forControlEvents: UIControlEventTouchUpInside];
    m_backButton.accessibilityLabel = NSLocalizedString(@"Back to commands", @"");
    [m_contentView addSubview: m_backButton];

    m_emptyHistoryLabel = [[UILabel alloc] initWithFrame: CGRectZero];
    m_emptyHistoryLabel.text = NSLocalizedString(@"No commands yet", @"");
    m_emptyHistoryLabel.textAlignment = NSTextAlignmentCenter;
    m_emptyHistoryLabel.textColor = [UIColor systemGrayColor]; // secondaryLabelColor was too faint over the story
    m_emptyHistoryLabel.font = [UIFont systemFontOfSize: 14];

    [m_contentView addSubview: m_wordPicker];
    [m_contentView addSubview: tableView];
}

- (void)butttonPressed:(UIButton*)button {
    NSString *string = [button currentTitle];
    if ([string isEqualToString: @"..."])
        [self switchToMode: FrotzInputHelperModeMoreWords];
    else if (isupper([string characterAtIndex: 0]))
        [m_delegate inputHelperString: [string stringByAppendingString: @"\n"]];
    else
        [m_delegate inputHelperString: [string stringByAppendingString: @" "]];
}

// Only a tab the player chose is remembered for the next opening: a double tap opens on History
// without making it the default.
- (void)tabTapped:(UIButton*)tab {
    m_lastTabMode = tab.tag == 1 ? FrotzInputHelperModeHistory : FrotzInputHelperModeWords;
    [self switchToMode: m_lastTabMode];
}

// Moves the highlight pill to the given tab and makes its title the bold one.
- (void)setSelectedTab:(NSInteger)index animated:(BOOL)animated {
    for (NSInteger i = 0; i < 2; i++) {
        UIButton *tab = m_tabButtons[i];
        tab.titleLabel.font = i == index ? [UIFont systemFontOfSize: 14 weight: UIFontWeightSemibold] : [UIFont systemFontOfSize: 14];
        tab.accessibilityTraits = i == index ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected) : UIAccessibilityTraitButton;
    }
    CGRect indicatorFrame = CGRectInset(m_tabButtons[index].frame, kTabIndicatorInset, kTabIndicatorInset);
    if (animated)
        [UIView animateWithDuration: 0.12 animations: ^{ self->m_tabIndicator.frame = indicatorFrame; }];
    else
        m_tabIndicator.frame = indicatorFrame;
}

- (void)layoutTabBarWithWidth:(CGFloat)width {
    m_tabBar.frame = CGRectMake(kTabPadding, kTabPadding, width - 2 * kTabPadding, kTabControlHeight);
    CGFloat tabWidth = m_tabBar.bounds.size.width / 2;
    for (NSInteger i = 0; i < 2; i++)
        m_tabButtons[i].frame = CGRectMake(i * tabWidth, 0, tabWidth, kTabControlHeight);
}

- (void)backToWords {
    [self switchToMode: FrotzInputHelperModeWords];
}

- (FrotzInputHelperMode)mode {
    return m_mode;
}

-(void)hideInputHelper {
    m_mode = FrotzInputHelperModeNone;
    [m_popupView removeFromSuperview];
}

// Lines the table would show in full, before fitting the popup to the space available.
- (NSUInteger)preferredTableLinesInView:(UIView*)parentView {
    CGSize parentSize = parentView.bounds.size;
    BOOL isLandscape = parentSize.width > parentSize.height;
    BOOL regularWidth = parentView.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular;
    NSUInteger maxLines = regularWidth ? (isLandscape ? 14 : 24) : (isLandscape ? 6 : 7);
    if (![m_delegate isFirstResponder])
        maxLines += regularWidth ? 10 : 6;
    NSUInteger nLines = m_mode == FrotzInputHelperModeMoreWords ? [m_commonCommands count] : [m_history count];
    return MIN(nLines, maxLines);
}

// Sizes and places the popup for the current mode, growing up from the anchor point (its
// bottom-left corner). The popup is never shorter than the tabs plus the picker grid, so the
// tabs stay put when switching. When there isn't room below the parent's top safe-area inset (the
// navigation bar), the table gives up lines first; the grid can't shrink, so for it the popup is
// moved down over the command line instead, as the helper always did when space was short.
- (void)layoutPopupAnimated:(BOOL)animated {
    UIView *parentView = m_parentView;
    if (!parentView)
        return;
    CGSize pickerSize = m_pickerSize;
    CGFloat width = pickerSize.width;
    BOOL tableMode = m_mode != FrotzInputHelperModeWords;
    CGFloat backBar = m_mode == FrotzInputHelperModeMoreWords ? kBackBarHeight : 0;

    // The back button takes the top line of the table's space rather than adding to it, so the
    // long word list opens at the same height as the grid.
    CGFloat contentHeight = pickerSize.height;
    if (tableMode)
        contentHeight = MAX(contentHeight, kHistoryLineHeight * [self preferredTableLinesInView: parentView] + 2);

    CGFloat minY = parentView.safeAreaInsets.top;
    CGPoint pt = m_anchorPoint;
    CGFloat total = kTabBarHeight + contentHeight;
    if (tableMode && pt.y - total < minY) {
        CGFloat fitHeight = pt.y - minY - kTabBarHeight;
        contentHeight = MAX(fitHeight, backBar + kHistoryLineHeight * kMinTableLines + 2);
        total = kTabBarHeight + contentHeight;
    }
    if (pt.y - total < minY)
        pt.y = minY + total;
    if (pt.x + width > parentView.bounds.size.width)
        pt.x = MAX(0, parentView.bounds.size.width - width);

    CGRect popupFrame = CGRectMake(pt.x, pt.y - total, width, total);
    CGRect contentFrame = CGRectMake(0, kTabBarHeight, width, contentHeight);
    CGRect tableFrame = CGRectMake(0, backBar, width, contentHeight - backBar);
    m_popupView.frame = popupFrame;
    [self layoutTabBarWithWidth: width];
    if (!animated) // on a switch the pill is already sliding (applyMode); don't snap it
        [self setSelectedTab: m_mode == FrotzInputHelperModeHistory ? 1 : 0 animated: NO];
    void (^layout)(void) = ^{
        self->m_contentView.frame = contentFrame;
        self->m_backButton.frame = CGRectMake(0, 0, width, kBackBarHeight);
        self->m_wordPicker.frame = self->m_contentView.bounds;
        self.tableView.frame = tableFrame;
        self->m_emptyHistoryLabel.frame = self.tableView.bounds;
    };
    // The content crossfades; the popup frame and the tab control are set outright. The popup
    // rarely changes size on a switch (it is never shorter than the grid), animating the table's
    // frame while it reloads flickered, and a fade over the tab control fought the segmented
    // control's own animation of its selection indicator.
    if (animated)
        [UIView transitionWithView: m_contentView duration: 0.15 options: UIViewAnimationOptionTransitionCrossDissolve animations: layout completion: nil];
    else
        layout();
}

// Switches which content the popup shows. Followed by layoutPopupAnimated: and refreshTable.
- (void)applyMode:(FrotzInputHelperMode)mode {
    m_mode = mode;
    if ([m_popupView superview]) // otherwise the first layout places the pill
        [self setSelectedTab: mode == FrotzInputHelperModeHistory ? 1 : 0 animated: YES];
    m_wordPicker.hidden = mode != FrotzInputHelperModeWords;
    m_backButton.hidden = mode != FrotzInputHelperModeMoreWords;
    self.tableView.hidden = mode == FrotzInputHelperModeWords;
    // The data source answers for the new mode from here on, so the table must not keep rows
    // from the old one: a later layout (even of a hidden table) would ask for cells at the old
    // indexes, past the end of the new mode's array.
    [self.tableView reloadData];
}

// Scrolls the table to the current mode's row of interest. After layout, so the scroll is
// measured against the table's final size.
- (void)refreshTable {
    UITableView *tableView = [self tableView];
    if (tableView.hidden)
        return;
    FrotzInputHelperMode mode = m_mode;
    NSIndexPath *idx = [tableView indexPathForSelectedRow];
    if (idx)
        [tableView deselectRowAtIndexPath: idx animated:NO];
    NSInteger count = [self menuCount];
    tableView.backgroundView = (mode == FrotzInputHelperModeHistory && count == 0) ? m_emptyHistoryLabel : nil;
    NSInteger scrollTo = mode == FrotzInputHelperModeMoreWords ? m_lastCommonWordPicked : count - 1;
    if (scrollTo >= 0 && scrollTo < count)
        [tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow: scrollTo inSection:0]
                         atScrollPosition: mode == FrotzInputHelperModeMoreWords ? UITableViewScrollPositionMiddle : UITableViewScrollPositionBottom animated:NO];
}

// A tab switch, or the "..." / back buttons, while the popup is up.
- (void)switchToMode:(FrotzInputHelperMode)mode {
    if (mode == m_mode || m_mode == FrotzInputHelperModeNone)
        return;
    [self applyMode: mode];
    [self layoutPopupAnimated: YES];
    [self refreshTable];
}

-(void)showInputHelperInView:(UIView*)parentView atPoint:(CGPoint)pt withMode:(FrotzInputHelperMode)mode {
    if (mode == FrotzInputHelperModeNone) {
        [self hideInputHelper];
        return;
    }
    (void)[self view]; // load the popup
    m_parentView = parentView;
    m_anchorPoint = pt;
    BOOL wasShown = [m_popupView superview] == parentView;
    [self applyMode: mode];
    if (wasShown) {
        [self layoutPopupAnimated: YES];
        [self refreshTable];
        return;
    }
    [m_popupView removeFromSuperview];
    [self layoutPopupAnimated: NO];
    [self refreshTable];
    CGFloat alpha = m_popupView.alpha;
    m_popupView.alpha = 0.0;
    [parentView addSubview: m_popupView];
    [UIView animateWithDuration: 0.15 animations: ^{ self->m_popupView.alpha = alpha; }];
}

- (void)clearHistory {
    [m_history removeAllObjects];
    m_currHistoryItem = 0;
}

- (NSUInteger)historyCount {
    return [m_history count];
}

- (NSArray<NSString*>*)historyItems {
    return [m_history copy];
}

- (NSUInteger)menuCount {
    return m_mode == FrotzInputHelperModeMoreWords ? [m_commonCommands count] : [m_history count];
}

- (NSString*)historyItem:(NSInteger)item {
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

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return m_mode == FrotzInputHelperModeMoreWords ? [m_commonCommands count] : [m_history count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {

    static NSString *MyIdentifier = @"inputnamecell";

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:MyIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle: UITableViewCellStyleDefault reuseIdentifier:MyIdentifier];
        cell.textLabel.font = [UIFont systemFontOfSize: 15];
        cell.backgroundColor = [UIColor clearColor];
    }
    // Configure the cell
    NSString *item = m_mode == FrotzInputHelperModeMoreWords ? m_commonCommands[indexPath.row] : m_history[indexPath.row];
    cell.textLabel.text = item;
    // the last few common words are meta commands (save, undo...), set apart by color
    cell.textLabel.textColor = m_mode == FrotzInputHelperModeMoreWords && indexPath.row > [m_commonCommands count] - 9 ? [UIColor systemOrangeColor] : [UIColor labelColor];

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
    self.edgesForExtendedLayout=UIRectEdgeNone;
    [super viewDidLoad];
}

// A CGColor doesn't follow light/dark changes on its own; re-resolve the border.
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange: previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection: previousTraitCollection])
        m_popupView.layer.borderColor = [UIColor systemGrayColor].CGColor;
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
