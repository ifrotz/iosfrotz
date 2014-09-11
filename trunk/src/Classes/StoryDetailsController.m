//
//  StoryDetailsController.m
//
//  Created by Craig Smith on 9/11/10.
//  Copyright 2010 Craig Smith. All rights reserved.
//

#import "StoryDetailsController.h"
#import "iphone_frotz.h"


@implementation FrotzImageView

@synthesize detailsController = m_detailsController;

- (void)releaseTapTimer {
    if (m_tapTimer) {
        [m_tapTimer invalidate];
        [m_tapTimer release];
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

-(void)magnifyImage:(BOOL)toggle {
    if ([self isMagnified]) {
    	[UIView beginAnimations:@"artmag" context:0];
        [UIView setAnimationTransition:UIViewAnimationTransitionNone forView:self cache:YES];
        self.bounds = m_savedBounds;
        m_savedBounds = CGRectZero;
        [m_detailsController dimArtwork: NO];
        [UIView commitAnimations];
    } else if (toggle) {
        const CGFloat kFactor = 1.4;
        CGRect bounds = [self bounds];
        CGSize imageSize = self.image.size;
        if (UIDeviceOrientationIsLandscape([m_detailsController interfaceOrientation]) && imageSize.height > bounds.size.height * 1.1) {
            [UIView beginAnimations:@"artmag" context:0];
            [UIView setAnimationTransition:UIViewAnimationTransitionNone forView:self cache:YES];
            m_savedBounds = bounds;
            CGSize superSize = self.superview.bounds.size;
            if (imageSize.width < superSize.width / kFactor
                && imageSize.height < superSize.height / kFactor)
                bounds.size = imageSize;
            else {
                bounds.size.width = superSize.width / kFactor;
                bounds.size.height = superSize.height / kFactor;
            }
            self.bounds = bounds;
            [m_detailsController dimArtwork: YES];
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
    if (gUseSplitVC) {
        UITouch *touch = [touches anyObject];
        int tapCount = [touch tapCount];
        if ([self isMagnified] && tapCount == 1)
            [self magnifyImage: NO];
        else if (tapCount == 2)
            [self magnifyImage: YES];
    }
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
    if ([gpBoard containsPasteboardTypes: [NSArray arrayWithObject: kAppleWebArchivePBType]]) {
        NSData *data = [gpBoard dataForPasteboardType: kAppleWebArchivePBType];
        if (data) {
            NSString *errorStr = nil;
            NSPropertyListFormat plFmt;
            NSDictionary *dict = [NSPropertyListSerialization propertyListFromData:data mutabilityOption:kCFPropertyListImmutable 
                                                                            format:&plFmt errorDescription:&errorStr];
            if (errorStr) [errorStr release];
            if (dict && [dict respondsToSelector:@selector(objectForKey:)]) {
                NSArray *resources = [dict objectForKey: kWebSubResourcesKey];
                if (resources && [resources count]==1) {
                    NSDictionary *subDict = [resources objectAtIndex:0];
                    NSString *mimeType = [subDict objectForKey: kWebResourceMIMETypeKey];
                    if ([mimeType isEqualToString: @"image/jpeg"] || [mimeType isEqualToString:@"image/png"])
                        return [subDict objectForKey: kWebResourceDataKey];
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
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Paste artwork?" message:@"This will replace previous artwork"
                                                   delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Paste", nil];
    [alert show];
    [alert release];
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (buttonIndex == 1)
        [self doPaste];
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

-(void)dealloc {
    [m_title release];
    [m_author release];
    [m_tuid release];
    [m_descriptionHTML release];
    [m_titleField release];
    [m_authorField release];
    [m_TUIDField release];
    [m_contentView release];
    [m_artwork release];
    [m_descriptionWebView release];
    [m_flipper release];
    [m_frotzInfoController release];
    [super dealloc];
}

-(void)clear {
    self.storyTitle = @"";
    self.author = @"";
    self.tuid = @"";
    self.artwork = nil;
    self.descriptionHTML = nil;
    self.storyInfo = nil;
    
    [self refresh];
}

-(void)dimArtwork:(BOOL)dim {
    m_descriptionWebView.alpha = dim ? 0.3 : 1.0;
}

-(void)refresh {
    if (m_storyInfo != nil && [m_browser canEditStoryInfo])
        self.navigationItem.rightBarButtonItem = [self editButtonItem];
    else {
        self.navigationItem.rightBarButtonItem = nil;
        if (self.isEditing)
            self.editing = NO;
    }
    if (![self isEditing])
        [self dismissKeyboard];
    [m_titleField setText: m_title];
    [m_authorField setText: m_author];
    [m_TUIDField setText: m_tuid];
    
    [m_artworkView magnifyImage: NO];
    [m_artworkView setImage: m_artwork];
    
    if (m_descriptionWebView) {
        [m_descriptionWebView loadHTMLString:
         [NSString stringWithFormat:
          @"<html><body><style type=\"text/css\">\n"
          "h2 { font-size: 12pt; color:#cfcf00; } h3 { font-size: 11pt; color:#cfcf00; } p { font-size:10pt; }\n"
          "* { color:#ffffff; background: #666666 } ul { margin-left: 0.2em; padding-left: 1em; margin-right: 0.2em;}\n</style>\n"
          "%@\n<br>%@<br>\n"
          "</body></html\n",
          ([m_descriptionHTML length] > 0
           ? [m_descriptionHTML stringByReplacingOccurrencesOfString:@"<img " withString:@"<!img "]
           : @"<i>No description available.</i><br><br>"),
          ([m_tuid length] > 0
           ? @"<small>Tap 'View in IFDB' for more information.</small>" : @"")
          ] baseURL:nil];
    }
    
    m_playButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    if (m_willResume) {
        if (gLargeScreenDevice) {
            [m_playButton setTitle: @"Resume Story" forState:UIControlStateNormal];
            [m_playButton setNeedsDisplay];
        } else {
            m_playButton.titleEdgeInsets = UIEdgeInsetsMake(0, 24, 0, 0);
            [m_playButton setTitle: @"Resume Story" forState:UIControlStateNormal];
            [m_playButton setNeedsDisplay];
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
    CGRect playFrame = m_playButton.frame, restartFrame = m_restartButton.frame;
    [m_restartButton setCenter: CGPointMake(playFrame.origin.x + restartFrame.size.width/2.0 + (gLargeScreenDevice?24:1),
                                            playFrame.origin.y + restartFrame.size.height/2.0 + (gLargeScreenDevice?2:1))];
    
    if ((m_title && [m_title length] > 0 || m_storyInfo) //|| UIDeviceOrientationIsLandscape([self interfaceOrientation])
        ) {
        if (/*!m_portraitCover.isHidden && */ UIDeviceOrientationIsLandscape([self interfaceOrientation])) {
            if (m_artSizeLandscape.width != 0) {
                CGRect bounds = m_artworkView.bounds;
                bounds.size = m_artSizeLandscape;
                m_artworkView.bounds = bounds;
            }
        }
        m_portraitCover.hidden = YES;
    } else {
        m_portraitCover.hidden = NO;
        if (m_artSizePortrait.width != 0) {
            CGRect bounds = m_artworkView.bounds;
            bounds.size = m_artSizePortrait;
            m_artworkView.bounds = bounds;
        }
        
    }
    
    if (m_artworkView) {
        if (m_artwork) {
            [m_artworkView setImage: m_artwork];
            [m_artworkView setAlpha: 1.0];
            [m_artworkLabel setAlpha: 0.0];
        } else {
            [m_artworkView setImage: [UIImage imageNamed: @"compass-med.png"]];
            [m_artworkView setAlpha: 0.25];
            [m_artworkLabel setAlpha: 1.0];
        }
    }
    [self repositionArtwork: [[UIApplication sharedApplication] statusBarOrientation]]; // [[UIDevice currentDevice] orientation]];

}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing: editing animated: animated];
    if (editing) {
    	if ([m_descriptionWebView superview] && ![m_descriptionWebView isHidden])
            [self toggleArtDescript];
        if (m_infoButton)
            [m_infoButton setEnabled:NO];
        [m_browser hidePopover];
        [m_titleField setBorderStyle: UITextBorderStyleRoundedRect];
        [m_titleField setTextColor: [UIColor blackColor]];
        [m_authorField setBorderStyle: UITextBorderStyleRoundedRect];
        [m_authorField setTextColor: [UIColor blackColor]];
        [m_TUIDField setBorderStyle: UITextBorderStyleRoundedRect];
        [m_TUIDField setTextColor: [UIColor blackColor]];
        [m_titleField becomeFirstResponder];
    } else {
        [self dismissKeyboard];
        if (m_infoButton)
            [m_infoButton setEnabled:YES];
        [m_titleField setBorderStyle: UITextBorderStyleNone];
        [m_titleField setTextColor: [UIColor whiteColor]];
        [m_authorField setBorderStyle: UITextBorderStyleNone];
        [m_authorField setTextColor: [UIColor whiteColor]];
        [m_TUIDField setBorderStyle: UITextBorderStyleNone];
        [m_TUIDField setTextColor: [UIColor whiteColor]];
    }
    [self refresh];
}

-(void)viewDidLoad {
    m_artSizePortrait = m_artworkView.bounds.size;
    
    // Originally we let auto-rotate resizing compute the landscape bounds, and cached it.
    // For some reason in iOS 4.2 this doesn't work because the frame hasn't been scaled yet
    // in willAnimRotation...  so I'm initializing it here with a hardcoded scale of half.
    m_artSizeLandscape = m_artworkView.bounds.size;
    CGFloat landscapeScale = gLargeScreenDevice ? 0.5 : 0.8;
    m_artSizeLandscape.width *= landscapeScale;
    m_artSizeLandscape.height *= landscapeScale;
    
    m_artworkView.detailsController = self;
    
    [self refresh];
    
    
    if (m_descriptionWebView) {
        NSArray *subviews = m_descriptionWebView.subviews;
        if ([subviews count] > 0) {
            UIScrollView *sv = [subviews objectAtIndex: 0];
            if (sv && [sv respondsToSelector:@selector(setBounces:)])
                [sv setBounces:NO];
        }
    }
    if (gUseSplitVC) {
        if (!m_frotzInfoController)
            m_frotzInfoController = [[FrotzInfo alloc] initWithSettingsController:[m_browser settings] navController:self.navigationController navItem:self.navigationItem];
        self.navigationItem.titleView = [m_frotzInfoController view];
    }
#ifdef NSFoundationVersionNumber_iOS_6_1
    if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1)
    {
        self.edgesForExtendedLayout=UIRectEdgeNone;
    }
#endif
}

-(void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateSelectionInstructions: NO];

    [self refresh];

    if (!gLargeScreenDevice) {
        [m_descriptionWebView removeFromSuperview];
        [m_descriptionWebView setHidden: YES];
    }
    if (m_flipper) {
        [m_flipper addSubview: m_artworkView];
        [m_flipper addSubview: m_artworkLabel];
    }
}

-(void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self setEditing: NO animated: animated];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return gLargeScreenDevice ? YES : interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    [m_artworkView magnifyImage:NO];
    
 //   m_artworkView.autoresizingMask &= ~UIViewAutoresizingFlexibleBottomMargin;
    
    if (m_title && [m_title length] > 0 || m_storyInfo) {
        m_portraitCover.hidden = YES;
    } else {
        m_portraitCover.hidden = NO;
    }
}

-(void)repositionArtwork:(UIInterfaceOrientation)toInterfaceOrientation {
    if (m_flipper) {
		CGPoint center = m_textFieldsView.superview.center;
        CGRect textRect = m_textFieldsView.frame;
        CGRect flipRect = m_flipper.frame;
        CGRect butttonsRect = m_buttonsView.frame;
        [m_textFieldsView.superview bringSubviewToFront:m_textFieldsView];

        if (UIDeviceOrientationIsLandscape(toInterfaceOrientation)) {
            if ([m_descriptionWebView superview] && ![m_descriptionWebView isHidden])
                [self toggleArtDescript];
//			flipRect.origin = CGPointMake(textRect.origin.x + butttonsRect.size.width - flipRect.size.width + 20, textRect.origin.y);
            flipRect.origin = CGPointMake(center.x, textRect.origin.y);
			m_artworkView.center = CGPointMake(flipRect.size.width/2, m_artworkView.center.y);
            m_infoButton.hidden = YES;
        } else {
			flipRect.size.width = butttonsRect.size.width;
			m_textFieldsView.center = CGPointMake(center.x, m_textFieldsView.center.y);
            m_flipper.transform = CGAffineTransformMakeScale(1.0, 1.0);
			CGFloat flipX = m_flipper.superview.bounds.size.width/2-flipRect.size.width/2;
            flipRect.origin = CGPointMake(flipX, textRect.origin.y + textRect.size.height);
            m_infoButton.hidden = NO;
        }
        flipRect.size.height = butttonsRect.origin.y - flipRect.origin.y;
        UINavigationBar *b =  self.navigationController.navigationBar;
        if (b && !b.superview) // work around iOS bug where we're not resized correctly when a search bar has taken over the nav bar
            flipRect.size.height -= b.frame.size.height+20;
        m_flipper.frame = flipRect;
        CGRect webFrame = m_descriptionWebView.frame;
        webFrame.size.height = flipRect.size.height;
		webFrame.size.width = flipRect.size.width - webFrame.origin.x*2;
        m_descriptionWebView.frame = webFrame;
    }

    CGRect artBounds = m_artworkView.bounds;
    if (m_title && [m_title length] > 0 || m_storyInfo) {
        m_portraitCover.hidden = YES;
        artBounds.size =  UIDeviceOrientationIsLandscape(toInterfaceOrientation) ? m_artSizeLandscape: m_artSizePortrait;
        m_artworkView.bounds = artBounds;
    } else {
        m_portraitCover.hidden = NO;
        if (m_artSizePortrait.width != 0) {
            artBounds.size =  m_artSizePortrait;
            m_artworkView.bounds = artBounds;
        }
    }

//    m_portraitCoverLabel.hidden = YES;
    if (gLargeScreenDevice) {
		CGPoint center = [m_artworkView.superview center];
        center.y = m_TUIDField.center.y + artBounds.size.height/2.0 + 20;
        [m_artworkView setCenter: center];
	}
    [m_artworkLabel setCenter: [m_artworkView center]];
}

-(void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    [self repositionArtwork: toInterfaceOrientation];
}

-(void)viewDidAppear:(BOOL)animated {
    [self repositionArtwork: [[UIApplication sharedApplication] statusBarOrientation]]; //[[UIDevice currentDevice] orientation]];
}

-(void)updateSelectionInstructions:(BOOL)hasPopover {
    [[self navigationItem] setTitle: m_portraitCover.hidden ? @"Story Info" : nil];
    if (hasPopover && [self isEditing])
        [self setEditing:NO animated: YES];
    
    if (UIDeviceOrientationIsLandscape([self interfaceOrientation]))
        m_portraitCoverLabel.text = @"Select a story to begin";
    else
        m_portraitCoverLabel.text = hasPopover ? nil : @"Tap 'Select Story' to begin";
}

-(void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [self repositionArtwork: [[UIApplication sharedApplication] statusBarOrientation]]; //[[UIDevice currentDevice] orientation]];

 //   m_artworkView.autoresizingMask &= ~UIViewAutoresizingFlexibleBottomMargin;
    [self updateSelectionInstructions: NO];
    m_portraitCoverLabel.hidden = NO;
    [self refresh];
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
    if (m_title)
        [m_title release];
    m_title = [title retain];
    if (m_titleField)
        [m_titleField setText: m_title];
}

-(NSString*)author {
    return m_author;
}

-(void)setAuthor:(NSString*)author {
    if (m_author == author)
        return;
    if (m_author)
        [m_author release];
    m_author = [author retain];
    if (m_authorField)
        [m_authorField setText: m_author];
}

-(NSString*)tuid {
    return m_tuid;
}

-(void)setTUID:(NSString*)tuid {
    if (m_tuid == tuid)
        return;
    if (m_tuid)
        [m_tuid release];
    m_tuid = [tuid retain];
    if (m_TUIDField)
        [m_TUIDField setText: m_tuid];
    
}

-(UIImage*)artwork {
    return m_artwork;
}

-(void)setArtwork:(UIImage*)artwork {
    if (m_artwork == artwork)
        return;
    if (m_artwork)
        [m_artwork release];
    m_artwork = [artwork retain];
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

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (buttonIndex == 0) {
        [[m_browser storyMainViewController] deleteAutoSaveForStory: m_storyInfo.path];
        m_willResume = NO;
        [self refresh];
    }
}

-(IBAction)showRestartMenu {
    UIActionSheet *actionView = [[UIActionSheet alloc] initWithTitle:@"Restart the story?\nThis will abandon the current auto-saved game."
                                                            delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:@"Restart from beginning"
                                                   otherButtonTitles: gUseSplitVC ? @"Keep progress":nil, nil];
    if (gUseSplitVC)
        [actionView showFromRect:m_restartButton.frame inView:m_contentView animated:YES];
    else
        [actionView showInView: m_contentView];
    [actionView release];
}

-(IBAction)IFDBButtonPressed {
    if (m_tuid && [m_tuid length] > 15)
        [m_browser launchBrowserWithURL: [NSString stringWithFormat: @"http://ifdb.tads.org/viewgame?id=%@", m_tuid]];
}

-(IBAction)toggleArtDescript {
    if (gUseSplitVC)
        return;
    if (m_descriptionWebView) {
        if ([self keyboardIsActive])
            return;
        BOOL descriptionShown = [m_descriptionWebView superview] && ![m_descriptionWebView isHidden];
        if ([self isEditing] && !descriptionShown)
            return;
        
        [UIView beginAnimations:@"sdflip" context:0];
        [UIView setAnimationTransition:UIViewAnimationTransitionFlipFromLeft forView:m_flipper cache:YES];
        if (descriptionShown) {
            [m_descriptionWebView removeFromSuperview];
            [m_flipper addSubview: m_artworkView];
            [m_flipper addSubview: m_artworkLabel];
            [m_descriptionWebView setHidden: YES];
        } else {
            [m_artworkView removeFromSuperview];
            [m_artworkLabel removeFromSuperview];
            [m_descriptionWebView setHidden: NO];
            m_flipper.autoresizesSubviews = YES;
            [m_flipper addSubview: m_descriptionWebView];
            [m_flipper bringSubviewToFront: m_descriptionWebView];
        }
        [m_flipper bringSubviewToFront: m_infoButton];
        [UIView commitAnimations];
    }
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
    return navigationType != UIWebViewNavigationTypeLinkClicked;
}

@end
