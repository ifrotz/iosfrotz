/* glkios.h: Private header file
        for GlkIOS, iPhone/IOS implementation of the Glk API.
    Designed by Andrew Plotkin <erkyrath@eblong.com>
    http://www.eblong.com/zarf/glk/index.html
*/

#ifndef GLKTERM_H
#define GLKTERM_H

#include "gi_dispa.h"
#include <stdio.h>
#include <sys/types.h>
#include <wchar.h>

/* We define our own TRUE and FALSE and NULL, because ANSI
    is a strange world. */
#ifndef TRUE
#define TRUE 1
#endif
#ifndef FALSE
#define FALSE 0
#endif
#ifndef NULL
#define NULL 0
#endif

/* This macro is called whenever the library code catches an error
    or illegal operation from the game program. */

#define gli_strict_warning(msg)   \
    (fputws(msg, stderr)) 

/* Some useful type declarations. */

typedef struct grect_struct {
    int left, top;
    int right, bottom;
} grect_t;

typedef struct glk_window_struct window_t;
typedef struct glk_stream_struct stream_t;
typedef struct glk_fileref_struct fileref_t;

#define MAGIC_WINDOW_NUM (9826)
#define MAGIC_STREAM_NUM (8269)
#define MAGIC_FILEREF_NUM (6982)

struct glk_window_struct {
    glui32 magicnum;
    glui32 rock;
    glui32 type;
    
    grect_t bbox; /* content rectangle, excluding borders */
    window_t *parent; /* pair window which contains this one */
    void *data; /* one of the window_*_t structures */
    
    stream_t *str; /* the window stream. */
    stream_t *echostr; /* the window's echo stream, if any. */
    
    int line_request;
    int line_request_uni;
    int char_request;
    int char_request_uni;
    int mouse_request;
    int hyper_request;

    int echo_line_input; /* applies to future line inputs, not the current */
    glui32 terminate_line_input; /* ditto; this is a bitmask of flags */

    glui32 style;
    glui32 hyperlink;
    
    // Save win open arguments for autosave, so window can be easily recreated
    glui32 size;
    glui32 method;
    
    intptr_t splitwin;
    int store;

    int iosif_glkViewNum;
    
    gidispatch_rock_t disprock;
    window_t *next, *prev; /* in the big linked list of windows */
};

#define strtype_File (1)
#define strtype_Window (2)
#define strtype_Memory (3)
#define strtype_Resource (4)

struct glk_stream_struct {
    glui32 magicnum;
    glui32 rock;

    int type; /* file, window, or memory stream */
    int unicode; /* one-byte or four-byte chars? Not meaningful for windows */
    
    glui32 readcount, writecount;
    int readable, writable;
    
    /* for strtype_Window */
    window_t *win;
    
    /* for strtype_File */
    FILE *file; 
    fileref_t *fileRef;
    glui32 lastop; /* 0, filemode_Write, or filemode_Read */

    /* for strtype_Resource */
    int isbinary;

    /* for strtype_Memory and strtype_Resource. Separate pointers for one-byte and four-byte
       streams */
    unsigned char *buf;
    unsigned char *bufptr;
    unsigned char *bufend;
    unsigned char *bufeof;
    glui32 *ubuf;
    glui32 *ubufptr;
    glui32 *ubufend;
    glui32 *ubufeof;
    glui32 buflen;
    gidispatch_rock_t arrayrock;

    int store;

    gidispatch_rock_t disprock;
    stream_t *next, *prev; /* in the big linked list of streams */
};

struct glk_fileref_struct {
    glui32 magicnum;
    glui32 rock;

    char *filename;
    int filetype;
    int textmode;

    gidispatch_rock_t disprock;
    fileref_t *next, *prev; /* in the big linked list of filerefs */
};

#define STYLEHINT_TEXT_BUFFER    0xFFFFFFF1
#define STYLEHINT_TEXT_GRID        0xFFFFFFF2
#define BAD_STYLE 0xBADDBADD

enum { kGlkStyleIndentationMask = 1, kGlkStyleParaIndentationMask = 2, kGlKStyleJustificationMask = 4, kGlkStyleSizeMask      = 8,
       kGlkStyleWeightMask     = 16, kGlkStyleObliqueMask        = 32, kGlkStyleProportionalMask = 64, kGlkStyleTextColorMask = 128,
       kGlKStyleBackColorMask = 256, kGlKStyleRevertColorMask   = 512 };

typedef struct {
    int8_t     indentation;
    int8_t     paraIndentation;
    int8_t     justification;
    int8_t     size;
    int8_t     weight;
    int8_t     oblique;
    int8_t     proportional;
    int8_t     reverseColor;
    glui32     textColor;
    glui32     backColor;

    glui32     styleSetMask; // bitset of kGlkStyle* bits for each style explicitly set
} GLK_STYLE_HINTS;

int gli_window_has_stylehints(void);
void gli_stylehint_set(glui32 wintype, glui32 styl, glui32 hint, glsi32 val);
glsi32 gli_stylehint_get(window_t *win, glui32 styl, glui32 hint);
void gli_stylehint_clear(glui32 wintype, glui32 styl, glui32 hint);
void gli_window_get_stylehints(winid_t win, GLK_STYLE_HINTS *hints);
void gli_window_set_stylehints(winid_t win, GLK_STYLE_HINTS *hints);
glui32 gli_window_style_distinguish(winid_t win, glui32 styl1, glui32 styl2);

#include "ipw_pair.h"

#define kIOSGlkScaleFactor 1.0

/* Arguments to keybindings */

#define gcmd_Left (1)
#define gcmd_Right (2)
#define gcmd_Up (3)
#define gcmd_Down (4)
#define gcmd_LeftEnd (5)
#define gcmd_RightEnd (6)
#define gcmd_UpEnd (7)
#define gcmd_DownEnd (8)
#define gcmd_UpPage (9)
#define gcmd_DownPage (10)
#define gcmd_Delete (11)
#define gcmd_DeleteNext (12)
#define gcmd_KillInput (13)
#define gcmd_KillLine (14)

/* A few global variables */

extern window_t *gli_rootwin;
extern window_t *gli_focuswin;
extern grect_t content_box;
extern void (*gli_interrupt_handler)(void);

/* The following typedefs are copied from cheapglk.h. They support the
   tables declared in cgunigen.c. */

typedef glui32 gli_case_block_t[2]; /* upper, lower */
/* If both are 0xFFFFFFFF, you have to look at the special-case table */

typedef glui32 gli_case_special_t[3]; /* upper, lower, title */
/* Each of these points to a subarray of the unigen_special_array
   (in cgunicode.c). In that subarray, element zero is the length,
   and that's followed by length unicode values. */

typedef glui32 gli_decomp_block_t[2]; /* count, position */
/* The position points to a subarray of the unigen_decomp_array.
   If the count is zero, there is no decomposition. */

extern int screen_size_changed;
extern int mouseEvent, iosEventX, iosEventY;
extern int hyperlinkEvent;
extern window_t *iosEventWin;

extern unsigned char char_printable_table[256];
extern unsigned char char_typable_table[256];
#ifndef OPT_NATIVE_LATIN_1
extern unsigned char char_from_native_table[256];
extern unsigned char char_to_native_table[256];
#endif /* OPT_NATIVE_LATIN_1 */

extern gidispatch_rock_t (*gli_register_obj)(void *obj, glui32 objclass);
extern void (*gli_unregister_obj)(void *obj, glui32 objclass, gidispatch_rock_t objrock);
extern gidispatch_rock_t (*gli_register_arr)(void *array, glui32 len, char *typecode);
extern void (*gli_unregister_arr)(void *array, glui32 len, char *typecode, 
    gidispatch_rock_t objrock);

extern int pref_printversion;
extern int pref_screenwidth;
extern int pref_screenheight;
extern int pref_messageline;
extern int pref_reverse_textgrids;
extern int pref_override_window_borders;
extern int pref_window_borders;
extern int pref_precise_timing;
extern int pref_historylen;
extern int pref_prompt_defaults;

/* Declarations of library internal functions. */

extern void gli_initialize_misc(void);

extern void gli_initialize_events(void);
extern void gli_event_store(glui32 type, window_t *win, glui32 val1, glui32 val2);

extern void gli_input_handle_key(glui32 key);
extern void gli_input_guess_focus(void);
extern glui32 gli_input_from_native(glui32 key);
extern int gli_get_key(glui32 *key, glui32 timeout);
extern int gli_legal_keycode(glui32 key);
extern int gli_bad_latin_key(glui32 key);

extern void gli_initialize_windows(void);
extern void gli_fast_exit(void);
extern window_t *gli_new_window(glui32 type, glui32 rock);
extern void gli_delete_window(window_t *win);
extern window_t *gli_window_iterate_backward(winid_t win, glui32 *rock);
extern window_t *gli_window_iterate_treeorder(window_t *win);
extern void gli_window_rearrange(window_t *win, grect_t *box);
extern void gli_window_redraw(window_t *win);
extern void gli_windows_redraw(void);
extern void gli_windows_update(void);
extern void gli_windows_size_change(void);
extern void gli_windows_place_cursor(void);
extern void gli_windows_set_paging(int forcetoend);
extern void gli_windows_trim_buffers(void);
extern void gli_window_put_char(window_t *win, glui32 ch);
extern void gli_windows_unechostream(stream_t *str);
extern void gli_print_spaces(int len);

extern void gcmd_win_change_focus(window_t *win, glui32 arg);
extern void gcmd_win_refresh(window_t *win, glui32 arg);

extern stream_t *gli_new_stream(int type, int readable, int writable, 
    glui32 rock);
extern void gli_delete_stream(stream_t *str);
extern stream_t *gli_stream_open_window(window_t *win);
extern strid_t gli_stream_open_pathname(char *pathname, int writemode,
                                        int textmode, glui32 rock);
extern void gli_stream_set_current(stream_t *str);
extern void gli_stream_fill_result(stream_t *str, 
    stream_result_t *result);
extern void gli_stream_echo_line(stream_t *str, char *buf, glui32 len);
extern void gli_stream_echo_line_uni(stream_t *str, glui32 *buf, glui32 len);
extern void gli_streams_close_all(void);

extern fileref_t *gli_new_fileref(char *filename, glui32 usage, 
    glui32 rock);
extern void gli_delete_fileref(fileref_t *fref);

/* N.B. The following conversion macros are architecture dependent
 * In particular, glui32_to_wchar() will have to be re-written for 
 * each new architecture and C library.
 * This example is for Linux gcc4+ with GNU libc6
 */
#define UCS(l) ((glui32) (0x000000FF & (l)))
#define Lat(u) ((u) & 0xFFFFFF00 ? '?' : (char) ((u) & 0xFF))
#define glui32_to_wchar(x) (x)
#define wchar_to_glui32(x) (x)

/* A macro that I can't think of anywhere else to put it. */

#define gli_event_clearevent(evp)  \
    ((evp)->type = evtype_None,    \
    (evp)->win = NULL,    \
    (evp)->val1 = 0,   \
    (evp)->val2 = 0)
    
#ifdef NO_MEMMOVE
    extern void *memmove(void *dest, void *src, int n);
#endif /* NO_MEMMOVE */

#endif /* GLKTERM_H */
