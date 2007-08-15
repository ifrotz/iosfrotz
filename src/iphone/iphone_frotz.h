/*
 * iphone_frotz.h
 *
 * IPhone interface, declarations, definitions, and defaults, based on Unix/ frotz
 *
 */

#define __IPHONE 1

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

extern f_setup_t f_setup;

bool is_terminator (zchar);


#define MASTER_CONFIG		"frotz.conf"
#define USER_CONFIG		".frotzrc"

#define ASCII_DEF		1
#define ATTRIB_ASSIG_DEF	0
#define ATTRIB_TEST_DEF		0
#define COLOR_DEF		1
#define ERROR_HALT_DEF		0
#define EXPAND_DEF		0
#define PIRACY_DEF		0
#define TANDY_DEF		0
#define OBJ_MOVE_DEF		0
#define OBJ_LOC_DEF		0
#define BACKGROUND_DEF		BLUE_COLOUR
#define FOREGROUND_DEF		WHITE_COLOUR
#define HEIGHT_DEF		-1	/* let curses figure it out */
#define CONTEXTLINES_DEF	0
#define WIDTH_DEF		80
#define TWIDTH_DEF		80
#define SEED_DEF		-1
#define SLOTS_DEF		MAX_UNDO_SLOTS
#define LMARGIN_DEF		0
#define RMARGIN_DEF		0
#define ERR_REPORT_DEF		ERR_REPORT_ONCE
#define	QUETZAL_DEF		1
#define SAVEDIR_DEF		"if-saves"
#define ZCODEPATH_DEF		"/usr/games/zcode:/usr/local/games/zcode"


#define LINELEN		256	/* for getconfig()	*/
#define COMMENT		'#'	/* for config files	*/
#define PATHSEP		':'	/* for pathopen()	*/
#define DIRSEP		'/'	/* for pathopen()	*/

#define EDITMODE_EMACS	0
#define EDITMODE_VI	1

#define PIC_NUMBER	0
#define PIC_WIDTH	2
#define PIC_HEIGHT	4
#define PIC_FLAGS	6
#define PIC_DATA	8
#define PIC_COLOUR	11


/* Paths where z-files may be found */
#define	PATH1		"ZCODE_PATH"
#define PATH2		"INFOCOM_PATH"

#define NO_SOUND

/* Some regular curses (not ncurses) libraries don't do this correctly. */
#ifndef getmaxyx
#define getmaxyx(w, y, x)	(y) = getmaxy(w), (x) = getmaxx(w)
#endif

extern bool color_enabled;		/* ui_text */

extern char stripped_story_name[FILENAME_MAX+1];
extern char semi_stripped_story_name[FILENAME_MAX+1];
extern char *progname;
extern char *gamepath;	/* use to find sound files */

extern f_setup_t f_setup;
extern u_setup_t u_setup;

#define MAX_ROWS 25
#define MAX_COLS 100

extern int top_win_height;
typedef unsigned short cell;
extern cell *screen_data;
extern int cursor_row, cursor_col;


/*** Functions specific to the Unix port of Frotz ***/

bool 	unix_init_pictures(void);       /* ui_pic */
int     getconfig(char *);
int     geterrmode(char *);
int     getcolor(char *);
int     getbool(char *);
FILE	*pathopen(const char *, const char *, const char *, char *);
void	sig_winch_handler(int);
void	redraw(void);


#ifdef NO_MEMMOVE
void *memmove(void *, void *);
#endif

void os_set_default_file_names(char *basename);

extern pthread_mutex_t outputMutex, winSizeMutex;
extern pthread_cond_t winSizeChangedCond;
extern bool winSizeChanged;

extern int iphone_getchar();
extern void iphone_puts();
extern void iphone_enable_input();
extern void iphone_enable_single_key_input();
extern void iphone_disable_input();
extern void iphone_putchar(char c);
extern void iphone_init_screen();
extern void iphone_more_prompt();
extern int iphone_read_file_name(char *file_name, const char *default_name, int flag);

extern int do_autosave, autosave_done;

extern int iphone_textview_width, iphone_textview_height;

#define kFrotzOldDir "/var/root/Library/Frotz"
#define kFrotzDir "/var/root/Media/Frotz"
#define kFrotzGameDir "/Games/"
#define kFrotzSaveDir "/Saves/"

#define kFrotzAutoSaveFile "FrotzSIP.sav"

#define IPHONE_FROTZ_VERS "0.3"

