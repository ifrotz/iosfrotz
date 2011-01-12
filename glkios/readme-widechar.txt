From: Alexander Beels <arb28@columbia.edu>
Subject: GlkTerm native charset port


1) Building:

1.A) Hand-Coding:

This port is designed to be compiled once per platform, and then run
in any locale. One of my goals was to have the program function with
no direct awareness of it's locale. Everything having to do with
charsets is handed off to ncurses and the C library.

The only exception is a set of macros for performing transformations
between the three known charsets that GlkTerm uses internally: Latin-1
(from Glk spec), UCS-4 (from Glk spec) and wchar (whatever that is on
this platform). These are implemented as macros for speed and
simplicity, and are necessarily platform dependent. (See Lat(), UCS()
etc. in glkterm.h) For true platform independence at the expense of
another dependency, they could be made into functions calling
iconv_*().

1.B) Dependencies:

GlkTerm is mostly ANSI C (I think). The exceptions are
wcwidth/wcswidth which require __USE_XOPEN, and the ncurses *wch* and
*wstr* functions which require _XOPEN_SOURCE_EXTENDED.

There is nothing I can do about wcwidth/wcswidth. Without these
functions, there is no way to know where anything is on the screen.
You can take heart in the fact that ncurses itself depends on them, so
any system that can provide ncurses should also be able to provide
them.

I have provided (rough) replacements for the *wch* and *wstr*
functions that GlkTerm uses. They can be activated by defining
LOCAL_NCURSESW in gtoption.h I have tested them, and they work. They
can probably be improved. If ncursesw is available, then the real
functions should be used. If ncursesw is not available, but curses is
magically able to handle wide characters, then these replacements
should do the trick.

The port uses setlocale(), wchar_t, the mbsrtowcs family of functions,
and macros from wtype.h.

1.C) Old-Fashioned Curses:

If compiled with old-fashioned curses and run in an 8-bit locale, the
port should work just like GlkTerm 0.8.0, except as noted in 2.B.



2) Program Behavior

2.A) Gestalt:

In order to achieve 1.A, I had to discard a lot of detailed
information about the platform. Basically, the only tools gestalt now
has to work with are iswprint() and ncurses has_key(). In particular,
GlkTerm has no way of knowing (output) if the user has installed the
right font for the locale, or (input) if the user has installed an
appropriate keyboard/input method for the locale. All gestalt can do
is report what should be possible on a correctly configured system.

That's a big drop in level of detail.  Sorry.

2.B) Approximate output:

For simplicity's sake, I made a decision early on to drop the "\017"
method of displaying non-printable characters. They are simply
rendered as "?" instead. This enforces a one-to-one correspondence
between characters on the screen and characters in internal buffers,
which made it easier for me to think about the port. This could
probably be changed back to the old behavior.

2.C) Input methods:

I didn't try to filter the player's input on-the-fly as he types in
response to a non-unicode line input request. So, if your terminal
supports fancy input methods, but the game doesn't want it, you can
get behavior like the following:

:> say [something in Arabic]
:You say '????'.

The Arabic input will show up on your screen. It will even be there in
your history. But the game treats it like "????", so tant pis. I'm not
sure if the spec cares about this sort of behavior.

This does have the nice side effect that you can save and restore
games with any name your locale can support, even if "unicode support"
is not compiled into GlkTerm. (I haven't checked...maybe this worked
in GlkTerm 0.8.0 as well.)



3) Internals:

My basic priciples were: (1) Never handle any data in the locale's
local character set. Everything should appear only in canonical forms.
(2) Allow any I/O the locale can support. CJK support was an explicit
goal. Bidi and complex-character support is way beyond my ability to
comprehend or test. My main assumption in this area is that I assume
that all characters can be represented in one or two glyphs. If there
are 3-glyph characters out there, parts of gtw_grid.c will have to be
rewritten.

3.A) wchar_t

GlkTerm 0.8.0 stored data in three formats: 
* hardcoded 8-bit (char type in display layer)
* Latin-1 (char type in Glk layer)
* UCS-4 (glui32 type in Glk layer)

In my port, this becomes:
* libc wide character (wchar_t/wint_t types in display layer)
* Latin-1 (char type in Glk layer)
* UCS-4 (glui32 type in Glk layer)

In general, I tried to enforce a rigorous distinction between data in
these three formats, so that every translation from one to the other
is visible. GlkTerm 0.8.0 could have a lot of knowledge about the
display layer's internal representation (and the locale's character
set), which allowed a certain amount of blurring between the layers.
This port's knowledge of wchar_t's implementation is reduced to only
two glui32-to-wchar_t conversion macros. It never directly touches the
locale's characterset at all. (see 3.C for an exception).

The conversion macros currently in use are:
* UCS(x) takes a Latin-1 character and returns a UCS-4 glui32.
* Lat(x) takes a UCS-4 glui32 and returns a Latin-1 character.  It
references the glui32 twice, so watch out for side-effects.
* wchar_to_glui32(x) takes a wchar_t value and returns a UCS-4 glui32.
* glui32_to_wchar(x) takes a UCS-4 glui32 and returns a wchar_t.

3.B) gtinput.c

This separation has required restructuring the code in places,
particularly in gtinput.c, where I chose to have the glk layer of the
program know only about glui32 keycodes, while the gli layer knows
about wint_t keycodes. Hopefully this should make it relatively easy
to move GlkTerm from platform to platform, but it required extensive
changes to gtinput.c, at least. The changes were extensive enough that
I decided to just delete GlkTerm 0.8.0's hand-coded charset handling
facilities, instead of try to work around them. Those facilities can
be added back in if you decide to go for a #ifdef merge of this port.

3.C) sprintf

Calls to sprintf should have been converted to calls to swprintf.
Unfortunately, swprintf does not appear to be universal (like it's
cousin snprintf). Therefore I replaced all sprintf code with repeated
calls to wcsncat. Looks awful.

3.D) gtfref.c

gtfref.c is the strange orphan of GlkTerm, because it has to actually
communicate with the filesystem in an unknown charset. I assume the
locale's charset is OK.

Once upon a time I made a version of gtfref.c that handled everything
as wchar_t, translating to the locale's charset only for the
filesystem calls. Then I got rid of swprintf (see 3.C), and that
threatened to make gtfref.c so unreadable that I just said to hell
with it and left the whole thing working in the local charset, with
conversions to wchar_t only for calls to gli_msgin_getline. This is a
project for another day.

The conversion routines gli_wcs_from_mbs and gli_mbs_from_wcs are ugly
and preliminary. Also a project for another day.


4) Rationale:

Last but not least.  Why did I do this?

Basically, I couldn't find any interpreter for Linux that could play 
TheAbbey.gblorb without complaints.

First of all, I am always annoyed at the way 64-bit Linux running in a
Chinese locale gets so little support. When the only relatively
up-to-date glulx engine I could find for my platform was a precompiled
32-bit Latin-only job, well, something had to be done. (I considered
bringing zag up to date, but I couldn't find a copy of the 2.0.0 glulx
spec to compare it to.) That got me hacking at the glulxe, git and
glk* code bases.

Then I noticed that glkterm's unicode support was not enough to let me
play The Abbey. Thought it doesn't display anything but ascii, It kept
on crashing all the time, unless run under cheapglk with the -u flag.
So I started porting utf8 support to glkterm. Supporting output-only
and no text grids just didn't seem right, so...here we are.

Second, I just think there ought to be a reference implementation of
Glk that runs on my machine, can do most of what most games need (i.e.
not cheapglk), and is not Latin-centric.

Third, I wanted to learn about Glk so that I can build a Qt port that
can build on Windows, UNIX and OSX. We ought to have a free
fully-functional reference implementation that runs on a wide variety
of platforms. For me as an IF newbie, the absence of something like
that has always made the IF Archive's interpreter section seem like an
intimidating mess.

*****

* I made some nitpicky changes to the code based on the assumption
that some day someone is going to translate this into a non-European
language. So all warnings are now L"Warning: " and so on. Pedantic, I
know. Makes it harder to merge, I know.

* I made some other nitpicky changes to the code just to get my
compiler to shut up when using -Wall. The switch statement in
gli_buffer_change_case in cgunicod.c is a good example. The intention
was only to make it easier for me to read my own compiler output.

* The definition of glui32 in glk.h was changed to work on a 64-bit
system. I didn't change it back in the tarball.

* I have tested this with ncursesw 5.6 on Linux Debian Etch (amd64)
and ncurses 5.2 OSX 10.3.9 (32-bit ppc).

On ncursesw 5.6, everything works fine. If linked with "ncurses"
instead of "ncursesw", it behaves like GlkTerm 0.8.0.

In an 8-bit locale on ncurses 5.2, everything is fine.

In a utf-8 locale on ncurses 5.2, the program runs and by some strange
quirk of Apple's implementation it even can do wide character utf-8
output in a text buffer window. Wide character utf-8 input works (i.e.
glk passes the right data to the progam), but cursor placement is
corrupt while the player types. Wide character utf-8 output to a text
grid is wildly corrupt. Of course, if the program does not use any
wide characters, everything is fine.
