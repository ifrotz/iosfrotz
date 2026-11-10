//
//  GettingStartedView.m
//  Frotz
//
//  Created by Craig Smith on 8/29/08.
//  Copyright 2008 Craig Smith. All rights reserved.
//

#import "GettingStarted.h"
#import "TextViewExt.h"
#import "iosfrotz.h"
#import "FrotzCommonWebView.h"

@implementation GettingStarted

- (instancetype)init {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        self.title = NSLocalizedString(@"Getting Started", @"");
    }
    return self;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self loadGettingStartedContent];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    // The status line advice depends on the horizontal size class, so refresh the page if the
    // size class changes while it is showing (e.g. folding/unfolding).
    if (self.viewIfLoaded.window && previousTraitCollection.horizontalSizeClass != self.traitCollection.horizontalSizeClass)
        [self loadGettingStartedContent];
}

- (void)loadGettingStartedContent {
    BOOL regularWidth = self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular;
    FrotzWebView *webView = [FrotzCommonWebViewController sharedWebView];

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
                              "a { color:#cfcf00; }\n"
                              "</style>\n"
                              "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
#if EnableStoryDictation
                              "<p><b style=\"color:#00cfcf;\">New in Frotz</b>: You can now <a href=\"#voice\">Play by Voice</a> (see below).</p>\n"
#endif
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
                              "<tr valign=top><td><b>save</b></td><td>Save a story session in progress.<br>(<b>Frotz</b> will auto-save your game periodically, or if you switch apps or take a phone call.)</td></tr>\n"
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
#if EnableStoryDictation
                              "<h2 id=\"voice\">Playing by Voice <em style=\"color:#00cfcf; font-size:10pt;\">(NEW!)</em></h2>" // the style goes on the innermost element: the page's * rule recolours anything nested inside
                              "<p>You can speak your commands instead of typing them.  Turn on <b>Story Voice Dictation</b> in Settings and a <b>microphone button</b> appears while you play.  "
                              "Tap it to start listening, then say a command, and after a short pause it is entered for you.  "
                              "Frotz keeps listening for your next command until you tap the microphone again, leave the story, or say nothing for a minute or two.  "
                               "The <b>Dictation Delay</b> setting controls how long Frotz waits after you stop speaking.</p>\n"
                              "<p>Recognition happens entirely on your device, in the language the story is written in; nothing you say leaves your phone.  "
                              "Frotz pays attention to the words the story has printed, so names, spells, and other invented words are usually understood once you have seen them.  "
                              "If a word still won't take, <b>spell it out</b> letter by letter and it will be entered exactly as spelled.</p>\n"
                              "<p>When a story asks for a single key, just say the letter, or <b>yes</b> or <b>no</b>, or a word which begins with the letter (such as the NATO alphabet; \"the letter <em>letter</em>\" also works).  "
                              "You can mix voice and touch freely: double tap a word in the story to add it to what you have said, or type to edit.  Editing holds the command until you speak again or press Return.</p>\n"
                              "<p>Story dictation also pauses temporarily if you go to the Notes or Settings page or a save/restore dialog, and resumes when you return (but you can still use the mic button on the keyboard to dictate there if you want).</p>\n"

                              "<p>When used with the <b>VoiceOver</b> Accessibility feature, a <b>Magic Tap</b> (two-finger double tap) starts and stops listening.  While VoiceOver reads the story's reply, the microphone mutes so VoiceOver's speech isn't taken as a command, and resumes when the reading ends; "
                              "to speak sooner, Magic Tap to cut the reading short.  If you would rather talk over the reading, turn on <b>Listen During VoiceOver</b> in Settings, "
                              "but note that VoiceOver's speech may crackle a bit while Frotz is listening; you can reduce it by turning off <b>Audio Ducking</b> in VoiceOver's settings.</p>\n"
#endif
                              "<br/>"
                              "</body>\n",
                              !regularWidth ?
                              @"<p>Many games display a status line at the top of the screen with your current location, the time or score, or other relevant info.\n"
                              "In some cases the story can only display all the information it needs to when using a small font.  If you are "
                              "using a larger font and the status line is truncated, you can pinch to decrease the font size temporarily in order to see the full status line.</p>\n" : @""]
     
                    baseURL:nil
     ];
}


- (void)dealloc {
    [FrotzCommonWebViewController releaseSharedWebView];
}


@end
