//
//  NotesViewController.m
//  Frotz
//
//  Created by Craig Smith on 9/6/10.
//  Copyright 2010 Craig Smith. All rights reserved.
//

#import "iosfrotz.h"
#import "NotesViewController.h"

#define kNotesLandscapeInset 40

@interface HScrollView : UIScrollView
{
}
@end

@implementation HScrollView

-(void)setFrame:(CGRect)frame {
    //    NSLog(@"ntv setFrame: (%f,%f,%f,%f)", frame.origin.x, frame.origin.y, frame.size.width, frame.size.height);
    [super setFrame: frame];
    frame.size.width *= 2;
    [self setContentSize: frame.size];
}

@end

@implementation NotesViewController
@synthesize delegate = m_delegate;
@synthesize fontName = m_fontName;

- (NotesViewController*)initWithFrame:(CGRect)frame {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        m_frame = frame;
        m_defaultFontSize = 0;
        // Initialization code
    }
    return self;
}

-(void)setChainResponder:(UIResponder*)responder {
    m_chainResponder = responder;
}

-(void)setFrame:(CGRect)frame {
    m_frame = frame;
    NSLog(@"note setframe h=%f w=%f", frame.size.height, frame.size.width);
    if (m_notesView)
        [m_scrollView setFrame:frame];
}

static const int kNotesTitleHeight = 24;

-(UIScrollView*)containerScrollView {
    if (!m_scrollView)
        [self loadView];
    return m_scrollView;
}

-(void)loadView {
    if (m_notesBGView) {
        self.view = m_notesBGView;
        return;
    }
    UIFont *font = [UIFont fontWithName:m_fontName ? m_fontName : @"MarkerFelt-Wide" size:self.defaultFontSize];

    m_scrollView = [[HScrollView alloc] initWithFrame:m_frame];
    [m_scrollView setAutoresizingMask:UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth];
    [m_scrollView setAutoresizesSubviews:YES];
    [m_scrollView setDelegate: self];

    m_frame.size.width *= 2;
    [m_scrollView setContentSize: m_frame.size];
    m_frame.size.width /= 2;
    [m_scrollView setBounces: NO];
    [m_scrollView setPagingEnabled: YES];

    m_notesBGView = [[UIView alloc] init];
    m_notesBGView.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed: @"parchment2.jpg"]]; // was a UIImageView, now just an image bg color
    [m_notesBGView setFrame: CGRectMake(m_frame.size.width, 0, m_frame.size.width, m_frame.size.height)];
    [m_notesBGView setAutoresizesSubviews: YES];
    [m_notesBGView setAutoresizingMask: UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight];
    [m_notesBGView setUserInteractionEnabled:YES];

    self.view = m_notesBGView;

    UIImage *glyph = [UIImage imageNamed: @"notes"];
    m_notesTitle = [[UISegmentedControl alloc] initWithItems:@[@"Notes", glyph]];
    [m_notesTitle setWidth: 24 forSegmentAtIndex:1];
    [m_notesTitle setEnabled:FALSE forSegmentAtIndex:0];

    [m_notesTitle setTitleTextAttributes:@{UITextAttributeTextColor: [UIColor blackColor]} forState:UIControlStateDisabled];

    [m_notesTitle setMomentary:YES];
    m_notesTitle.segmentedControlStyle = UISegmentedControlStyleBar;
    m_notesTitle.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin;
    m_notesTitle.tintColor = [UIColor blackColor];

    m_notesTitle.center = CGPointMake(self.view.frame.size.width/2, m_notesTitle.frame.size.height/2);
    [m_notesTitle addTarget:self action:@selector(notesAction:) forControlEvents:UIControlEventValueChanged];
    
    [self setTitle: nil];
    [m_notesBGView addSubview: m_notesTitle];
    
    m_notesView = [[UITextView alloc] init];
    [m_notesView setFrame: CGRectMake(0 /*m_frame.size.width*/, kNotesTitleHeight, m_frame.size.width, m_frame.size.height-kNotesTitleHeight)];
    
    [m_notesView setEditable: YES];
    [m_notesView setDelegate: self];
    if (UIInterfaceOrientationIsLandscape([self interfaceOrientation]))
        m_notesView.textContainerInset = UIEdgeInsetsMake(0, kNotesLandscapeInset, 0, kNotesLandscapeInset);
    else
        m_notesView.textContainerInset = UIEdgeInsetsMake(0, 0, 0, 0);
    [m_notesView setAutoresizingMask:UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleLeftMargin];
    [m_notesView setBackgroundColor: [UIColor colorWithWhite:1.0 alpha:0.0]];
    [m_notesView setTextColor: [UIColor blackColor]];
    [m_notesView setFont: font];

    [m_notesView setAutocapitalizationType:UITextAutocapitalizationTypeNone];

    [m_notesBGView addSubview: m_notesView];
}

-(NSInteger)defaultFontSize {
    return m_defaultFontSize ? m_defaultFontSize : gLargeScreenDevice ? 20 : 16;
}

-(BOOL)hasCustomDefaultFontSize {
    return m_defaultFontSize != 0;
}

-(void)setDefaultFontSize:(NSInteger)size {
    m_defaultFontSize = size;
}

-(NSInteger)fontSize {
    return m_notesView ? (NSInteger)(m_notesView.font.pointSize) : self.defaultFontSize;
}

// note, m_fontName is only set when the font is explicitly set; the default marker felt font name isn't stored,
// so the synthesized self.fontName may return nil, but you can still query the actual font. This way we can change the
// default font in the future and it will only be saved in settings if the user explicitly changed it.
-(UIFont*)font {
    return m_notesView ? m_notesView.font : nil;
}

-(void)setFont:(UIFont*)font {
    m_fontName = [font fontName];
    if (m_notesView)
        [m_notesView setFont: font];
}

-(void)setFontName: (nullable NSString*)fontName {
    NSInteger size = self.defaultFontSize;
    [self setFont: [UIFont fontWithName: fontName size:(CGFloat)size]];
}

-(void)setFont: (NSString*)fontName withSize:(NSInteger)size {
    self.defaultFontSize = size;
    if (!fontName)
        fontName = m_fontName;
    if (fontName) {
        [self setFont: [UIFont fontWithName: fontName size:(CGFloat)size]];
    } else { // font name never set, leave default and just change size
        if (m_notesView)
            [m_notesView setFont: [m_notesView.font fontWithSize: (CGFloat)size]];
    }
}

-(UIFont*)fixedFont {
    return nil;
}

-(void)notesAction:(id)sender {
    NSInteger seg = [m_notesTitle selectedSegmentIndex];
    if (seg == 1) {
        FileBrowser *fileBrowser = [[FileBrowser alloc] initWithDialogType:kFBDoShowViewScripts];
        
        [fileBrowser setPath: [m_delegate textFileBrowserPath]];
        [fileBrowser setDelegate: self];
        if ([fileBrowser textFileCount] > 0) {
            UINavigationController *nc = [[UINavigationController alloc] initWithRootViewController: fileBrowser];
            nc.modalPresentationStyle = UIModalPresentationFormSheet;
            [m_delegate.navigationController presentModalViewController: nc animated: YES];
        }
    }
}

-(void) fileBrowser: (FileBrowser *)browser fileSelected:(NSString *)file {
    [m_delegate.navigationController dismissModalViewControllerAnimated:YES];
}

-(void) fileBrowser: (FileBrowser *)browser deleteFile: (NSString*)filePath {
    [m_delegate fileBrowser:browser deleteFile: filePath];
}

-(void)setTitle:(NSString *)title {
    NSString *text;
    if (title)
        text = [NSString stringWithFormat:@"Notes - %@", title];
    else
        text = @"Notes";
	[m_notesTitle setTitle: text forSegmentAtIndex:0];
    //	[m_notesTitle setText: text];
    [m_notesTitle setWidth: 0 forSegmentAtIndex:0];
    [m_notesTitle setWidth: 20 forSegmentAtIndex:1];
    [m_notesTitle sizeToFit];
    m_notesTitle.center = CGPointMake(m_scrollView.frame.size.width/2, m_notesTitle.frame.size.height/2);
}

-(NSString*)title {
    //    return [m_notesTitle text];
    return [m_notesTitle titleForSegmentAtIndex:0];
}

-(void)setText:(NSString*)text {
    [m_notesView setText: text ? text : @""];
}

-(NSString*)text {
    return [m_notesView text];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (scrollView == m_scrollView) {
        CGPoint ofst = [scrollView contentOffset];
        CGRect frame = [scrollView frame];
        if (ofst.x >= frame.size.width) {
            if (m_chainResponder && [m_chainResponder isFirstResponder])
                [m_notesView becomeFirstResponder];
        } else {
            if (m_chainResponder && [m_notesView isFirstResponder] && [m_chainResponder canBecomeFirstResponder]) {
                [m_chainResponder becomeFirstResponder];
                [scrollView setContentOffset:CGPointMake(scrollView.contentInset.left, scrollView.contentInset.top)];
            }
            else
                [m_notesView resignFirstResponder];
        }
        [m_delegate showKeyboardLockState];
    }
}

-(void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    CGPoint ofst = [scrollView contentOffset];
    if (scrollView == m_scrollView && decelerate) {
        [m_notesView setEditable: YES];
        if (m_chainResponder && [m_chainResponder isFirstResponder] && ofst.x >= scrollView.frame.size.width*0.75) {
            [m_notesView becomeFirstResponder];
        }
        [m_delegate showKeyboardLockState];
    }
}


-(BOOL)isVisible {
    CGPoint ofst = [m_scrollView contentOffset];
    return (ofst.x > 0);
}

-(void)show {
    CGRect frame = [m_scrollView frame];
    [m_notesView setEditable: YES];
    [m_scrollView setContentOffset:CGPointMake(frame.size.width, 0)];
}

-(void)hide {
    [m_scrollView setContentOffset:CGPointMake(0, 0)];
}

#if 0
- (BOOL)textViewShouldBeginEditing:(UITextView *)textView {
//    if (m_chainResponder) return [m_chainResponder canBecomeFirstResponder];
    return YES;
}
#endif

-(void) keyboardWillShow:(CGRect)kbBounds {
    CGRect notesFrame = [m_notesBGView frame];
    BOOL isVisible = [self isVisible];
    notesFrame.size.height = m_scrollView.frame.size.height - kbBounds.size.height;
    
    if (isVisible) {
        [UIView beginAnimations: @"noteskbd" context: 0];
        [UIView setAnimationDuration:0.3];
    }
    [m_notesBGView setFrame: notesFrame];
    if (isVisible)
        [UIView commitAnimations];
}

-(void) keyboardWillHide {
    CGRect notesFrame = [m_notesBGView frame];
    BOOL isVisible = [self isVisible];
    notesFrame.size.height = m_scrollView.frame.size.height;
    
    if (isVisible) {
        [UIView beginAnimations: @"noteskbd" context: 0];
        [UIView setAnimationDuration:0.3];
    }
    [m_notesBGView setFrame: notesFrame];
    if (isVisible)
        [UIView commitAnimations];
}

-(void)activateKeyboard {
    if ([self isVisible]) {
        [m_notesView becomeFirstResponder];
        [m_notesView setEditable: YES];
    }
}

-(void)workaroundFirstResponderBug {
    [m_notesView setEditable: NO];
}

-(void)dismissKeyboard {
    [m_notesView resignFirstResponder];
}

- (void)toggleKeyboard {
    if ([m_notesView isFirstResponder])
        [self dismissKeyboard];
    else
        [self activateKeyboard];
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    CGRect frame = m_scrollView.frame;
    frame.origin.x = frame.size.width*2; // make sure notes aren't temporarily visible during rotation
    [m_notesBGView  setFrame: frame];
    if ([m_scrollView contentOffset].x > 0)
        [m_scrollView setContentOffset: CGPointMake(0, 0)];
}

- (void)autosize {
    CGRect frame = m_scrollView.frame;
    
    frame.origin.x = frame.size.width;
    frame.origin.y = 0;
    [m_notesBGView  setFrame: frame];
    
    frame.size.width *= 2;
    [m_scrollView setContentSize: frame.size];
    if ([m_scrollView contentOffset].x > frame.size.width/4)
        [m_scrollView setContentOffset: CGPointMake(frame.size.width/2, 0)];
    else
        [m_scrollView setContentOffset: CGPointMake(0, 0)];

    if (UIInterfaceOrientationIsLandscape([self interfaceOrientation]))
        m_notesView.textContainerInset = UIEdgeInsetsMake(0, kNotesLandscapeInset, 0, kNotesLandscapeInset);
    else
        m_notesView.textContainerInset = UIEdgeInsetsMake(0, 0, 0, 0);
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [self autosize];
    if (m_chainResponder && [m_notesView isFirstResponder] && [m_chainResponder canBecomeFirstResponder]) {
        [m_chainResponder becomeFirstResponder];
    }
}

-(void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self autosize];
}

-(void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [m_notesView resignFirstResponder];
}

- (void)dealloc {
    m_scrollView = nil;
}

@end
