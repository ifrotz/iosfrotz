/* gtevent.c: Event handling, including glk_select() and timed input code
 for GlkIOS, iPhone/IOS implementation, curses.h implementation of the Glk API.
 Designed by Andrew Plotkin <erkyrath@eblong.com>
 http://www.eblong.com/zarf/glk/index.html
 */

#include "gtoption.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#ifdef OPT_TIMED_INPUT
#include <sys/time.h>
#endif /* OPT_TIMED_INPUT */

#include "glk.h"
#include "glkios.h"

#include "iphone_frotz.h"

/* A pointer to the place where the pending glk_select() will store its
 event. When not inside a glk_select() call, this will be NULL. */
static event_t *curevent = NULL; 

static int halfdelay_running; /* TRUE if halfdelay() has been called. */
static glui32 timing_msec; /* The current timed-event request, exactly as
                            passed to glk_request_timer_events(). */

#ifdef OPT_TIMED_INPUT

/* The time at which the next timed event will occur. This is only valid 
 if timing_msec is nonzero. */
static struct timeval next_time; 

static void add_millisec_to_time(struct timeval *tv, glui32 msec);

#endif /* OPT_TIMED_INPUT */

/* Set up the input system. This is called from main(). */
void gli_initialize_events()
{
    halfdelay_running = FALSE;
    timing_msec = 0;
    
}

int mouseEvent = FALSE;
int hyperlinkEvent = FALSE;
window_t *iosEventWin = NULL;
int iosEventX = 0, iosEventY = 0;

void glk_select(event_t *event)
{
    int needrefresh = TRUE;
    
    curevent = event;
    gli_event_clearevent(curevent);
    
    gli_windows_update();
    gli_windows_set_paging(FALSE);
    gli_input_guess_focus();
    
    if (gli_focuswin && gli_focuswin->char_request)
        iphone_enable_single_key_input();
    else
        iphone_enable_input();
    
    while (curevent->type == evtype_None && !finished) {
        wint_t key;
        glui32 key32;
        int status;
        
        /* It would be nice to display a "hit any key to continue" message in
         all windows which require it. */
        if (needrefresh) {
            gli_windows_place_cursor();
            //bcs            refresh();
            needrefresh = FALSE;
        }
        
        status = gli_get_key(&key32, timing_msec);
        key = key32;
        if (key == ZC_AUTOSAVE) {
            printf("got glk autosave\n");
            break;
        }
        
        /* key == ERR; it's an idle event */
        
        /* Check to see if the screen-size has changed. The 
         screen_size_changed flag is set by the SIGWINCH signal
         handler. */
        if (hyperlinkEvent) {
            hyperlinkEvent = FALSE;
            gli_event_store(evtype_Hyperlink, iosEventWin, iosEventX, iosEventY);
            iosEventWin = NULL;
            iosEventX = iosEventY = 0;
            continue;
        }
        if (mouseEvent) {
            mouseEvent = FALSE;
            gli_event_store(evtype_MouseInput, iosEventWin, iosEventX, iosEventY);
            iosEventWin = NULL;
            iosEventX = iosEventY = 0;
            continue;
        }
        if (screen_size_changed) {
            screen_size_changed = FALSE;
            gli_windows_size_change();
            needrefresh = TRUE;
            if (status != -1)
                gli_input_handle_key(key);
            continue;
        }
        
        if (status != -1) {
            /* An actual key has been hit */
            gli_input_handle_key(key);
            needrefresh = TRUE;
            continue;
        }
        
        
#ifdef OPT_TIMED_INPUT
        /* Check to see if we've passed next_time. */
        if (timing_msec) {
            struct timeval tv;
            gettimeofday(&tv, NULL);
            if (tv.tv_sec > next_time.tv_sec
                || (tv.tv_sec == next_time.tv_sec &&
                    tv.tv_usec > next_time.tv_usec)) {
                    next_time = tv;
                    add_millisec_to_time(&next_time, timing_msec);
                    gli_event_store(evtype_Timer, NULL, 0, 0);
                    continue;
                }
        }
#endif /* OPT_TIMED_INPUT */
        
    }
    
    if (curevent->type != evtype_Timer)
        iphone_disable_input();
    
    /* An event has occurred; glk_select() is over. */
    gli_windows_trim_buffers();
    curevent = NULL;
}

void glk_select_poll(event_t *event)
{
    int firsttime = TRUE;
    
    curevent = event;
    gli_event_clearevent(curevent);
    
    gli_windows_update();
    
    /* Now we check, once, all the stuff that glk_select() checks
     periodically. This includes rearrange events and timer events. 
     Yes, this looks like a loop, but that's just so we can use
     continue; it executes exactly once. */
    
    while (firsttime) {
        firsttime = FALSE;
        
        gli_windows_place_cursor();
        //bcs        refresh();
        
        /* Check to see if the screen-size has changed. The 
         screen_size_changed flag is set by the SIGWINCH signal
         handler. */
        if (hyperlinkEvent) {
            hyperlinkEvent = FALSE;
            gli_event_store(evtype_Hyperlink, iosEventWin, iosEventX, iosEventY);
            iosEventWin = NULL;
            iosEventX = iosEventY = 0;
            continue;
        }
        if (mouseEvent) {
            mouseEvent = FALSE;
            gli_event_store(evtype_MouseInput, iosEventWin, iosEventX, iosEventY);
            iosEventWin = NULL;
            iosEventX = iosEventY = 0;
            continue;
        }
        if (screen_size_changed) {
            screen_size_changed = FALSE;
            gli_windows_size_change();
            continue;
        }
        
#ifdef OPT_TIMED_INPUT
        /* Check to see if we've passed next_time. */
        if (timing_msec) {
            struct timeval tv;
            gettimeofday(&tv, NULL);
            if (tv.tv_sec > next_time.tv_sec
                || (tv.tv_sec == next_time.tv_sec &&
                    tv.tv_usec > next_time.tv_usec)) {
                    next_time = tv;
                    add_millisec_to_time(&next_time, timing_msec);
                    gli_event_store(evtype_Timer, NULL, 0, 0);
                    continue;
                }
        }
#endif /* OPT_TIMED_INPUT */
    }
    
    curevent = NULL;
}

/* Various modules can call this to indicate that an event has occurred.
 This doesn't try to queue events, but since a single keystroke or
 idle event can only cause one event at most, this is fine. */
void gli_event_store(glui32 type, window_t *win, glui32 val1, glui32 val2)
{
    if (curevent) {
        curevent->type = type;
        curevent->win = win;
        curevent->val1 = val1;
        curevent->val2 = val2;
    }
}

void glk_request_timer_events(glui32 millisecs)
{
    if (millisecs < 20) // there's no reason for any text adventure to be firing timers a thousand times a second
        millisecs = 20;
    timing_msec = millisecs;
}

#ifdef OPT_TIMED_INPUT

/* Given a time value, add a fixed delay to it. */
static void add_millisec_to_time(struct timeval *tv, glui32 msec)
{
    int sec;
    
    sec = msec / 1000;
    msec -= sec*1000;
    
    tv->tv_sec += sec;
    tv->tv_usec += (msec * 1000);
    
    if (tv->tv_usec >= 1000000) {
        tv->tv_usec -= 1000000;
        tv->tv_sec++;
    }
}

#endif /* OPT_TIMED_INPUT */

