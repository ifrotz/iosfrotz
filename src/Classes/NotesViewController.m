//
//  NotesViewController.m
//  Frotz
//
//  Created by Craig Smith on 9/6/10.
//  Copyright 2010 Craig Smith. All rights reserved.
//

#import "iphone_frotz.h"
#import "NotesViewController.h"

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

- (NotesViewController*)initWithFrame:(CGRect)frame {
    m_frame = frame;
    if ((self = [super init])) {
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
#if 0
    if (m_scrollView) {
        self.view = m_scrollView;
        return;
    }
#endif
    UIFont *font = [UIFont fontWithName:@"MarkerFelt-Wide" size:gLargeScreenDevice ? 20:16];
    if (!font)
        font = [UIFont fontWithName:@"MarkerFelt-Thin" size:gLargeScreenDevice ? 20:16];

    m_scrollView = [[HScrollView alloc] initWithFrame:m_frame];
    [m_scrollView setAutoresizingMask:UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth];
    [m_scrollView setAutoresizesSubviews:YES];
    [m_scrollView setDelegate: self];

    m_frame.size.width *= 2;
    [m_scrollView setContentSize: m_frame.size];
    m_frame.size.width /= 2;
    [m_scrollView setBounces: NO];
    [m_scrollView setPagingEnabled: YES];

    m_notesBGView = [[UIImageView alloc] initWithImage: [UIImage imageNamed: @"parchment.jpg"]];
    [m_notesBGView setFrame: CGRectMake(m_frame.size.width, 0, m_frame.size.width, m_frame.size.height)];
    [m_notesBGView setAutoresizesSubviews: YES];
    [m_notesBGView setAutoresizingMask: UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight];
    [m_notesBGView setUserInteractionEnabled:YES];
    [m_notesBGView setContentMode:UIViewContentModeTopLeft];

    //new
    self.view = m_notesBGView;

    //    m_notesTitle = [[UILabel alloc] initWithFrame: CGRectMake(0, 0, m_frame.size.width, kNotesTitleHeight)];
    //    [m_notesTitle setBackgroundColor: [UIColor colorWithWhite:1.0 alpha:0.0]];
    //    [m_notesTitle setAutoresizingMask:UIViewAutoresizingFlexibleWidth];
    //    [m_notesTitle setTextAlignment: UITextAlignmentCenter];
    //    [m_notesTitle setFont: font];
    
    UIImage *glyph = [UIImage imageNamed: @"notes.png"];
    m_notesTitle = [[UISegmentedControl alloc] initWithItems:[NSArray arrayWithObjects: @"Notes", glyph, nil]];
    [m_notesTitle setWidth: 24 forSegmentAtIndex:1];
    [m_notesTitle setEnabled:FALSE forSegmentAtIndex:0];
#ifdef NSFoundationVersionNumber_iOS_6_1
    if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1)
        [m_notesTitle setTitleTextAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[UIColor blackColor], UITextAttributeTextColor, nil] forState:UIControlStateDisabled];
#endif

    [m_notesTitle setMomentary:YES];
    m_notesTitle.segmentedControlStyle = UISegmentedControlStyleBar;
    m_notesTitle.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin;
#ifdef NSFoundationVersionNumber_iOS_6_1
    if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1)
    {
       m_notesTitle.tintColor = [UIColor blackColor];
    } else
#endif
    {
        m_notesTitle.tintColor = [UIColor darkGrayColor];
    }
    m_notesTitle.center = CGPointMake(self.view.frame.size.width/2, m_notesTitle.frame.size.height/2);
    [m_notesTitle addTarget:self action:@selector(notesAction:) forControlEvents:UIControlEventValueChanged];
    
    [self setTitle: nil];
    [m_notesBGView addSubview: m_notesTitle];
    
    m_notesView = [[UITextView alloc] init];
    [m_notesView setFrame: CGRectMake(0 /*m_frame.size.width*/, kNotesTitleHeight, m_frame.size.width, m_frame.size.height-kNotesTitleHeight)];
    
    [m_notesView setEditable: YES];
    [m_notesView setDelegate: self];
    [m_notesView setAutoresizingMask:UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleLeftMargin];
    [m_notesView setBackgroundColor: [UIColor colorWithWhite:1.0 alpha:0.0]];
    [m_notesView setFont: font];

#ifdef NSFoundationVersionNumber_iOS_6_1
    if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_6_1) {
        m_notesView.keyboardAppearance = UIKeyboardAppearanceAlert;
    }
    [m_notesView setAutocapitalizationType:UITextAutocapitalizationTypeNone];
    //if (floor(NSFoundationVersionNumber) >= 1133.0) { // iOS 8.0 QuickType completion screws up notes
    //     [m_notesView setAutocorrectionType: UITextAutocorrectionTypeNo];
    //}
#else
    m_notesView.keyboardAppearance = UIKeyboardAppearanceAlert;
#endif

    //    UIButton *scriptBrowseButton = [UIButton buttonWithType: UIButtonTypeDetailDisclosure];
    //    [m_notesView addSubview: scriptBrowseButton];
    
//qqq    [m_scrollView addSubview: m_notesBGView];
    [m_notesBGView addSubview: m_notesView];
}

-(void)setDelegate:(UIViewController<TextFileBrowser,FileSelected,LockableKeyboard>*)delegate {
    m_delegate = delegate;
}

-(UIViewController<TextFileBrowser,FileSelected, LockableKeyboard>*)delegate {
    return m_delegate;
}

-(void)notesAction:(id)sender {
    NSInteger seg = [m_notesTitle selectedSegmentIndex];
    if (seg == 1) {
        FileBrowser *fileBrowser = [[FileBrowser alloc] initWithDialogType:kFBDoShowViewScripts];
        
        [fileBrowser setPath: [m_delegate textFileBrowserPath]];
        [fileBrowser setDelegate: self];
        if ([fileBrowser textFileCount] > 0) {
            if (gUseSplitVC) {
                UINavigationController *nc = [[UINavigationController alloc] initWithRootViewController: fileBrowser];
                [nc.navigationBar setBarStyle: UIBarStyleBlackOpaque];   
                nc.modalPresentationStyle = UIModalPresentationFormSheet;
                [m_delegate.navigationController presentModalViewController: nc animated: YES];
            } else {
                if (!gLargeScreenDevice)
                    [m_delegate.navigationController setNavigationBarHidden:NO animated:YES];
                [m_delegate.navigationController pushViewController: fileBrowser animated: YES];
            }
        }
        [fileBrowser release];
    }
}

-(void) fileBrowser: (FileBrowser *)browser fileSelected:(NSString *)file {
    if (gUseSplitVC) {
        UINavigationController *nc = browser.navigationController;
        [m_delegate.navigationController dismissModalViewControllerAnimated:YES];
        [nc release];
    }
    else {
        [m_delegate.navigationController popViewControllerAnimated:YES];
        if (!gLargeScreenDevice) {
            BOOL isLandscape = UIInterfaceOrientationIsLandscape([self interfaceOrientation]);
            [m_delegate.navigationController setNavigationBarHidden:isLandscape animated:YES];
        }
    }
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
    if (scrollView == m_scrollView && decelerate) {
        [m_notesView setEditable: YES];
        if (m_chainResponder && [m_chainResponder isFirstResponder]) {
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
    if ([m_scrollView contentOffset].x > 0)
        [m_scrollView setContentOffset: CGPointMake(frame.size.width/2, 0)];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [self autosize];
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
    [m_notesView release];
    [m_notesTitle release];
    [m_notesView release];
    [m_scrollView release];
    m_scrollView = nil;
    [super dealloc];
}

@end
