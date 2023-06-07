//
//  ReleaseNotes.m
//  Frotz
//
//  Created by Craig Smith on 8/29/08.
//  Copyright 2008 Craig Smith. All rights reserved.
//

#import "ReleaseNotes.h"
#import "TextViewExt.h"
#import "iosfrotz.h"
#import "StoryMainViewController.h"
#import "FrotzCommonWebView.h"
#import "NetworkController.h"

#define kRelNotesFilename "release_" IPHONE_FROTZ_RN_VERS ".html"

#ifndef OO
#define OO
#endif

@implementation ReleaseNotes

- (instancetype)init {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        self.title = NSLocalizedString(@"Release Notes", @"");
        NSString *appSuppPath = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, true)[0];
        m_relNotesPath = [appSuppPath stringByAppendingPathComponent: @kRelNotesFilename];
        [self performSelector:@selector(updateReleaseNotesAuto) withObject:nil afterDelay:1.0];
    }
    return self;
}


-(void)loadView {
    [super loadView];
    if (!m_rateButton ) {
        m_rateButton = [UIButton buttonWithType: UIButtonTypeRoundedRect];
        [m_rateButton setTitle: @"Rate Frotz" forState:UIControlStateNormal];
        [m_rateButton setTitleColor: [UIColor cyanColor] forState:UIControlStateNormal];
        [[m_rateButton layer] setOpacity:0.8];
        [m_rateButton addTarget:self action:@selector(rateFrotz) forControlEvents: UIControlEventTouchUpInside];
    }
}

-(void)rateFrotz {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://apps.apple.com/us/app/frotz/id287653015"]];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    [m_data setLength: 0];
}
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [m_data appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    FrotzWebView *webView = [FrotzCommonWebViewController sharedWebView];
    
    NSError *error;
    NSString *contents = [[NSString alloc] initWithBytes:[m_data bytes] length:[m_data length] encoding: NSUTF8StringEncoding];
    NSRange r;
    if ((r = [contents rangeOfString: @"--bcs"]).length > 0) { // sanity check so we don't load an error page or something
        [contents writeToFile:m_relNotesPath atomically:YES encoding:NSUTF8StringEncoding error:&error];OO
    }
    m_data = nil;
    m_request = nil;
    m_connection = nil;
    if (webView && r.length > 0)
        [self showReleaseNotes];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    m_request = nil;
    m_data = nil;
    m_connection = nil;
}

- (void)updateReleaseNotesAuto {
    [self updateReleaseNotes: NO];
}

- (void)updateReleaseNotes:(BOOL)force {
#ifdef FROTZ_REL_URL
    if (force || [NetworkController localWifiIPAddress]!=nil) {
#if !FROTZ_BETA
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSDictionary *fileAttributes = [ fileManager attributesOfItemAtPath:m_relNotesPath error:nil];
        if (fileAttributes) {
            NSDate *fileModified = [fileAttributes valueForKey:NSFileModificationDate];
            NSTimeInterval interval =  [[NSDate date] timeIntervalSinceDate: fileModified];
            if (interval < 5*60 || !force && interval < 24*60*60)
                return;
        }
#endif
        NSString *devModel = [[[UIDevice currentDevice] localizedModel] stringByReplacingOccurrencesOfString:@" " withString:@"_"];
        NSString *devVers = [[[UIDevice currentDevice] systemVersion] stringByReplacingOccurrencesOfString:@" " withString:@"_"];
        NSURL *myURL = [NSURL URLWithString: [NSString stringWithFormat:@"%@?q=%@,%@&%lu", @FROTZ_REL_URL kRelNotesFilename,
                                                devModel, devVers, time(0)]];
        m_request = [NSURLRequest requestWithURL: myURL];    
        m_data = [NSMutableData data];
        m_connection = [[NSURLConnection alloc] initWithRequest:m_request delegate:self];
    } else
        [self performSelector:@selector(updateReleaseNotesAuto) withObject:nil afterDelay:60*60];
#endif
}

- (void)showReleaseNotes {
    NSError *error;
    FrotzWebView *webView = [FrotzCommonWebViewController sharedWebView];
    [webView removeFromSuperview];
    [webView setFrame: self.view.frame];
    [self.view addSubview: webView];
    [webView setAutoresizingMask: UIViewAutoresizingFlexibleBottomMargin|UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight];
    webView.backgroundColor = [UIColor darkGrayColor];
    int baseFontSize = 11; // + (gLargeScreenDevice?3:0);
    NSString *htmlString = nil;
    NSString *cssString = [NSString stringWithFormat: @
                           "<style type=\"text/css\">\n"
                           "h2 { font-size: %dpt; color:#cfcf00; }\n"
                           "h3 { font-size: %dpt; color:#ffffff; }\n"
                           "p { font-size:%dpt; }\n"
                           "em { bold; color:#af0000; }\n"
                           "* { color:#f0f0f0; background: #555555 }\n"
                           "ul { margin-left: 0.2em;\n"
                           "    padding-left: 1em; font-size:%dpt; }\n"
                           "</style>\n", baseFontSize+3, baseFontSize+1, baseFontSize, baseFontSize];
    
    
    if ([[NSFileManager defaultManager] fileExistsAtPath: m_relNotesPath]) {
        htmlString = [NSString stringWithContentsOfFile:m_relNotesPath encoding:NSUTF8StringEncoding error:&error];
    } else {
        htmlString = @
        "<h2>What's New in Frotz?</h2>\n"
        "<hr/>\n"
        "<p>New in <b>Frotz 1.8.7</b>:</p>\n"
        "<p><ul>\n"
        "<li>Update glulx (git) interpreter standard to 1.3.7.</li>\n"
        "<li>Better support for Unicode/non-Latin alphabet games</li>\n"
        "<li>New IFDB search options, updated search URLs and built-in bookmarks</li>\n"
        "<li>Dropbox API update, sync improvements</li>\n"
        "<li>Option to swap text/background colors in color picker</li>\n"
        "<li>Improved handling of ZIP file downloads from IFDB: you can now select which stories to install.</li>\n"
        "<li>Enable 'iTunes File sharing: supported story files and saved games dragged into Frotz will be automatcally installed.\n"
        "<li>Restored keyboard long-press hide/lock functionality.</li>\n"
        "<li>Other bug fixes/minor UI tweaks.</li>\n"
        "</ul></p>\n"
        "<h3>If you enjoy Frotz, please rate it in the App Store.<br>Or write a review! Thanks!</h3>"
        "<p><small><i>Craig Smith, June 8, 2023</i><br>\n"
        "<hr>\n"
        "<p><i>Previous release notes</i></p>\n"
        "\n"
        "<p>Version 1.8.6:</p>\n"
        "<p><ul>\n"
        "<li>Fix iPad crash when trying to restart story from Story Details view.</li>\n"
        "<li>Fix hang which can occur when scrolling in Frotz Settings.</li>\n"
        "</ul></p>\n"
        "<p>Version 1.8.5:</p>\n"
        "<p><ul>\n"
        "<li>Configurable text size and font on Notes screen.</li>\n"
        "<li>Fix unreadable Notes text in dark mode.</li>\n"
        "<li>General bug fixes and refactoring to use more modern iOS APIs.</li>\n"
        "</ul></p>\n"
        "<p>Version 1.8.4:</p>\n"
        "<p><ul>\n"
        "<li>Bug fixes, more light/dark mode enhancements.</li>\n"
        "</ul></p>\n"
        "<p>Version 1.8.3:</p>\n"
        "<p><ul>\n"
        "<li>Improved support for iOS 13, including light/dark mode.</li>\n"
        "<li>Better support for newer devices/screen sizes.</li>\n"
        "<li>Other bug fixes.</li>\n"
        "</ul></p>\n"
        "<p>Version 1.8.2:</p>\n"
        "<p><ul>\n"
        "<li>Prevent games from being confused by iOS 11's &#x201c;smart punctuation&#x201d;.</li>\n"
        "<li>Fix bug with text window partition sizing in glulx games.</li>\n"
        "<li>Add launch shortcut to Story List (without resuming current story).</li>\n"
        "<li>Other bug fixes.</li>\n"
        "</ul></p>\n"
        "<p>Version 1.8.1:</p>\n"
        "<p><ul>\n"
        "<li>Update to <b>Dropbox</b> API v2.</li>\n"
        "<li>Improvements for iOS 11.</li>\n"
        "<li>Bug fixes, but a couple new bugs.</li>\n"
        "</ul></p>\n"
        "<p>Version 1.8:</p>\n"
        "<p><ul>\n"
        "<li>Now plays games in <b>TADS</b> format (v2/v3).</li>\n"
        "<li>Improved performance and <b>64-bit</b> support.</li>\n"
        "<li>Split-screen <b>multitasking</b> support on iPads.</li>\n"
        "<li>Fix crash when task-switching back to Frotz in iOS 9.x.</li>\n"
        "<li>Various other bug fixes.</b></li>\n"
        "</ul></p>\n"
        "<p>Version 1.7.1:</p>\n"
        "<p><ul>\n"
        "<li>Improved support for iPhone 6, iPhone 6 Plus, and iOS 8.</li>\n"
        "<li>Fixed bug printing accented characters in status window.</li>\n"
        "<li>Allow pinch gesture to change story font size.</li>\n"
        "<li>Several minor bug fixes in glk game support.</li>\n"
        "</ul></p>\n"

        "<p>Version 1.7:</p>\n"
        "<p><ul>\n"
        "<li>UI makeover with support for iOS 7.</li>\n"
        "<li>New Search Bar in Story List.</li>\n"
        "<li>Word auto-completion now uses the current game's vocabulary/dictionary.</li>\n"
        "<li>Fixed issues with accented characters/Unicode support.</li>\n"
        "<li>Improved support for graphics windows, inline images, and hyperlinks in glulx games.</li>\n"
        "<li>Fixed problem where VoiceOver wouldn't read new text right after the game clears the screen.</li>\n"
        "<li>Ability to long-press keyboard toggle button to hide and lock keyboard (for menu-only command input).</li>\n"
        "<li>Update to glk spec 0.7.4, git interpreter 1.3.3.</li>\n"
        "<li>Lots of other minor bug fixes.</li>\n"
        "</ul></p>\n"
#if 1
        "<p>Version 1.6:</p>\n"
        "<p><ul>\n"
        "<li><b>Support for iPhone 5, iOS 6, and Retina Displays.</b></li>\n"
        "<li><b>Hyperlinks</b>:  now supports hyperlinks in glulx games.</li>\n"
        "<li><b>Dropbox</b>: updated to latest Dropbox API.</li>\n"
        "<li><b>Other minor bug fixes.</b></li>\n"
        "</ul></p>\n"
#endif
#if 1 // 1.5.3
        "<p>Version 1.5.3:</p>\n"
        "<p><ul>\n"
        "<li><b>Readability:</b> Wider margins and spacing for better readability on iPad.</li>\n"
        "<li><b>Unicode</b>: Improved Unicode text support for games with non-Latin characters.</li>\n"
        "<li><b>Updated glulx support</b>: Now conforms to standard spec 3.1.2.</li>\n"
        "<li><b>Graphics improvements</b>: Performance and stability of games using glk graphics improved; Frotz now supports inline images in text.</li>\n"
        "<li><b>VoiceOver support</b>: Fixed bug preventing automatic announcement of new output in glulx games.</li>\n"
        "<li><b>Keyboard</b>: Improved support for playing with a Bluetooth keyboard (you can now scroll via keyboard and no longer have to tap the screen).</li>\n"
        "<li><b>Other bug fixes</b>: New FTP server compatible with more clients; restored 'Open in' functionality for launching Frotz from other apps.</li>\n"
        "</ul></p>\n"
#endif
#if 1 // 1.5.2
        "<p>Version 1.5.2:</p>\n"
        "<p><ul>"
        "<li><b>Fixed crash on older devices</b>: iPod Touch (1st/2nd gen.) and iPhone 3G would crash on launch due to bugs in the compiler used to build Frotz. This has been resolved.</li>"
        "<li><b>Other minor bug fixes</b>: Fixed issue where navigation bar would disappear after viewing save/restore/transcript dialog on small screen "
        "devices; allow transfer of transcripts in web file transfer server; fixed crash when restarting a story immediately after quitting..</li>"
        "</ul></p>\n"
#endif
#if 1 // 1.5.1
        "<p>Version 1.5.1:</p><ul>\n"
        "<li><b>iOS 4.3 compatibility</b>: Fixed crash when deleting text that occurred only in iOS 4.3</li>"
        "<li><b>Other minor bug fixes</b>: Fixed issue deleting files via web interface, viewing transcripts in landscape, and text color issues in glulx games.</li>"
        "</ul></p>\n"
#endif
        "<p>New features in 1.5:</p><ul>\n"
#if 1 // 1.5
        "<li><b>Improved UI</b>: The interface has been improved and refined, particularly on the iPad.</li>\n"
        "<li><b>Recently Played Stories</b>: Frotz now keeps track of your most recently played stories at the top of the Story List.</li>\n"
        "<li><b>Note taking</b>: Swipe left while playing any story to view a note-taking area for that story.</li>\n"
        "<li><b>View/Edit Story Details</b>: Frotz now has authors, descriptions, and artwork for all built-in stories and can link back to the full IFDB entry for each.</li>\n"
        "<li><b>Dropbox support</b>: Frotz now supports synchronizing saved games with Dropbox, so you can seamlessly play on multiple devices.</li>\n"
        "<li><b>Bookmarks in Story Browser</b>: You can now bookmark individual pages in the IFDB browser.</li>\n"
        "<li><b>More bundled games added from IFDB</b>: Includes an updated IFDB snapshot with more recent well-rated works.</li>\n"
        "<li><b>Miscellaneous bug fixes</b>: Fixed Bluetooth keyboard support, status line/text resizing bugs, and various other minor bugs.</li>\n"
        "</ul></p>\n"
#endif
#if 1 // 1.4
        "<p>New features in 1.4:</p><ul>\n"
        "<li><b>Improved autosave</b>: Frotz now autosaves each story independently, so you can switch stories without having to manually save or abandon your current one.</li>\n"
        "<li><b>Better text performance</b>: Frotz's text output support has been rewritten and is now faster and has a larger scroll back history.</li>\n"
        "<li><b>Word selection</b>: You can now double-tap on a word in the story output to copy it to the command line.</li>\n"
        "<li><b>Font sizes</b>: The maximim story font size has been increased to 20 pt.</li>\n"
        "<li><b>Web-based File Transfer</b>: You can now transfer game files with a web browser as well as FTP.</li>\n"
        "<li><b>Infocom support</b>: More filename variants of Infocom data files are now recognized.</li>\n"
        "<li><b>Text color bug fixed</b>: Fixed a problem where text color would draw in black instead of customized color.</li>\n"
        "<li><b>Other Bug fixes</b>: Various other minor bugs have been fixed too uninteresting to mention by name.</li>\n"
        "</ul></p>\n"
#endif
#if 1 // 1.3
        "<p>New features in 1.3:</p><ul>\n"
        "<li><b>Story Font Size preference</b>: allows you to vary the main story font size from 8 to 16 point.</li>\n"
        "<li><b>Status Line magnification</b>:  tap anywhere on the status line to magnify it for readability.\n"
        "(This is in lieu of allowing larger status line fonts, because many games require a minimum number\n"
        "of screen columns, which would force you to scroll left and right to see the entire line.)\n"
        "</li>\n"
        "<li><b>Command Helper Menu</b>: tap on the command prompt to bring up a helper menu of common words.\n"
        "</li>\n"
        "<li><b>Command Line History</b>: double-tap on the command line to bring up a menu of recently\n"
        "entered commands.</li>\n"
        "<li><b>Accessibility Improvements</b>: improved accessibility hints for VoiceOver users. Selecting\n"
        "the story window will recite only the story output since the most recent command.\n"
        "</li>\n"
        "<li><b>Bug fixes (OS 3.0)</b>: restored the ability to tap on the story output to scroll one page, or show the keyboard if at the end.</li>\n"
        "<li><b>Bundled stories</b>: includes a large subset of well-rated stories from the IFDB bundled with Frotz; the IFDB story browser uses these bundled files instead of downloading them from the Internet. </li>\n"
        "</ul></p>\n"
#endif
        "<br/>\n";
        // 1.6: sep xx, 2012
        // 1.5.3: june 2, 2011
        // 1.5.1: mar 23, 2011
        // 1.5: oct 25, 2010
        // 1.4: mar 19, 2010
        // 1.3: sep 4, 2009
    }
    NSString *metaString = @"<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">";
    NSString *contentString = [NSString stringWithFormat: @"<html><body>\n%@\n%@\n%@\n</body>\n\n", cssString, metaString, htmlString];
    [webView loadHTMLString: contentString baseURL: nil];
#if FROTZ_BETA > 1
    NSLog(@"%@", htmlString);
#endif
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self showReleaseNotes];
    [self updateReleaseNotes: YES];
}

-(void)viewDidAppear:(BOOL)animated {
    FrotzWebView *view = [FrotzCommonWebViewController sharedWebView];
    if ([view respondsToSelector: @selector(scrollView)]) {
        [[view scrollView] addSubview: m_rateButton];
        CGRect frame = self.view.frame;
        [m_rateButton setFrame: CGRectMake(frame.size.width - 112 , 10, 100, 24)];
    }    
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [m_rateButton removeFromSuperview];
}

- (void)dealloc {
    m_rateButton = nil;
    m_data =  nil;
    m_relNotesPath = nil;
    [FrotzCommonWebViewController releaseSharedWebView];
}


@end
