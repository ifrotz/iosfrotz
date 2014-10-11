//
//  GettingStartedView.m
//  Frotz
//
//  Created by Craig Smith on 8/29/08.
//  Copyright 2008 Craig Smith. All rights reserved.
//

#import "GettingStarted.h"
#import "TextViewExt.h"
#import "iphone_frotz.h"
#import "FrotzCommonWebView.h"

@implementation GettingStarted

- (id)init {
    if ((self = [super init])) {
        self.title = NSLocalizedString(@"Getting Started", @"");
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
    BOOL oldOS = NO;
    NSString *osVersStr = [[UIDevice currentDevice] systemVersion];
    if (osVersStr && [osVersStr characterAtIndex: 0] == '3' && [osVersStr characterAtIndex: 2] < '2')
        oldOS = YES;

    [webView removeFromSuperview];
    [webView setFrame: self.view.frame];
    [self.view addSubview: webView];

    [webView setAutoresizingMask: UIViewAutoresizingFlexibleBottomMargin|UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight];
    webView.backgroundColor = [UIColor darkGrayColor];
    [webView loadHTMLString: [NSString stringWithFormat:@
                              "<html><body>\n"
                              "<style type=\"text/css\">\n"
                              "h2 { font-size: 14pt; color:#cfcf00; }\n"
                              "* { color:#ffffff; background: #555555 }\n"
                              "p { font-size:12pt; }\n"
                              "</style>\n"
                              "<h2>New to Interactive Fiction?</h2>"
                              "<p>Interactive Fiction makes you the main character in a story.  You control what your character does by entering imperative commands, such as "
                              "<b>light the lamp</b> or <b>give the banana to the monkey</b> at the story prompt (<b>&gt;</b>).  IF contains many subgenres, ranging from classic puzzle-based adventure games and "
                              "treasure hunts, to murder mysteries, to more literary works with intricate plots and character interaction.  "
                              "Since every story is different, most support <b>about</b> and <b>help</b> commands to get you started.</p>\n"
                              
                              "<h2>No, Really, Where Do I Start?</h2>"
                              "<p>If you've never played interactive fiction before, don't worry.  Frotz includes several stories that are well-suited to "
                              "beginners:</p>"
                              
                              "<p><table>\n"
                              "<tr valign=top><td><b>Lost Pig</b></td><td>"
                              "You play an orc named Grunk on a mission in this clever and entertaining game.</td></tr>\n"
                              "<tr valign=top><td><b>Bronze</b></td><td>"
                              "Set in the world of a familiar fairy tale, Bronze is a well-written story designed with beginners in mind.</td></tr>\n"
                              "<tr valign=top><td><b>The Dreamhold</b></td><td>"
                              "In The Dreamhold you explore a wizard's castle looking for clues to your past.  Also designed for people who are new to IF, with tutorial help and even "
                              "automatic hints.</td></tr>\n"
                              "<tr valign=top><td><b>Photopia</b></td><td>"
                              "An intriguing, complex story with virtually no puzzle content, this is less a game and more a true work of interactive fiction.</td></tr>\n"
                              "<tr valign=top><td><b>9:05</b></td><td>"
                              "This is a short, fun little slice-of-life game (with a twist!) that you can play through in about ten minutes.  This game does not have built-in help, "
                              "though, so you might want to try other games first to get a feel for how IF works."
                              "</td></tr>\n"
                              "</table></p>\n"
                              "<p>These are just suggestions.  All of the built-in stories are fine for beginners, with the notable exception of A Change in the Weather, "
                              "which is downright cruel and should be considered advanced.</p>"
                              
                              
                              "<p>You can read descriptions of any of the built-in stories by selecting the story details (disclosure arrow) in the Story List. "
                              "You can then click 'View in IFDB' to read reviews and get more information about the story."
                              "</p>"
                              
                              "<h2>Interacting with Stories</h2>"
                              "<p>While playing a story, the most common verbs you'll use are <b>look</b>, which describes your surroundings, <b>examine</b> (abbreviated <b>x</b>), "
                              "which inspects an object, and <b>inventory</b> (<b>i</b>), which lists all your possessions.\n"
                              "Movement is usually done with cardinal directions, which can be abbreviated as <b>n</b>, <b>e</b>, <b>sw</b>, and so on, "
                              "as well as <b>up</b> and <b>down</b>.  Just typing <b>n</b> is the same as <b>walk north</b>."
                              "</p><p>"
                              
                              "<span style=\"color:yellow;\">More examples of commands:</span><br/>\n"
                              "  <b>&gt; look under the bed</b><br/>\n"
                              "  <b>&gt; lie down in front of bulldozer</b><br/>\n"
                              "  <b>&gt; drop all but blue diamond and green clover</b><br/>\n"
                              "  <b>&gt; take sandwich, towel and lint from satchel</b><br/>\n"
                              "  <b>&gt; tell Fred about the pocketwatch</b><br/>\n"
                              "  <b>&gt; get in hot air balloon</b><br/>\n"
                              "  <b>&gt; robot, give me the crystal ball</b><br/>\n"
                              "  <b>&gt; cast frotz spell on book</b> (or just <b>frotz book</b>)<br>\n"
                              "</p><p>(Articles like 'the' and 'a' are always optional.)</p>\n"
                              
                              "<p><b>Some commands control or query the game state rather than progressing the story:</b></p>\n"
                              "<p><table><tr><td><i><span style=\"color:yellow;\">Command</span></i></td><td><i><span style=\"color:yellow;\">Description</span></i></td></tr>\n"
                              "<tr valign=top><td><b>save</b></td><td>Save a story session in progress.<br>(<b>Frotz</b> will auto-save your game periodically, or if you press the Home button or take a phone call.)</td></tr>\n"
                              "<tr valign=top><td><b>restore</b></td><td>Restore (load) a saved session.</td></tr>\n"
                              "<tr valign=top><td><b>restart</b></td><td>Restart a story from the beginning.</td></tr>\n"
                              "<tr valign=top><td><b>quit</b></td><td>Quit a story and return to story list.</td></tr>\n"
                              "<tr valign=top><td><b>about</b></td><td>Give story-specific introduction and gameplay details.</td></tr>\n"
                              "<tr valign=top><td><b>undo</b></td><td>Undo the last command.</td></tr>\n"
                              "<tr valign=top><td><b>again</b> (<b>g</b>)</td><td>Repeat the last command.</td></tr>\n"
                              "<tr valign=top><td><b>score</b></td><td>Give the game score, if there is one.</td></tr>\n"
                              "<tr valign=top><td><b>version</b></td><td>Print the title, author, version, and other information about the story.</td></tr>\n"
                              "<tr valign=top><td><b>verbose</b></td><td>Print room descriptions always, even if you've been there before.</td></tr>\n"
                              "</table></p>\n"
                              "<span style=\"color:yellow;\">Gestures</span><br/>\n"
                              "<p>While playing, you can <b>tap the story window</b> once to scroll down one page, <b>double tap</b> to scroll to the end and show the keyboard, <b>triple tap</b> to hide the keyboard, or use a <b>flick</b> gesture to scroll.  Use a <b>pinch</b> gesture to increase or decrease the font size.</p>"
                              
                              "<p>You can also <b>tap on the command line</b> to bring up a helper menu of common words, or <b>double tap</b> to bring up a menu of recently entered commands. "
                              "<b>Double tapping</b> on any word in the story window will copy it to the end of the command line.  A <b>long press</b> on the keyboard show/hide button will hide and lock the keyboard, if you prefer to control the "
                              "game using only the input helper menu and other shortcuts.</p>\n"
                              "<p>When displaying built-in <b>help</b>, and in some other situations, games may present a text menu of choices.  In lieu of "
                              "arrow keys, you can use the <b>N</b> and <b>P</b> keys to go to the next and previous item, and <b>Return</b> to make a selection. If the game says to use ESC to back out of a menu, you can tap with two fingers to simulate this key.</p>"
                              "%@"
                              "<br/>"
                              "</body>\n",
                              (oldOS) ?
                              @"<p>Many games display a status line at the top of the screen with your current location, the time or score, or other relevant info.\n"
                              "In order for the story to properly display all the info it expects to, the status line "
                              "uses a small font.  If you have trouble reading the status line, you can <b>press and hold</b> on it magnify it.</p>\n"
                              : !gLargeScreenDevice ?
                              @"<p>Many games display a status line at the top of the screen with your current location, the time or score, or other relevant info.\n"
                              "In some cases the story can only display all the information it needs to when using a small font.  If you are "
                              "using a larger font and the status line is truncated, you can pinch to decrease the font size temporarily in order to see the full status line.</p>\n" : @""]
     
                    baseURL:nil
     ];
}


- (void)dealloc {
    [FrotzCommonWebViewController releaseSharedWebView];
    [super dealloc];
}


@end
