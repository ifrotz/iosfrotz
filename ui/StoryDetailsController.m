//
//  StoryDetailsController.m
//
//  Created by Craig Smith on 9/11/10.
//  Copyright 2010 Craig Smith. All rights reserved.
//

#import "StoryDetailsController.h"
#import "iosfrotz.h"

#import "StoryWebBrowserController.h"

@implementation StoryDetailsControllerNC
@end

@implementation FrotzImageView

@synthesize detailsController = m_detailsController;

- (void)releaseTapTimer {
    if (m_tapTimer) {
        [m_tapTimer invalidate];
    }
    m_tapTimer = nil;
}
- (void)timerFireMethod:(NSTimer*)theTimer {
    [self releaseTapTimer];
    [self displayMenu];
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    if (![self isMagnified]) {
        NSDate *fireTime = [NSDate dateWithTimeIntervalSinceNow: 0.5];
        m_tapTimer = [[NSTimer alloc] initWithFireDate: fireTime interval:0.0
                                                target:self selector:@selector(timerFireMethod:) userInfo:nil repeats:NO];
        [[NSRunLoop currentRunLoop] addTimer: m_tapTimer forMode: NSDefaultRunLoopMode];
    }
}
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    if (m_tapTimer && [m_tapTimer isValid]) {
        NSDate *newTime = [NSDate dateWithTimeIntervalSinceNow: 0.3];
        [m_tapTimer setFireDate: newTime];
	}
}
-(BOOL)isMagnified {
    return (m_savedBounds.size.width != 0);
}
-(void)resetMagnification {
    if ([self isMagnified]) {
        self.frame = m_savedBounds;
        m_savedBounds = CGRectZero;
        [m_detailsController dimDescription: NO];
        self.translatesAutoresizingMaskIntoConstraints = NO;
    }
}

-(void)magnifyImage:(BOOL)toggle {
    if ([self isMagnified]) {
        [UIView beginAnimations:@"artmag" context:0];
        [UIView setAnimationTransition:UIViewAnimationTransitionNone forView:self cache:YES];
        [self resetMagnification];
        [UIView commitAnimations];
    } else if (toggle) {
        const CGFloat kFactor = 0.9;
        CGRect bounds = [self bounds];
        CGSize imageSize = self.image.size;
        CGSize superSize = self.superview.bounds.size;
        if (imageSize.width < superSize.width * kFactor
            && imageSize.height < superSize.height * kFactor)
            superSize = imageSize;
        else {
            superSize.width *= kFactor;
            superSize.height *= kFactor;
        }
        if (m_detailsController.artwork
            && self.traitCollection.verticalSizeClass != UIUserInterfaceSizeClassCompact 
            && (imageSize.width > bounds.size.width * 1.1 || imageSize.height > bounds.size.height * 1.1))
        {
            [UIView beginAnimations:@"artmag" context:0];
            [UIView setAnimationTransition:UIViewAnimationTransitionNone forView:self cache:YES];
            m_savedBounds = self.frame;
            bounds.size = superSize;
            self.translatesAutoresizingMaskIntoConstraints = YES;
            self.bounds = bounds;
            [self.superview bringSubviewToFront: self];
            [m_detailsController dimDescription: YES];
            [UIView commitAnimations];
        }
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    [self releaseTapTimer];
    if ([m_detailsController keyboardIsActive]) {
        [m_detailsController dismissKeyboard];
        return;
    }
    UITouch *touch = [touches anyObject];
    NSUInteger tapCount = [touch tapCount];
    if ([self isMagnified] && tapCount == 1)
        [self magnifyImage: NO];
    else if (tapCount == 2)
        [self magnifyImage: YES];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [self releaseTapTimer];
}

-(void)displayMenu {
    if ([self becomeFirstResponder]) {
        UIMenuController *sharedMenuController = [UIMenuController sharedMenuController];
        [sharedMenuController setTargetRect: self.frame inView:self.superview];
        [sharedMenuController setMenuVisible:YES animated:YES];
    }
}

-(BOOL)canBecomeFirstResponder {
    return YES;
}

static NSString *kAppleWebArchivePBType = @"Apple Web Archive pasteboard type";
static NSString *kWebSubResourcesKey = @"WebSubresources";
static NSString *kWebResourceMIMETypeKey = @"WebResourceMIMEType";
static NSString *kWebResourceDataKey = @"WebResourceData";

static NSData *pasteboardWebArchiveImageData(UIPasteboard* gpBoard) {
    if ([gpBoard containsPasteboardTypes: @[kAppleWebArchivePBType]]) {
        NSData *data = [gpBoard dataForPasteboardType: kAppleWebArchivePBType];
        if (data) {
            NSString *errorStr = nil;
            NSPropertyListFormat plFmt;
            NSDictionary *dict = [NSPropertyListSerialization propertyListFromData:data mutabilityOption:NSPropertyListImmutable 
                                                                            format:&plFmt errorDescription:&errorStr];
            if (dict && [dict respondsToSelector:@selector(objectForKey:)]) {
                NSArray *resources = dict[kWebSubResourcesKey];
                if (resources && [resources count]==1) {
                    NSDictionary *subDict = resources[0];
                    NSString *mimeType = subDict[kWebResourceMIMETypeKey];
                    if ([mimeType isEqualToString: @"image/jpeg"] || [mimeType isEqualToString:@"image/png"])
                        return subDict[kWebResourceDataKey];
                }
            }
        }
    }
    return nil;
}

-(BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if (action == @selector(copy:))
        return (m_detailsController.artwork != nil);
    if (action == @selector(paste:)) {
        if (![m_detailsController isEditing])
            return NO;
        UIPasteboard *gpBoard = [UIPasteboard generalPasteboard]; 
        if ([gpBoard containsPasteboardTypes: UIPasteboardTypeListImage])
            return YES;
        if (pasteboardWebArchiveImageData(gpBoard) != nil)
            return YES;
        return NO;	    
    }
    return [super canPerformAction:action withSender:sender];
}

-(void)copy:(id)sender {
    UIPasteboard *gpBoard = [UIPasteboard generalPasteboard];
    [gpBoard setImage: self.image];
}

-(void)paste:(id)sender {
        UIAlertController *alertController =
          [UIAlertController alertControllerWithTitle: @"Paste artwork?"
                                              message: @"This will replace previous artwork"
                                       preferredStyle: UIAlertControllerStyleAlert];
        [alertController addAction:
        [UIAlertAction actionWithTitle: @"Paste" style: UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
                    [self doPaste];
                }]];
        [alertController addAction:
        [UIAlertAction actionWithTitle: @"Cancel" style: UIAlertActionStyleCancel handler:^(UIAlertAction *action) { }]];
    [m_detailsController presentViewController:alertController animated:YES completion:^{ }];
}

-(void)doPaste {
    UIPasteboard *gpBoard = [UIPasteboard generalPasteboard]; 
    UIImage *img = nil;
    if ([gpBoard containsPasteboardTypes: UIPasteboardTypeListImage]) {
        img = [gpBoard image];
    } else {
        NSData *data = pasteboardWebArchiveImageData(gpBoard);
        img = [UIImage imageWithData: data];
    }
    if (img) {
        self.detailsController.artwork = img;
        [self.detailsController refresh];
        NSData *data = UIImageJPEGRepresentation(img, 0.8);
        if (data)
            [m_detailsController.storyBrowser addSplashData:data forStory: [m_detailsController.storyInfo.path storyKey]];
    }
}

//-(void)setFrame:(CGRect)frame {
//    NSLog(@"frotz image view size %f,%f +%fx%f", frame.origin.x, frame.origin.y, frame.size.width, frame.size.height);
//    [super setFrame: frame];
//}

@end


@implementation StoryDetailsController

@dynamic storyTitle;
@dynamic author;
@dynamic tuid;
@dynamic artwork;

@synthesize storyInfo = m_storyInfo;
@synthesize storyBrowser = m_browser;
@synthesize contentView = m_contentView;
@synthesize descriptionWebView = m_descriptionWebView;
@synthesize flipper = m_flipper;
@synthesize infoButton = m_infoButton;
@synthesize descriptionHTML = m_descriptionHTML;
@synthesize willResume = m_willResume;

-(void)clear {
    self.storyTitle = @"";
    self.author = @"";
    self.tuid = @"";
    self.artwork = nil;
    self.descriptionHTML = nil;
    self.storyInfo = nil;
    
    [self refresh];
}

-(void)dimDescription:(BOOL)dim {
    m_descriptionWebView.alpha = dim ? 0.3 : 1.0;
    m_descriptionWebView.translatesAutoresizingMaskIntoConstraints = dim;
}

-(void)updateSelectStoryHint {
    if (m_title && [m_title length] > 0 || m_storyInfo) {
        m_portraitCover.hidden = YES;
        m_textFieldsView.hidden = NO;
        m_descriptionWebView.hidden = self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact ? YES : NO;
        m_noArtworkLabel.hidden = m_artwork ? YES : NO;
        m_playButton.hidden = NO;
        m_ifdbButton.hidden = NO;
    } else {
        m_portraitCover.hidden = NO;
        m_textFieldsView.hidden = YES;
        m_descriptionWebView.hidden = YES;
        m_noArtworkLabel.hidden = YES;
        m_playButton.hidden = YES;
        m_ifdbButton.hidden = YES;
    }
}

-(void)refresh {
    if (m_storyInfo != nil && [m_browser canEditStoryInfo])
        self.navigationItem.rightBarButtonItem = [self editButtonItem];
    else {
        self.navigationItem.rightBarButtonItem = nil;
        if (self.isEditing)
            self.editing = NO;
    }
    if (![self isEditing]) {
        [self dismissKeyboard];
        [m_titleField setText: m_title];
        [m_authorField setText: m_author];
        [m_TUIDField setText: m_tuid];
    }
    
    if (m_descriptionWebView) {
        [m_realWebView loadHTMLString:
         [NSString stringWithFormat:
          @"<html><body><style type=\"text/css\">\n"
          "h2 { font-size: 12pt; color:#cfcf00; } h3 { font-size: 11pt; color:#cfcf00; } p { font-size:10pt; }\n"
          "* { color:#ffffff; background: #666666 } ul { margin-left: 0.2em; padding-left: 1em; margin-right: 0.2em;}\n</style>\n"
          "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
          "%@\n<br/>%@%@<br/>\n"
          "</body></html\n",
          ([m_descriptionHTML length] > 0
           ? [m_descriptionHTML stringByReplacingOccurrencesOfString:@"<img " withString:@"<!img "]
           : @"<i>No description available.</i><br><br>"),
          [NSString stringWithFormat: @"<small>Story filename: %@</small><br/>", [[m_storyInfo path] lastPathComponent]],
          ([m_tuid length] > 0
           ? @"<small>Tap 'View in IFDB' for more information.</small>" : @"")
          ] baseURL:nil];
    }
    
    m_playButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    if (m_willResume) {
        if (gLargeScreenDevice) {
            [m_playButton setTitle: @"Resume Story" forState:UIControlStateNormal];
        } else {
            [m_playButton setTitle: @"Resume Story" forState:UIControlStateNormal];
        }
        m_restartButton.hidden = NO;
    } else {
        [m_playButton setTitle: @"Play Story" forState:UIControlStateNormal];
        m_playButton.titleEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 0);
        m_restartButton.hidden = YES;
    }
    
    BOOL enable = (m_storyInfo!=nil && ![self isEditing]);
    [m_playButton setEnabled: enable];
    [m_playButton setAlpha: enable ? 1.0 : 0.5];
    if (enable)
        enable = m_tuid != nil && [m_tuid length] > 0;
    [m_ifdbButton setEnabled: enable];
    [m_ifdbButton setAlpha: enable ? 1.0 : 0.5];
    [m_restartButton.superview bringSubviewToFront: m_restartButton];
    if (m_artworkView) {
        if (m_artwork) {
            [m_artworkView setImage: m_artwork];
            [m_artworkView setAlpha: 1.0];
        } else {
            [m_artworkView setImage: [UIImage imageNamed: @"compass-med"]];
            [m_artworkView setAlpha: 0.25];
        }
    }
    [self updateSelectStoryHint];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing: editing animated: animated];
    if (editing) {
        if (m_infoButton)
            [m_infoButton setEnabled:NO];
        [m_titleField setBorderStyle: UITextBorderStyleRoundedRect];
        [m_authorField setBorderStyle: UITextBorderStyleRoundedRect];
        [m_TUIDField setBorderStyle: UITextBorderStyleRoundedRect];
        [m_titleField becomeFirstResponder];
    } else {
        [self dismissKeyboard];
        if (m_infoButton)
            [m_infoButton setEnabled:YES];
        [m_titleField setBorderStyle: UITextBorderStyleNone];
        [m_authorField setBorderStyle: UITextBorderStyleNone];
        [m_TUIDField setBorderStyle: UITextBorderStyleNone];
    }
    [self refresh];
}

-(void)viewDidLoad {
    [super viewDidLoad];

    [m_browser.splitViewController setDelegate: m_browser];

    m_realWebView = [[WKWebView alloc] init];
    [m_descriptionWebView addSubview: m_realWebView];
#if UseWKWebViewForFrotzStoryDetails
    [m_realWebView setNavigationDelegate: self];
#else
    [m_realWebView setDelegate: self];
#endif
    [m_realWebView setFrame: m_descriptionWebView.bounds];
    [m_realWebView setAutoresizingMask: UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight];
    [m_descriptionWebView setAutoresizesSubviews: YES];

    m_artSizePortrait = m_artworkView.bounds.size;
    
    // Originally we let auto-rotate resizing compute the landscape bounds, and cached it.
    // For some reason in iOS 4.2 this doesn't work because the frame hasn't been scaled yet
    // in willAnimRotation...  so I'm initializing it here with a hardcoded scale of half.
    m_artSizeLandscape = m_artworkView.bounds.size;
    CGFloat landscapeScale = gLargeScreenDevice ? 0.5 : 0.8;
    m_artSizeLandscape.width *= landscapeScale;
    m_artSizeLandscape.height *= landscapeScale;
    
    m_artworkView.detailsController = self;

    
    if (m_descriptionWebView) {
        NSArray *subviews = m_realWebView.subviews;
        if ([subviews count] > 0) {
            UIScrollView *sv = subviews[0];
            if (sv && [sv respondsToSelector:@selector(setBounces:)])
                [sv setBounces:NO];
        }
    }
    if (!m_frotzInfoController)
        m_frotzInfoController = [[FrotzInfo alloc] initWithSettingsController:[m_browser settings] navController:self.navigationController navItem:self.navigationItem];
    self.navigationItem.titleView = [m_frotzInfoController view];

    self.edgesForExtendedLayout=UIRectEdgeNone;
}

-(void)viewDidAppear:(BOOL)animated {
    [self updateSelectStoryHint];
    [self updateBarButtonAndSelectionInstructions: self.splitViewController.displayMode];
}

-(void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (@available(iOS 13.0, *)) {
        [self.navigationController.navigationBar setBarStyle: UIBarStyleDefault];
        [self.navigationController.navigationBar setBarTintColor: [UIColor systemBackgroundColor]];
        [self.navigationController.navigationBar setTintColor: [UIColor labelColor]];
    } else {
        [self.navigationController.navigationBar setBarStyle: UIBarStyleBlack];
        [self.navigationController.navigationBar setBarTintColor: [UIColor whiteColor]];
        [self.navigationController.navigationBar setTintColor: [UIColor darkGrayColor]];
    }

    // animation works around issues when returnig to details from story
    [UIView animateWithDuration:0.5f delay:0.0f usingSpringWithDamping:1.0f initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.splitViewController.preferredDisplayMode = UISplitViewControllerDisplayModeAutomatic;
        [self.view setNeedsUpdateConstraints];
        [self.view layoutIfNeeded];
    } completion:NULL];

    [self updateBarButtonAndSelectionInstructions: UISplitViewControllerDisplayModeAutomatic];
    [self updateSelectStoryHint];
    [m_artworkView resetMagnification];
    [self refresh];
}

-(void)viewDidLayoutSubviews {
    [self refresh];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [m_artworkView resetMagnification];
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context)
     {
        [self updateSelectStoryHint];
     } completion:^(id<UIViewControllerTransitionCoordinatorContext> context)
     {
        [self updateBarButtonAndSelectionInstructions: UISplitViewControllerDisplayModeAutomatic];
        [self refresh];
     }];

    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
}

-(void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [m_artworkView magnifyImage: NO];
    [self setEditing: NO animated: animated];
}

-(void)updateBarButtonAndSelectionInstructions:(UISplitViewControllerDisplayMode)displayMode {
    if (displayMode == UISplitViewControllerDisplayModeAutomatic)
        displayMode = self.splitViewController.displayMode;
    if (displayMode == UISplitViewControllerDisplayModePrimaryOverlay && [self isEditing])
        [self setEditing:NO animated: YES];

    m_descriptionWebView.hidden = self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact ? YES : NO;
    if (displayMode == UISplitViewControllerDisplayModeAllVisible
        && self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular)
        m_portraitCoverLabel.text = @"Select a story to begin";
    else if (displayMode == UISplitViewControllerDisplayModePrimaryHidden
        && self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular)
        m_portraitCoverLabel.text = @"Tap 'Select Story' to begin";
    else // if (self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact)
        m_portraitCoverLabel.text = nil;

    if (displayMode == UISplitViewControllerDisplayModeAllVisible) {
        self.navigationItem.leftBarButtonItem = nil;
    } else if (displayMode == UISplitViewControllerDisplayModePrimaryHidden || displayMode == UISplitViewControllerDisplayModePrimaryOverlay) {
        [self setEditing: NO animated: YES];
        if (self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact) {
            self.navigationItem.leftBarButtonItem = nil; // will have Back button instead
        }
        else
            self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Select Story" style:UIBarButtonItemStylePlain target:self.splitViewController.displayModeButtonItem.target action:self.splitViewController.displayModeButtonItem.action];
    }
}

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField {
    if (!m_storyInfo || ![m_storyInfo path] || [[m_storyInfo path] length] == 0)
        return NO;
    if (![self isEditing])
        return NO;
    return YES;
}

-(void)textFieldDidEndEditing:(UITextField *)textField {
    if (textField == m_titleField)
        self.storyTitle = m_titleField.text;
    else if (textField == m_authorField)
        self.author = m_authorField.text;
    else if (textField == m_TUIDField)
        self.tuid = m_TUIDField.text;
    [m_browser storyInfoChanged];
}

-(NSString*)storyTitle {
    return m_title;
}

-(void)setStoryTitle:(NSString*)title {
    if (m_title == title)
        return;
    m_title = title;
    if (m_titleField)
        [m_titleField setText: m_title];
    [m_artworkView magnifyImage:NO];
}

-(NSString*)author {
    return m_author;
}

-(void)setAuthor:(NSString*)author {
    if (m_author == author)
        return;
    m_author = author;
    if (m_authorField)
        [m_authorField setText: m_author];
}

-(NSString*)tuid {
    return m_tuid;
}

-(void)setTUID:(NSString*)tuid {
    if (m_tuid == tuid)
        return;
    m_tuid = tuid;
    if (m_TUIDField)
        [m_TUIDField setText: m_tuid];
    
}

-(UIImage*)artwork {
    return m_artwork;
}

-(void)setArtwork:(UIImage*)artwork {
    if (m_artwork == artwork)
        return;
    m_artwork = artwork;
    [self refresh];
}

-(BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == m_titleField)
        [m_authorField becomeFirstResponder];
    else
        [textField resignFirstResponder];
    return YES;
}

-(BOOL)keyboardIsActive {
    return ([m_titleField isFirstResponder] || [m_authorField isFirstResponder] || [m_TUIDField isFirstResponder]);
}

-(IBAction)dismissKeyboard {
    if ([m_titleField isFirstResponder])
        [m_titleField resignFirstResponder];
    else if ([m_authorField isFirstResponder])
        [m_authorField resignFirstResponder];
    else if ([m_TUIDField isFirstResponder])
        [m_TUIDField resignFirstResponder];
}

-(IBAction)playButtonPressed {
    [m_browser launchStoryInfo: m_storyInfo];
}

-(IBAction)showRestartMenu {
    UIAlertController *alertController =
      [UIAlertController alertControllerWithTitle: @"Restart the story?"
                                          message: @"This will abandon the current auto-saved game."
                                   preferredStyle: UIAlertControllerStyleActionSheet];
    UIPopoverPresentationController *popPresenter = [alertController
                                                  popoverPresentationController];
    popPresenter.sourceView = m_restartButton;
    popPresenter.sourceRect = m_restartButton.bounds;
    [alertController addAction:
    [UIAlertAction actionWithTitle: @"Restart from beginning"
            style: UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
                [[m_browser storyMainViewController] deleteAutoSaveForStory: m_storyInfo.path];
                m_willResume = NO;
                [self refresh];
            }]];
    [alertController addAction:
    [UIAlertAction actionWithTitle: @"Cancel (Keep progress)"
             style: UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            }]];
    [self presentViewController:alertController animated:YES completion:^{ }];
}

-(IBAction)IFDBButtonPressed {
    if (m_tuid && [m_tuid length] >= 15)
        [m_browser launchBrowserWithURL: [NSString stringWithFormat: @"https://%@/viewgame?id=%@", kIFDBHost, m_tuid]];
}

#if UseWKWebViewForFrotzStoryDetails
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    //NSString *url = [navigationAction.request.URL query];
    decisionHandler(navigationAction.navigationType !=  WKNavigationTypeLinkActivated);
}
#else
- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
    return navigationType != UIWebViewNavigationTypeLinkClicked;
}
#endif

@end
