/*
 * ui_init.c - Unix interface, initialisation
 *	Galen Hazelwood <galenh@micron.net>
 *	David Griffith <dgriffi@cs.csubak.edu>
 *
 * This file is part of Frotz.
 *
 * Frotz is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * Frotz is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <time.h>

#include <unistd.h>
#include <ctype.h>

/* We will use our own private getopt functions. */
#include "getopt.h"

#include <termios.h>

#include "iphone_frotz.h"

f_setup_t f_setup;
u_setup_t u_setup;

#define PATHSEP		':'	/* for pathopen()	*/
#define DIRSEP		'/'	/* for pathopen()	*/

char stripped_story_name[FILENAME_MAX+1];
char semi_stripped_story_name[FILENAME_MAX+1];

/*
 * os_fatal
 *
 * Display error message and exit program.
 *
 */

void os_fatal (const char *s)
{

   // os_reset_screen();
 
    iphone_puts ("\nFatal error: ");
    iphone_puts ((char*)s);
    iphone_puts ("\n\n");

    finished = 2;

}/* os_fatal */

extern char script_name[];
extern char command_name[];
extern char save_name[];
extern char auxilary_name[];

int autorestore = 0;

int os_process_arguments (int argc, char *argv[])
{
    return iphone_main(argc, argv);
}/* os_process_arguments */

void os_set_default_file_names(char *basename) {
    char *p = (char *)basename;
    int i;

    /* Strip path off the story file name */
    for (i = 0; basename[i] != 0; i++)
        if (basename[i] == '/')
          p = (char *)basename + i + 1;

    for (i = 0; p[i] != '\0'; i++)
	semi_stripped_story_name[i] = p[i];
    semi_stripped_story_name[i] = '\0';

    for (i = 0; p[i] != '\0' && p[i] != '.'; i++)
        stripped_story_name[i] = p[i];
    stripped_story_name[i] = '\0';

    /* Create nice default file names */

    strcpy (script_name, stripped_story_name);
    strcpy (command_name, stripped_story_name);
    strcpy (save_name, stripped_story_name);
    strcpy (auxilary_name, stripped_story_name);

    /* Don't forget the extensions */

    strcat (script_name, "-transcript.txt");
    strcat (command_name, ".rec");
    strcat (save_name, ".sav");
    strcat (auxilary_name, ".aux");
}

/*
 * os_init_screen
 *
 * Initialise the IO interface. Prepare the screen and other devices
 * (mouse, sound board). Set various OS depending story file header
 * entries:
 *
 *     h_config (aka flags 1)
 *     h_flags (aka flags 2)
 *     h_screen_cols (aka screen width in characters)
 *     h_screen_rows (aka screen height in lines)
 *     h_screen_width
 *     h_screen_height
 *     h_font_height (defaults to 1)
 *     h_font_width (defaults to 1)
 *     h_default_foreground
 *     h_default_background
 *     h_interpreter_number
 *     h_interpreter_version
 *     h_user_name (optional; not used by any game)
 *
 * Finally, set reserve_mem to the amount of memory (in bytes) that
 * should not be used for multiple undo and reserved for later use.
 *
 * (Unix has a non brain-damaged memory model which dosen't require such
 *  ugly hacks, neener neener neener. --GH :)
 *
 */

void os_init_screen (void)
{
    if (h_version == V3 && u_setup.tandy_bit != 0)
        h_config |= CONFIG_TANDY;

    if (h_version == V3)
	h_config |= CONFIG_SPLITSCREEN;

    if (h_version >= V4)
	h_config |= CONFIG_BOLDFACE | CONFIG_EMPHASIS | CONFIG_FIXED | CONFIG_TIMEDINPUT;

    if (h_version >= V5)
      h_flags &= ~(GRAPHICS_FLAG | MOUSE_FLAG | MENU_FLAG);

#ifdef NO_SOUND
    if (h_version >= V5)
      h_flags &= ~SOUND_FLAG;

    if (h_version == V3)
      h_flags &= ~OLD_SOUND_FLAG;
#else
    if ((h_version >= 5) && (h_flags & SOUND_FLAG))
	h_flags |= SOUND_FLAG;

    if ((h_version == 3) && (h_flags & OLD_SOUND_FLAG))
	h_flags |= OLD_SOUND_FLAG;

    if ((h_version == 6) && (f_setup.sound != 0)) 
	h_config |= CONFIG_SOUND;
#endif

    if (h_version >= V5 && (h_flags & UNDO_FLAG))
        if (f_setup.undo_slots == 0)
            h_flags &= ~UNDO_FLAG;

    h_screen_rows = kDefaultTextViewHeight; // iphone_textview_height;
    h_screen_cols = iphone_textview_width;

    if (u_setup.screen_height != -1)
        h_screen_rows = u_setup.screen_height;
    if (u_setup.screen_width != -1)
        h_screen_cols = u_setup.screen_width;
    
    h_screen_width = h_screen_cols;
    h_screen_height = h_screen_rows;

    h_font_width = 1;
    h_font_height = 1;

    /* Must be after screen dimensions are computed.  */
#if 0
    if (h_version == V6) {
      if (unix_init_pictures())
	h_config |= CONFIG_PICTURES;
      else
	h_flags &= ~GRAPHICS_FLAG;
    }
#endif

    /* Use the ms-dos interpreter number for v6, because that's the
     * kind of graphics files we understand.  Otherwise, use DEC.  */
    h_interpreter_number = h_version == 6 ? INTERP_MSDOS : INTERP_DEC_20;
    h_interpreter_version = 'F';

#ifdef COLOR_SUPPORT
    /* Enable colors if the terminal supports them, the user did not
     * disable colors, and the game or user requested colors.  User
     * requests them by specifying a foreground or background.
     */
    u_setup.color_enabled = (!u_setup.disable_color
			&& (((h_version >= 5) && (h_flags & COLOUR_FLAG))
			  || (u_setup.foreground_color != -1)
			  || (u_setup.background_color != -1)));

    /* Maybe we don't want to muck about with changing $TERM to
     * xterm-color which some supposedly current Unicies still don't
     * understand.
     */ 
    //if (u_setup.force_color)
	u_setup.color_enabled = TRUE;

    if (u_setup.color_enabled) {
        h_config |= CONFIG_COLOUR;
        h_flags |= COLOUR_FLAG; /* FIXME: beyond zork handling? */
	h_default_foreground =	1; //(u_setup.foreground_color == -1) ? FOREGROUND_DEF : u_setup.foreground_color;
	h_default_background =  1; //(u_setup.background_color ==-1) ? BACKGROUND_DEF : u_setup.background_color;
    } else 
#endif
    {
	/* Set these per spec 8.3.2. */
	h_default_foreground = BLACK_COLOUR;
	h_default_background = WHITE_COLOUR;
	if (h_flags & COLOUR_FLAG) h_flags &= ~COLOUR_FLAG;
    }
    
    iphone_init_screen();    

    //NSLog (@"uiinit f %d b %d\n", h_default_foreground, h_default_background);
#if FROTZ_IOS_PORT
    if (!do_autosave)
#endif
    {
	os_set_colour(h_default_foreground, h_default_background);
	os_erase_area(1, 1, h_screen_rows, h_screen_cols, 0);
    }

}/* os_init_screen */

/*
 * os_reset_screen
 *
 * Reset the screen before the program stops.
 *
 */

void os_reset_screen (void)
{

    os_stop_sample(0);
    os_set_text_style(0);
    os_display_string((zchar *) "[Hit any key to exit.]");
    os_read_key(0, FALSE); 

}/* os_reset_screen */

/*
 * os_restart_game
 *
 * This routine allows the interface to interfere with the process of
 * restarting a game at various stages:
 *
 *     RESTART_BEGIN - restart has just begun
 *     RESTART_WPROP_SET - window properties have been initialised
 *     RESTART_END - restart is complete
 *
 */

void os_restart_game (int stage)
{
}

/*
 * os_random_seed
 *
 * Return an appropriate random seed value in the range from 0 to
 * 32767, possibly by using the current system time.
 *
 */

int os_random_seed (void)
{

    if (u_setup.random_seed == -1)
      /* Use the epoch as seed value */
      return (time(0) & 0x7fff);
    else return u_setup.random_seed;

}/* os_random_seed */


/*
 * os_path_open
 *
 * Open a file in the current directory.  If this fails, then search the
 * directories in the ZCODE_PATH environmental variable.  If that's not
 * defined, search INFOCOM_PATH.
 *
 */

FILE *os_path_open(const char *name, const char *mode)
{
	FILE *fp;
	char buf[FILENAME_MAX + 1];

	/* Let's see if the file is in the currect directory */
	/* or if the user gave us a full path. */
	if ((fp = fopen(name, mode))) {
		return fp;
	}

	/* If zcodepath is defined in a config file, check that path. */
	/* If we find the file a match in that path, great. */
	/* Otherwise, check some environmental variables. */
	if (option_zcode_path != NULL) {
		if ((fp = pathopen(name, option_zcode_path, mode, buf)) != NULL) {
			strncpy(story_name, buf, FILENAME_MAX);
			return fp;
		}
	}

	return NULL;	/* give up */
} /* os_path_open() */

/*
 * pathopen
 *
 * Given a standard Unix-style path and a filename, search the path for
 * that file.  If found, return a pointer to that file and put the full
 * path where the file was found in fullname.
 *
 */

FILE *pathopen(const char *name, const char *p, const char *mode, char *fullname)
{
	FILE *fp;
	char buf[FILENAME_MAX + 1];
	char *bp, lastch;

	lastch = 'a';	/* makes compiler shut up */

	while (*p) {
		bp = buf;
		while (*p && *p != PATHSEP)
			lastch = *bp++ = *p++;
		if (lastch != DIRSEP)
			*bp++ = DIRSEP;
		strcpy(bp, name);
		if ((fp = fopen(buf, mode)) != NULL) {
			strncpy(fullname, buf, FILENAME_MAX);
			return fp;
		}
		if (*p)
			p++;
	}
	return NULL;
} /* FILE *pathopen() */

void redraw(void)
{
	/* not implemented */
}


void os_init_setup(void)
{

	f_setup.attribute_assignment = 0;
	f_setup.attribute_testing = 0;
	f_setup.context_lines = 0;
	f_setup.object_locating = 0;
	f_setup.object_movement = 0;
	f_setup.left_margin = 0;
	f_setup.right_margin = 0;
	f_setup.ignore_errors = 0;
	f_setup.piracy = 0;		/* enable the piracy opcode */
	f_setup.undo_slots = MAX_UNDO_SLOTS;
	f_setup.expand_abbreviations = 0;
	f_setup.script_cols = 80;
	f_setup.save_quetzal = QUETZAL_DEF;
	f_setup.sound = 1;
	f_setup.err_report_mode = ERR_REPORT_NEVER;

	u_setup.disable_color = 1;
	u_setup.force_color = 0;
	u_setup.foreground_color = -1;
	u_setup.background_color = -1;
	u_setup.screen_width = -1;
	u_setup.screen_height = -1;
	u_setup.random_seed = -1;
	u_setup.random_seed = -1;
	u_setup.tandy_bit = 0;
	u_setup.current_text_style = 0;
			/* Since I can't use attr_get, which
			would make things easier, I need
			to use the same hack the MS-DOS port
			does...keep the current style in a
			global variable. */
	u_setup.plain_ascii = 0; /* true if user wants to disable Latin-1 */
	/* u_setup.interpreter = INTERP_DEFAULT; */
	u_setup.current_color = 0;
	u_setup.color_enabled = FALSE;

}

