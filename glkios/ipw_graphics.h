
/* ipw_graphics.h: The graphics window header file
        for iOS implementation of the Glk API.
    Designed by Andrew Plotkin <erkyrath@eblong.com>
    http://www.eblong.com/zarf/glk/index.html
*/

typedef struct window_graphics_struct {
    window_t *owner;
    int width, height;
    glui32 backcolor;
} window_graphics_t;

extern window_graphics_t *win_graphics_create(window_t *win);
extern void win_graphics_destroy(window_graphics_t *dwin);
extern void win_graphics_rearrange(window_t *win, grect_t *box);
extern void win_graphics_redraw(window_t *win);

glui32 win_graphics_get_background_color(window_t *win);
void win_graphics_set_background_color(window_t *win, glui32 color);

