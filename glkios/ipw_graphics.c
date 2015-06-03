

/* ipw_graphics.c: The graphics window type
        for iOS implementation of the Glk API.
    Designed by Andrew Plotkin <erkyrath@eblong.com>
    http://www.eblong.com/zarf/glk/index.html
*/

#include "glk.h"
#include "glkios.h"
#include "ipw_graphics.h"
#include "iosfrotz.h"

#include <stdlib.h>

window_graphics_t *win_graphics_create(window_t *win)
{
    window_graphics_t *dwin = (window_graphics_t *)calloc(sizeof(window_graphics_t),1);
    dwin->owner = win;
    dwin->width = -1;
    dwin->height = -1;
    dwin->backcolor = 0xffffff; // default background 24-bit color
    return dwin;
}

void win_graphics_destroy(window_graphics_t *dwin)
{
    dwin->owner = NULL;
    free(dwin);
}

void win_graphics_rearrange(window_t *win, grect_t *box)
{
    window_graphics_t *dwin = win->data;

    dwin->owner->bbox = *box;

    dwin->width = box->right - box->left;
    dwin->height = box->bottom - box->top;
}

void win_graphics_redraw(window_t *win)
{
}

void win_graphics_update(window_t *win) {
    iphone_glk_window_graphics_update(win->iphone_glkViewNum);
}

#ifdef GLK_MODULE_IMAGE

glui32 glk_image_draw(winid_t win, glui32 image, glsi32 val1, glsi32 val2) {
    if (!win || win->iphone_glkViewNum < 0 || win->type != wintype_Graphics
        && win->type != wintype_TextBuffer)
        return FALSE;
    
    return iphone_glk_image_draw(win->iphone_glkViewNum, image, val1, val2, 0, 0);
}

glui32 glk_image_draw_scaled(winid_t win, glui32 image,  glsi32 val1, glsi32 val2, glui32 width, glui32 height) {
    if (!win || win->iphone_glkViewNum < 0 || win->type != wintype_Graphics
        && win->type != wintype_TextBuffer)
        return FALSE;

    return iphone_glk_image_draw(win->iphone_glkViewNum, image, val1, val2, width, height);
}

glui32 glk_image_get_info(glui32 image, glui32 *width, glui32 *height)
{
    return iphone_glk_image_get_info(image, width, height);
}

void glk_window_flow_break(winid_t win)
{
    gli_strict_warning(L"window_flow_break: graphics not supported.");
}

void glk_window_erase_rect(winid_t win, 
    glsi32 left, glsi32 top, glui32 width, glui32 height)
{
    if (!win || win->iphone_glkViewNum < 0 ||  win->type != wintype_Graphics)
	return;
    iphone_glk_window_erase_rect(win->iphone_glkViewNum, left, top, width, height);
}

void glk_window_fill_rect(winid_t win, glui32 color, 
    glsi32 left, glsi32 top, glui32 width, glui32 height)
{
    if (!win || win->iphone_glkViewNum < 0 ||  win->type != wintype_Graphics)
	return;
    iphone_glk_window_fill_rect(win->iphone_glkViewNum, color, left, top, width, height);
}

void glk_window_set_background_color(winid_t win, glui32 color)
{
    if (!win || win->iphone_glkViewNum < 0 ||  win->type != wintype_Graphics)
	return;
    window_graphics_t *wgp = (window_graphics_t*)win->data;
    wgp->backcolor = color;
    iphone_set_background_color(win->iphone_glkViewNum, color);
}

#endif /* GLK_MODULE_IMAGE */

