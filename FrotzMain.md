# Interactive Fiction at Your Fingertips #

Frotz for iOS lets you play hundreds of free works of Interactive Fiction (a.k.a. text adventure games) on your iPhone or iPod Touch.

Frotz plays games written in the Z-Machine format.  This format was invented by Infocom and was used to produce great text adventures from the 80s such as the Zork Trilogy, Hitchhiker's Guide to the Galaxy, and Trinity.

In the past decade, text adventures have experienced a renaissance thanks to a great Internet community of interactive fiction writers and fans.  Many of these games are written using the same engine that powered Infocom's titles, thanks to the Inform compiler and authoring system created by Graham Nelson.  Frotz also supports the glulx format, a newer format which is more powerful than Z-machine and supports games with images/graphics.

![http://iphonefrotz.googlecode.com/svn/trunk/resources/Frotz-320x480.png](http://iphonefrotz.googlecode.com/svn/trunk/resources/Frotz-320x480.png)

Frotz includes several built-in games, and includes a web portal for downloading new ones from the Internet.

Click [here](http://code.google.com/p/iphonefrotz/wiki/FrotzSupport) for support and FAQ.


---


**Update - Version 1.7 now available!**

**10/20/2014**

  * Improved support for iPhone 6, iPhone 6 Plus, and iOS 8.
  * Fixed bug printing accented characters in status window.
  * Allow using pinch gesture to change story font size.
  * Smaller app download size; full IFDB access enabled!
  * Several minor bug fixes in glk game support.

**Update - Version 1.7 now available!**

08/21/2014

  * UI makeover with support for iOS 7/8
  * New Search Bar in Story List.
  * Word auto-completion now uses the current game's vocabulary/dictionary.
  * Fixed issues with accented characters/Unicode support.
  * Improved support for graphics windows, inline images, and hyperlinks in glulx games.
  * Fixed problem where VoiceOver wouldn't read new text right after the game clears the screen.
  * Ability to long-press keyboard toggle button to hide and lock keyboard (for menu-only command input).
  * Update to glk spec 0.7.4, git interpreter 1.3.3.
  * Lots of other minor bug fixes.

**Update - Version 1.6 now available!**

10/22/2012

  * Support for iPhone 5, iOS 6, and Retina Displays.
  * Hyperlink:  now supports hyperlinks in glulx games.
  * Dropbox: updated to latest Dropbox API.
  * Lots of other minor bug fixes.

**Update - Version 1.5.3 now available!**

06/09/2011

  * Readability: Wider margins and spacing for better readability on iPad.
  * Unicode: Improved Unicode text support for games with non-Latin characters.
  * Updated glulx support: Now conforms to standard spec 3.1.2.
  * Graphics improvements: Performance and stability of games using glk graphics improved; Frotz now supports inline images in text.
  * VoiceOver support: Fixed bug preventing automatic announcement of new output in glulx games
  * Keyboard: Improved support for playing with a Bluetooth keyboard (you can now scroll via keyboard and no longer have to tap the screen).
  * Other bug fixes: New FTP server compatible with more clients; restored 'Open in' functionality for launching Frotz from other apps.

**Update - Version 1.5.2 now available!**

04/06/2011

  * Fixed crashing issue on older devices: Frotz would crash when launching or auto-restoring any story on 1st/2nd generation iPod Touch and iPhone 3G/1st gen. devices only due to a compiler bug in the tools used to build Frotz.  This has been resolved.
  * UI Navigation Bar: On iPhone and iPod Touch, the navigation bar would disappear after leaving the save/restore/transcript dialogs in portrait mode.  (Rotating to landscape and back would bring it back).  This has been fixed.
  * Web Transfer interface: Allow downloading/viewing game transcripts.
  * Hang on story quit/restart: Fixed bug where Frotz would hang if you restart a story immediately after quitting.

**Update - Version 1.5.1 available!**

03/30/2011

New features in 1.5.1:
  * Fixed iOS 4.3 issues: Frotz would crash when pressing Backspace multiple times, only in iOS 4.3.  This is now fixed.
  * Web Transfer interface:  Fixed a bug where Frotz would fail to delete stories if the filenames contained spaces.
  * Transcript viewer: On iPhone only, trying to view transcripts from the note taking screen when in landscape mode would get you stuck, because the navigation bar where the 'Done" button is was hidden.
  * Glulx font issues: Games which set a text color hint for attributed text w/o setting one for normal text would incorrectly leave the color set after printing the attributed text, instead of returning to default color.

**Update - Version 1.5 available!**

11/05/2010

New features in 1.5:
  * Improved UI: The interface has been improved and refined, particularly on the iPad.
  * Recently Played Stories: Frotz now keeps track of your most recently played stories at the top of the Story List.
  * Note taking: Swipe left while playing any story to view a note-taking area for that story.
  * View/Edit Story Details: Frotz now has authors, descriptions, and artwork for all built-in stories and can link back to the full IFDB entry for each.
  * Dropbox support: Frotz now supports synchronizing saved games with Dropbox, so you can seamlessly play on multiple devices.
  * Bookmarks in Story Browser: You can now bookmark individual pages in the IFDB browser.
  * More bundled games added from IFDB: Includes an updated IFDB snapshot with more recent well-rated works.
  * Miscellaneous bug fixes: Fixed Bluetooth keyboard support, status line/text resizing bugs, and various other minor bugs.
  * Support launching Frotz as "Open in..." handler for game files as e-mail attachments, Safari downloads, and general file management apps such as Good Reader/Dropbox, etc.

Version 1.5 also includes preliminary support for Glulx games.  This support is considered beta, so no Glulx games are yet bundled with Frotz.  If you want to play Glulx games, you can transfer them to Frotz from your computer using the built-in File Transfer server, or even navigate to the page on IFDB and launch Frotz via the .gblorb/.ulx download link.

**Update - Version 1.4.1 available**

04/06/2010

New features in Frotz 1.4.1:
  * Native iPad support.
  * Fixed bug where custom text color settings were not being honored, causing text to be unreadable on dark backgrounds.

New features in Frotz 1.4:
  * Better text performance: Frotz' text output support has been rewritten and is now faster and has a larger scroll-back buffer.
  * Word selection: You can now double-tap on a word in the story output to copy it to the command line.
  * Web-based File Transfer: You can now transfer game files with an easy-to-use web interface as well as FTP.
  * Improved Auto-save:  Frotz now maintains separate auto-save files for every story, and saves your progress automatically during play to avoid accidental loss of progress.
  * Bug fixes - various and sundry.

The code is also iPad ready, and I'll submit an update with support for running full-screen on iPad as soon as Apple allows submissions.


---


|![http://iphonefrotz.googlecode.com/svn/trunk/resources/FrotzSplash.png](http://iphonefrotz.googlecode.com/svn/trunk/resources/FrotzSplash.png)| Burned out on all the new-fangled graphics and dazzling eye candy on your shiny new iPhone?<br><br><br>Nostalgic for a simpler time?<br><br><br>Then take advantage of those crisp high-resolution fonts to relive the glory days of the Great Underground Empire, or play any of hundreds of great works from the Interactive Fiction Database.</tbody></table>


<b>Update - Version 1.3 available</b>

09/19/2009<br>
<br>
Three months and 1 day after being originally submitted for approval, Frotz 1.3 is now finally available in the App Store.<br>
<br>
New features in Frotz 1.3:<br>
<ul><li>Story Font Size preference: allows you to vary the main story font size from 8 to 16 point.<br>
</li><li>Status Line magnification: tap anywhere on the status line to magnify it for readability. (This is in lieu of allowing larger status line fonts, because many games require a minimum number of screen columns, which would force you to scroll left and right to see the entire line.)<br>
</li><li>Command Helper Menu: tap on the command prompt to bring up a helper menu of common words.<br>
</li><li>Command Line History: double-tap on the command line to bring up a menu of recently entered commands.<br>
</li><li>Accessibility Improvements: improved accessibility hints for VoiceOver users. Selecting the story window will recite only the story output since the most recent command.<br>
</li><li>Bug fixes (OS 3.0): restored the ability to tap on the story output to scroll one page, or show the keyboard if at the end.<br>
</li><li>Bundled stories: includes a large subset of well-rated stories from the IFDB bundled with Frotz; the IFDB story browser uses these bundled files instead of downloading them from the Internet.</li></ul>


<b>Update - Version 1.3 resubmitted</b>

09/04/2009<br>
<br>
Version 1.3, with font size options and command line history, has been resubmitted to the App Store as of Sept. 4, 2009 after being previously rejected.  The point of contention was Frotz's ability to download new games from the Internet, as downloading interpreted content is disallowed by the App Store rules.<br>
<br>
To obtain compliance, the newly submitted version no longer has Internet download capability.  Instead, it now has all Z-code games rated 3 stars or more from the Interactive Fiction Database  pre-bundled with Frotz; the user experience of browsing IFDB to select and add games is still the same unless you try to pick an unbundled game.  Not included with Frotz are games which are low-rated, in a language other than English, newer than the IFDB snapshot taken on 9/1/2009, or games not in IFDB at all.<br>
<br>
<br>
<b>Version 1.3 Rejected by Apple</b>

08/10/2009<br>
<br>
Apple has rejected my update to Frotz on the grounds that it violates the clause of the SDK agreement dealing with interpreters.  They did not, however, take down the previous version of Frotz.  I'm investigating what my options are.<br>
<br>
<a href='Hidden comment:  The Apple guy who called me was very nice but completely non-technical and unable to discuss the exact meaning of interpreter held by Apple.  He suggested I try to modify the program to bring it in compliance, but could offer no help as to how to do so.   Since the clause in question actually says "no interpreted code may be downloaded", I am going to try to remove the IFDB browsing component which downloads new games and see if that is accepted.   Obviously this entails a loss of functionality and usability, and I"m not happy about it.  I may rename the app as well so that existing users who would rather retain download ability in lieu of any new features can continue using 1.2 without having to explicitly skip future Frotz updates.
'></a><br>
<b>Version 1.3 Pending</b>

07/21/2009<br>
<br>
I submitted a new version of Frotz to the App Store for approval on June 18.  It's been over 7 weeks in limbo now and I haven't heard anything back from Apple.   It's extremely frustrating, so much so I am considering abandoning the App Store and moving Frotz to jailbroken iPhones.   If you have opinions on this, feel free to post to the <a href='http://groups.google.com/group/ifrotz-discuss'>Frotz Discussion board</a>.<br>
<br>
Assuming it's eventually approved by Apple, 1.3 will include:<br>
<br>
<ul><li>New Story Font Size option: change the main story font size from 8 to 16 point font<br>
</li><li>Status Line magnification:  tap anywhere on the status line to magnify it for readability.   (Because many games expect a minimum number of screen columns, supporting larger status line fonts requires scrolling left and right, which is awkward and cumbersome, but magnification seems to solve the problem.)<br>
</li><li>Command Line History: double tap on the command line to bring up a menu of recently enter command<br>
</li><li>Common Words Menu: Triple tap on the command line to bring up a menu of common words.  (This is an initial implementation and I plan to add a compass rose and improve the UI in the future.)<br>
</li><li>Bug fixes for iPhone OS 3.0, restoring the ability to tap to scroll and show/hide the keyboard</li></ul>

<hr />
<b>New Version 1.2 Available</b>

04/15/2009<br>
<br>
My apologies for the long hiatus in development.  A new version of Frotz is now available on the App Store.  Changes include:<br>
<br>
<ul><li>More performance improvements:  Frotz manages story metadata better and uses less memory.<br>
</li><li>Support for transferring both story files and saved games using a built-in FTP server<br>
</li><li>Preferences allowing you to select custom text and background colors and change the story font<br>
</li><li>Ability to disable automatic word completion, useful for playing games in languages than English<br>
</li><li>Fixed bugs handling fixed-width text in story output</li></ul>

<hr />

<b>New Version 1.0.1 Available</b>

8/27/2008<br>
<br>
A new version of Frotz is now available on the App Store.  Changes include:<br>
<br>
<ul><li>Performance improvements:  Frotz no longer slows down during long sessions, and uses less memory.<br>
</li><li>Miscellaneous bug fixes and interface improvements.<br>
</li><li>Added help for users new to Interactive Fiction.<br>
</li><li>Support for deleting bundled games from Story List.<br>
</li><li>Support for transferring games with MobileFinder.</li></ul>

Color/font settings did not make it into this version, but will be available shortly.  Well, as shortly as possible given Apple's week long turn around for approval.