/*

 This program is free software; you can redistribute it and/or
 modify it under the terms of the GNU General Public License
 as published by the Free Software Foundation; version 2
 of the License.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program; if not, write to the Free Software
 Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

 */
#import <UIKit/UIKit.h>
#import "iosfrotz.h"
#import "StoryWebBrowserController.h"
#import "StoryBrowser.h"
#import "ui_utils.h"
#import "iosfrotz.h"

#import "extractzfromz.h"
#import <QuartzCore/QuartzCore.h>

#import "Frotz-Swift.h"

NSString *const kIFDBHost = @"ifdb.org";
NSString *const kIFDBOldHost = @"ifdb.tads.org";
NSString *const kBookmarksFN = @"bookmarks.plist";

const NSString *kBookmarkURLsKey = @"URLs";
const NSString *kBookmarkTitlesKey = @"Titles";
const NSString *kBookmarkVersionKey = @"Version";

@implementation StoryWebBrowserController

@synthesize snarfedStoryName;

-(StoryWebBrowserController*)initWithBrowser:(StoryBrowser*)sb {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        m_storyBrowser = sb;
    }
    return self;
}

-(StoryBrowser*)storyBrowser {
    return m_storyBrowser;
}

-(FrotzInfo*)frotzInfoController {
    return m_frotzInfoController;
}

-(void)loadView {
    UINavigationController *nc = [self navigationController];
    const float navBarHeight = nc ? nc.navigationBar.frame.size.height : 0.0;
    const float toolBarHeight = nc ? navBarHeight : 44.0;
    CGRect frame = [[UIScreen mainScreen] bounds];
    UIEdgeInsets safeInsets = UIEdgeInsetsMake(0, 0, 0, 0);
    if (@available(iOS 11.0,*)) {
        safeInsets = [[[UIApplication sharedApplication] keyWindow] safeAreaInsets];
    }
    frame.origin.y += navBarHeight;
    frame.size.height -= navBarHeight;

    m_background = [[UIView alloc] initWithFrame: frame];

    frame.origin.y = 0;
    frame.size.height -= toolBarHeight;
    m_scrollView = [[UIScrollView alloc] initWithFrame: frame];
    [m_scrollView setScrollEnabled: NO];
    [m_scrollView setBackgroundColor: [UIColor blackColor]];
    [m_scrollView setDelegate: self];

    m_urlBarController = [[URLPromptController alloc] init];
    [m_urlBarController setDelegate: self];

    [m_background setBackgroundColor: [UIColor blackColor]];
    [m_background addSubview: m_scrollView];

    frame = [m_scrollView bounds];
    frame.size.height -= safeInsets.bottom;
    m_webView = [[StoryWebView alloc] initWithFrame: frame];
    [m_background setAutoresizesSubviews: YES];

    [m_webView setAutoresizesSubviews: YES];
    [m_webView setAutoresizingMask: UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleRightMargin|UIViewAutoresizingFlexibleBottomMargin];

    [m_scrollView addSubview: m_webView];
    [m_scrollView setAutoresizesSubviews: YES];
    [m_scrollView setAutoresizingMask: UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight];
    [m_scrollView bringSubviewToFront: m_webView];

    [self setView: m_background];
#if UseWKWebViewForIFDBBrowser
    [m_webView setNavigationDelegate: self];
#else
    [m_webView setScalesPageToFit: YES];
    [m_webView setDetectsPhoneNumbers: NO];
    [m_webView setDelegate: self];
#endif

    frame.origin.y = frame.size.height;
    frame.size.height = toolBarHeight;
    m_toolBar = [[UIToolbar alloc] initWithFrame: frame];
    [m_toolBar setAutoresizingMask: UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleWidth];

    [m_toolBar setBarStyle: UIBarStyleBlack];
    [m_toolBar setTintColor: [UIColor whiteColor]];

    m_backButtonItem = [[UIBarButtonItem alloc] initWithImage: [UIImage imageNamed: @"NavBack"] style:UIBarButtonItemStylePlain target:self action:@selector(goBack)];
    m_spaceButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    m_cancelButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop target:self action:@selector(cancel)];
    m_reloadButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh)];
    m_forwardButtonItem = [[UIBarButtonItem alloc] initWithImage: [UIImage imageNamed: @"NavForward"] style:UIBarButtonItemStylePlain target:self action:@selector(goForward)];
    m_URLButtonItem = [[UIBarButtonItem alloc] initWithImage: [UIImage imageNamed: @"icon-url-tool"] style:UIBarButtonItemStylePlain target:self action:@selector(promptURL)];
    m_searchButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSearch target:self action:@selector(setSearchType)];

    m_activityView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    m_activButtonItem = [[UIBarButtonItem alloc] initWithCustomView: m_activityView];

    self.navigationItem.rightBarButtonItem = m_activButtonItem;

    [self setButtonItems: YES];

    [m_background addSubview: m_toolBar];
    [m_background bringSubviewToFront: m_toolBar];

    m_bookmarkListController = [[BookmarkListController alloc] init];
    [m_bookmarkListController setDelegate: self];
    CGRect blistFrame = [m_webView bounds];
    blistFrame.size.height += [m_toolBar frame].size.height;
    [[m_bookmarkListController view] setFrame: blistFrame];

    self.navigationItem.title = @"Story Browser";

    [self setInformSearchType];
}

-(void)setButtonItems:(BOOL)canCancel {
    [m_toolBar setItems: @[m_backButtonItem, m_spaceButtonItem, m_forwardButtonItem, m_spaceButtonItem,
                           canCancel ? m_cancelButtonItem : m_reloadButtonItem, m_spaceButtonItem,
                           m_URLButtonItem, m_spaceButtonItem, m_searchButtonItem]];
}

-(void)viewDidLoad {
    self.navigationItem.titleView = [m_frotzInfoController view];
    UIBarButtonItem* backItem = [[UIBarButtonItem alloc] initWithTitle:@"Story List" style:UIBarButtonItemStyleBordered target:self action:@selector(browserDidPressBackButton)];
    self.navigationItem.leftBarButtonItem = backItem;

    self.edgesForExtendedLayout=UIRectEdgeNone;
}

-(void)pickFilesFromZip:(NSString*)zipFile list:(NSMutableArray *)zList{
    NSString *gamePath = [[[self storyBrowser] storyMainViewController] storyGamePath];
    NSString *storyboardName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"UIMainStoryboardFile"];
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:storyboardName bundle:nil];
    SelectFilesViewController *selectFilesVC = [storyboard instantiateViewControllerWithIdentifier:@"SelectFilesViewController"];
    [selectFilesVC setTitle: @"Select story files to add" files: zList
        doneHandler:^(NSArray<NSString*>* files) {
            NSUInteger count = 0;
            NSString *storyFile, *storyList = @"";
            for (storyFile in files) {
                if ([storyFile hasPrefix: @"SAVE"])
                    continue;
                if (extractOneFileFromZIP(zipFile, gamePath, storyFile) == 0) {
                    storyList = [storyList stringByAppendingFormat: @" %@", storyFile];
                    ++count;
                }
            }
            NSFileManager *fileMgr = [NSFileManager defaultManager];
            [fileMgr removeItemAtPath: zipFile error: nil];
            if (count > 0) {
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Extracted the following story files from archive:" message: storyList delegate:self cancelButtonTitle:@"OK" otherButtonTitles: nil];
                [alert show];
                [self browserDidPressBackButton];
            }
        }
        canceledHandler: ^{
            NSFileManager *fileMgr = [NSFileManager defaultManager];
            [fileMgr removeItemAtPath: zipFile error: nil];
        }];
    [selectFilesVC setInstructions: @"\n"
        "The ZIP file contains more than one story file.\n"
        "\n"
        "(Frotz may not retain meta-data for stories other than the loaded IFDB page.)\n"];
    if (self.snarfedStoryName)
        [selectFilesVC checkAllMatches: self.snarfedStoryName];
    UINavigationController *nc = [[UINavigationController alloc] initWithRootViewController: selectFilesVC];

    [self presentViewController:nc animated:YES completion: nil];
}

-(void)viewDidAppear:(BOOL)animated {
}

-(void)browserDidPressBackButton {
    m_backToStoryList = YES;
    [self.storyBrowser didPressModalStoryListButton];
    [self.navigationController popViewControllerAnimated: NO];
}

-(NSString*)bookmarkPath {
    NSString *appSuppPath = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, true)[0];
    NSString *bmPath = [appSuppPath stringByAppendingPathComponent: kBookmarksFN];
    return bmPath;
}

-(void)loadBookmarksWithURLs:(NSArray<NSString*>**)pUrls andTitles:(NSArray<NSString*>**)pTitles {
    NSString *bmPath = [self bookmarkPath];
    NSMutableDictionary *bmDict = [NSMutableDictionary dictionaryWithContentsOfFile: bmPath];
    if (bmDict) {
        NSMutableArray *urls = bmDict[kBookmarkURLsKey];
        NSMutableArray *titles = bmDict[kBookmarkTitlesKey];
        NSString *vers = bmDict[kBookmarkVersionKey];
        BOOL changed = NO;
        if (!vers || [vers compare: @"2"] == NSOrderedAscending) {
            NSUInteger firstAddIndex = 0, firstObsoleteIndex = 0;
            NSArray *addUrls = @[
                @"eblong.com/infocom",
                @"planet-if.com",
                @"intfiction.org",
                @"eblong.com/zarf/if.html",
                @"m.youtube.com/watch?feature=youtu.be&v=4nigRT2KmCE"
            ];
            NSArray *addTitles = @[
                @"The Obsessively Complete Infocom Catalog",
                @"Planet Interactive Fiction",
                @"The Interactive Fiction Community Forum",
                @"Zarf's Interactive Fiction",
                @"MC Frontalot - It Is Pitch Dark"
            ];
            NSArray *obsoleteUrls = @[
                @"www.xyzzynews.com",
                @"sparkynet.com/spag",
                @"www.wurb.com/if",
                @"www.csd.uwo.ca/Infocom/",
                @"https://eblong.com/infocom"
            ];
            NSUInteger i = 0;
            if (vers) { // must be "1"
                firstAddIndex = 0; // re-add w/o https
                firstObsoleteIndex = 4;
            }
            for (NSString *oUrl in obsoleteUrls) {
                if (i++ < firstObsoleteIndex)
                    continue;
                NSUInteger foundIndex = [urls indexOfObject: oUrl];
                if (foundIndex != NSNotFound) {
                    [urls removeObjectAtIndex: foundIndex];
                    [titles removeObjectAtIndex: foundIndex];
                    changed = YES;
                }
            }
            i = 0;
            for (NSString *aUrl in addUrls) {
                if (i++ < firstAddIndex)
                    continue;
                NSUInteger foundIndex = [urls indexOfObject: aUrl];
                if (foundIndex == NSNotFound) {
                    [urls addObject: aUrl];
                    [titles addObject: [addTitles objectAtIndex: i-1]];
                    changed = YES;
                }
            }
        } else if ([vers compare: @"3"] == NSOrderedAscending) {
            NSUInteger i = 0, n = [urls count];
            NSString *aUrl;
            for (; i < n; ++i) {
                aUrl = [urls objectAtIndex: i];
                if ([aUrl containsString: kIFDBOldHost]) {
                    NSString *repl = [aUrl stringByReplacingOccurrencesOfString:kIFDBOldHost withString:kIFDBHost];
                    [urls replaceObjectAtIndex:i withObject:repl];
                    changed = YES;
                }
            }
        }
        if (changed)
            [self saveBookmarksWithURLs:urls andTitles:titles];
        if (pUrls)
            *pUrls = urls;
        if (pTitles)
            *pTitles = titles;
        return;
    }

    if (pUrls)
        *pUrls = @[kIFDBHost,
                   @"gallery.guetech.org/greybox.html",
                   @"inform7.com",
                   @"www.ifwiki.org/index.php/Main_Page",
                   @"www.ifarchive.org",
                   @"www.ifcomp.org",
                   @"eblong.com/infocom",
                   @"brasslantern.org",
                   @"nickm.com/if",
                   @"planet-if.com",
                   @"intfiction.org",
                   @"eblong.com/zarf/if.html",
                   @"m.youtube.com/watch?feature=youtu.be&v=4nigRT2KmCE"
        ];
    if (pTitles)
        *pTitles = @[@"Interactive Fiction Database - IF and Text Adventures",
                     @"Infocom Gallery (Artwork, Docs)",
                     @"Inform 7 - A Design System for Interactive Fiction",
                     @"IFWiki Home",
                     @"The Interactive Fiction Archive",
                     @"The Annual Interactive Fiction Competition",
                     @"The Obsessively Complete Infocom Catalog",
                     @"Brass Latern",
                     @"Interactive Fiction - Nick Montfort",
                     @"Planet Interactive Fiction",
                     @"The Interactive Fiction Community Forum",
                     @"Zarf's Interactive Fiction",
                     @"MC Frontalot - It Is Pitch Dark"
        ];
}

-(void)saveBookmarksWithURLs:(NSArray*)urls andTitles:(NSArray*)titles {
    NSString *bmPath = [self bookmarkPath];
    NSDictionary *bmDict = [NSDictionary dictionaryWithObjectsAndKeys:
                            urls, kBookmarkURLsKey, titles, kBookmarkTitlesKey,
                            @"3", kBookmarkVersionKey,
                            nil, nil];
    if (bmDict)
        [bmDict writeToFile:bmPath atomically:YES];
}


-(void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Convenient, but makes navigation feel inconsistent, and hides activity spinner.
    //self.navigationItem.rightBarButtonItem = [[self storyBrowser] nowPlayingNavItem];
    [m_frotzInfoController setKeyboardOwner: self];

    [self.navigationController.navigationBar setBarStyle: UIBarStyleBlack];
    [self.navigationController.navigationBar setBarTintColor: [UIColor blackColor]];
    [self.navigationController.navigationBar  setTintColor:  [UIColor whiteColor]];
}

-(void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [m_webView resignFirstResponder];

    if (!m_backToStoryList) {
        CATransition *animation = [CATransition animation];
        [animation setType:kCATransitionReveal];
        [animation setSubtype: kCATransitionFromTop];
        [animation setDuration: 0.4];
        [animation setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
        [[[[self view] superview] layer] addAnimation:animation forKey:@"browseBack"];
    }
    m_backToStoryList = NO;
}

-(UIActivityIndicatorView*)activityIndicator {
    return m_activityView;
}

-(id)dismissKeyboard {
    [self dismissURLPrompt];
    return nil;
}

-(UIBarButtonItem*)backButton {
    return m_backButtonItem;
}

-(StoryWebView*)webView {
    return m_webView;
}

-(void)goBack {
    [[self webView] goBack];
}
-(void)goForward {
    [[self webView] goForward];
}
-(void)cancel {
    [[self webView] stopLoading];
}

-(void)loadDefaultSearchWithKey:(NSString*)key value:(NSString*)value {
    [m_backButtonItem setEnabled: [m_webView canGoBack]];
    [m_forwardButtonItem setEnabled: [m_webView canGoForward]];
    [m_cancelButtonItem setEnabled: NO];
    [self setButtonItems: NO];

    m_state = kSWBIdle;
    NSURL *url = [NSURL URLWithString:
                    [NSString stringWithFormat:
                         @"https://%@/search?searchfor=%@%%3A%@+rating%%3A3-+%%23ratings%%3A2-&browse=1",
                     kIFDBHost, key, value]];
    [m_webView loadRequest: [NSURLRequest requestWithURL: url]];
}

-(void)refresh {
    [[self webView] reload];
}

-(void)setInformSearchType {
    [self loadDefaultSearchWithKey: @"system" value: @"inform"];
}

-(void)setSearchType {
    const NSString *kSearchName = @"name", *kSearchKey = @"key", *kSearchVal = @"value";
    NSArray<NSDictionary*> *items = @[
        @{kSearchName: @"Stories written in Inform",kSearchKey:@"system", kSearchVal: @"inform" },
        @{kSearchName: @"Stories written in TADS 2", kSearchKey:@"format", kSearchVal: @"tads%202" },
        @{kSearchName: @"Stories written in Dialog", kSearchKey:@"system", kSearchVal: @"dialog" },
//        @{kSearchName: @"Stories written in ZIL (Infocom Zork Implementation Language)", kSearchKey:@"system", kSearchVal: @"zil" }
    ];

    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"IFDB Search by Story Format"
                                                                            message:nil
                                                                     preferredStyle:UIAlertControllerStyleActionSheet];

    for (NSDictionary *item in items) {
        UIAlertAction *action = [UIAlertAction actionWithTitle: item[kSearchName]
                                          style: UIAlertActionStyleDefault
                                        handler: ^(UIAlertAction *action) {
                                          [self loadDefaultSearchWithKey: item[kSearchKey] value: item[kSearchVal]];
                                        }];
        [alertController addAction: action];
    }
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle: @"Cancel"
                                                          style: UIAlertActionStyleCancel
                                                        handler: ^(UIAlertAction *action) {
                                                        }];

    [alertController addAction: cancelAction];

    UIPopoverPresentationController *popPresenter = [alertController popoverPresentationController];
    popPresenter.barButtonItem = m_searchButtonItem;
    [self presentViewController:alertController animated:YES completion:nil];

}

-(void)setupFade {
    CATransition *animation = [CATransition animation];
    [animation setType:kCATransitionFade];
    [animation setDuration: 0.3];
    [animation setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
    [[[self view] layer] addAnimation:animation forKey:@"fadebar"];
}

-(void)promptURL {
    UIView *urlView = [m_urlBarController view];
    if (![urlView superview]) {
        //	[self setupFade];

        CGRect webFrame = [m_webView frame];
        webFrame.origin.y += kSearchBarHeight;
        webFrame.size.height -= kSearchBarHeight;

        [urlView setFrame: CGRectMake(0, -kSearchBarHeight, webFrame.size.width, kSearchBarHeight)];
        UIView *v = [self view];
        [v addSubview: urlView];

        [UIView beginAnimations: @"srchshow" context: 0];
        [m_webView setFrame: webFrame];

        [urlView setFrame: CGRectMake(0, 0, webFrame.size.width, kSearchBarHeight)];
        [v bringSubviewToFront: urlView];
        [UIView commitAnimations];
    } else {
        [self dismissURLPrompt];
    }
}

-(void)enterURL:(NSString*)url {
    NSURL *myURL;
    [m_urlBarController setText: url];
    [self dismissURLPrompt];

    if ([url rangeOfString: @"://" ].length > 0)
        myURL = [NSURL URLWithString: url];
    else if ([url hasPrefix: @"//" ])
        myURL = [NSURL URLWithString: [@"http:" stringByAppendingString: url]];
    else
        myURL = [NSURL URLWithString: [@"http://" stringByAppendingString: url]];

    (void)[self view]; // make sure view is loaded
    NSURLRequest *request = [NSURLRequest requestWithURL: myURL];
    [m_webView performSelector: @selector(loadRequest:) withObject:request afterDelay:1.0];
}


-(void)animationDidFinish:(NSString *)animationID finished:(NSNumber *)finished context:(void *)context {
    [UIView setAnimationDelegate: nil];
    [[m_urlBarController view] removeFromSuperview];
}

-(void)dismissURLPrompt {
    UIView *urlView = [m_urlBarController view];

    if ([urlView superview]) {
        //	[self setupFade];
        CGRect webFrame = [m_webView frame];
        webFrame.origin.y -= kSearchBarHeight;
        webFrame.size.height += kSearchBarHeight;
        [UIView beginAnimations: @"srchshow" context: 0];
        [m_webView setFrame: webFrame];
        [urlView setFrame: CGRectMake(0, -kSearchBarHeight, webFrame.size.width, kSearchBarHeight)];
        if ([[m_bookmarkListController view] superview]) {
            [self setupFade];
            [[m_bookmarkListController view] removeFromSuperview];
        }
        [UIView setAnimationDelegate: self];
        [UIView setAnimationDidStopSelector: @selector(animationDidFinish:finished:context:)];
        [UIView commitAnimations];
    }
}

-(void)hideBookmarks {
    if ([[m_bookmarkListController view] superview]) {
        [self setupFade];
        [[m_bookmarkListController view] removeFromSuperview];
    }
}

-(void)showBookmarks {
    [self setupFade];
    if ([[m_bookmarkListController view] superview])
        [[m_bookmarkListController view] removeFromSuperview];
    else {
        CGRect webFrame = [m_webView frame];
        UIView *bmView = [m_bookmarkListController view];
        [bmView setFrame: CGRectMake(0, 40+kSearchBarHeight, webFrame.size.width, webFrame.size.height+44-kSearchBarHeight)];
        //	[m_webView addSubview: bmView];
        [m_background addSubview: bmView];
        [m_webView layoutSubviews];
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    [m_receivedData setLength: 0];
}
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [m_receivedData appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    NSURLRequest *request = m_currentRequest;

    //NSLog(@"m_currentRequest use connDidFinishLoading %@", m_currentRequest);

    //m_currentRequest = nil;
    NSURL *url = [request mainDocumentURL];
    NSString *urlString = [[url path] lastPathComponent];
    NSString *ext = [[urlString pathExtension] lowercaseString];
    NSError *error;
    BOOL stay = NO, isBadLoad = NO, doAddedAlert = NO;
    char tempbuf[16];

    NSString *gamePath = [[[self storyBrowser] storyMainViewController] storyGamePath];
    if (m_state == kSWBFetchingImage) {
        if (m_receivedData && m_delayedRequest) {
            NSString *storyFile = [[[m_delayedRequest mainDocumentURL] path] lastPathComponent];
            NSString *story;
            if (self.snarfedStoryName)
                story = self.snarfedStoryName;
            else if ([[[storyFile pathExtension] lowercaseString] isEqualToString: @"zip"]
                && m_expectedArchiveFiles && [m_expectedArchiveFiles count] > 0)
                story = [m_expectedArchiveFiles[0] stringByDeletingPathExtension];
            else
                story = [storyFile stringByDeletingPathExtension];
            if (story) {
                if ([self savePicData:m_receivedData forStory:story])
                    [m_storyBrowser saveMetaData];
            }
        }

        m_receivedData = nil;

        if (m_delayedRequest) {
            m_state = kSWBFetchingStory;
            [self loadZFile: m_delayedRequest];
            m_delayedRequest = nil;
        } else {
            m_state = kSWBIdle;
            [m_activityView stopAnimating];
        }
        return;
    }
    NSString *outFile = [gamePath stringByAppendingPathComponent: urlString];
    tempbuf[0] = 0;
    [m_receivedData getBytes: tempbuf length:4];
    if (tempbuf[0]=='<' && tempbuf[1]=='!') {
        NSString *str = [[NSString alloc] initWithData: m_receivedData encoding:NSUTF8StringEncoding];
        [m_webView loadHTMLString: str baseURL:nil];
        isBadLoad = YES;
    }
    else
        [m_receivedData writeToFile: outFile atomically: NO];
    m_receivedData = nil;
    m_currentRequest = nil;
    UIAlertView *alert = nil;
    NSString *storyFile = nil;
    if (isBadLoad) {
        alert = [[UIAlertView alloc] initWithTitle:@"Unable to retrieve file"
                                           message:@"The web server returned an error page instead of the expected file"
                                          delegate:self cancelButtonTitle:@"OK" otherButtonTitles: nil];
        stay = YES;
    }
    else if ([ext isEqualToString: @"zip"] || [ext isEqualToString: @"ZIP"]) {
        NSMutableArray *zList = listOfZFilesInZIP(outFile);
        BOOL delZip = NO;
        if (!zList || [zList count] == 0) {
            alert = [[UIAlertView alloc] initWithTitle:@"No Z-Code content"
                                               message:@"Sorry, this archive contains no playable story files"
                                              delegate:self cancelButtonTitle:@"OK" otherButtonTitles: nil];
            delZip = YES;
        } else {
            if ([zList count] > 1) {
                [self pickFilesFromZip: outFile list:zList];
                stay = YES;
            } else {
                for (storyFile in zList) {
                    if (extractOneFileFromZIP(outFile, gamePath, storyFile) == 0) {
                        doAddedAlert = YES;
                        break;
                    }
                }
                delZip = YES;
            }
        }
        if (delZip) {
            NSFileManager *fileMgr = [NSFileManager defaultManager];
            [fileMgr removeItemAtPath: outFile error: &error];
        }
    } else if ([ext  hasPrefix: @"z"] || [ext isEqualToString: @"gam"] || [ext isEqualToString: @"gblorb"] || [ext isEqualToString: @"blb"] || [ext isEqualToString: @"ulx"]) {
        storyFile = urlString;
        doAddedAlert = YES;
    }
    if (doAddedAlert)
        alert = [[UIAlertView alloc] initWithTitle:@"Selected story added\nto Story List" message: [m_storyBrowser fullTitleForStory: storyFile]
                                          delegate:self cancelButtonTitle:@"OK" otherButtonTitles: nil];
    if (alert) {
        [alert show];
    }

    [m_activityView stopAnimating];
    [m_storyBrowser reloadData];
    m_state = kSWBIdle;

    if (!stay)
        [self browserDidPressBackButton];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    [m_activityView stopAnimating];
    //NSLog(@"m_currentRequest release connDidFailWithError");
    m_receivedData = nil;
    m_currentRequest = nil;
    m_state = kSWBIdle;

    [m_backButtonItem setEnabled: [m_webView canGoBack]];
    [m_forwardButtonItem setEnabled: [m_webView canGoForward]];
    [m_cancelButtonItem setEnabled: [m_webView isLoading]];
    [self setButtonItems: [m_webView isLoading]];
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error" message:@"Couldn't load content"
                                                   delegate:self cancelButtonTitle:@"OK" otherButtonTitles: nil];
    [alert show];
}

#if UseWKWebViewForIFDBBrowser
-(NSString*)syncStringByEvaluatingJavaScriptFromString:(NSString*)jsExpr {
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    __block NSString *result = nil;
    [m_webView evaluateJavaScript:jsExpr completionHandler: ^(NSString *r, NSError *error) {
        result = r;
        dispatch_semaphore_signal(sema);
    }];
    while (dispatch_semaphore_wait(sema, DISPATCH_TIME_NOW)) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    }
    return result;
}
#endif

- (BOOL)snarfMetaData: (NSURLRequest*)request loadRequest: (NSURLRequest*)delayedRequest forStory:(NSString*)story {
    NSString *pageStr;
#if UseWKWebViewForIFDBBrowser
    pageStr = [self syncStringByEvaluatingJavaScriptFromString: @"document.body.innerHTML;"];
#else
    pageStr = [m_webView stringByEvaluatingJavaScriptFromString:@"document.body.innerHTML;"];
#endif
    BOOL loadingPic = [self snarfMetaDataFromPage:pageStr pageRequest:request loadRequest:delayedRequest forStory:story];
    return loadingPic;
}

- (BOOL)snarfMetaDataFromPage:(NSString*)pageStr pageRequest:(NSURLRequest*)request loadRequest: (NSURLRequest*)delayedRequest forStory:(NSString*)story {
    BOOL loadingPic = NO;
    NSURL *url = [request mainDocumentURL];
    NSString *urlHost = [url host];
    NSString *urlPath = [url path];
    NSString *urlQuery = [url query];
    self.snarfedStoryName = nil;
    NSLog(@"ZDL from url w/host %@, path %@, query=%@, story='%@'", urlHost, urlPath, urlQuery, story);
    if (!(([urlHost isEqualToString: kIFDBHost] || [urlHost isEqualToString: kIFDBOldHost])
          && [urlPath isEqualToString:@"/viewgame"]
          && ![story isEqualToString: @"hhgg"])) // ifdb hitchhiker pic is low-res, don't override built-in
        return NO;

    BOOL saveMeta = NO;
    BOOL isZipDL = [[[delayedRequest mainDocumentURL] pathExtension] isEqualToString: @"zip"];
    NSUInteger len = [pageStr length];
    NSRange range1 = [pageStr rangeOfString: @"<h1>"];
    if (range1.length > 0) {
        range1.location += 4;
        range1.length = len - range1.location;
        NSRange range2 = [pageStr rangeOfString: @"</h1>" options:0 range:range1];
        if (range2.length > 0 && range2.location > range1.location) {
            range1.length = range2.location - range1.location;
            NSString *fullName = [pageStr substringWithRange: range1];
            fullName = [fullName stringByReplacingOccurrencesOfString: @"Cover Art for " withString: @""];
            fullName = [fullName stringByReplacingOccurrencesOfString: @" - Details" withString: @""];
            if (isZipDL) // ZIP might be collection, override with page title
                story = [fullName lowercaseString];
            // class="zip-contents-arrow">Contains <b>stor.z8</b>
            NSRange zipContentsRange = [pageStr rangeOfString: @"class=\"zip-contents-arrow\">Contains <b>"];
            if (isZipDL && zipContentsRange.length > 0) {
                NSUInteger zb = zipContentsRange.location + zipContentsRange.length;
                NSRange zipEndRange = [pageStr rangeOfString: @"</b>" options:0 range: NSMakeRange(zb, len-zb)];
                NSString *zipContentsName = [pageStr substringWithRange: NSMakeRange(zb, zipEndRange.location-zb)];
                NSRange slashRange = [zipContentsName rangeOfString: @"/" options:NSBackwardsSearch range:NSMakeRange(0, [zipContentsName length])];
                if (slashRange.length)
                    zipContentsName = [zipContentsName substringFromIndex:slashRange.location+1];
                if (IsSupportedFileExtension([[zipContentsName pathExtension] lowercaseString])) {
                    NSUInteger extOffset = [zipContentsName rangeOfString: @"."].location;
                    if (extOffset != NSNotFound) {
                        zipContentsName = [zipContentsName substringToIndex: extOffset];
                        NSLog(@"ZIP contents name %@ replacing story %@", zipContentsName, story);
                        story = zipContentsName;
                    }
                }
            }
            if (!story)
                story = [fullName lowercaseString];
            if (story) {
                self.snarfedStoryName = story;
                [m_storyBrowser addTitle: fullName forStory: story];

                NSString *authorsStr = nil, *tuidStr = nil, *descriptStr = nil;

                //Look for authors: by <a href="search?searchfor=author%3ANick+Montfort">Nick Montfort</a></b>
                range1.location = range2.location + range2.length;
                range1.length = len - range1.location;
                range2 = [pageStr rangeOfString: @"<a href=\"search?searchfor=author%3A" options:0 range:range1];
                while (range2.length > 0) {
                    range1.location = range2.location + range2.length;
                    range1.length = len - range1.location;
                    range2 = [pageStr rangeOfString: @"\">" options:0 range:range1];
                    if (range2.length > 0) {
                        range1.location = range2.location + range2.length;
                        range1.length = len - range1.location;
                        range1 = [pageStr rangeOfString: @"</a>" options:0 range:range1];
                        if (range1.length > 0) {
                            range2.location += range2.length;
                            NSString *atmp = [pageStr substringWithRange: NSMakeRange(range2.location,  range1.location-range2.location)];
                            if (authorsStr)
                                authorsStr = [authorsStr stringByAppendingFormat: @", %@", atmp];
                            else
                                authorsStr = atmp;
                            range2.location = range1.location + range1.length;
                            range2.length = len - range2.location;
                            range2 = [pageStr rangeOfString: @"<a href=\"search?searchfor=author%3A" options:0 range:range2];
                        } else
                            range2.length = 0;
                    }
                }

                // Look for tuid: >TUID</a>:            xi4s5ne9m6w821xd            </span>
                range1.location = range1.location + range1.length;
                range1.length = len - range1.location;
                NSRange srange = range1;
                range2 = [pageStr rangeOfString: @">TUID</a>:" options:0 range:range1];
                if (range2.length > 0) {
                    range1.location = range2.location + range2.length;
                    range1.length = len - range1.location;
                    range1 = [pageStr rangeOfString: @"</span>" options:0 range:range1];
                    if (range1.length > 0) {
                        range2.location += range2.length;
                        tuidStr = [pageStr substringWithRange: NSMakeRange(range2.location,  range1.location-range2.location)];
                        tuidStr = [tuidStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    }
                }

                range1 = [pageStr rangeOfString: @"<h3>About the Story</h3>" options:0 range:srange];
                if (range1.length > 0) {
                    range2.location = range1.location + range1.length;
                    range2.length = len - range2.location;
                    range2 = [pageStr rangeOfString: @"<h2>" options:0 range:range2];
                    if (range2.length > 0) {
                        descriptStr = [pageStr substringWithRange: NSMakeRange(range1.location, range2.location - range1.location)];
                        srange.location = range2.location;
                        srange.length = len - srange.location;
                    }
                }
                range1 = [pageStr rangeOfString: @"<h2>Editorial Reviews</h2>" options:0 range:srange];
                if (range1.length > 0) {
                    range2.location = range1.location + range1.length;
                    range2.length = len - range2.location;
                    range2 = [pageStr rangeOfString: @"<h2>" options:0 range:range2];
                    if (range2.length > 0) {
                        NSString *ds = [pageStr substringWithRange: NSMakeRange(range1.location, range2.location - range1.location)];
                        if (!descriptStr)
                            descriptStr = ds;
                        else
                            descriptStr = [NSString stringWithFormat: @"%@\n<br>\n%@", descriptStr, ds];
                        srange.location = range2.location;
                        srange.length = len - srange.location;
                    }
                }

                if (authorsStr)
                    [m_storyBrowser addAuthors:authorsStr forStory:story];
                if (tuidStr)
                    [m_storyBrowser addTUID:tuidStr forStory:story];
                if (descriptStr)
                    [m_storyBrowser addDescript:descriptStr forStory:story];
                saveMeta = YES;
            }
        }
    }
    if (story) {
        urlQuery = [urlQuery stringByReplacingOccurrencesOfString: @"&ldesc" withString:@""];
        NSURL *picURL = [NSURL URLWithString: [NSString stringWithFormat: @"http://%@%@?coverart&%@", urlHost, urlPath, urlQuery]];
        //NSData *picData = [NSURLConnection sendSynchronousRequest:[NSURLRequest requestWithURL: picURL] returningResponse:&response error:&error];
        //saveMeta |= [self savePicData: picData forStory:story];

        NSURLRequest *picRequest = [NSURLRequest requestWithURL: picURL];
        NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:picRequest delegate:self];
        if (connection) {
            m_delayedRequest = delayedRequest;
            m_receivedData = [NSMutableData data];
            m_state = kSWBFetchingImage;
            loadingPic = YES;
        } else {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Connection error" message:@"Could not download cover art"
                                                           delegate:self cancelButtonTitle:@"OK" otherButtonTitles: nil];
            [alert show];
        }

    }
    if (saveMeta) {
        [m_storyBrowser saveMetaData];
        [m_storyBrowser refreshDetails];
    }
    return loadingPic;
}

- (BOOL)savePicData:(NSData*)picData forStory:(NSString*)story{
    BOOL saveMeta = NO;
    @autoreleasepool {
        if (picData) {
            UIImage *image = [UIImage imageWithData: picData];
            if (image) {
                NSLog(@"saving pic data for %@", story);
                UIImage *thumb = scaledUIImage(image, 40, 32);
                if (thumb) {
                    [m_storyBrowser addThumbData: UIImagePNGRepresentation(thumb) forStory:story];
                    saveMeta = YES;
                }
                UIImage *splash = scaledUIImage(image, 0, 0);
                if (splash) {
                    [m_storyBrowser addSplashData: UIImageJPEGRepresentation(splash, 0.8) forStory:story];
                }
            }
        }
        return saveMeta;
    }
}

- (void)loadZMeta:(NSURLRequest*)request {
    self.navigationItem.rightBarButtonItem = m_activButtonItem;

    [m_activityView startAnimating];

    NSLog(@"Load meta, curreq=%@, req=%@", m_currentRequest, request);
    if (m_currentRequest) {
        NSString *story = [[[[request mainDocumentURL] path] lastPathComponent] stringByDeletingPathExtension];
        BOOL loadingPic = [self snarfMetaData: m_currentRequest loadRequest: request forStory: story];
        if (loadingPic)
            return; // loadZFile will be done after pic loaded
    }
    [self loadZFile: request];
}

#if APPLE_FASCISM
static bool bypassBundle = NO;
#endif

- (void)loadZFile:(NSURLRequest*)request {
#if APPLE_FASCISM
    NSString *urlPath = [[request mainDocumentURL] path];
    if (!bypassBundle && ((iosif_ifrotz_verbose_debug & 4)==0 ||
                          [urlPath rangeOfString: @"competition201"].length==0 && [urlPath rangeOfString: @"Comp"].length==0)) {
        NSString *gamePath = [[[self storyBrowser] storyMainViewController] storyGamePath];
        NSString *storyFile;
        if (m_expectedArchiveFiles && [m_expectedArchiveFiles count] > 0)
            storyFile = (NSString*)m_expectedArchiveFiles[0];
        else
            storyFile = [[[request mainDocumentURL] path] lastPathComponent];
        NSString *bundledGamesPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: @kBundledZIPFile];
        if (extractOneFileFromZIP(bundledGamesPath, gamePath, storyFile) == 0) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Selected story added\nto Story List:"
                                                            message: [m_storyBrowser fullTitleForStory: storyFile]
                                                           delegate:self cancelButtonTitle:@"OK" otherButtonTitles: nil];
            [alert show];
            [self browserDidPressBackButton];
        } else {
            UIAlertView *alert;
            if (m_storyAlreadyInstalled)
                alert = [[UIAlertView alloc] initWithTitle:@"Metadata installed" message:@"Refreshed metadata (title, authors, etc.) for previously installed unbundled story"
                                                  delegate:self cancelButtonTitle:@"OK" otherButtonTitles: nil];
            else
                alert = [[UIAlertView alloc] initWithTitle:@"Error" message:@"Could not extract story from bundled archive"
                                                  delegate:self cancelButtonTitle:@"OK" otherButtonTitles: nil];
            [alert show];
        }
        if (m_expectedArchiveFiles) {
            m_expectedArchiveFiles = nil;
        }
        [m_activityView stopAnimating];
        return;
    }
#endif
    m_storyAlreadyInstalled = NO;
    [m_activityView startAnimating];

    //NSLog(@"Load %@", request);
    m_currentRequest = request;
    //NSLog(@"m_currentRequest retain loadZFile %@", m_currentRequest);
    NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
    if (connection) {
        m_receivedData = [NSMutableData data];
        m_state = kSWBFetchingStory;
        //	[connection release];
    } else {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Connection error" message:@"Could not retrieve file"
                                                       delegate:self cancelButtonTitle:@"OK" otherButtonTitles: nil];
        [alert show];
    }
}

#if APPLE_FASCISM
- (BOOL)IFDBContentExistsInBundle:(NSString*)filename {
    NSString *bundledGamesPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: @kBundledZIPFile];
    if (!bundledGamesPath || ![[NSFileManager defaultManager] fileExistsAtPath: bundledGamesPath])
        return NO;
    NSMutableArray *zList = listOfZFilesInZIP(bundledGamesPath);
    if (!zList || [zList count] == 0)
        return NO;
    else if (m_expectedArchiveFiles && [m_expectedArchiveFiles count] > 0 && [zList indexOfObject: m_expectedArchiveFiles[0]] != NSNotFound)
        return YES;
    else if ([zList indexOfObject: filename] != NSNotFound)
        return YES;
    return NO;
}
#endif

- (BOOL)webViewShouldStartLoadWithRequest:(NSURLRequest *)request {
    NSURL *url = [request mainDocumentURL];
    NSString *urlRelPath = [url relativeString];
    NSString *urlString = [urlRelPath lastPathComponent];
    NSString *ext = [[urlString pathExtension] lowercaseString];
    //NSLog(@"ShouldStartLoad: %@", request);
    if ([urlString isEqualToString: @"http:"]) // null url
        return NO;
    if (IsSupportedFileExtension(ext) || [ext isEqualToString: @"zip"]) {
#if APPLE_FASCISM
        NSFileManager *defaultManager = [NSFileManager defaultManager];
        NSString *bundledGamesListPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: @kBundledFileList];
        if (![defaultManager fileExistsAtPath: bundledGamesListPath]) {
            bypassBundle = YES;
            iosif_ifrotz_verbose_debug |= 2;
        } else
            bypassBundle = (iosif_ifrotz_verbose_debug & 2) != 0;
        if (bypassBundle || ((iosif_ifrotz_verbose_debug & 4)!=0 &&
                             ([urlRelPath rangeOfString: @"competition201"].length>0 || [urlRelPath rangeOfString: @"ifcomp"].length>0))) {
            [self performSelector: @selector(loadZMeta:) withObject: request afterDelay: 0.25];
            return NO;
        }
        if ([ext isEqualToString: @"zip"]) {
            NSURL *urlGame = nil;
            if (m_currentRequest)
                urlGame = [m_currentRequest mainDocumentURL];
            else if ([self currentURL])
                urlGame = [NSURL URLWithString:[self currentURL]];
            NSString *urlHost = [urlGame host];
            NSString *urlPath = [urlGame path];
            NSString *urlQuery = [urlGame query];
            if (m_expectedArchiveFiles) {
                m_expectedArchiveFiles = nil;
            }
            if ([urlHost isEqualToString: kIFDBHost] && [urlPath isEqualToString:@"/viewgame"]) {
                if ([urlQuery length]==19) {
                    NSString *bundledGamesListPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: @kBundledFileList];
                    if (bundledGamesListPath && [defaultManager fileExistsAtPath: bundledGamesListPath]) {
                        NSString *bundledList = [NSString stringWithContentsOfFile: bundledGamesListPath];
                        NSString *gameID = [urlQuery substringFromIndex: 3];
                        NSString *searchString = [NSString stringWithFormat: @"%@\t%@\t", gameID, urlString];
                        NSInteger len = [bundledList length];
                        NSRange r = NSMakeRange(0, len), r2;
                        m_expectedArchiveFiles = [[NSMutableArray alloc] init];
                        while ((r2 = [bundledList rangeOfString: searchString options:0 range:r]).length > 0) {
                            NSRange r3 = [bundledList rangeOfString: @"\n" options:0 range: NSMakeRange(r2.location, len-r2.location)];
                            if (r3.length == 0)
                                break;
                            NSRange r4 = [bundledList rangeOfString: @"\t\t" options:0 range: NSMakeRange(r2.location, r3.location-r2.location)];
                            //NSLog(@"authors: %@", r4.length ? [bundledList substringWithRange: NSMakeRange(r4.location+2, r4.location-(r2.location+2))]:@"none");
                            if (r4.length == 0)
                                r4.location = r3.location;
                            NSString *match = [bundledList substringWithRange: NSMakeRange(r2.location + r2.length, r4.location - (r2.location+r2.length))];
                            if ([match length] > 0) {
                                [m_expectedArchiveFiles addObject: match];
                            }
                            r.location = r3.location + 1;
                            r.length = len - r.location;
                        }
                    }
                }
            }
        }
        urlString = [urlString stringByReplacingPercentEscapesUsingEncoding: NSUTF8StringEncoding];
        if ([urlString isEqualToString:@"Bedtime.zip"]) { // IFDBentry has a zip in a zip for no reason; work around
            urlString = @"Bedtime story.z8";
            if (!m_expectedArchiveFiles)
                m_expectedArchiveFiles = [[NSMutableArray alloc] init];
            [m_expectedArchiveFiles addObject: urlString];
        }

        m_storyAlreadyInstalled = [m_storyBrowser storyIsInstalled: urlString];
        if (![self IFDBContentExistsInBundle: urlString]  // in bundled
            && !m_storyAlreadyInstalled) { // or they've already manually installed it; allow redownload to get title and artwork
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"In-App Download unsupported"
                                                            message:@"Sorry, this story is not bundled and can't be downloaded by Frotz."
                                  //"\nVisit the Frotz support page if you'd like to request it be bundled in a future update."
                                                           delegate:self cancelButtonTitle:@"Dismiss"
                                                  otherButtonTitles: m_currentRequest && (iosif_ifrotz_verbose_debug & 8)==0 ? @"Open in Safari":nil, nil];
            [alert show];
            return NO;
        }
#endif
        [self performSelector: @selector(loadZMeta:) withObject: request afterDelay: 0.25];
        return NO;
    }
    m_currentRequest = request;
    //NSLog(@"m_currentRequest retain shouldStart %@", m_currentRequest);
    [m_urlBarController setText: [[m_currentRequest mainDocumentURL] absoluteString]];
    m_state = kSWBIdle;
    return YES;
}

- (void)updateButtonsForIdle:(StoryWebView*)webView
{
    [m_activityView stopAnimating];
    [m_backButtonItem setEnabled: [webView canGoBack]];
    [m_forwardButtonItem setEnabled: [webView canGoForward]];
    [m_cancelButtonItem setEnabled: [webView isLoading]];
    [self setButtonItems: [m_webView isLoading]];

    m_state = kSWBIdle;
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == 1) {
        if (m_currentRequest)
            [[UIApplication sharedApplication] openURL: [m_currentRequest mainDocumentURL]];
    }
}

- (void)handleLoadFinished {
    if (m_currentRequest) {
        //NSLog(@"m_currentRequest use didFinishLoad %@", m_currentRequest);

        NSURL *url = [m_currentRequest mainDocumentURL];

        NSString *urlHost = [url host];
        NSString *urlPath = [url path];
        NSString *urlQuery = [url query];

        if (([kIFDBHost isEqualToString: urlHost] || [kIFDBOldHost isEqualToString: urlHost])
            && [urlPath isEqualToString:@"/viewgame"]) {
            if ([urlQuery hasPrefix: @"coverart&"])
                [self snarfMetaData: m_currentRequest loadRequest:nil forStory: nil];
        }
    }
}

- (void)handleLoadFailureWithError:(NSError *)error {
    UIAlertView *alert = nil;

    if ([error code]==102) { //WebKitErrorDomain, Frame Load Error
        if (m_currentRequest && [[[m_currentRequest URL] host] isEqualToString: @"www.youtube.com"])
            ; // ignore (happens when you use YT 'Open in App' button, which succeeds, but also fails here)
        else
            alert = [[UIAlertView alloc] initWithTitle:@"Unknown File Type" message:@"Frotz cannot handle this type of file.\n"
                 //"Select .z3, .z4, .z5, .z8, or .zblorb game file to download and install it."
                                          delegate:self cancelButtonTitle:@"OK" otherButtonTitles: nil];
    } else if ([error code] != NSURLErrorCancelled) {
        alert = [[UIAlertView alloc] initWithTitle:[error localizedDescription] message:[error localizedFailureReason]
                                          delegate:self cancelButtonTitle:@"OK"otherButtonTitles: nil];
    }
    if (alert) {
        [alert show];
    }
    //NSLog(@"m_currentRequest release webviewdidFail %@", m_currentRequest);

    m_currentRequest = nil;
}

#if UseWKWebViewForIFDBBrowser

-(NSString*)currentURL {
    return [self syncStringByEvaluatingJavaScriptFromString: @"document.URL;"];
}

-(NSString*)currentURLTitle {
    return [self syncStringByEvaluatingJavaScriptFromString: @"document.title;"];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = navigationAction.request.URL;
    if ([url.scheme isEqualToString:@"itms-appss"])
    {
        UIApplication *app = [UIApplication sharedApplication];
        if ([app canOpenURL:url]) {
            [webView stopLoading];
            [app openURL: url];
            decisionHandler(WKNavigationActionPolicyCancel);
        } else{
            decisionHandler(WKNavigationActionPolicyCancel);
        }
    } else {
        BOOL answer = [self webViewShouldStartLoadWithRequest: navigationAction.request];
        decisionHandler(answer ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
    }
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    [m_activityView startAnimating];
    [m_cancelButtonItem setEnabled: YES];
    [self setButtonItems: YES];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation*)navigation withError:(NSError *)error {
    [self updateButtonsForIdle: webView];
    [self handleLoadFailureWithError: error];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [self updateButtonsForIdle: webView];
    [self handleLoadFinished];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self updateButtonsForIdle: webView];
    [self handleLoadFailureWithError: error];
}
#else
-(NSString*)currentURL {
    NSString *url = [m_webView stringByEvaluatingJavaScriptFromString:@"document.URL;"];
    return url;
}

-(NSString*)currentURLTitle {
    NSString *title = [m_webView stringByEvaluatingJavaScriptFromString:@"document.title;"];
    return title;
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
    return [self webViewShouldStartLoadWithRequest: request];
}

- (void)webViewDidStartLoad:(UIWebView *)webView {
    [m_activityView startAnimating];
    [m_cancelButtonItem setEnabled: YES];
    [self setButtonItmes: YES];
}

- (void)webViewDidFinishLoad:(UIWebView *)webView {
    [self updateButtonsForIdle: webView];
    [self handleLoadFinished];
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
    [self updateButtonsForIdle: webView];
    [self handleLoadFailureWithError: error];
}

#endif

@end
