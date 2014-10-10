//
//  AboutFrotz.m
//  Frotz
//
//  Created by Craig Smith on 8/29/08.
//  Copyright 2008 Craig Smith. All rights reserved.
//

#import "AboutFrotz.h"
#import "TextViewExt.h"
#import "iphone_frotz.h"
#import "StoryMainViewController.h"
#import "FrotzCommonWebView.h"

@implementation AboutFrotz

- (id)init {
    if ((self = [super init])) {
        self.title = NSLocalizedString(@"About Frotz", @"");
    }
    return self;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return gLargeScreenDevice ? YES : interfaceOrientation == UIInterfaceOrientationPortrait;
}


-(void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [super didRotateFromInterfaceOrientation: fromInterfaceOrientation];
    [self viewWillAppear:NO];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    UIWebView *webView = [FrotzCommonWebViewController sharedWebView];
    [webView removeFromSuperview];
    [webView setFrame: self.view.frame];
    [self.view addSubview: webView];
    [webView setAutoresizingMask: UIViewAutoresizingFlexibleBottomMargin|UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight];
    webView.backgroundColor = [UIColor darkGrayColor];
    int baseFontSize = 12 + (gLargeScreenDevice?2:0);
    NSString *content = [NSString stringWithFormat: @
                         "<html><body>\n"
                         "<style type=\"text/css\">\n"
                         "h2 { font-size: %dpt; color:#cfcf00; }\n"
                         "* { color:#ffffff; background: #555555 }\n"
                         "p { font-size:%dpt; }\n"
                         "</style>\n"
                         "<h2>Welcome to Frotz!</h2>\n"
                         "<p>\n"
                         "<b>Frotz</b> lets you play hundreds of works of Interactive Fiction (a.k.a. text adventure games) on your iPhone,<sup>&reg;</sup> iPad,<sup>&reg;</sup> or iPod Touch.<sup>&reg;</sup></p>\n"
                         "%@"
                         "</p><p>\n"
                         "<b>Frotz</b> can also play the original <b>Infocom</b> titles such as Zork 1-3, Enchanter, Hitchhiker's Guide to the Galaxy, Bureaucracy, and Trinity.  \n"
                         "These games are under copyright and most are not available for download, but are available for purchase via Activision's Lost Treasures of Infocom series.  \n"
                         "If you have the game files, you can transfer them to <b>Frotz</b> using the built-in file server, which can be enabled on the File Transfer Info page.\n"
                         "</p><p>\n"
                         "This version of <b>Frotz</b> does not yet support Version 6 games with graphics.\n"
                         "</p>%@<hr><p>\n"
                         "<p><b>Frotz Version "
                         IPHONE_FROTZ_VERS
                         " for iOS.</b></p>"
                         "<p><b>Frotz</b> for iOS was developed by Craig Smith, based on Unix Frotz 2.43 by David Griffith and Galen Hazelwood.  \n"
                         "Frotz was originally written by Stefan Jokisch in 1995-1997.  ZIP archive support based on minizip 1.01e by Gilles Vollant and zlib 1.2.3 by Jean-loup Gailly and Mark Adler. \n"
                         "Frotz 1.5 introduced (beta) Glulx game support, using the Git engine by Iain Merrick, and the Glk I/O system by Andrew Plotkin. \n"
                         "Game splash screens include artwork by	Andrew Bossi, Trey Radcliff, and Mike Green, distributed under Creative Commons with attribution."
                         "</p>\n"
                         "<hr>\n"
                         "<small><p><i>Frotz is licensed under the GNU Public License version&nbsp;2, with some components under compatible MIT and BSD licenses; "
#if FROTZ_BETA
                         "source code is available at http://code.google.com/p/iphonefrotz/.  \n"
#else
                         "see the Frotz support link in the App Store for more info.  \n"
#endif
                         "Versions of Frotz for other platforms as well as other Interactive Fiction resources are at http://frotz.sourceforge.net/.</i></small></p>\n"
                         "<p><small><i>iPhone, iPad, iPod Touch, and App Store are registered trademarks of Apple, Inc.</i><br>\n"
                         "<i>Zork is a registered trademark of Activision.</i></small>\n"
                         "</p>%@<br/>\n"
                         "</body>\n",
                         baseFontSize+2, baseFontSize,
                         (iphone_ifrotz_verbose_debug & 2) ?
                         @"<b>Frotz</b> comes with a collection of bundled stories/games, and works with most stories written in the Z-Machine or glulx formats. "
                         "More stories are available from the Interactive Fiction Database (IFDB) and elsewhere on the Internet and can be "
                         "opened in Frotz via Safari or other apps or browsed to using the "
                         "built-in IFDB browser.   Just navigate to the Details page for a story file that interests you and click on the story link to launch the story.  (Supported story files end in extensions .z3, .z4, .z5, .z8, .zblorb, .ulx, .blb, or .gblorb.)\n"
                                                  :
                         @"<p><b>Frotz</b> comes with a very large collection of stories/games. Twenty-five preselected stories appear by default in the Story List, but "
                         "over 300 more are bundled with Frotz.\n</p>"
                         "<p>To enable other stories, use the built-in Story Browser to read reviews and descriptions from the "
                         "Interactive Fiction Database (IFDB). When you find one that interests you, select the link for the story file (extensions .z3, .z4, .z5, .z8, .zblorb, .ulx, .blb, or .gblorb) "
                         "from its description page, and the story file will be extracted from the bundled archive and added to the Story List. "
                         "Very recent additions to IFDB (or poorly reviewed ones) may not be available in the bundle. "
                         "The bundled list of stories will be expanded with each release of Frotz, but if you'd like to request a particular addition, "
                         "visit the Frotz support link in the App Store<sup>*</sup>.",
                         (!gLargeScreenDevice) ?
                         @"<strong>Please note that some games expect a screen at least 80 columns wide, and may produce clipped output</strong>, especially when printing fixed-width text or block quotations.  "
                         "Turning your device into landscape (sideways) orientation will usually allow you to view such content correctly.  " : @"",
                         ((iphone_ifrotz_verbose_debug & 2) || !(iphone_ifrotz_verbose_debug & 4)) ? @"" :
                         @"<p><small><sup><b>*</b></sup> Note that App Store policy does not allow Frotz to download new content from the Internet, "
                         "so many more games are now bundled with Frotz to try to mitigate this unfortunate and restrictive policy.</small></p>"
                         ];
	[webView loadHTMLString: content baseURL:nil];
}

- (void)dealloc {
    [FrotzCommonWebViewController releaseSharedWebView];
    [super dealloc];
}


@end
