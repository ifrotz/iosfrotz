//
//  glkios.c
//  glkios
//
//  Created by Craig Smith on 4/22/23.
//
#include "glkios.h"

int pref_printversion = FALSE;
int pref_screenwidth = 0;
int pref_screenheight = 0;
int pref_messageline = TRUE;
int pref_reverse_textgrids = FALSE;
int pref_window_borders = FALSE;
int pref_override_window_borders = FALSE;
int pref_precise_timing = FALSE;
int pref_historylen = 20;
int pref_prompt_defaults = TRUE;

strid_t glkunix_stream_open_pathname(char *pathname, glui32 textmode,
    glui32 rock)
{
    return gli_stream_open_pathname(pathname, FALSE, (textmode != 0), rock);
}


