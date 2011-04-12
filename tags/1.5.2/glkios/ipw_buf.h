/* ipw_buf.h: The buffer window header
        for GlkIOS, iPhone/IOS implementation of the Glk API.
    Designed by Andrew Plotkin <erkyrath@eblong.com>
    http://www.eblong.com/zarf/glk/index.html
*/

#if 0
/* Word types. */
#define wd_Text (1) /* Nonwhite characters */
#define wd_Blank (2) /* White (space) characters */
#define wd_EndLine (3) /* End of line character */
#define wd_EndPage (4) /* End of the whole text */

/* One word */
typedef struct tbword_struct {
    short type; /* A wd_* constant */
    short style;
    long pos; /* Position in the chars array. */
    long len; /* This is zero for wd_EndLine and wd_EndPage. */
    long width; /* Number of spaces word takes up on display */
} tbword_t;

/* One style run */
typedef struct tbrun_struct {
    short style;
    long pos;
} tbrun_t;

/* One laid-out line of words */
typedef struct tbline_struct {
    int numwords;
    tbword_t *words;
    
    long pos; /* Position in the chars array. */
    long len; /* Number of characters, including blanks */
    int startpara; /* Is this line the start of a new paragraph, or is it
        wrapped? */
    int printwords; /* Number of words to actually print. (Excludes the last
        blank word, if that goes outside the window.) */
} tbline_t;
#endif

typedef struct window_textbuffer_struct {
    window_t *owner;

    wchar_t *chars;
    long numchars;
    long charssize;
    
    GLK_STYLE_HINTS hints[style_NUMSTYLES];

//    int width, height;

    /* for line input */
    void *inbuf; /* char* or glui32*, depending on inunicode. */
    int inunicode;
    int inmax;
    long infence;
    long incurs;

    glui32 origstyle;
    gidispatch_rock_t inarrayrock;
} window_textbuffer_t;

/* changed to int per attrset (3ncurses) man page */
extern GLK_STYLE_HINTS win_textbuffer_styleattrs[style_NUMSTYLES];

extern window_textbuffer_t *win_textbuffer_create(window_t *win);
extern void win_textbuffer_destroy(window_textbuffer_t *dwin);
extern void win_textbuffer_rearrange(window_t *win, grect_t *box);
extern void win_textbuffer_redraw(window_t *win);
extern void win_textbuffer_update(window_t *win);
extern void win_textbuffer_putchar(window_t *win, wchar_t ch);
extern void win_textbuffer_clear(window_t *win);
extern void win_textbuffer_trim_buffer(window_t *win);
extern void win_textbuffer_place_cursor(window_t *win, int *xpos, int *ypos);
extern void win_textbuffer_set_paging(window_t *win, int forcetoend);
extern void win_textbuffer_init_line(window_t *win, void *buf, int unicode, int maxlen, int initlen);
extern void win_textbuffer_cancel_line(window_t *win, event_t *ev);

extern void gcmd_buffer_accept_key(window_t *win, glui32 arg);
extern void gcmd_buffer_accept_line(window_t *win, glui32 arg);
extern void gcmd_buffer_insert_key(window_t *win, glui32 arg);
extern void gcmd_buffer_move_cursor(window_t *win, glui32 arg);
extern void gcmd_buffer_delete(window_t *win, glui32 arg);
extern void gcmd_buffer_history(window_t *win, glui32 arg);
extern void gcmd_buffer_scroll(window_t *win, glui32 arg);

extern void win_textbuffer_stylehint_set(glui32 styl, glui32 hint, glsi32 val);
extern glui32 win_textbuffer_stylehint_get(window_t *win, glui32 styl, glui32 hint);
extern void win_textbuffer_stylehint_clear(glui32 styl, glui32 hint);

extern void win_textbuffer_set_stylehints(window_t *win, GLK_STYLE_HINTS *hints);
extern void win_textbuffer_get_stylehints(window_t *win, GLK_STYLE_HINTS *hints);
extern glui32 win_textbuffer_style_distinguish(window_t *win, glui32 styl1, glui32 styl2);
