/*
 * iosfrotz.h
 *
 * IPhone interface, declarations, definitions, and defaults, based on Unix/ frotz
 *
 */

#define FROTZ_IOS_FILE 1

#include <stdbool.h>
#define FALSE 0
#define TRUE 1

#ifdef __cplusplus
extern "C" {
#endif

#include "frotz.h"

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
extern char iosif_filename[MAX_FILE_NAME];

extern f_setup_t f_setup;
//extern u_setup_t u_setup;

#define MAX_ROWS 100
#define MAX_COLS 100

extern int ztop_win_height;
typedef unsigned short cell, cellcolor;
extern cell *screen_data, *screen_colors;
extern int cursor_row, cursor_col;

extern int finished; // set by z_quit


FILE *pathopen(const char *name, const char *p, const char *mode, char *fullname);
void os_set_default_file_names(char *basename);
bool is_terminator (zchar);

int iosif_getchar(int timeout);
int iosif_peek_inputline(const wchar_t *buf, int maxlen);
void iosif_set_input_line(wchar_t *s, int len);
void iosif_puts(char *s);
void iosif_win_puts(int winNum, char *s);
void iosif_win_putwcs(int winNum, wchar_t *s, int len);
void iosif_enable_input();
void iosif_enable_single_key_input();
void iosif_disable_input();
void iosif_enable_tap(int winNum);
void iosif_disable_tap(int winNum);
void iosif_putchar(wchar_t c);
void iosif_win_putchar(int winNum, wchar_t c);
void iosif_disable_autocompletion();
void iosif_enable_autocompletion();
void iosif_erase_screen();
void iosif_erase_mainwin();
void iosif_erase_win(int winnum);
void iosif_set_top_win_height(int height);
void iosif_mark_recent_save();
void iosif_more_prompt();
char *iosif_get_temp_filename();
void iosif_set_text_attribs(int viewNum, int style, int color, bool lock);
void iosif_put_image(int viewNum, int imageNum, int imageAlign, bool lock);
void iosif_set_hyperlink_value(int viewNum, int val, bool lock);
int iosif_prompt_file_name (char *file_name, const char *default_name, int flag);
int iosif_read_file_name(char *file_name, const char *default_name, int flag);
void iosif_start_script(char *scriptName);
void iosif_stop_script();
void iosif_set_glk_default_colors(int winNum);
void iosif_glk_window_graphics_update(int viewNum);
glui32 iosif_glk_image_draw(int viewNum, glui32 image, glsi32 val1, glsi32 val2, glui32 width, glui32 height);
glui32 iosif_glk_image_get_info(glui32 image, glui32 *width, glui32 *height);
void iosif_glk_window_erase_rect(int viewNum, glsi32 left, glsi32 top, glui32 width, glui32 height);
void iosif_glk_window_fill_rect(int viewNum, glui32 color, glsi32 left, glsi32 top, glui32 width, glui32 height);
void iosif_glk_set_text_colors(int viewNum, unsigned int textColor, unsigned int bgColor);
void iosif_set_background_color(int viewNum, glui32 color);
void iosif_save_glk_win_graphics_img(int ordNum, int viewNum);
void iosif_restore_glk_win_graphics_img(int ordNum, int viewNum);

#define kMaxGlkViews 64

typedef struct {
    int nRows, nCols;
    unsigned int bgColor;
    window_t *win;
    wchar_t *gridArray;
    bool pendingClose;
    bool tapsEnabled;
} IPGlkGridArray;

void iosif_glk_wininit();
int iosif_new_glk_view(window_t *win);
void iosif_glk_view_rearrange(int viewNum, window_t *win);
void iosif_destroy_glk_view(int viewNum);
void iosif_glk_game_loaded();

IPGlkGridArray *iosif_glk_getGridArray(int viewNum);

//int iosif_main(int argc, char **argv);
#define XYZZY()
extern int do_autosave, autosave_done, refresh_savedir;
extern char AUTOSAVE_FILE[];

extern int iosif_textview_width, iosif_textview_height; // in characters
extern int iosif_screenwidth, iosif_screenheight; // in pixels
extern int iosif_fixed_font_width, iosif_fixed_font_height;
void iosif_recompute_screensize();

extern int iosif_ifrotz_verbose_debug;

extern bool gLargeScreenDevice;
extern int gLargeScreenPhone;
extern bool gUseSplitVC;

#ifdef __cplusplus
} // extern "C"
#endif

#define kFrotzGameDir "Games"
#define kFrotzSaveDir "Saves"

#define kFrotzOldAutoSaveFile "FrotzSIP.sav"
#define kFrotzAutoSaveFile "autosave.sav"
#define kFrotzAutoSavePListFile "FrotzSIP.plist"
#define kFrotzAutoSaveActiveFile "Current.plist"
#define kFrotzAutoSaveGlkImgPrefix "glkwingfx"
#define kFrotzAutoSaveFileGlkWin "glkwin.sav"

#define kDefaultTextViewMinWidth 65
#define kDefaultTextViewHeight 28

#define UseFullSizeStatusLineFont 1

#define IPHONE_FROTZ_VERS "1.7.2+"
#define FROTZ_BETA 1

#define APPLE_FASCISM (!FROTZ_BETA)

#define UseNewFTPServer 1

#include "ifrotzdefs.h"


