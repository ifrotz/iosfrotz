This page contains frequently asked questions and miscellaneous help about using Frotz for the iPhone and iPad.

Jump to the [FAQ](#faq), or read on for release news.

**Reporting Bugs**

To report a **bug or usability issue** with Frotz, please click [here to file a bug report](https://github.com/ifrotz/iosfrotz/issues/new?title=One-line%20summary&body=%5BPlease%20glance%20at%20the%20existing%20issues%20to%20make%20sure%20the%20problem%20you%20are%0Areporting%20isn%27t%20a%20known%20issue%20before%20reporting.%20Feel%20free%20to%20remove%20or%0Aedit%20any%20parts%20of%20the%20form%20template%20which%20don%27t%20apply%20to%20your%20issue.%5D%0A%0AWhat%20steps%20will%20reproduce%20the%20problem%3F%0A1.%0A2.%0A3.%0A%0AWhat%20is%20the%20expected%20output%20or%20behavior%3F%20What%20do%20you%20see%20instead%3F%0A%0AWhat%20version%20of%20Frotz%20are%20you%20using%3F%20%28Settings%20%3E%20About%20Frotz%29%0A1.9.0%0A%0AWhat%20device%20model%20are%20you%20using%3F%20%28e.g.%2C%20iPhone%2017%2C%20iPhone%20Duo%2C%20iPad%20Air%29%0A%0A%0AWhat%20version%20of%20iOS%3F%20%28e.g.%2C%2026.1%29%0A%0A%0APlease%20provide%20any%20additional%20information%20below.%0A).

If you have general comments or feedback about Frotz, you can post it on the [Frotz Discussion group](https://groups.google.com/group/ifrotz-discuss), or feel free to send email to **ifrotz at gmail dot com**.

---

**Update 11/15/2026**

**Frotz 1.9.0** will soon be available, with the following changes:

  * Story Voice Dictation, enabled in Settings. Tap the microphone to start continuous dictation, which enters your commands after a (configurable) pause. Recognition runs entirely on your device and is tuned to the story's vocabulary and language. See the Getting Started page in Settings for instructions on playing by voice. VoiceOver users can start and stop dictation with Magic Tap (a two-finger double tap).
  * Saved games can be synced between devices through iCloud Drive. Turn on Sync Saves with iCloud in Settings. Dropbox syncing is still supported, and the two can be used together.
  * Frotz now appears in the Files app; story and save files can be copied in or out, and story files can be opened from Files or other apps.
  * Settings is organized into grouped sections.
  * The Commands and History input helper dialogs are combined into one, with a tab bar to switch between them.
  * TADS 2 and TADS 3 stories now support automatic word completion.
  * Improved support for iPhone Duo; less important buttons are hidden when vertical bar space is limited.
  * VoiceOver reads story text more naturally and no longer cuts off new output.
  * Fixed Story Browser bookmark controls and other minor bugs.

**Update 10/30/2026**

**Frotz 1.8.9** is now available, with the following changes:

  * Support for iPhone Duo: Frotz's buttons move to the vertical bar, and the story, status line, notes and color picker adapt to both the folded and open displays.
  * Updated look for iOS 26 and later, including the Story List search bar and Edit buttons, and a translucent Story Browser with a proper toolbar.
  * Long-pressing the keyboard button now shows a menu with the Lock Keyboard option, making keyboard locking easier to discover. Show/Hide Keyboard and Lock Keyboard also appear in the overflow menu.
  * The unhelpful system AutoFill menu no longer pops up on the command line.
  * Other minor bug fixes and UI tweaks.

**Update 09/23/2023**

**Frotz 1.8.8** is now available, with the following changes:

  * Fixed issue with arrow keys on Bluetooth keyboards.

**Update 09/08/2023**

**Frotz 1.8.7** is now available, with the following changes:

  * Updated glulx (git) interpreter to spec 1.3.7.
  * Better support for Unicode/non-Latin alphabet games.
  * New IFDB search options, updated search URLs and built-in bookmarks.
  * Dropbox API update and sync improvements.
  * Option to swap text and background colors in the color picker.
  * Improved handling of ZIP file downloads from IFDB: you can now select which stories to install.
  * Enabled iTunes File Sharing: supported story files and saved games dragged into Frotz are installed automatically.
  * Restored keyboard long-press hide/lock functionality.
  * Other bug fixes and minor UI tweaks.

**Update 09/07/2020**

**Frotz 1.8.6** is now available, with the following changes:
  * Fix crash on iPad when trying to restart story from Story Details view.<
  * Fix hang which can occur when scrolling in Frotz Settings.

**Update 09/03/2020**

**Frotz 1.8.5** is now available, with the following changes:

  * Configurable text size and font on Notes screen.
  * Fix unreadable Notes text in dark mode.
  * General bug fixes and refactoring to use more modern iOS APIs.

**Update 07/03/2020**

**Frotz 1.8.4** is now available, with the following changes:

  * Support for iOS 13, including light/dark mode.
  * Support for newer devices with larger screen sizes.
  * Bug fixes.

**Update 07/01/2020**

**Frotz 1.8.3** is now available, with the following changes:

  * This version added support for iOS 13, but introduced a usability bug with manual saved games, fixed in 1.8.4.

**Update 10/03/2017**

**Frotz 1.8.2** now available, with the following changes:

  * Prevent games from being confused by iOS 11 'smart punctuation' feature.
  * Fix window resizing bug in glulx/glk games accidentally introduced in 1.8.1.
  * Launch shortcut to Story List (without resuming current game).
  * Other minor bug fixes, improvements to scrolling behavior.

**Update 09/30/2017**

**Frotz 1.8.1** now available, with the following changes:

  * Updated to DropBox API V2 for DropBox saved game syncing
  * Improvements for iOS 11
  * Other minor bug fixes
  
**Attention DropBox users:**

On September 28, 2017 Dropbox discontinued the version of their API which Frotz uses to automatically
sync saved games between devices and your DropBox account.  They forced all of their application
clients to completely re-write their DropBox support to continue functioning.
Frotz *1.8.1*, which restores DB support, was submitted to the App Store on 9/24, but was stuck in App Review limbo for 5 days, and wasn't
released in time for the API cut-off.   It is available now, and DB syncing will resume automatically
when you upgrade.  You do not have to re-authenticate or re-link your DropBox account.
Sorry for the inconvenience.


**Update 09/06/2016**

**Frotz 1.8** now available, with following enhancements and bug fixes:

  * Now plays TADS games (v2/v3)
  * Improved support for iOS 9 and 10, including split screen multitasking
  * Performance improvements / 64-bit support
  * Various other bug fixes, including iOS 9 crash switching back to app

Previous version *Frotz 1.7.x* had with following enhancements and bug fixes:

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


## FAQ

  * **How do I get story files and saved games in and out of Frotz?**

> Starting with Frotz 1.9, Frotz has its own folder in the **Files** app (under "On My iPhone" or "On My iPad"), with a Games folder for story files and a Saves folder with a subfolder of saved games for each story. You can copy files in or out there, or from a Mac or PC with Finder or iTunes file sharing, which Frotz has supported since 1.8.7. Any supported story file dropped in is installed automatically.

> For saved games across devices, the easier way is to let Frotz sync them: turn on **Sync Saves with iCloud** or link a **Dropbox** account in Settings, and manually saved games are mirrored between your devices.

> Frotz also still includes its original built-in File Transfer server (Settings > File Transfer), which lets you move files from any computer on the same Wi-Fi network with a web browser or FTP client.

  * **Speaking of Folders...**
> A couple of people have asked for the ability to move games into folders.  This sounds like a nice idea, but it's actually really hard to design a good interface for manipulating folders that allows everything you'd want to be able to do without moving to a file-centric UI, where you end up with something looking like a desktop file browser.  I think this would benefit a few users at the expense of most, and don't think it's worth it.  (Even Apple didn't do a very good job of implementing Folders in IOS - how is dragging one app on top of another to make a folder intuitive in the least?)

> **Update** - I'm thinking of adding arbitrary, user-editable tags collections to the stories. Combined with the search bar, this may be better than folders.

  * **How can I transfer my own story files (e.g. Infocom files) so Frotz can find them?**

> If you have the Lost Treasures of Infocom, other Infocom game files from antiquity, or your own personal Z-Machine, Glulx or TADS game files, you can use them with Frotz.
    * Copy them into Frotz's Games folder in the Files app, or drop them into Frotz with Finder or iTunes file sharing. They are installed the next time Frotz is in front.
    * Open a story file from the Files app, from a mail attachment, or from any other app's share sheet, and choose Frotz. Frotz installs it and adds it to the Story List.
    * If the file is on a web page, you can download it directly in Frotz's built-in Story Browser: open Browse IFDB, enter the page's address in the URL bar (the link icon), and tap the download link. Frotz installs story files it recognizes, and for ZIP archives lets you pick which stories inside to install. Tapping a link in Safari and opening the download in Frotz works too.
    * Or use the built-in File Transfer server (Settings > File Transfer) from a web browser or FTP client on the same Wi-Fi network.
    * Frotz will not look for stories inside ZIP files you copy into its folder; copy the files individually, and make sure they end in a standard suffix such as .z5, .z8, .zblorb, .ulx, .gblorb, .gam or .t3.

  * **What device/OS versions is Frotz compatible with?**

> Frotz 1.9 works on iPhone and iPad running iOS 15 or later, including the iPhone Duo. Story Voice Dictation needs a device that supports on-device speech recognition.
> If your device can't run iOS 15, the App Store offers the last version of Frotz compatible with it when you download from that device.

<a href='Hidden comment: 
Frotz would be worth nothing without the wealth of great games created by the talented writers and game designers in the IF (Interactive Fiction) community.  I"ve gotten a lot of enjoyment playing these games over the years, and since I"m not a very good writer, this is my way of giving back.
'></a>

  * **Can I make a donation?**

> If you really like Frotz and want to make a donation, you can do so via [PayPal](https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=QW8GW5T3U553L&item_name=Frotz%20for%20iOS&no_shipping=0&no_note=1&tax=0&currency_code=USD&lc=US&bn=PP%2dDonationsBF&charset=UTF%2d8).   (Also consider sending thank you emails to the authors of the games you like!)

  * **How do I save my game?**
> If you leave Frotz, switch apps, or answer a call, Frotz automatically saves your game state. A separate autosave is kept per story, and the game is also autosaved when you switch stories or after a period of inactivity. You can also manually save your game in progress the old-fashioned way by typing "**`save`**" at the command prompt; this is recommended for the harder or more complex games, so you can backtrack and try alternate solutions.

> Type "**`restore`**" to load a previously saved game. Both commands are also on the Commands tab of the helper that appears when you tap the command prompt.

> Manually saved games can be synced between your devices with **Sync Saves with iCloud** or **Dropbox**, both in Settings. Autosaves stay on the device.

  * **How do I delete games?**
> In the Story List, tap the Edit (pencil) button at the top right to go into delete mode, or swipe left on a story.
> You can also delete story files from Frotz's Games folder in the Files app, or through the File Transfer web interface.

  * **Does voice dictation send my speech anywhere?**
> No. Story Voice Dictation uses the speech recognition built into iOS, running entirely on your device; nothing you say is sent to Frotz's author or any server. (The system permission prompt uses Apple's generic wording, which Frotz can't change.) Dictation is off until you turn it on in Settings.

  * **Should I use iCloud or Dropbox to sync saved games?**
> Either works, and you can use both. iCloud needs no account setup beyond being signed in to iCloud on each device, and is the simpler choice if all your devices are Apple's. Dropbox is useful if you also want your saved games on a computer or in other interpreters. Both sync only manually saved games, and if the same save is changed on two devices Frotz keeps both copies rather than overwriting one.

