/* ipw_blnk.h: The blank window header file
        for GlkIOS, iPhone/IOS implementation of the Glk API.
    Designed by Andrew Plotkin <erkyrath@eblong.com>
    http://www.eblong.com/zarf/glk/index.html
*/

typedef struct window_blank_struct {
    window_t *owner;
} window_blank_t;

extern window_blank_t *win_blank_create(window_t *win);
extern void win_blank_destroy(window_blank_t *dwin);
extern void win_blank_rearrange(window_t *win, grect_t *box);
extern void win_blank_redraw(window_t *win);
