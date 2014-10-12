/* gtstyle.c: Style formatting hints.
        for GlkIOS, iPhone/IOS implementation of the Glk API.
    Designed by Andrew Plotkin <erkyrath@eblong.com>
    http://www.eblong.com/zarf/glk/index.html
*/

#include "gtoption.h"
#include <stdio.h>
#include <wchar.h>

#include "glk.h"
#include "glkios.h"
#include "ipw_grid.h"
#include "ipw_buf.h"

#include "iphone_frotz.h"

void glk_stylehint_set(glui32 wintype, glui32 styl, glui32 hint, glsi32 val)
{
    gli_stylehint_set(wintype, styl, hint, val);
}

void glk_stylehint_clear(glui32 wintype, glui32 styl, glui32 hint)
{
    gli_stylehint_clear(wintype, styl, hint);
}

glui32 glk_style_distinguish(window_t *win, glui32 styl1, glui32 styl2)
{
    return gli_window_style_distinguish(win, styl1, styl2);
}

glui32 glk_style_measure(window_t *win, glui32 styl, glui32 hint, 
    glui32 *result)
{
#if 0
    int *styleattrs;
    glui32 dummy;

    if (!win) {
        gli_strict_warning(L"style_measure: invalid ref");
        return FALSE;
    }
    
    if (styl >= style_NUMSTYLES || hint >= stylehint_NUMHINTS)
        return FALSE;
    
    switch (win->type) {
#if 0
        case wintype_TextBuffer:
            styleattrs = win_textbuffer_styleattrs;
            break;
        case wintype_TextGrid:
            styleattrs = win_textgrid_styleattrs;
            break;
#endif
        default:
            return FALSE;
    }
    
    if (!result)
        result = &dummy;
    
    switch (hint) {
        case stylehint_Indentation:
        case stylehint_ParaIndentation:
            *result = 0;
            return TRUE;
        case stylehint_Justification:
            *result = stylehint_just_LeftFlush;
            return TRUE;
        case stylehint_Size:
            *result = iphone_fixed_font_height;
            return TRUE;
        case stylehint_Weight:
            *result = 0; //bcs ((styleattrs[styl] & A_BOLD) != 0);
            return TRUE;
        case stylehint_Oblique:
            *result = 0; //bcs ((styleattrs[styl] & A_UNDERLINE) != 0);
            return TRUE;
        case stylehint_Proportional:
            *result = FALSE;
            return TRUE;
    }
#endif
    return FALSE;
}
