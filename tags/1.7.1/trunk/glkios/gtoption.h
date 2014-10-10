/* gtoption.h: Options header file
        for GlkIOS, iPhone/IOS implementation of the Glk API.
    Designed by Andrew Plotkin <erkyrath@eblong.com>
    http://www.eblong.com/zarf/glk/index.html
*/

#ifndef GTOPTION_H
#define GTOPTION_H

/* Options: */

#define LIBRARY_VERSION "1.7.1"
#define LIBRARY_PORT "iOS Port 1.7.1"

#define OPT_TIMED_INPUT
/* OPT_TIMED_INPUT should be defined if your OS allows timed
 input using the halfdelay() curses library call. If this is
 defined, GlkTerm will support timed input. If not, it won't
 (and the -precise command-line option will also be removed.)
 Note that GlkTerm implements time-checking using both the
 halfdelay() call in curses.h, and the gettimeofday() call in
 sys/time.h. If your OS does not support gettimeofday(), you
 will have to comment this option out, unless you want to hack
 gtevent.c to use a different time API.
 */

/*#define OPT_USE_SIGNALS*/

/* OPT_USE_SIGNALS should be defined if your OS uses SIGINT, SIGHUP,
 SIGTSTP and SIGCONT signals when the program is interrupted, paused,
 and resumed. This will likely be true on all Unix systems. (With the
 ctrl-C, ctrl-Z and "fg" commands.)
 If this is defined, GlkTerm will call signal() to set a handler
 for SIGINT and SIGHUP, so that glk_set_interrupt_handler() will work
 right. GlkTerm will also set a handler for SIGCONT, and redraw the
 screen after you resume the program. If this is not defined, GlkTerm
 will not run Glk interrupt handlers, and may not redraw the screen
 until a key is hit.
 The pause/resume (redrawing) functionality will be ignored unless
 OPT_TIMED_INPUT is also defined. This is because GlkTerm has to
 check periodically to see if it's time to redraw the screen. (Not
 the greatest solution, but it works.)
 */

/*#define OPT_WINCHANGED_SIGNAL*/

/* OPT_WINCHANGED_SIGNAL should be defined if your OS sends a
 SIGWINCH signal whenever the window size changes. If this
 is defined, GlkTerm will call signal() to set a handler for
 SIGWINCH, and rearrange the screen properly when the window
 is resized. If this is not defined, GlkTerm will think that
 the window size is fixed, and not watch for changes.
 This should generally be defined; comment it out only if your
 OS does not define SIGWINCH.
 OPT_WINCHANGED_SIGNAL will be ignored unless OPT_USE_SIGNALS
 is also defined.
 */

/* #define NO_MEMMOVE */

/* NO_MEMMOVE should be defined if your standard library doesn't
 have a memmove() function. If this is defined, a simple
 memmove() will be defined in gtmisc.c.
 */


#endif /* GTOPTION_H */

