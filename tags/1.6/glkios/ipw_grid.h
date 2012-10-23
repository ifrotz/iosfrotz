/* ipw_grid.h: The grid window header
        for GlkIOS, iPhone/IOS implementation of the Glk API.
    Designed by Andrew Plotkin <erkyrath@eblong.com>
    http://www.eblong.com/zarf/glk/index.html
*/

/* One line of the window. */
typedef struct tgline_struct {
    int size; /* this is the allocated size; only width is valid */
    wchar_t *chars;
    short *attrs; /* changed to short for compatibility with 'style' usage in gtw_bf.* */
    int *hyperlink;
    int dirtybeg, dirtyend; /* characters [dirtybeg, dirtyend) need to be redrawn */
} tgline_t;

typedef struct window_textgrid_struct {
    window_t *owner;
    
    int width, height;
    
    GLK_STYLE_HINTS hints[style_NUMSTYLES];

    tgline_t *lines;
    int linessize; /* this is the allocated size of the lines array;
        only the first height entries are valid. */
    
    int curx, cury; /* the window cursor position */
    
    int dirtybeg, dirtyend; /* lines [dirtybeg, dirtyend) need to be redrawn */
    
    /* for line input */
    void *inbuf; /* char* or glui32*, depending on inunicode. */
    int inunicode;
    int inorgx, inorgy;
    int inoriglen, inmax;
    int incurs, inlen;
    glui32 origstyle;
    gidispatch_rock_t inarrayrock;
} window_textgrid_t;

extern GLK_STYLE_HINTS win_textgrid_styleattrs[style_NUMSTYLES];

extern window_textgrid_t *win_textgrid_create(window_t *win);
extern void win_textgrid_destroy(window_textgrid_t *dwin);
extern void win_textgrid_rearrange(window_t *win, grect_t *box);
extern void win_textgrid_redraw(window_t *win);
extern void win_textgrid_update(window_t *win);
extern void win_textgrid_putchar(window_t *win, wchar_t ch);
extern void win_textgrid_clear(window_t *win);
extern void win_textgrid_move_cursor(window_t *win, int xpos, int ypos);
extern void win_textgrid_place_cursor(window_t *win, int *xpos, int *ypos);
extern void win_textgrid_init_line(window_t *win, void *buf, int unicode, int maxlen, int initlen);
extern void win_textgrid_cancel_line(window_t *win, event_t *ev);

extern void gcmd_grid_accept_key(window_t *win, glui32 arg);
extern void gcmd_grid_accept_line(window_t *win, glui32 arg);
extern void gcmd_grid_insert_key(window_t *win, glui32 arg);
extern void gcmd_grid_delete(window_t *win, glui32 arg);
extern void gcmd_grid_move_cursor(window_t *win, glui32 arg);


extern void win_textgrid_stylehint_set(glui32 styl, glui32 hint, glsi32 val);
extern glui32 win_textgrid_stylehint_get(window_t *win, glui32 styl, glui32 hint);
extern void win_textgrid_stylehint_clear(glui32 styl, glui32 hint);

extern void win_textgrid_set_stylehints(window_t *win, GLK_STYLE_HINTS *hints);
extern void win_textgrid_get_stylehints(window_t *win, GLK_STYLE_HINTS *hints);
extern glui32 win_textgrid_style_distinguish(window_t *win, glui32 styl1, glui32 styl2);
