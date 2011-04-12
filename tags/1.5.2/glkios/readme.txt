GlkTerm: Curses.h Implementation of the Glk API.

GlkTerm Library: version 0.8.1.
Glk API which this implements: version 0.7.0.
Designed by Andrew Plotkin <erkyrath@eblong.com>
http://eblong.com/zarf/glk/index.html

This is source code for an implementation of the Glk library which runs
in a terminal window, using the curses.h library for screen control.
Curses.h (no relation to the Meldrews) should be available on all Unix
systems. I don't know whether it's available under DOS/Windows, but I
trust someone will tell me.

I will try to incorporate options for as many OSes as I can, using those
ugly #ifdefs. So if you get this to compile under some OS not listed
below, send me mail and tell me how it went.

This source code is not directly applicable to any other display system.
Curses library calls are scattered all through the code; I haven't tried
to abstract them out. If you want to create a Glk library for a
different display system, you'd best start over. Use GlkTerm for a
starting point for terminal-window-style display systems, and MacGlk or
XGlk for graphical/windowed display systems.

* Command-line arguments:

GlkTerm can accept command-line arguments both for itself and on behalf
of the underlying program. These are the arguments the library accepts
itself:

    -width NUM, -height NUM: These set the screen width and height
manually. Normally GlkTerm determines the screen size itself, by asking
the curses library. If this doesn't work, you can set a fixed size using
these options.
    -ml BOOL: Use message line (default "yes"). Normally GlkTerm
reserves the bottom line of the screen for special messages. By setting
this to "no", you can free that space for game text. Note that some
operations will grab the bottom line temporarily anyway.
    -revgrid BOOL: Reverse text in grid (status) windows (default "no").
Set this to "yes" to display all textgrid windows (status windows) in
reverse text.
    -historylen NUM: The number of commands to keep in the command
history of each window (default 20).
    -border BOOL: Draw one-character borders between windows (default
"yes"). These are lines of '-' and '|' characters. If you set this "no",
there's a little more room for game text, but it may be hard to
distinguish windows. The -revgrid option may help.
    -precise BOOL: More precise timing for timed input (default "no").
The curses.h library only provides timed input in increments of a tenth
of a second. So Glk timer events will only be checked ten times a
second, even on fast machines. If this isn't good enough, you can try
setting this option to "yes"; then timer events will be checked
constantly. This busy-spins the CPU, probably slowing down everything
else on the machine, so use it only when necessary. For that matter, it
may not even work on all OSes. (If GlkTerm is compiled without support
for timed input, this option will be removed.)
    -version: Display Glk library version.
    -help: Display list of command-line options.
    
NUM values can be any number. BOOL values can be "yes" or "no", or no
value to toggle.

Future versions of GlkTerm will have options to control display styles,
window border styles, and maybe other delightful things.

* Notes on building this mess:

There are a few compile-time options. These are defined in gtoption.h.
Before you compile, you should go into gtoption.h and make any changes
necessary. You may also need to edit some include and library paths in
the Makefile.

See the top of the Makefile for comments on installation.

When you compile a Glk program and link it with GlkTerm, you must supply
one more file: you must define a function called glkunix_startup_code(),
and an array glkunix_arguments[]. These set up various Unix-specific
options used by the Glk library. There is a sample "glkstart.c" file
included in this package; you should modify it to your needs.

The glkunix_arguments[] array is a list of command-line arguments that
your program can accept. The library will sort these out of the command
line and pass them on to your code. The array structure looks like this:

typedef struct glkunix_argumentlist_struct {
    char *name;
    int argtype;
    char *desc;
} glkunix_argumentlist_t;

extern glkunix_argumentlist_t glkunix_arguments[];

In each entry, name is the option as it would appear on the command line
(including the leading dash, if any.) The desc is a description of the
argument; this is used when the library is printing a list of options.
And argtype is one of the following constants:

    glkunix_arg_NoValue: The argument appears by itself.
    glkunix_arg_ValueFollows: The argument must be followed by another
argument (the value).
    glkunix_arg_ValueCanFollow: The argument may be followed by a value,
optionally. (If the next argument starts with a dash, it is taken to be
a new argument, not the value of this one.)
    glkunix_arg_NumberValue: The argument must be followed by a number,
which may be the next argument or part of this one. (That is, either
"-width 20" or "-width20" will be accepted.)
    glkunix_arg_End: The glkunix_arguments[] array must be terminated
with an entry containing this value.

To accept arbitrary arguments which lack dashes, specify a name of ""
and an argtype of glkunix_arg_ValueFollows.

If you don't care about command-line arguments, you must still define an
empty arguments list, as follows:

glkunix_argumentlist_t glkunix_arguments[] = {
    { NULL, glkunix_arg_End, NULL }
};

Here is a more complete sample list:

glkunix_argumentlist_t glkunix_arguments[] = {
    { "", glkunix_arg_ValueFollows, "filename: The game file to load."
},
    { "-hum", glkunix_arg_ValueFollows, "-hum NUM: Hum some NUM." },
    { "-bom", glkunix_arg_ValueCanFollow, "-bom [ NUM ]: Do a bom (on
the NUM, if given)." },
    { "-goo", glkunix_arg_NoValue, "-goo: Find goo." },
    { "-wob", glkunix_arg_NumberValue, "-wob NUM: Wob NUM times." },
    { NULL, glkunix_arg_End, NULL }
};

This would match the arguments "thingfile -goo -wob8 -bom -hum song".

After the library parses the command line, it does various occult
rituals of initialization, and then calls glkunix_startup_code().

int glkunix_startup_code(glkunix_startup_t *data);

This should return TRUE if everything initializes properly. If it
returns FALSE, the library will shut down without ever calling your
glk_main() function.

The data structure looks like this:

typedef struct glkunix_startup_struct {
    int argc;
    char **argv;
} glkunix_startup_t;

The fields are a standard Unix (argc, argv) list, which contain the
arguments you requested from the command line. In deference to custom,
argv[0] is always the program name.

You can put other startup code in glkunix_startup_code(). This should
generally be limited to finding and opening data files. There are a few
Unix Glk library functions which are convenient for this purpose:

strid_t glkunix_stream_open_pathname(char *pathname, glui32 textmode, 
    glui32 rock);

This opens an arbitrary file, in read-only mode. Note that this function
is *only* available during glkunix_startup_code(). It is inherent
non-portable; it should not and cannot be called from inside glk_main().

void glkunix_set_base_file(char *filename);

This sets the library's idea of the "current directory" for the executing
program. The argument should be the name of a file (not a directory).
When this is set, fileref_create_by_name() will create files in the same
directory as that file, and create_by_prompt() will base default filenames
off of the file. If this is not called, the library works in the Unix
current working directory, and picks reasonable default defaults.

* Operating systems and compatibility tests:

I've given up on using original curses, where that's different from ncurses.
Ncurses is now required. The Makefile links it explicitly. You may have
to change "#include <curses.h>" to "#include <ncurses.h>".

SunOS:
    Uncomment the lines in the Makefile:
        INCLUDEDIRS = -I/usr/5include
        LIBDIRS = -L/usr/5lib
    #define NO_MEMMOVE in gtoption.h

Solaris:
    Compiles as is (but if you have Solaris 2.4 or earlier, you may have
to change memcpy() calls to memmove())

IRIX:
    Compiles as is

HPUX:
    May have to comment out OPT_TIMED_INPUT, and remove references to
KEY_END and KEY_HELP. (Reported for HPUX 9.0.5; I have no idea how
current that is.)

AIX:
    See HPUX. (Reported for AIX 3.2.5).
    
FreeBSD:
    Compiles as is.

Unixware:
    In the Makefile, uncomment
        CC = cc
    (instead of gcc)

* Notes on the source code:

Functions which begin with glk_ are, of course, Glk API functions. These
are declared in glk.h, which is included in this package.

Functions which begin with gli_ are internal to the GlkTerm library
implementation. They don't exist in every Glk library, because different
libraries implement things in different ways. (In fact, they may be
declared differently, or have different meanings, in different Glk
libraries.) These gli_ functions (and other internal constants and
structures) are declared in glkterm.h.

As you can see from the code, I've kept a policy of catching every error
that I can possibly catch, and printing visible warnings.

Other than that, this code should be portable to any C environment which
has an ANSI stdio library and a curses.h library. The likely trouble
spots are glk_fileref_delete_file() and glk_fileref_does_file_exist() --
I've implemented them with the Unix calls unlink() and stat()
respectively. glk_fileref_create_by_prompt() also contains a call to
stat(), to implement a "Do you want to overwrite that file?" prompt. 

I have not yet tried to deal with character-set issues. The library
assumes that all input and output characters are in Latin-1.

Thanks to Matt Kimball for finding information on SIGWINCH and the
curses library.

* Bugs and Feature-Lacks

On some (most?) Unixes, the window doesn't resize properly. This is
probably because I'm not doing the SIGWINCH dance correctly. Still
working on it.

During glk_exit(), the "hit any key to exit" prompt doesn't do paging.
(That is, if a game prints a lot of text and then exits, the player will
only see the last page.) This should be fixed.

Could accept style hints, to the limited extent allowed by curses.h.
Indentation, centering, bold, and underline/italics are all possible.

Could display some visible indication of paging, in windows which need
to page.

When closing windows, + signs can be left in the window borders.

* Version History

0.8.1:
    Fixed file-creation bug in glk_stream_open_file().
    Fixed a bug that could leave cruft in a grid window that was
    contracted and then expanded.

0.8.0:
    Upgraded to Glk API version 0.7.0; added the Unicode functions.
    (But the interface cannot yet print or read Unicode characters.)

0.7.8:
    Upgraded to Glk API version 0.6.1; i.e., a couple of new gestalt
    selectors.
    Fixed dispatch bug for glk_get_char_stream.

0.7.7:
    Fixed a couple of display bugs (one that could cause freezes)

0.7.6:
    Upgraded to Glk API version 0.6.0; i.e., stubs for hyperlinks.

0.7.5:
    Input of accented characters should work right on non-Latin-1 systems
    now.
    A bit more buffer-overflow checking in the fileref code.

0.7.4:
    Fixed bugs in window resizing.
    Changed the default save game name to "game.sav".
    Added "-defprompt" switch, to suppress default file names.
    Added glkunix_set_base_file().
    Changed Makefile to use ncurses instead of original curses.

0.7.3:
    Added the ability to open a Blorb file, although the library never
    makes use of it. (This allows an interpreter to read a game file
    from Blorb.)

0.7.2:
    Upgraded to Glk API version 0.5.2; added sound and graphics stubs.
    Made the license a bit friendlier.

0.7.1:
    Fixed a couple of memory errors in the retained-array registry code.

0.7:
    Upgraded to Glk API version 0.5; added dispatch layer code.

0.6:
    The one true Unix Glk Makefile system.
    Startup code and command-line argument system.
    Command history (only in textbuffers)

0.5: Alpha release.

* Permissions

The source code in this package is copyright 1998-2000 by Andrew Plotkin. You
may copy and distribute it freely, by any means and under any conditions,
as long as the code and documentation is not changed. You may also
incorporate this code into your own program and distribute that, or modify
this code and use and distribute the modified version, as long as you retain
a notice in your program or documentation which mentions my name and the
URL shown above.

