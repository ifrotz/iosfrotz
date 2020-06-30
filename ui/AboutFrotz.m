//
//  AboutFrotz.m
//  Frotz
//
//  Created by Craig Smith on 8/29/08.
//  Copyright 2008 Craig Smith. All rights reserved.
//

#import "AboutFrotz.h"
#import "TextViewExt.h"
#import "iosfrotz.h"
#import "StoryMainViewController.h"
#import "FrotzCommonWebView.h"

@implementation AboutFrotz

- (instancetype)init {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        self.title = NSLocalizedString(@"About Frotz", @"");
    }
    return self;
}

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil {
    if ((self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil])) {
        self.title = NSLocalizedString(@"About Frotz", @"");
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
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

    FrotzWebView *webView = [FrotzCommonWebViewController sharedWebView];
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
                         "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
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
                         "<p><b>Frotz</b> for iOS was developed by Craig Smith, based on Unix Frotz 2.43 by <b>David Griffith</b> and <b>Galen Hazelwood</b>.  \n"
                         "Frotz was originally written by <b>Stefan Jokisch</b> in 1995-1997.\n"
                         "Frotz 1.5 introduced Glulx game support, using the Git engine by <b>Iain Merrick</b> and based on the Glulx game specification and Glk I/O system by <b>Andrew Plotkin</b>. \n"
                         "Frotz 1.8 introduced TADS game support, based on TADS 2 and TADS 3 game engines by <b>Michael J. Roberts</b> under the TADS Freeware License, and using the TADS Glk I/O binding from Gargoyle by <b>Tor Andersson</b> and <b>Ben Cressey</b>.</p>\n"
                         "<p>Special thanks to <b>Michael Roberts</b> for maintaining the IFDB web resources and <b>Peter Piers</b> for invaluable testing and feedback.  Thanks also to <b>Graham Nelson</b>, <b>Andrew Plotkin</b>, <b>Emily Short</b>, <b>Adam Cadre</b>, and the other IF authors whose works are distributed with Frotz for iOS or made freely available to adventurers everywhere on IFDB.\n"
                         "</p>\n"
                         "<p>Game splash screens include artwork by <b>Andrew Bossi</b>, <b>Trey Radcliff</b>, and <b>Mike Green</b>, distributed under Creative Commons with attribution.\n"
                         "</p>\n"
                         "<hr>\n"
                         "<small><p><i>Frotz is licensed under the GNU Public License version&nbsp;2, with some components under compatible MIT.  BSD and freeware licenses; "
                         "source code is available at https://github.com/ifrotz.\n"
                         "See the Frotz support link in the App Store for more info.  \n"
                         "Versions of Frotz for other platforms as well as other Interactive Fiction resources are at http://frotz.sourceforge.net/.</i></small></p>\n"
                         "<p><small><i>iPhone, iPad, iPod Touch, and App Store are registered trademarks of Apple, Inc.</i><br>\n"
                         "<i>Zork is a registered trademark of Activision.</i></small>\n"
                         "</p>%@<br/>\n"
                         "</body>\n",
                         baseFontSize+2, baseFontSize,
                         (iosif_ifrotz_verbose_debug & 2) ?
                         @"<b>Frotz</b> comes with a collection of bundled stories/games, and works with most stories written in the Z-Machine, glulx and TADS formats. "
                         "More stories are available from the Interactive Fiction Database (IFDB) and elsewhere on the Internet and can be "
                         "opened in Frotz via Safari or other apps or browsed to using the "
                         "built-in IFDB browser.   Just navigate to the Details page for a story file that interests you and click on the story link to launch the story.  (Supported story files end in extensions .z3, .z4, .z5, .z8, .zblorb, .ulx, .blb, .gblorb, .gam and .t3.)\n"
                                                  :
                         @"<p><b>Frotz</b> comes with a very large collection of stories/games. Twenty-five preselected stories appear by default in the Story List, but "
                         "over 300 more are bundled with Frotz.\n</p>"
                         "<p>To enable other stories, use the built-in Story Browser to read reviews and descriptions from the "
                         "Interactive Fiction Database (IFDB). When you find one that interests you, select the link for the story file (extensions .z3, .z4, .z5, .z8, .zblorb, .ulx, .blb, .gblorb, .gam or .t3) "
                         "from its description page, and the story file will be extracted from the bundled archive and added to the Story List. "
                         "Very recent additions to IFDB (or poorly reviewed ones) may not be available in the bundle. "
                         "The bundled list of stories will be expanded with each release of Frotz, but if you'd like to request a particular addition, "
                         "visit the Frotz support link in the App Store<sup>*</sup>.",
                         (!gLargeScreenDevice) ?
                         @"<strong>Please note that some games expect a screen at least 80 columns wide, and may produce clipped output</strong>, especially when printing fixed-width text or block quotations.  "
                         "Turning your device into landscape (sideways) orientation will usually allow you to view such content correctly.  " : @"",
                         ((iosif_ifrotz_verbose_debug & 2) || !(iosif_ifrotz_verbose_debug & 4)) ? @"" :
                         @"<p><small><sup><b>*</b></sup> Note that App Store policy does not allow Frotz to download new content from the Internet, "
                         "so many more games are now bundled with Frotz to try to mitigate this unfortunate and restrictive policy.</small></p>"
                         ];
	[webView loadHTMLString: content baseURL:nil];
}

- (void)dealloc {
    [FrotzCommonWebViewController releaseSharedWebView];
}


@end
