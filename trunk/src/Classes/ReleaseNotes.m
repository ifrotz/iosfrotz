//
//  ReleaseNotes.m
//  Frotz
//
//  Created by Craig Smith on 8/29/08.
//  Copyright 2008 Craig Smith. All rights reserved.
//

#import "ReleaseNotes.h"
#import "TextViewExt.h"
#import "iphone_frotz.h"
#import "StoryMainViewController.h"
#import "FrotzCommonWebView.h"

#define kRelNotesFilename "release_" IPHONE_FROTZ_VERS ".html"

#ifndef OO
#define OO
#endif

@implementation ReleaseNotes

- (id)init {
    if ((self = [super init])) {
        self.title = NSLocalizedString(@"Release Notes", @"");
        NSArray *array = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, true);
        NSString *docPath = [array objectAtIndex: 0];
        m_relNotesPath = [[docPath stringByAppendingPathComponent: @kRelNotesFilename] retain];
    }
    return self;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    [m_data setLength: 0];
}
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [m_data appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    UIWebView *webView = (UIWebView*)self.view;
    
    NSError *error;
    NSString *contents = [[NSString alloc] initWithBytes:[m_data bytes] length:[m_data length] encoding: NSUTF8StringEncoding];
    NSRange r;
    if ((r = [contents rangeOfString: @"--bcs"]).length > 0) { // sanity check so we don't load an error page or something
        [contents writeToFile:m_relNotesPath atomically:YES encoding:NSUTF8StringEncoding error:&error];OO
    }
    [contents release];
    [m_data release];
    m_data = nil;
    [connection release];
    if (webView && r.length > 0)
        [self showReleaseNotes];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    [m_data release];
    m_data = nil;
    [connection release];
}

- (void)updateReleaseNotes {
#ifdef FROTZ_REL_URL
    NSURL *myURL = [NSURL URLWithString: @FROTZ_REL_URL kRelNotesFilename];
    m_request = [NSURLRequest requestWithURL: myURL];    
    m_data = [[NSMutableData data] retain];
    [[NSURLConnection alloc] initWithRequest:m_request delegate:self];
#endif
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return gLargeScreenDevice ? YES : interfaceOrientation == UIInterfaceOrientationPortrait;
}



- (void)showReleaseNotes {
    NSError *error;
    UIWebView *webView = [FrotzCommonWebViewController sharedWebView];
    self.view = webView;
    [webView setAutoresizingMask: UIViewAutoresizingFlexibleBottomMargin|UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight];
    webView.backgroundColor = [UIColor darkGrayColor];
    int baseFontSize = 11; // + (gLargeScreenDevice?3:0);
    NSString *htmlString = nil;
    NSString *cssString = [NSString stringWithFormat: @
                           "<style type=\"text/css\">\n"
                           "h2 { font-size: %dpt; color:#cfcf00; }\n"
                           "p { font-size:%dpt; }\n"
                           "* { color:#ffffff; background: #555555 }\n"
                           "ul { margin-left: 0.2em;\n"
                           "    padding-left: 1em; font-size:%dpt; }\n"
                           "</style>\n", baseFontSize+3, baseFontSize, baseFontSize];
    
    
    if ([[NSFileManager defaultManager] fileExistsAtPath: m_relNotesPath]) {
        htmlString = [NSString stringWithContentsOfFile:m_relNotesPath encoding:NSUTF8StringEncoding error:&error];
    } else {
        htmlString = @
        "<h2>What's New in Frotz?</h2>\n"
        "<hr/>\n"
        "<p>New in <b>Frotz</b> " IPHONE_FROTZ_VERS ":</p>\n"
        "<p><ul>\n"
        "<li><b>Readability:</b> Wider margins and spacing for better readability on iPad.</li>\n"
        "<li><b>Unicode</b>: Improved Unicode text support for games with non-Latin characters.</li>\n"
        "<li><b>Updated glulx support</b>: Now conforms to standard spec 3.1.2.</li>\n"
        "<li><b>Graphics improvements</b>: Performance and stability of games using glk graphics improved; Frotz now supports inline images in text.</li>\n"
        "<li><b>VoiceOver support</b>: Fixed bug preventing automatic announcement of new output in glulx games.</li>\n"
        "<li><b>Keyboard</b>: Improved support for playing with a Bluetooth keyboard (you can now scroll via keyboard and no longer have to tap the screen).</li>\n"
        "<li><b>Other bug fixes</b>: New FTP server compatible with more clients; restored 'Open in' functionality for launching Frotz from other apps.</li>\n"
        "</ul>"
        "<hr>\n"
        "<p>Author's note: If you've rated Frotz in the App Store before, I'd really appreciate it if you would rate the new version.  Or write  a review! Thanks!</p>"
        "<p><small><i>June 2, 2011</i><br>\n"
        "<hr>\n"
#if 1
        "<p><i>Previous release notes</i></p>\n"
        "<br/>\n"
        "<p>Fixed in 1.5.2:</p>\n"
        "<p><ul>"
        "<li><b>Fixed crash on older devices</b>: iPod Touch (1st/2nd gen.) and iPhone 3G would crash on launch due to bugs in the compiler used to build Frotz. This has been resolved.</li>"
        "<li><b>Other minor bug fixes</b>: Fixed issue where navigation bar would disappear after viewing save/restore/transcript dialog on small screen "
        "devices; allow transfer of transcripts in web file transfer server; fixed crash when restarting a story immediately after quitting..</li>"
        "</ul>"
#endif
#if 1 // 1.5.1
        "<p>Fixed in 1.5.1:</p><ul>\n"
        "<li><b>iOS 4.3 compatibility</b>: Fixed crash when deleting text that occurred only in iOS 4.3</li>"
        "<li><b>Other minor bug fixes</b>: Fixed issue deleting files via web interface, viewing transcripts in landscape, and text color issues in glulx games.</li>"
        "</ul>"
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
        "</ul>"
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
        "</ul>"
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
        "</ul>"
#endif
        "<br/>\n";
        // 1.5.1: mar 23, 2011
        // 1.5: oct 25, 2010
        // 1.4: mar 19, 2010
        // 1.3: sep 4, 2009
    }
    [webView loadHTMLString: [NSString stringWithFormat: @"<html><body>\n%@\n%@\n</body>\n\n", cssString, htmlString] baseURL: nil];
#if FROTZ_BETA
    NSLog(@"%@", htmlString);
#endif
}

- (void)viewWillAppear:(BOOL)animated {
    [self showReleaseNotes];
    [self updateReleaseNotes];
}

- (void)dealloc {
    if (m_data)
        [m_data release];
    m_data =  nil;
    [m_relNotesPath release];
    m_relNotesPath = nil;
    [FrotzCommonWebViewController releaseSharedWebView];
    [super dealloc];
}


@end
