/* gtw_blnk.c: The blank window type
        for GlkIOS, iPhone/IOS implementation of the Glk API.
    Designed by Andrew Plotkin <erkyrath@eblong.com>
    http://www.eblong.com/zarf/glk/index.html
*/

#include "gtoption.h"
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>
//#include <curses.h>
#include "glk.h"
#include "glkios.h"
#include "ipw_blnk.h"

/* This code is just as simple as you think. A blank window is filled with
    ':' characters on the screen, except for the corners, which are marked
    with slashes just so you can see where they are. */

window_blank_t *win_blank_create(window_t *win)
{
    window_blank_t *dwin = (window_blank_t *)malloc(sizeof(window_blank_t));
    dwin->owner = win;
    
    return dwin;
}

void win_blank_destroy(window_blank_t *dwin)
{
    dwin->owner = NULL;
    free(dwin);
}

void win_blank_rearrange(window_t *win, grect_t *box)
{
    window_blank_t *dwin = win->data;
    dwin->owner->bbox = *box;
}

void win_blank_redraw(window_t *win)
{
}

