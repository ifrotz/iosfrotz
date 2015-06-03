/*
 * ui_input.c - Unix interface, input functions, repurposed for iPhone interface.
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
#include <limits.h>

#include <sys/time.h>

#include "iosfrotz.h"

static struct timeval global_timeout;

/* Some special characters. */
#define MOD_CTRL 0x40
#define MOD_META 0x80
#define CHR_DEL (MOD_CTRL ^'?')

/* These are useful for circular buffers.
 */
#define RING_DEC( ptr, beg, end) (ptr > (beg) ? --ptr : (ptr = (end)))
#define RING_INC( ptr, beg, end) (ptr < (end) ? ++ptr : (ptr = (beg)))

#define MAX_HISTORY 20
static char *history_buffer[MAX_HISTORY];
static char **history_next = history_buffer; /* Next available slot. */
static char **history_view = history_buffer; /* What the user is looking at. */
#define history_end (history_buffer + MAX_HISTORY - 1)

extern bool is_terminator (zchar);
extern void read_string (int, zchar *);
extern int completion (const zchar *, zchar *);

/*
 * unix_set_global_timeout
 *
 * This sets up a time structure to determine when unix_read_char should
 * return zero (representing input timeout).  When current system time
 * equals global_timeout, boom.
 *
 */

static void unix_set_global_timeout(int timeout)
{
    if (!timeout)
	global_timeout.tv_sec = 0;
    else {
        gettimeofday(&global_timeout, NULL);
        global_timeout.tv_sec += (timeout/10);
        global_timeout.tv_usec += ((timeout%10)*100000);
        if (global_timeout.tv_usec > 999999) {
          global_timeout.tv_sec++;
          global_timeout.tv_usec -= 1000000;
        }
    }
}

/* This returns the number of milliseconds until the input timeout
 * elapses or zero if it has already elapsed.  -1 is returned if no
 * timeout is in effect, otherwise the return value is non-negative.
 */
static int timeout_to_ms()
{
    struct timeval now, diff;

    if (global_timeout.tv_sec == 0)
	return -1;
    gettimeofday( &now, NULL);
    diff.tv_usec = global_timeout.tv_usec - now.tv_usec;
    if (diff.tv_usec < 0) {
	/* Carry */
	now.tv_sec++;
	diff.tv_usec += 1000000;
    }
    diff.tv_sec = global_timeout.tv_sec - now.tv_sec;
    if (diff.tv_sec < 0) return 0;
    if (diff.tv_sec >= INT_MAX / 1000 - 1) /* Paranoia... */
	return INT_MAX - 1000;
    return diff.tv_sec * 1000 + diff.tv_usec / 1000;
}

/*
 * unix_read_char
 *
 * This uses iphone_getchar() routine to get the next character
 * typed, and returns it.  It returns values which the standard
 * considers to be legal input, and also returns editing and frotz hot
 * keys.  If called with extkeys set it will also return line-editing
 * keys like INSERT etc.
 *
 * If unix_set_global_timeout has been used to set a global timeout
 * this routine may also return ZC_TIME_OUT if input times out.
 */
static int unix_read_char(int extkeys)
{
    int c;
    while(1) {
	int tmo = timeout_to_ms();
	c = iphone_getchar(tmo);
	if (c == ZC_AUTOSAVE) {
	    do_autosave = 1;
	    return c;
	}


	/* Catch 98% of all input right here... */
	if ((c >= ZC_ASCII_MIN && c <= ZC_ASCII_MAX)
	    || (!u_setup.plain_ascii
		&& c >= ZC_LATIN1_MIN && c <= ZC_LATIN1_MAX)) 
	    return c;

	/* ...and the other 2% makes up 98% of the code. :( */

	switch(c) {
	/* Normally ERR means timeout.  I suppose we might also get
	   ERR if a signal hits getch. */
	case -1:
	    if (timeout_to_ms() == 0)
		return ZC_TIME_OUT;
	    else
		continue;

	/* Screen decluttering. */
	case MOD_CTRL ^ 'L': case MOD_CTRL ^ 'R':
	    // clearok( curscr, 1); refresh(); clearok( curscr, 0);
	    continue;
	case '\n': case '\r': return ZC_RETURN;
	/* I've seen KEY_BACKSPACE returned on some terminals. */
	case '\b': return ZC_BACKSPACE;
	/* On terminals with 8-bit character sets or 7-bit connections
	   "Alt-Foo" may be returned as an escape followed by the ASCII
	   value of the letter.  We have to decide here whether to
	   return a single escape or a frotz hot key. */
	case -30:
	    c = iphone_getchar(timeout_to_ms());
	    switch(c) {
	    case -1: return ZC_ESCAPE;
	    case 'p': return ZC_HKEY_PLAYBACK;
	    case 'r': return ZC_HKEY_RECORD;
	    case 's': return ZC_HKEY_SEED;
	    case 'u': return ZC_HKEY_UNDO;
	    case 'n': return ZC_HKEY_RESTART;
	    case 'x': return ZC_HKEY_QUIT;
	    case 'd': return ZC_HKEY_DEBUG;
	    case 'h': return ZC_HKEY_HELP;
	    default: continue;	/* Ignore unknown combinations. */
	    }
	/* The standard function key block. */
//    case ZC_IP_ARROW_UP: return ZC_ARROW_UP;
//    case ZC_IP_ARROW_DOWN: return ZC_ARROW_DOWN;
//    case ZC_IP_ARROW_LEFT: return ZC_ARROW_LEFT;
//    case ZC_IP_ARROW_RIGHT: return ZC_ARROW_RIGHT;
    case 0x1b: return ZC_ESCAPE;
	//case KEY_UP: return ZC_ARROW_UP;
	//case KEY_DOWN: return ZC_ARROW_DOWN;
	//case KEY_LEFT: return ZC_ARROW_LEFT;
	//case KEY_RIGHT: return ZC_ARROW_RIGHT;
	//case KEY_F(1): return ZC_FKEY_MIN;
	//case KEY_F(2): return ZC_FKEY_MIN + 1;
	//case KEY_F(3): return ZC_FKEY_MIN + 2;
	//case KEY_F(4): return ZC_FKEY_MIN + 3;
	//case KEY_F(5): return ZC_FKEY_MIN + 4;
	//case KEY_F(6): return ZC_FKEY_MIN + 5;
	//case KEY_F(7): return ZC_FKEY_MIN + 6;
	//case KEY_F(8): return ZC_FKEY_MIN + 7;
	//case KEY_F(9): return ZC_FKEY_MIN + 8;
	//case KEY_F(10): return ZC_FKEY_MIN + 9;
	//case KEY_F(11): return ZC_FKEY_MIN + 10;
	//case KEY_F(12): return ZC_FKEY_MIN + 11;
        /* Catch the meta key on those plain old ASCII terminals where
	   it sets the high bit.  This only works in
	   u_setup.plain_ascii mode: otherwise these character codes
	   would have been interpreted according to ISO-Latin-1
	   earlier. */
	case MOD_META | 'p': return ZC_HKEY_PLAYBACK;
	case MOD_META | 'r': return ZC_HKEY_RECORD;
	case MOD_META | 's': return ZC_HKEY_SEED;
	case MOD_META | 'u': return ZC_HKEY_UNDO;
	case MOD_META | 'n': return ZC_HKEY_RESTART;
	case MOD_META | 'x': return ZC_HKEY_QUIT;
	case MOD_META | 'd': return ZC_HKEY_DEBUG;
	case MOD_META | 'h': return ZC_HKEY_HELP;

/* these are the emacs-editing characters */
	case MOD_CTRL ^ 'B': return ZC_ARROW_LEFT;
	case MOD_CTRL ^ 'F': return ZC_ARROW_RIGHT;
	case MOD_CTRL ^ 'P': return ZC_ARROW_UP;
	case MOD_CTRL ^ 'N': return ZC_ARROW_DOWN;
	//case MOD_CTRL ^ 'A': c = KEY_HOME; break;
	//case MOD_CTRL ^ 'E': c = KEY_END; break;
	//case MOD_CTRL ^ 'D': c = KEY_DC; break;
	//case MOD_CTRL ^ 'K': c = KEY_EOL; break;

	default: break; /* Who knows? */
	}

	/* Control-N through Control-U happen to map to the frotz hot
	 * key codes, but not in any mnemonic manner.  It annoys an
	 * emacs user (or this one anyway) when he tries out of habit
	 * to use one of the emacs keys that isn't implemented and he
	 * gets a random hot key function.  It's less jarring to catch
	 * them and do nothing.  [APP] */
      if ((c >= ZC_HKEY_MIN) && (c <= ZC_HKEY_MAX))
	continue;

	/* Finally, if we're in full line mode (os_read_line), we
	   might return codes which aren't legal Z-machine keys but
	   are used by the editor. */
	if (extkeys) return c;
    }
}


/*
 * unix_add_to_history
 *
 * Add the given string to the next available history buffer slot.
 *
 */

static void unix_add_to_history(zchar *str)
{

    if (*history_next != NULL)
	free( *history_next);
    *history_next = (char *)malloc(strlen((char *)str) + 1);
    strcpy( *history_next, (char *)str);
    RING_INC( history_next, history_buffer, history_end);
    history_view = history_next; /* Reset user frame after each line */
}

/*
 * unix_history_back
 *
 * Copy last available string to str, if possible.  Return 1 if successful.
 * Only lines of at most maxlen characters will be considered.  In addition
 * the first searchlen characters of the history entry must match those of str.
 */
static int unix_history_back(zchar *str, int searchlen, int maxlen)
{
    char **prev = history_view;

    do {
	RING_DEC( history_view, history_buffer, history_end);
	if ((history_view == history_next)
	    || (*history_view == NULL)) {
	    os_beep(BEEP_HIGH);
	    history_view = prev;
	    return 0;
	}
    } while (strlen( *history_view) > maxlen
	     || (searchlen != 0 && strncmp( (char *)str, *history_view, searchlen)));
    strcpy((char *)str + searchlen, *history_view + searchlen);
    return 1;
}

/*
 * unix_history_forward
 *
 * Opposite of unix_history_back, and works in the same way.
 */
static int unix_history_forward(zchar *str, int searchlen, int maxlen)
{
    char **prev = history_view;

    do {
	RING_INC( history_view, history_buffer, history_end);
	if ((history_view == history_next)
	    || (*history_view == NULL)) {

	    os_beep(BEEP_HIGH);
	    history_view = prev;
	    return 0;
	}
    } while (strlen( *history_view) > maxlen
	     || (searchlen != 0 && strncmp( (char *)str, *history_view, searchlen)));
    strcpy((char *)str + searchlen, *history_view + searchlen);
    return 1;
}



/*
 * os_read_key
 *
 * Read a single character from the keyboard (or a mouse click) and
 * return it. Input aborts after timeout/10 seconds.
 *
 */

zchar os_read_key (int timeout, int cursor)
{
    zchar c;

//    if (!cursor) curs_set(0); //xxx
    iphone_enable_single_key_input();
    unix_set_global_timeout(timeout);
    c = (zchar) unix_read_char(0);
    if (cwin == 1 && c == ZC_BACKSPACE) {
	iphone_backspace();
	iphone_putchar(c);
    }
    iphone_disable_input();

//    if (!cursor) curs_set(1); //xxx
    return c;

}/* os_read_key */

enum input_type {
  INPUT_CHAR,
  INPUT_LINE,
  INPUT_LINE_CONTINUED,
};

static void translate_special_chars(char *s)
{ 
  char *src = s, *dest = s;
  while (*src)   
    switch(*src++) {
    default: *dest++ = src[-1]; break;
    case '\n': *dest++ = ZC_RETURN; break;
    case '~':
      switch (*src++) {
//      case '\n': *dest++ = ZC_RETURN; break;
      case '~': *dest++ = '~'; break;
      case '?': *dest++ = ZC_BACKSPACE; break;
      case '[': *dest++ = ZC_ESCAPE; break;
      case '_': *dest++ = ZC_RETURN; break;
      case '^': *dest++ = ZC_ARROW_UP; break;
      case '.': *dest++ = ZC_ARROW_DOWN; break;
      case '<': *dest++ = ZC_ARROW_LEFT; break;
      case '>': *dest++ = ZC_ARROW_RIGHT; break;
      case 'R': *dest++ = ZC_HKEY_RECORD; break;
      case 'P': *dest++ = ZC_HKEY_PLAYBACK; break;
      case 'S': *dest++ = ZC_HKEY_SEED; break;
      case 'U': *dest++ = ZC_HKEY_UNDO; break;
      case 'N': *dest++ = ZC_HKEY_RESTART; break;
      case 'X': *dest++ = ZC_HKEY_QUIT; break;
      case 'D': *dest++ = ZC_HKEY_DEBUG; break;
      case 'H': *dest++ = ZC_HKEY_HELP; break;
      case '1': case '2': case '3': case '4':
      case '5': case '6': case '7': case '8': case '9':
        *dest++ = ZC_FKEY_MIN + src[-1] - '0' - 1; break;
      case '0': *dest++ = ZC_FKEY_MIN + 9; break;
      default:
        fprintf(stderr, "DUMB-FROTZ: unknown escape char: %c\n", src[-1]);
        fprintf(stderr, "Enter \\help to see the list\n");
      }
    }
  *dest = '\0';
}


/* Read one line, including the newline, into s.  Safely avoids buffer
 * overruns (but that's kind of pointless because there are several
 * other places where I'm not so careful).  */
static void zgetline(char *s)
{
    int c = 0;
    char *p = s;
    iphone_enable_input();
    while (p < s + INPUT_BUFFER_SIZE - 1)
//	if ((c = iphone_getchar(timeout_to_ms())) != '\n')
	if ((c = unix_read_char(0)) != '\n' && c != ZC_RETURN)
	{
	    if (c == -1) {
		c = ZC_TIME_OUT;
		break;
	    }
	    if (c == ZC_AUTOSAVE) {
		do_autosave = 1;
                break;
	    }
	    if (c == ZC_BACKSPACE && p > s)
                p--;
	    else if (c == ZC_ESCAPE) {
                *p = 0;
		if (p > s) {
		    if (*--p == ' ' || ispunct(*p))
			*p = 0;
		}
		while (p > s && *p != ' ' && !ispunct(*p))
		    p--;
                if (p != s) p++;
	    }
	    else
		*p++ = c;
	} else
	    break;
    if (c == ZC_AUTOSAVE)
	*p++ = c;
    else
	*p++ = '\n';
    *p++ = '\0';
    iphone_disable_input();
  
    if (c == ZC_TIME_OUT || p < s + INPUT_BUFFER_SIZE - 1)
        return;
   
    while (iphone_getchar(-1) != '\n')
      ;
    printf("Line too long, truncated to %s\n", s - INPUT_BUFFER_SIZE);
}

/* Read a line, processing commands (lines that start with a backslash
 * (that isn't the start of a special character)), and write the
 * first non-command to s.
 * Return true if timed-out.  */
static bool ui_read_line(char *s, char *prompt, bool show_cursor,
                           int timeout, enum input_type type,
                           zchar *continued_line_chars)
{
    unix_set_global_timeout(timeout);
    if (prompt)
	iphone_puts(prompt);
    zgetline(s);
    translate_special_chars(s);
    if (*s == ZC_AUTOSAVE)
	return FALSE;
    if (*s == ZC_TIME_OUT)
	return TRUE;
    return FALSE;
}

/* Read a line that is not part of z-machine input (more prompts and
 * filename requests).  */
static void ui_read_misc_line(char *s, char *prompt)
{
  ui_read_line(s, prompt, 0, 0, 0, 0);
  /* Remove terminating newline */
  s[strlen(s) - 1] = '\0';
}

/* For allowing the user to input in a single line keys to be returned
 * for several consecutive calls to read_char, with no screen update
 * in between.  Useful for traversing menus.  */
static char read_key_buffer[INPUT_BUFFER_SIZE];

/* Similar.  Useful for using function key abbreviations.  */
static char read_line_buffer[INPUT_BUFFER_SIZE];

zchar os_read_line (int max, zchar *buf, int timeout, int width, int continued)
{
  char *p;
  int terminator;
  static bool timed_out_last_time;
  int timed_out;

  /* Discard any keys read for single key input.  */
  read_key_buffer[0] = '\0';

  /* After timing out, discard any further input unless we're continuing.  */
  if (timed_out_last_time && !continued)
    read_line_buffer[0] = '\0';

  if (read_line_buffer[0] == '\0')
    timed_out = ui_read_line(read_line_buffer, NULL, TRUE, timeout,
                               buf[0] ? INPUT_LINE_CONTINUED : INPUT_LINE,
                               buf);
  else
    timed_out = 0; // check_timeout(timeout); xxxxx
  
  if (timed_out) {
    timed_out_last_time = TRUE;
    return ZC_TIME_OUT;
  }
    
  /* find the terminating character.  */
  for (p = read_line_buffer;; p++) {
    if (is_terminator(*p)) {
      terminator = *p;
      *p = '\0';
      break;
    }
  }

  /* TODO: Truncate to width and max.  */

  /* copy to screen */
 // iphone_puts(read_line_buffer); // dumb_display_user_input
  /* copy to the buffer and save the rest for next time.  */
  strcat((char*)buf, read_line_buffer);
  p = read_line_buffer + strlen(read_line_buffer) + 1;
  memmove(read_line_buffer, p, strlen(p) + 1);
    
  /* If there was just a newline after the terminating character,
   * don't save it.  */
  if ((read_line_buffer[0] == '\r') && (read_line_buffer[1] == '\0'))
    read_line_buffer[0] = '\0';

  timed_out_last_time = FALSE;
  return terminator;
}

extern char SAVE_PATH[];

void	os_mark_recent_save() {
    iphone_mark_recent_save();
}

int os_read_file_name (char *file_name, const char *default_name, int flag) {
    return iphone_prompt_file_name(file_name, default_name, flag);
}

int iphone_prompt_file_name (char *file_name, const char *default_name, int flag)
{
  char buffer[INPUT_BUFFER_SIZE*2], *buf; // prompt[INPUT_BUFFER_SIZE]
  char *dflt, *ext = NULL, *altext = NULL, *pext;

  if ((dflt = strrchr(default_name, '/'))) // only use filename conpoment in default_name prompt
    dflt++;
  else
    dflt = (char*)default_name;

  strcpy(buffer, SAVE_PATH);
  strcat(buffer, "/");
  buf = buffer + strlen(buffer);
  if (flag == FILE_SAVE || flag == FILE_SAVE_AUX || flag == FILE_RECORD || flag == FILE_PLAYBACK || flag == FILE_SCRIPT) {
    buf[0] = '\0';
    if (!iphone_read_file_name (buf, dflt, flag))
        return FALSE;
    if (!buf[0])
	strcpy(buf, dflt);
    if (!buf[0])
	return FALSE;
    pext = strrchr(buf, '.');
    switch(flag) {
	case FILE_SAVE:
	    ext = ".sav"; altext = ".qut";
	    break;
	case FILE_SAVE_AUX:
	    ext = ".aux";
	    break;
	case FILE_RECORD:
    case FILE_PLAYBACK:
	    ext = ".rec";
	    break;
	case FILE_SCRIPT:
	    ext = ".txt";
	    break;
	default:
	    break;
    }
    if (pext == NULL || (strcmp(pext, ext)!=0 && (!altext || strcmp(pext, altext)!=0)))
	strcat(buf, ext);
  } else {
      buf[0] = '\0';
      if (!iphone_read_file_name (buf, dflt, flag))
         return FALSE;
  }

  if (strlen(buf) > MAX_FILE_NAME) {
    iphone_puts("\nFilename too long!\n");
    return FALSE;
  }
  // restore filenames are abs, save are rel
  strcpy (file_name, buf[0]=='/' ? buf : buffer);

  /* Warn if overwriting a file.  */
#if !FROTZ_IOS_PORT
  FILE *fp;
  if ((flag == FILE_SAVE || flag == FILE_SAVE_AUX || flag == FILE_RECORD)
      && ((fp = fopen(file_name, "rb")) != NULL)) {
    fclose (fp);
    char overwritePrompt[MAX_FILE_NAME + 40];
    char *fn = strrchr(file_name, '/');
    if (fn)
	fn++;
    else
	fn = file_name;
    sprintf(overwritePrompt, "Overwrite existing file \"%s\"? ", fn);
    ui_read_misc_line(buf, overwritePrompt);
    iphone_putchar('\n');
    return(tolower(buf[0]) == 'y');
  }
#endif
  return TRUE;
}

/*
 * os_read_mouse
 *
 * Store the mouse position in the global variables "mouse_x" and
 * "mouse_y" and return the mouse buttons currently pressed.
 *
 */
zword ui_read_mouse (void)
{
	/* INCOMPLETE */
    return 0;
} /* os_read_mouse */




/* What's this? */
/*
 * Local Variables:
 * c-basic-offset: 4
 * End:
 */


#ifdef NO_MEMMOVE
/*
 * This is for operating systems based on 4.2BSD or older or SYSVR3 or
 * older.  Since they lack the memmove(3) system call, it is provided
 * here.  Because I don't have a machine like this to play with, this code
 * is untested.  If you happen to have a spare SunOS 4.1.x install CD 
 * lying around, please consider sending it my way.  Dave.
 *
 */
void *memmove(void *s, void *t, size_t n)
{
	char *p = s; char *q = t;

	if (p < q) {
		while (n--) *p++ = *q++;
	} else {
		p += n; q += n;
		while (n--) *--p = *--q;
	}
}

#endif /* NO_MEMMOVE */
