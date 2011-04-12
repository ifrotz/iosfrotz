//
//  FontPicker.m
//  Frotz
//
//  Created by Craig Smith on 9/6/08.
//  Copyright 2008 Craig Smith. All rights reserved.
//

#import "FontPicker.h"
#import "UIFontExt.h"

@implementation FrotzFontInfo
@synthesize family;
@synthesize fontName;
@synthesize font;

-(id)initWithFamily:(NSString*)aFamily fontName:(NSString*)aFontName font:(UIFont*)aFont {
    if ((self = [super init])) {
        self.family = aFamily;
        self.fontName = aFontName;
        self.font = aFont;
    }
    return self;
}
@end

@implementation FontPicker

static NSInteger sortFontsByFamilyName(id a, id b, void *context) {
    FrotzFontInfo *fa = (FrotzFontInfo*)a;
    FrotzFontInfo *fb = (FrotzFontInfo*)b;
    return [fa.family caseInsensitiveCompare: fb.family];
} 

// ??? allow bold/italic toggles using [font traits] - italic/oblique 1,  bold 2
enum { kUIFontItalic=1, kUIFontBold=2 };

- (id)init {
    m_fonts = [[NSMutableArray alloc] initWithCapacity: 50];
    m_fixedFonts = [[NSMutableArray alloc] initWithCapacity: 50];
    self = [super initWithStyle:UITableViewStyleGrouped];
    return self;
}

-(void)loadView {
    [super loadView];
    [m_fonts removeAllObjects];
    [m_fixedFonts removeAllObjects];
    NSArray *fontFamilies = [UIFont familyNames];
    for (NSString *familyName in fontFamilies) {
        if ([familyName hasPrefix: @"STHeiti"] || [familyName hasPrefix: @"Hira"]
            || [familyName hasPrefix: @"Zapf"] || [familyName hasPrefix: @"Heit"]
            || [familyName hasPrefix: @"Geeza"])
            continue;
        NSArray *fonts = [UIFont fontNamesForFamilyName: familyName];
        NSString *fontName = nil;
        UIFont *font = nil;
        for (NSString *aFontName in fonts) {
            font = [UIFont fontWithName: aFontName size: 12];
            int traits = [font fontTraits];  // skip italic, etc. fonts.  traits not documented
            if (!traits) {
                fontName = aFontName;
                break;
            }
        }
        if (fontName) {
            [m_fonts addObject: [[[FrotzFontInfo alloc] initWithFamily: familyName fontName:fontName font:font] autorelease]];
            if (//[font isFixedPitch] || // this doesn't seem to ever return true forcing us to do nasty name comparisons
                [familyName hasPrefix: @"Courier"] || [familyName hasPrefix: @"American Typewriter"])
                [m_fixedFonts addObject: [[[FrotzFontInfo alloc] initWithFamily: familyName fontName:fontName font:font] autorelease]];
        }
    }
    [m_fonts sortUsingFunction: sortFontsByFamilyName context: nil];
    [m_fixedFonts sortUsingFunction: sortFontsByFamilyName context: nil];
}

- (void)setFixedFontsOnly:(BOOL)fixed {
    m_fixedFontsOnly = fixed;
}

-(NSObject*)delegate {
    return m_delegate;
}

-(void)setDelegate:(NSObject<FrotzFontDelegate>*)delegate {
    m_delegate = delegate;
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
        cell = [[[UITableViewCell alloc] initWithFrame:CGRectZero reuseIdentifier:MyIdentifier] autorelease];
    }
    // Configure the cell
    FrotzFontInfo *f = [m_fixedFontsOnly ? m_fixedFonts : m_fonts objectAtIndex: indexPath.row];
    cell.text = f.family;
    cell.font = [UIFont fontWithName: cell.text size:12];
    return cell;
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (m_delegate && [m_delegate respondsToSelector: @selector(setFont:withSize:)]) {
        if (m_fixedFontsOnly) {
            FrotzFontInfo *f = [m_fixedFonts objectAtIndex: indexPath.row];
            [m_delegate setFixedFont: f.fontName];
        } else {
            FrotzFontInfo *f = [m_fonts objectAtIndex: indexPath.row];
            [m_delegate setFont: f.fontName withSize: [m_delegate fontSize]];
        }
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
    [m_fonts release];
    [m_fixedFonts release];
    [super dealloc];
}

- (void)viewWillAppear:(BOOL)animated {
    
    if (m_fixedFontsOnly)
        self.title = NSLocalizedString(@"Set Fixed Font", @"");
    else
        self.title = NSLocalizedString(@"Set Story Font", @"");
    
    [super viewWillAppear:animated];
    [[self tableView] reloadData];
    if (m_delegate && [m_delegate respondsToSelector: @selector(font)]) {
        NSString *font = m_fixedFontsOnly ? [m_delegate fixedFont] : [m_delegate font];
        if (font) {
            NSArray *fontArr = m_fixedFontsOnly ? m_fixedFonts : m_fonts;
            int i;
            for (i = 0; i < [fontArr count]; ++i) {
                FrotzFontInfo *f = [fontArr objectAtIndex: i];
                if ([[f fontName] isEqualToString: font]) {
                    [[self tableView] selectRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0] animated:NO scrollPosition:UITableViewScrollPositionMiddle];
                    break;
                }
            }
        }
    }
    
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}


@end

