//
//  FontPicker.m
//  Frotz
//
//  Created by Craig Smith on 9/6/08.
//  Copyright 2008 Craig Smith. All rights reserved.
//

#import "FontPicker.h"

// FrotzFontPicker implemented as a lightweight shim on UIFontPickerViewController (iOS 13+ only)
API_AVAILABLE(ios(13.0)) @interface FontPickerImpl_FP : UIFontPickerViewController<FrotzFontPicker, UIFontPickerViewControllerDelegate> {
    id<FrotzFontDelegate> __weak m_delegate;
    BOOL m_fixedFontsOnly;
    UIView *m_navBarBlocker; // workaround UIFontPickerViewController bug; the font list bleeds under the nav bar, ignoring safe insets
}
-(void)setDelegate:(id<FrotzFontDelegate> _Nullable)delegate;
@property (nonatomic, assign) BOOL fixedFontsOnly;
@end

// Fallback FrotzFontPicker implemented directly using UITableViewController
@interface FontPickerImpl_TV : UITableViewController<FrotzFontPicker> {
    NSMutableArray *m_fonts;
    NSMutableArray *m_fixedFonts;
    id<FrotzFontDelegate> __weak m_delegate;
    BOOL m_fixedFontsOnly;
    BOOL m_includeFaces;
}

@property (nonatomic, weak) id<FrotzFontDelegate> delegate;
@property (nonatomic, assign) BOOL fixedFontsOnly;
@property (nonatomic, assign) BOOL includeFaces;
- (instancetype)init;
@end
// Turns out the font list is way too long without collapsing families together to be usable and I don't feel like
// implementing that just for pre-iOS 13.
#define AllowIncludeFacesWithOldFontPicker 0

@implementation FontPicker
+(UIViewController<FrotzFontPicker>*) frotzFontPickerWithTitle:(NSString*)title includingFaces:(BOOL)includeFaces monospaceOnly:(BOOL)monospaceOnly {
    UIViewController<FrotzFontPicker> *fp;
    if (@available(iOS 13.0, *)) {
        UIFontPickerViewControllerConfiguration *config = [[UIFontPickerViewControllerConfiguration alloc] init];
        config.includeFaces = includeFaces;
        // The filteredTraits interface is fucking next to useless.  You can't show only fonts with normal
        // weights, and you can't filter out the font with only symbols, because just a mask is not enough,
        // it needs both a mask and a compare-to value.
        // Basically the example of monospace selection is the only useful way to use the property.
        config.filteredTraits = monospaceOnly ? UIFontDescriptorTraitMonoSpace : 0;
        FontPickerImpl_FP *impl = [[FontPickerImpl_FP alloc] initWithConfiguration: config];
        impl.fixedFontsOnly = monospaceOnly;
        fp = impl;
    } else
    {
        FontPickerImpl_TV *impl = [[FontPickerImpl_TV alloc] init];
        // include faces not implemented
        impl.fixedFontsOnly = monospaceOnly;
        impl.includeFaces = includeFaces;
        fp = impl;
    }
    if (title)
        fp.title = title;
    return fp;
}

+(UIViewController<FrotzFontPicker>*) frotzFontPicker {
    return [FontPicker frotzFontPickerWithTitle:nil includingFaces:NO monospaceOnly:NO];
}

@end

// iOS 13 font picker implementation, trivial wrapper
@implementation FontPickerImpl_FP
@synthesize fixedFontsOnly = m_fixedFontsOnly;

-(void)setDelegate:(id<FrotzFontDelegate>)delegate {
    [super setDelegate: self];
    m_delegate = delegate;
}

- (void)fontPickerViewControllerDidPickFont:(UIFontPickerViewController *)viewController {
    UIFontDescriptor *fontDesc = viewController.selectedFontDescriptor;
    UIFont *font = [UIFont fontWithDescriptor:fontDesc size:[m_delegate fontSize]];
    [m_delegate setFont:font];
}

- (void)fontPickerViewControllerDidCancel:(UIFontPickerViewController *)viewController {
}

- (void)loadView {
    [super loadView];

    m_navBarBlocker = [[UIView alloc] initWithFrame: CGRectMake(0, 0, self.view.frame.size.width, 44)];
    m_navBarBlocker.backgroundColor = [UIColor systemBackgroundColor];

    [self.view addSubview:m_navBarBlocker];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    // Work around iOS bug where the font list draws under the nav bar when you scroll up by creating
    // an opaque view at the top of the content area (positioned underneath the nav bar).
    // Attempts at using content insets to fix this failed; they are already set correctly but are being ignored.
    // Trying to use additionalSafeAreaInsets left space below the nav bar, not under it.
    CGFloat navigationBarHeight = self.navigationController.navigationBar.frame.size.height;
    m_navBarBlocker.frame = CGRectMake(0, 0, self.view.frame.size.width, navigationBarHeight);
    m_navBarBlocker.backgroundColor = [UIColor systemBackgroundColor];

    [self.view bringSubviewToFront: m_navBarBlocker];
}

-(void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    m_navBarBlocker.backgroundColor = [UIColor systemBackgroundColor];
}
@end

// TableView-based implementation (pre-iOS 13) font picker classes

@interface FrotzFontInfo : NSObject {
    NSString *family;
    NSString *fontName;
    UIFont *font;
}
-(instancetype)initWithFamily:(NSString*)aFamily fontName:(NSString*)aFont font:(UIFont*)aFont NS_DESIGNATED_INITIALIZER;
-(instancetype)init NS_UNAVAILABLE;

@property(nonatomic,strong) NSString *family;
@property(nonatomic,strong) NSString *fontName;
@property(nonatomic,strong) UIFont *font;
@end

@implementation FrotzFontInfo
@synthesize family;
@synthesize fontName;
@synthesize font;

-(instancetype)initWithFamily:(NSString*)aFamily fontName:(NSString*)aFontName font:(UIFont*)aFont {
    if ((self = [super init])) {
        self.family = aFamily;
        self.fontName = aFontName;
        self.font = aFont;
    }
    return self;
}
-(NSString*)description {
    return self.fontName;
}
@end

@implementation FontPickerImpl_TV
@synthesize delegate = m_delegate;
@synthesize fixedFontsOnly = m_fixedFontsOnly;
@synthesize includeFaces = m_includeFaces;

static NSInteger sortFontsByFamilyName(id a, id b, void *context) {
    FrotzFontInfo *fa = (FrotzFontInfo*)a;
    FrotzFontInfo *fb = (FrotzFontInfo*)b;
    NSComparisonResult res = [fa.family caseInsensitiveCompare: fb.family];
    if (res == NSOrderedSame)
        res = [fa.fontName caseInsensitiveCompare: fb.fontName];
    return res;
} 

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        m_fonts = [[NSMutableArray alloc] initWithCapacity: 75];
        m_fixedFonts = [[NSMutableArray alloc] initWithCapacity: 10];
    }
    return self;
}

-(void)loadView {
    [super loadView];
    [m_fonts removeAllObjects];
    [m_fixedFonts removeAllObjects];
    NSArray *fontFamilies = [UIFont familyNames];
    for (NSString *familyName in fontFamilies) {
        NSArray *fonts = [UIFont fontNamesForFamilyName: familyName];
        UIFont *font = nil;
        BOOL isMonoSpace = NO;
        for (NSString *aFontName in fonts) {
            font = [UIFont fontWithName: aFontName size: 16];
            UIFontDescriptorSymbolicTraits symtraits = font.fontDescriptor.symbolicTraits;
            if ((symtraits & UIFontDescriptorClassMask) == UIFontDescriptorClassSymbolic)
                continue;
            if ((!AllowIncludeFacesWithOldFontPicker || !m_includeFaces) && ((symtraits & (UIFontDescriptorTraitBold|UIFontDescriptorTraitItalic)) != 0))
                continue;
            if (symtraits & UIFontDescriptorTraitMonoSpace)
                isMonoSpace = YES;
            [m_fonts addObject: [[FrotzFontInfo alloc] initWithFamily: familyName fontName:aFontName font:font]];
            if (isMonoSpace)
                [m_fixedFonts addObject: [[FrotzFontInfo alloc] initWithFamily: familyName fontName:aFontName font:font]];
            if (!AllowIncludeFacesWithOldFontPicker || !m_includeFaces)
                break;
        }
    }
    [m_fonts sortUsingFunction: sortFontsByFamilyName context: nil];
    [m_fixedFonts sortUsingFunction: sortFontsByFamilyName context: nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [m_fixedFontsOnly ? m_fixedFonts : m_fonts count];
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	
    static NSString *MyIdentifier = @"fontnamecell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:MyIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithFrame:CGRectZero reuseIdentifier:MyIdentifier];
    }
    // Configure the cell
    FrotzFontInfo *f = (m_fixedFontsOnly ? m_fixedFonts : m_fonts)[indexPath.row];
    cell.text = AllowIncludeFacesWithOldFontPicker && m_includeFaces ? f.fontName : f.family;
    cell.font = [UIFont fontWithName: cell.text size:16];
    return cell;
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (m_delegate && [m_delegate respondsToSelector: @selector(setFont:withSize:)]) {
        if (m_fixedFontsOnly) {
            FrotzFontInfo *f = m_fixedFonts[indexPath.row];
            [m_delegate setFixedFont: f.fontName];
        } else {
            FrotzFontInfo *f = m_fonts[indexPath.row];
            [m_delegate setFont: f.fontName withSize: [m_delegate fontSize]];
        }
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[self tableView] reloadData];

    if (m_delegate && [m_delegate respondsToSelector: @selector(fontName)]) {
        NSString *fontName = m_fixedFontsOnly ? [m_delegate fixedFont] : [m_delegate fontName];
        if (fontName) {
            NSArray *fontArr = m_fixedFontsOnly ? m_fixedFonts : m_fonts;
            int i;
            for (i = 0; i < [fontArr count]; ++i) {
                FrotzFontInfo *f = fontArr[i];
                if ([[f fontName] isEqualToString: fontName]) {
                    [[self tableView] selectRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0] animated:NO scrollPosition:UITableViewScrollPositionMiddle];
                    break;
                }
            }
        }
    }
}

@end
