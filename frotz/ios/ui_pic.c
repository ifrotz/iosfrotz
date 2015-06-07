/*
 * ui_pic.c - Unix interface, picture outline functions
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

#include <stdlib.h>
#include <string.h>

#include "iosfrotz.h"

#define PIC_FILE_HEADER_FLAGS 1
#define PIC_FILE_HEADER_NUM_IMAGES 4
#define PIC_FILE_HEADER_ENTRY_SIZE 8
#define PIC_FILE_HEADER_VERSION 14

#define PIC_HEADER_NUMBER 0
#define PIC_HEADER_WIDTH 2
#define PIC_HEADER_HEIGHT 4

static struct {
  int z_num;
  int width;
  int height;
  int orig_width;
  int orig_height;
} *pict_info;
static int num_pictures = 0;

#if 0 // unused
static unsigned char lookupb(unsigned char *p, int n)
{
  return p[n];
}

static unsigned short lookupw(unsigned char *p, int n)
{
  return (p[n + 1] << 8) | p[n];
}

/*
 * Do a rounding division, rounding to even if fraction part is 1/2.
 * We assume x and y are nonnegative.
 *
 */
static int round_div(int x, int y)
{
	int quotient = x / y;
	int dblremain = (x % y) << 1;

	if ((dblremain > y) || (dblremain == y) && (quotient & 1))
		quotient++;
	return quotient;
}
#endif

/* Convert a Z picture number to an index into pict_info.  */
static int z_num_to_index(int n)
{
  int i;
  for (i = 0; i <= num_pictures; i++)
    if (pict_info[i].z_num == n)
      return i;
  return -1;
}

/*
 * os_picture_data
 *
 * Return true if the given picture is available. If so, write the
 * width and height of the picture into the appropriate variables.
 * Only when picture 0 is asked for, write the number of available
 * pictures and the release number instead.
 *
 */
bool os_picture_data(int num, int *height, int *width)
{
  int index;

  *height = 0;
  *width = 0;

  if (!pict_info)
    return FALSE;

  if ((index = z_num_to_index(num)) == -1)
    return FALSE;

  *height = pict_info[index].height;
  *width = pict_info[index].width;

  return TRUE;
}

/*
 * os_draw_picture
 *
 * Display a picture at the given coordinates. Top left is (1,1).
 *
 */

/* TODO: handle truncation correctly.  Spec 8.8.3 says all graphics should
 * be clipped to the current window.  To do that, we should probably
 * modify z_draw_picture in the frotz core to pass some extra parameters.
 */

void os_draw_picture (int num, int row, int col)
{
}

/*
 * os_peek_colour
 *
 * Return the colour of the pixel below the cursor. This is used
 * by V6 games to print text on top of pictures. The coulor need
 * not be in the standard set of Z-machine colours. To handle
 * this situation, Frotz extends the colour scheme: Values above
 * 15 (and below 256) may be used by the interface to refer to
 * non-standard colours. Of course, os_set_colour must be able to
 * deal with these colours. Interfaces which refer to characters
 * instead of pixels might return the current background colour
 * instead.
 *
 */

int os_peek_colour (void)
{
  return BLACK_COLOUR;
}
