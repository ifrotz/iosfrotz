This page contains frequently asked questions and miscellaneous help about using Frotz for the iPhone, iPad, and iPod Touch.


**Reporting Bugs**

If you have general comments or feedback about Frotz, you can post it on the [Frotz Discussion group](http://groups.google.com/group/ifrotz-discuss), or feel free to send email to **ifrotz at gmail dot com**.

To report a **bug or usability issue** with Frotz, please click [here](https://github.com/ifrotz/iosfrotz/issues/new?title=foo&body=bar), or go to the Issues tab, click "New Issue", and describe your problem.
(Note that the bug report system requires you to sign in to GMail.  If you do not have a GMail account, you can report a bug using the above e-mail address.)

**Update 08/21/2014**

**Frotz 1.7** now available, with following enhancements and bug fixes:

  * UI makeover with support for iOS 7/8
  * New Search Bar in Story List.
  * Word auto-completion now uses the current game's vocabulary/dictionary.
  * Fixed issues with accented characters/Unicode support.
  * Improved support for graphics windows, inline images, and hyperlinks in glulx games.
  * Fixed problem where VoiceOver wouldn't read new text right after the game clears the screen.
  * Ability to long-press keyboard toggle button to hide and lock keyboard (for menu-only command input).
  * Update to glk spec 0.7.4, git interpreter 1.3.3.
  * Lots of other minor bug fixes.


---



---


**FAQ**

  * **Why can't you transfer files to Frotz using the iTunes file sharing feature?**

> Unfortunately, iTunes FIle Sharing doesn't support folders well, and Frotz uses folders internally to keep saved games separate for each story.  I'm not willing to make Frotz put all files at the top level in order for the files to show up in iTunes File Sharing.  If Apple adds better folder support, I will enable the ability in Frotz.  But check out the Dropbox feature, which is by far the easiest way to access your saved game files from multiple computers.

  * **Speaking of Folders...**
> A couple of people have asked for the ability to move games into folders.  This sounds like a nice idea, but it's actually really hard to design a good interface for manipulating folders that allows everything you'd want to be able to do without moving to a file-centric UI, where you end up with something looking like a desktop file browser.  I think this would benefit a few users at the expense of most, and don't think it's worth it.  (Even Apple didn't do a very good job of implementing Folders in IOS - how is dragging one app on top of another to make a folder intuitive in the least?)

  * **How can I transfer my own story files (e.g. Infocom files) so Frotz can find them?**

> If you have the Lost Treasures of Infocom, other Infocom game files from antiquity, or your own personal Z-Machine game files, you can use them with Frotz.
    * Starting in Frotz 1.5, you can launch Frotz from a story file mail attachment, or from a generic file management program such as Good Reader or Dropbox.
    * If the file is available on the Internet, although Frotz cannot (read: is not allowed to) download the file directly, you can browser to it in Mobile Safari, and then launch Frotz via the "Open In..." dialog which comes up when tapping a download link.
    * Frotz includes a built-in File Transfer server, so you can easily transfer your own story files, as well as saved games, from pretty much any computer.   To enable the server, press the (i)nfo button in Frotz,  select the "File Transfer" button, and follow the instructions.  Note that you must be connected to a wireless network to use file transfer; it will not work over cellular.  You can then connect to Frotz using either a web browser or ftp client over the local network.  The web interface is much easier to use than ftp and is recommended.
    * Note that Frotz will not look for stories in ZIP files if you transfer them; you should transfer the files individually and make sure they end in a standard suffix such as .z8 or .zblorb.
<a href='Hidden comment: 
* If you have your files on a web server, you can access them using the built-in web interface:
* In Frotz, go to "Browse IFDB", select the Search icon at the bottom, and type in the URL of your web server.
* Frotz will download and install if you click on any link ending in .z3, .z4, .z5, .z8, .dat, or .zblorb.
* You cannot download saved games this way; use the FTP server instead.
* Frotz can also handle ZIP downloads.  If you click on a ZIP file, Frotz will download it, extract files with the playable extensions and add them to the story list, and then delete the ZIP file.  Again, this doesn"t work with FTP, but I plan to add that in a future version.
'></a>

  * **What device/OS versions is Frotz compatible with?**

> Frotz 1.7 works on iPhone, iPad and iPod Touch with OS versions 3.0 and later.
> (Version 1.6 had a bug which caused it to crash on 1st generation/armv6 devices, but this is fixed in 1.7.)

<a href='Hidden comment: 
Frotz would be worth nothing without the wealth of great games created by the talented writers and game designers in the IF (Interactive Fiction) community.  I"ve gotten a lot of enjoyment playing these games over the years, and since I"m not a very good writer, this is my way of giving back.
'></a>

  * **Can I make a donation?**

> If you really like Frotz and want to make a donation, you can do so via [PayPal](https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=craig%40ni%2ecom&item_name=Frotz%20for%20iPhone%2fiPod%20Touch&no_shipping=0&no_note=1&tax=0&currency_code=USD&lc=US&bn=PP%2dDonationsBF&charset=UTF%2d8).   (Also consider sending thank you emails to the authors of the games you like!)

  * **How do I save my game?**
> If you press the Home button or answer a call, Frotz will automatically save your game state.  Starting with Frotz 1.4, a separate autosave is kept per game, and the game is autosaved when you switch stories or after a period of inactivity.   You can also manually save your game in progress the old-fashioned way by typing "**`save`**" at the command prompt; this is recommended for some of the harder/more complex games, so you have the ability to backtrack and try alternate solutions.

> Type "**`restore`**" to load a previously saved game.  These commands are available in the shortcut menu that appears when you double tap the command prompt as well.

  * **How do I delete games?**
> When you're not playing a story, the standard Edit button in the top right can be used to go into 'delete' mode.  When a story is active, this is replaced by "Now Playing", but you can still use the swipe gesture to delete a story.
> You can also delete games via the web file transfer interface.

  * **Performance**
> The performance problems in Frotz 1.0 were fixed in 1.0.1, and further improved in 1.2 and 1.4  If you notice very poor performance, please file a new bug report.  Please do not just file a negative review on iTunes without also filing a bug report so I can have an opportunity to reproduce and fix it.
