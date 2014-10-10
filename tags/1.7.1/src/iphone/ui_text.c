/*
 * ui_text.c - Unix interface, text functions
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

#include "iphone_frotz.h"
#include "RichTextStyle.h"

/* When color_enabled is FALSE, we still minimally keep track of colors by
 * setting current_color to A_REVERSE if the game reads the default
 * foreground and background colors and swaps them.  If we don't do this,
 * Strange Results can happen when playing certain V6 games when
 * color_enabled is FALSE.
 */
bool color_enabled = FALSE;

// \ character / cursor management stuff copied from 'dumb' frontend

static int screen_cells;

/* The in-memory state of the screen.  */
/* Each cell contains a style in the upper byte and a char in the lower. */
cell *screen_data = NULL;
cellcolor *screen_colors = NULL;

static cell make_cell(int style, char c) {return (style << 8) | (0xff & c);}
static char cell_char(cell c) {return c & 0xff;}
static int cell_style(cell c) {return c >> 8;}

/* A cell's style is REVERSE_STYLE, normal (0), or PICTURE_STYLE.
 * PICTURE_STYLE means the character is part of an ascii image outline
 * box.  (This just buys us the ability to turn box display on and off
 * with immediate effect.  No, not very useful, but I wanted to give
 * the rv bit some company in that huge byte I allocated for it.)  */
#define PICTURE_STYLE 16

static int current_style = 0;

/* Which cells have changed (1 byte per cell).  */
//static char *screen_changes;

int cursor_row = 0, cursor_col = 0;

static cell *scr_row(int r) { return screen_data + r * MAX_COLS; }
static cellcolor *scr_color(int r) { return screen_colors + r * MAX_COLS; }

static inline int frotz_to_richtext_style(int fstyle) {
    int style = kFTNormal;
    if (fstyle & BOLDFACE_STYLE)
        style |= kFTBold;
    if (fstyle & EMPHASIS_STYLE)
        style |= kFTItalic;
    if (fstyle & FIXED_WIDTH_STYLE)
        style |= kFTFixedWidth;
    if (fstyle & REVERSE_STYLE)
        style |= kFTReverse;
    return style;
}

void iphone_init_screen() {
    screen_cells = MAX_ROWS * MAX_COLS;
    int i;
    
    if (!screen_data)
        screen_data = malloc(screen_cells * sizeof(cell));
    if (!screen_colors)
        screen_colors = malloc(screen_cells * sizeof(cellcolor));
    if (do_autosave)
        return;
    for (i = 0; i < screen_cells; ++i) {
        screen_data[i] = ' ';
        screen_colors[i] = (h_default_foreground<<4) | h_default_background;
    }
}


/* int current_color = 0; */

static char latin1_to_ascii[] =
"   !  c  L  >o<Y  |  S  '' C  a  << not-  R  _  "
"^0 +/-^2 ^3 '  my P  .  ,  ^1 o  >> 1/41/23/4?  "
"A  A  A  A  Ae A  AE C  E  E  E  E  I  I  I  I  "
"Th N  O  O  O  O  Oe *  O  U  U  U  Ue Y  Th ss "
"a  a  a  a  ae a  ae c  e  e  e  e  i  i  i  i  "
"th n  o  o  o  o  oe :  o  u  u  u  ue y  th y  ";
/*
 * os_font_data
 *
 * Return true if the given font is available. The font can be
 *
 *    TEXT_FONT
 *    PICTURE_FONT
 *    GRAPHICS_FONT
 *    FIXED_WIDTH_FONT
 *
 * The font size should be stored in "height" and "width". If
 * the given font is unavailable then these values must _not_
 * be changed.
 *
 */

int os_font_data (int font, int *height, int *width)
{
    
    if (font == TEXT_FONT) {
        *height = 1; *width = 1; return 1; /* Truth in advertising */
    }
    return 0;
    
}/* os_font_data */

/*
 * os_set_colour
 *
 * Set the foreground and background colours which can be:
 *
 *     DEFAULT_COLOUR
 *     BLACK_COLOUR
 *     RED_COLOUR
 *     GREEN_COLOUR
 *     YELLOW_COLOUR
 *     BLUE_COLOUR
 *     MAGENTA_COLOUR
 *     CYAN_COLOUR
 *     WHITE_COLOUR
 *
 *     MS-DOS 320 columns MCGA mode only:
 *
 *     GREY_COLOUR
 *
 *     Amiga only:
 *
 *     LIGHTGREY_COLOUR
 *     MEDIUMGREY_COLOUR
 *     DARKGREY_COLOUR
 *
 * There may be more colours in the range from 16 to 255; see the
 * remarks on os_peek_colour.
 *
 */

void os_set_colour (int new_foreground, int new_background)
{
    //    if (new_foreground == 1) new_foreground = h_default_foreground;
    //    if (new_background == 1) new_background = h_default_background;
    
    int new_color = u_setup.current_color = (new_foreground << 4) | new_background;
    iphone_set_text_attribs(0, frotz_to_richtext_style(u_setup.current_text_style), new_color, TRUE);
}/* os_set_colour */

/*
 * os_set_text_style
 *
 * Set the current text style. Following flags can be set:
 *
 *     REVERSE_STYLE
 *     BOLDFACE_STYLE
 *     EMPHASIS_STYLE (aka underline aka italics)
 *     FIXED_WIDTH_STYLE
 *
 */

void os_set_text_style (int new_style)
{
    current_style = new_style;
    u_setup.current_text_style = new_style;
    iphone_set_text_attribs(0, frotz_to_richtext_style(new_style), u_setup.current_color, TRUE);
} /* os_set_text_style */

/*
 * os_set_font
 *
 * Set the font for text output. The interpreter takes care not to
 * choose fonts which aren't supported by the interface.
 *
 */

void os_set_font (int new_font)
{
    
    /* Not implemented */
    
}/* os_set_font */

static void iphone_set_cell(int row, int col, cell c)
{
    int color = u_setup.current_color;
    if (color != 0x11 && (color >> 4) == (color & 0xf)) { // varicella workaround
        if ((color >> 4) == BLACK_COLOUR)
            color = (WHITE_COLOUR<<4)|BLACK_COLOUR;
        else
            
            color = (BLACK_COLOUR<<4)|(color & 0xf);
    }
    if (row < 0)
        row = 0;
    scr_row(row)[col] = c;
    scr_color(row)[col] = color;

    if (col == h_screen_cols-1 && (c & (REVERSE_STYLE << 8))) {
        while (++col < MAX_COLS) {
            scr_row(row)[col] = make_cell(REVERSE_STYLE, ' ');
            scr_color(row)[col] = color;
        }
    }
}

/* Copy a cell and copy its changedness state.
 * This is used for scrolling.  */
static void scr_copy_cell(int dest_row, int dest_col,
                          int src_row, int src_col)
{
    scr_row(dest_row)[dest_col] = scr_row(src_row)[src_col];
    scr_color(dest_row)[dest_col] = scr_color(src_row)[src_col];
}

int top_win_height = 1; // hack; for use by iphone frontend


/* put a character in the cell at the cursor and advance the cursor.  */
void iphone_display_char(unsigned int c)
{
    // hack to make the status line/uppper window auto-grow for games like anchorhead which
    // don't resize it big enough for the menus they want to display
    if (cwin == 1 && cursor_row >= top_win_height && cursor_row < h_screen_rows) {
        iphone_set_top_win_height(cursor_row+1);
    }

    iphone_set_cell(cursor_row, cursor_col, make_cell(current_style, c <= 0xff ? c : '?'));
    iphone_putchar(c);

    if (++cursor_col == h_screen_cols) {
        if (cursor_row == h_screen_rows - 1)
            cursor_col--;
        else if (cwin==0 || cursor_col >= MAX_COLS) {
            cursor_row++;
            cursor_col = 0;
        }
    }
}

void iphone_backspace()
{
    cursor_col--;
    if (cursor_col < 0)
        cursor_col = 0;
    iphone_set_cell(cursor_row, cursor_col, make_cell(current_style, ' '));
}

/*
 * os_display_char
 *
 * Display a character of the current font using the current colours and
 * text style. The cursor moves to the next position. Printable codes are
 * all ASCII values from 32 to 126, ISO Latin-1 characters from 160 to
 * 255, ZC_GAP (gap between two sentences) and ZC_INDENT (paragraph
 * indentation). The screen should not be scrolled after printing to the
 * bottom right corner.
 *
 */

void os_display_char (unsigned int c)
{
    
    if (c >= ZC_LATIN1_MIN /*&& c <= ZC_LATIN1_MAX*/) {
        if (u_setup.plain_ascii) {
            
            char *ptr = latin1_to_ascii + 3 * (c - ZC_LATIN1_MIN);
            char c1 = *ptr++;
            char c2 = *ptr++;
            char c3 = *ptr;
            
            iphone_display_char(c1);
            
            if (c2 != ' ')
                iphone_display_char(c2);
            if (c3 != ' ')
                iphone_display_char(c3);
            
        } else
            iphone_display_char(c);
        return;
    }
    if (c >= ZC_ASCII_MIN && c <= ZC_ASCII_MAX) {
        iphone_display_char(c);
        return;
    }
    if (c == ZC_BACKSPACE) {
        iphone_backspace();
        return;
    }
    if (c == ZC_INDENT) {
        iphone_display_char(' '); iphone_display_char(' '); iphone_display_char(' ');
        return;
    }
    if (c == ZC_GAP) {
        iphone_display_char(' '); iphone_display_char(' ');
        return;
    }
    
}/* os_display_char */

/*
 * os_display_string
 *
 * Pass a string of characters to os_display_char.
 *
 */

void os_display_string (const zchar *s)
{
    
    zchar c;
    
    while ((c = (unsigned char) *s++) != 0)
        
        if (c == ZC_NEW_FONT || c == ZC_NEW_STYLE) {
            
            int arg = (unsigned char) *s++;
            
            if (c == ZC_NEW_FONT)
                os_set_font (arg);
            if (c == ZC_NEW_STYLE)
                os_set_text_style (arg);
            
        } else os_display_char (c);
    
}/* os_display_string */

/*
 * os_char_width
 *
 * Return the width of the character in screen units.
 *
 */

int os_char_width (zchar c)
{
    
    if (c >= ZC_LATIN1_MIN /*&& c <= ZC_LATIN1_MAX*/ && u_setup.plain_ascii) {
        
        int width = 0;
        const char *ptr = latin1_to_ascii + 3 * (c - ZC_LATIN1_MIN);
        ptr++;
        char c2 = *ptr++;
        char c3 = *ptr;
        
        /* Why, oh, why did you declare variables that way??? */
        
        width++;
        if (c2 != ' ')
            width++;
        if (c3 != ' ')
            width++;
        return width;
    }
    return 1;
    
}/* os_char_width*/

/*
 * os_string_width
 *
 * Calculate the length of a word in screen units. Apart from letters,
 * the word may contain special codes:
 *
 *    NEW_STYLE - next character is a new text style
 *    NEW_FONT  - next character is a new font
 *
 */

int os_string_width (const zchar *s)
{
    int width = 0;
    zchar c;
    
    while ((c = *s++) != 0)
        
        if (c == ZC_NEW_STYLE || c == ZC_NEW_FONT) {
            
            s++;
            /* No effect */
            
        } else width += os_char_width(c);
    
    return width;
    
}/* os_string_width */

/*
 * os_set_cursor
 *
 * Place the text cursor at the given coordinates. Top left is (1,1).
 *
 */

extern int lastInputWindow;

void os_set_cursor (int row, int col)
{
    //printf ("os_set_cursor %d %d\n", row, col);
    cursor_row = row - 1; cursor_col = col - 1;
    if (cursor_row >= h_screen_rows && h_screen_rows > 0)
        cursor_row = h_screen_rows - 1;
    lastInputWindow = -1;
    
}/* os_set_cursor */

/*
 * os_more_prompt
 *
 * Display a MORE prompt, wait for a keypress and remove the MORE
 * prompt from the screen.
 *
 */

void os_more_prompt (void)
{
    //    iphone_more_prompt();
}/* os_more_prompt */

/*
 * os_erase_area
 *
 * Fill a rectangular area of the screen with the current background
 * colour. Top left coordinates are (1,1). The cursor does not move.
 *
 */

void os_erase_area (int top, int left, int bottom, int right, int windowNum)
{
    int row, col;
    if (top == 1 && bottom == h_screen_rows &&
        left == 1 && right == h_screen_cols) {
        iphone_erase_screen();
        right = MAX_COLS;
    } else if (windowNum == 0)
        iphone_erase_mainwin();    
    top--; left--; bottom--; right--;
    for (row = top; row <= bottom; row++)
        for (col = left; col <= right; col++)
            iphone_set_cell(row, col, make_cell(current_style, ' '));
}/* os_erase_area */



void os_split_win(int height) {
    if (height > h_screen_height || height > MAX_ROWS)
        height = h_screen_height;
    if (height > top_win_height && top_win_height > 1) { // >0 cond to help reduce bronze flicker
        int row, col;
        for (row = top_win_height; row < h_screen_rows; row++)
            for (col = 0; col < h_screen_cols; col++)
                iphone_set_cell(row, col, make_cell(current_style, ' '));
    }
    iphone_set_top_win_height(height);
}

extern int currTextStyle;

void os_new_line(bool wrapping) { // only called by word wrap
    if (wrapping)
        iphone_putchar(' '); // all word wrapping handled by text view
    else
        iphone_putchar('\n');
}

/*
 * os_scroll_area
 *
 * Scroll a rectangular area of the screen up (units > 0) or down
 * (units < 0) and fill the empty space with the current background
 * colour. Top left coordinates are (1,1). The cursor stays put.
 *
 */

void os_scroll_area (int top, int left, int bottom, int right, int units)
{
    int row, col;
    top--; left--; bottom--; right--;
    if (units > 0) { 
        for (row = top; row <= bottom - units; row++)
            for (col = left; col <= right; col++)
                scr_copy_cell(row, col, row + units, col);
        os_erase_area(bottom - units + 2, left + 1, bottom + 1, right + 1, -1);
    } else if (units < 0) {
        for (row = bottom; row >= top - units; row--)
            for (col = left; col <= right; col++)
                scr_copy_cell(row, col, row + units, col);
        os_erase_area(top + 1, left + 1, top - units, right + 1, -1);
    }
    //  if (cwin == 0 && units == 1 && left == 0 && right == h_screen_cols-1 && bottom == h_screen_rows-1)
    //    iphone_putchar('\n');
    
}/* os_scroll_area */

extern char script_name[];

void	os_start_script() {
    iphone_start_script(script_name);
}

void	os_stop_script() {
    iphone_stop_script();
}

