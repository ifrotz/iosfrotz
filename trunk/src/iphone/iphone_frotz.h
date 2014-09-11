/*
 * iphone_frotz.h
 *
 * IPhone interface, declarations, definitions, and defaults, based on Unix/ frotz
 *
 */

#define FROTZ_IOS_FILE 1

#include <stdbool.h>
#define FALSE 0
#define TRUE 1

#include "../common/frotz.h"

#include "ui_setup.h"
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <ctype.h>
#include <time.h>
#include <pthread.h>
#include <CoreGraphics/CGGeometry.h>

#include "glk.h"
#include "glkios.h"

#define	QUETZAL_DEF 1
#define NO_SOUND 1

extern bool color_enabled;		/* ui_text */

extern char stripped_story_name[FILENAME_MAX+1];
extern char semi_stripped_story_name[FILENAME_MAX+1];
extern char iphone_filename[MAX_FILE_NAME];

extern f_setup_t f_setup;
extern u_setup_t u_setup;

#define MAX_ROWS 100
#define MAX_COLS 100

extern int top_win_height;
typedef unsigned short cell, cellcolor;
extern cell *screen_data, *screen_colors;
extern int cursor_row, cursor_col;

extern int finished; // set by z_quit

FILE *pathopen(const char *name, const char *p, const char *mode, char *fullname);
void os_set_default_file_names(char *basename);
bool is_terminator (zchar);

int iphone_getchar(int timeout);
int iphone_peek_inputline(const wchar_t *buf, int maxlen);
void iphone_set_input_line(wchar_t *s, int len);
void iphone_puts(char *s);
void iphone_win_puts(int winNum, char *s);
void iphone_win_putwcs(int winNum, wchar_t *s, int len);
void iphone_enable_input();
void iphone_enable_single_key_input();
void iphone_disable_input();
void iphone_enable_tap(int winNum);
void iphone_disable_tap(int winNum);
void iphone_putchar(wchar_t c);
void iphone_win_putchar(int winNum, wchar_t c);
void iphone_backspace();
void iphone_disable_autocompletion();
void iphone_enable_autocompletion();
void iphone_init_screen();
void iphone_erase_screen();
void iphone_erase_mainwin();
void iphone_erase_win(int winnum);
void iphone_set_top_win_height(int height);
void iphone_mark_recent_save();
void iphone_more_prompt();
void iphone_set_text_attribs(int viewNum, int style, int color, bool lock);
void iphone_put_image(int viewNum, int imageNum, int imageAlign, bool lock);
void iphone_set_hyperlink_value(int viewNum, int val, bool lock);
int iphone_prompt_file_name (char *file_name, const char *default_name, int flag);
int iphone_read_file_name(char *file_name, const char *default_name, int flag);
void iphone_start_script(char *scriptName);
void iphone_stop_script();
void iphone_set_glk_default_colors(int winNum);
void iphone_glk_window_graphics_update(int viewNum);
glui32 iphone_glk_image_draw(int viewNum, glui32 image, glsi32 val1, glsi32 val2, glui32 width, glui32 height);
glui32 iphone_glk_image_get_info(glui32 image, glui32 *width, glui32 *height);
void iphone_glk_window_erase_rect(int viewNum, glsi32 left, glsi32 top, glui32 width, glui32 height);
void iphone_glk_window_fill_rect(int viewNum, glui32 color, glsi32 left, glsi32 top, glui32 width, glui32 height);
void iphone_glk_set_text_colors(int viewNum, unsigned int textColor, unsigned int bgColor);
void iphone_set_background_color(int viewNum, glui32 color);
void iphone_save_glk_win_graphics_img(int ordNum, int viewNum);
void iphone_restore_glk_win_graphics_img(int ordNum, int viewNum);

#define kMaxGlkViews 64

typedef struct {
    int nRows, nCols;
    unsigned int bgColor;
    window_t *win;
    wchar_t *gridArray;
    bool pendingClose;
    bool tapsEnabled;
} IPGlkGridArray;

void iphone_glk_wininit();
int iphone_new_glk_view(window_t *win);
void iphone_glk_view_rearrange(int viewNum, window_t *win);
void iphone_destroy_glk_view(int viewNum);
void iphone_glk_game_loaded();

IPGlkGridArray *iphone_glk_getGridArray(int viewNum);

int iphone_main(int argc, char **argv);
#define XYZZY()
extern int do_autosave, autosave_done, refresh_savedir;
extern char AUTOSAVE_FILE[];

extern int iphone_textview_width, iphone_textview_height; // in characters
extern int iphone_screenwidth, iphone_screenheight; // in pixels
extern int iphone_fixed_font_width, iphone_fixed_font_height;
void iphone_recompute_screensize();

extern int iphone_ifrotz_verbose_debug;

extern bool gLargeScreenDevice;
extern int gLargeScreenPhone;
extern bool gUseSplitVC;

#define kFrotzGameDir "Games"
#define kFrotzSaveDir "Saves"

#define kFrotzOldAutoSaveFile "FrotzSIP.sav"
#define kFrotzAutoSaveFile "autosave.sav"
#define kFrotzAutoSavePListFile "FrotzSIP.plist"
#define kFrotzAutoSaveActiveFile "Current.plist"
#define kFrotzAutoSaveGlkImgPrefix "glkwingfx"

#define IPHONE_FROTZ_VERS "1.7.1"
#define FROTZ_BETA 1

#define APPLE_FASCISM (!FROTZ_BETA)

#define UseNewFTPServer 1

#include "ifrotzdefs.h"


