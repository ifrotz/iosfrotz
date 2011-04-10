/* gtgestal.c: The Gestalt system
        for GlkIOS, iPhone/IOS implementation of the Glk API.
    Designed by Andrew Plotkin <erkyrath@eblong.com>
    http://www.eblong.com/zarf/glk/index.html
*/

#define _XOPEN_SOURCE /* wcwidth */
#include "gtoption.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <wchar.h>
#include <wctype.h>
#include "glk.h"
#include "glkios.h"

int gli_untypable (glui32 key);

glui32 glk_gestalt(glui32 id, glui32 val)
{
    return glk_gestalt_ext(id, val, NULL, 0);
}

glui32 glk_gestalt_ext(glui32 id, glui32 val, glui32 *arr, glui32 arrlen)
{
    switch (id) {
        
        case gestalt_Version:
            return 0x00000700;
        
        case gestalt_LineInput:
            /*
             * basic text API, the buffer will contain only printable Latin-1 characters (32 to 126, 160 to 255).
             * It is guaranteed to be able to accept the ASCII characters (32 to 126.)
             * never a nonprintable Latin-1 character (0 to 31, 127 to 159)
             */
            return ! ((gli_bad_latin_key(val) || gli_untypable(val)) || (val >=0x100 && iswprint(glui32_to_wchar(val))));
                
        case gestalt_CharInput: 
            /*
             * basic text API, the character code which is returned can be any value from 0 to 255
             * Keycodes (starting backwards from(0xFFFFFFFF) 
             * keycode_Left, keycode_Right, keycode_Up, keycode_Down (arrow keys)
             * keycode_Return (return or enter)
             * keycode_Delete (delete or backspace)
             * keycode_Escape
             * keycode_Tab
             * keycode_PageUp
             * keycode_PageDown
             * keycode_Home
             * keycode_End
             * keycode_Func1, keycode_Func2, keycode_Func3, ... keycode_Func12 (twelve function keys)
             * keycode_Unknown (any key which has no Latin-1 or special code) 
             The arrow keys and return are nearly certain to be available, rest in order of decreasing importance.
             */
         return ! ((gli_bad_latin_key(val) || gli_untypable(val)) || (val >=0x100 && ! (gli_legal_keycode(val) || iswprint(glui32_to_wchar(val)))));

        case gestalt_CharOutput: 
        /* Rules
         * In Latin mode:
         * can print 32 to 126, 160 to 255 and 10.
         * cannot print 0 to 9, 11 to 31, 127 to 159
         * You may not print even common formatting characters such as tab (control-I), carriage return (control-M), or page break (control-L)
         *
         * In Uni mode:
         * gestalt_CharOutput_CannotPrint if ch is an unprintable eight-bit character (0 to 9, 11 to 31, 127 to 159.)
         */
        /* Is providing wcwidth(val) as the number of glyphs advisable?
           As long as usage is limited to deciding how to lay out a grid,
           then it's OK.  But as soon as a user tries to treat a grid 
           containing a character of width==2 as actually containing two 
           half-characters, we're going to have trouble.
         */
            if ( ! (gli_bad_latin_key(val) || (val >= 0x100 && ! iswprint(glui32_to_wchar(val)))) ) {
                int width = wcwidth(glui32_to_wchar(val));
                if (arr && arrlen >= 1) {
                    arr[0] = width;
                }
                if ( width == 1 )
                    return gestalt_CharOutput_ExactPrint;
                else
                    return gestalt_CharOutput_ApproxPrint;
            }
            else {
                   if (arr && arrlen >= 1)
                       arr[0] = 0;
                   return gestalt_CharOutput_CannotPrint;
            }
            
        case gestalt_MouseInput: 
            return FALSE;
            
        case gestalt_Timer: 
#ifdef OPT_TIMED_INPUT
            return TRUE;
#else /* !OPT_TIMED_INPUT */
            return FALSE;
#endif /* OPT_TIMED_INPUT */

        case gestalt_Graphics:
	    return TRUE;
        case gestalt_GraphicsTransparency:
            return FALSE;
            
        case gestalt_DrawImage:
	    if (val == wintype_Graphics)
		return TRUE;
            return FALSE;
            
        case gestalt_Unicode:
#ifdef GLK_MODULE_UNICODE
            return TRUE;
#else
            return FALSE;
#endif /* GLK_MODULE_UNICODE */
            
        case gestalt_Sound:
        case gestalt_SoundVolume:
        case gestalt_SoundNotify: 
        case gestalt_SoundMusic:
            return FALSE;
  
        default:
            return 0;

    }
}

/* Keys that are not typable in this implementation */
int gli_untypable (glui32 key)
{
    /* Many control characters are untypable, for many reasons. */
    switch (key) {
    case keycode_Tab: /* reserved by the input system */
    case L'\t':   /* reserved by the input system */
        case L'\014': /* reserved by the input system */
    case L'\003': /* interrupt/suspend signals */
    case L'\032': /* interrupt/suspend signals */
    case L'\010': /* parsed as keycode_Delete */
    case L'\012': /* parsed as keycode_Return */
    case L'\015': /* parsed as keycode_Return */
    case L'\033': /* parsed as keycode_Escape */
         return TRUE;
        break;
    default:
        return FALSE;
    }
}

