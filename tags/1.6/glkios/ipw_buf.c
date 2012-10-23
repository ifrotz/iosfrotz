/* gtw_buf.c: The buffer window type
        for GlkIOS, iPhone/IOS implementation of the Glk API.
    Designed by Andrew Plotkin <erkyrath@eblong.com>
    http://www.eblong.com/zarf/glk/index.html
*/

#define _XOPEN_SOURCE /* wcwidth */
#include "gtoption.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#include "glk.h"
#include "glkios.h"
#include "ipw_buf.h"

#include "iphone_frotz.h"


/* Maximum buffer size. The slack value is how much larger than the size 
    we should get before we trim. */
#define BUFFER_SIZE (5000)
#define BUFFER_SLACK (1000)

static void final_lines(window_textbuffer_t *dwin, long beg, long end);
static long find_style_by_pos(window_textbuffer_t *dwin, long pos);
static long find_line_by_pos(window_textbuffer_t *dwin, long pos);
static void set_last_run(window_textbuffer_t *dwin, glui32 style);
static void import_input_line(window_textbuffer_t *dwin, void *buf, 
    int unicode, long len);
static void export_input_line(void *buf, int unicode, long len, wchar_t *chars);

window_textbuffer_t *win_textbuffer_create(window_t *win)
{
    window_textbuffer_t *dwin = (window_textbuffer_t *)calloc(sizeof(window_textbuffer_t), 1);
    dwin->owner = win;

    dwin->numchars = 0;
    dwin->charssize = 500;
    dwin->chars = (wchar_t *)malloc(dwin->charssize * sizeof(wchar_t));

    dwin->inbuf = NULL;
    dwin->inunicode = FALSE;
    dwin->incurs = 0;
    dwin->infence = 0;
    dwin->inmax = 1;
    dwin->origstyle = 0;
    dwin->inarrayrock.num = 0;
    
    for (int ix = 0; ix < style_NUMSTYLES; ix++)
        dwin->hints[ix] = win_textbuffer_styleattrs[ix];

    return dwin;
}

void win_textbuffer_destroy(window_textbuffer_t *dwin)
{
    if (dwin->inbuf) {
        if (gli_unregister_arr) {
            char *typedesc = (dwin->inunicode ? "&+#!Iu" : "&+#!Cn");
            (*gli_unregister_arr)(dwin->inbuf, dwin->inmax, typedesc, dwin->inarrayrock);
        }
        dwin->inbuf = NULL;
    }
    
    dwin->owner = NULL;

    if (dwin->chars) {
        free(dwin->chars);
        dwin->chars = NULL;
    }
    free(dwin);
}

void win_textbuffer_rearrange(window_t *win, grect_t *box)
{
    window_textbuffer_t *dwin = win->data;
    dwin->owner->bbox = *box;

#if 0

    dwin->width = box->right - box->left;
    dwin->height = box->bottom - box->top;
#endif
}

void win_textbuffer_redraw(window_t *win)
{
}

void win_textbuffer_update(window_t *win)
{
//    window_textbuffer_t *dwin = win->data;
}

void win_textbuffer_putchar(window_t *win, wchar_t ch)
{
    if (win->iphone_glkViewNum != -1)
        iphone_win_putchar(win->iphone_glkViewNum, ch);
#if 0
    window_textbuffer_t *dwin = win->data;
    long lx;
    
    if (dwin->numchars >= dwin->charssize) {
        dwin->charssize *= 2;
        dwin->chars = (wchar_t *)realloc(dwin->chars, 
            dwin->charssize * sizeof(wchar_t));
    }
    
    lx = dwin->numchars;

    dwin->chars[lx] = ch;
    dwin->numchars++;
#endif
}

/* This assumes that the text is all within the final style run. 
    Convenient, but true, since this is only used by editing in the
    input text. */
static void put_text(window_textbuffer_t *dwin, wchar_t *buf, long len,
    long pos, long oldlen)
{

    long diff = len - oldlen;

    if (dwin->numchars + diff > dwin->charssize) {
        while (dwin->numchars + diff > dwin->charssize)
            dwin->charssize *= 2;
        dwin->chars = (wchar_t *)realloc(dwin->chars, 
            dwin->charssize * sizeof(wchar_t));
    }
    
    if (diff != 0 && pos+oldlen < dwin->numchars) {
        memmove(dwin->chars+(pos+len), dwin->chars+(pos+oldlen), 
            ((dwin->numchars - (pos+oldlen)) * sizeof(wchar_t)));
    }
    if (len > 0) {
        memmove(dwin->chars+pos, buf, len * sizeof(wchar_t));
    }
    dwin->numchars += diff;
    
    if (dwin->inbuf) {
        if (dwin->incurs >= pos+oldlen)
            dwin->incurs += diff;
        else if (dwin->incurs >= pos)
            dwin->incurs = pos+len;
    }
}

void win_textbuffer_clear(window_t *win)
{
    window_textbuffer_t *dwin = win->data;
    dwin->numchars = 0;

    iphone_erase_win(win->iphone_glkViewNum);
}

void win_textbuffer_trim_buffer(window_t *win)
{
//    window_textbuffer_t *dwin = win->data;
#if 0
    long trimsize;
    long lnum, snum, cnum;
    long lx, wx, rx;
    tbline_t *ln;
    
    if (dwin->numchars <= BUFFER_SIZE + BUFFER_SLACK)
        return; 
        
    /* We need to knock BUFFER_SLACK chars off the beginning of the buffer, if
        such are conveniently available. */
        
    trimsize = dwin->numchars - BUFFER_SIZE;
    if (dwin->dirtybeg != -1 && trimsize > dwin->dirtybeg)
        trimsize = dwin->dirtybeg;
    if (dwin->inbuf && trimsize > dwin->infence) 
        trimsize = dwin->infence;
    
    lnum = find_line_by_pos(dwin, trimsize);
    if (lnum <= 0)
        return;
    /* The trimsize point is at the beginning of lnum, or inside it. So lnum
        will be the first remaining line. */
        
    ln = &(dwin->lines[lnum]);
    cnum = ln->pos;
    if (cnum <= 0)
        return;
    snum = find_style_by_pos(dwin, cnum);
    
    /* trim chars */
    
    if (dwin->numchars > cnum)
        memmove(dwin->chars, &(dwin->chars[cnum]), 
            (dwin->numchars - cnum) * sizeof(wchar_t));
    dwin->numchars -= cnum;

    if (dwin->dirtybeg == -1) {
        /* nothing dirty; leave it that way. */
    }
    else {
        /* dirty region is after the chunk; quietly slide it back. We already
            know that (dwin->dirtybeg >= cnum). */
        dwin->dirtybeg -= cnum;
        dwin->dirtyend -= cnum;
    }
    
    /* trim runs */
    
    if (snum >= dwin->numruns) {
        short sstyle = dwin->runs[snum].style;
        dwin->runs[0].style = sstyle;
        dwin->runs[0].pos = 0;
        dwin->numruns = 1;
    }
    else {
        for (rx=snum; rx<dwin->numruns; rx++) {
            tbrun_t *srun2 = &(dwin->runs[rx]);
            if (srun2->pos >= cnum)
                srun2->pos -= cnum;
            else
                srun2->pos = 0;
        }
        memmove(dwin->runs, &(dwin->runs[snum]), 
            (dwin->numruns - snum) * sizeof(tbrun_t));
        dwin->numruns -= snum;
    }
    
    /* trim lines */
    
    final_lines(dwin, 0, lnum);
    for (lx=lnum; lx<dwin->numlines; lx++) {
        tbline_t *ln2 = &(dwin->lines[lx]);
        ln2->pos -= cnum;
        for (wx=0; wx<ln2->numwords; wx++) {
            tbword_t *wd = &(ln2->words[wx]);
            wd->pos -= cnum;
        }
    }

    if (lnum < dwin->numlines)
        memmove(&(dwin->lines[0]), &(dwin->lines[lnum]), 
            (dwin->numlines - lnum) * sizeof(tbline_t));
    dwin->numlines -= lnum;

    /* trim all the other assorted crap */

    if (dwin->inbuf) {
        /* there's pending line input */
        dwin->infence -= cnum;
        dwin->incurs -= cnum;
    }
    if (dwin->scrollpos > cnum) {
        dwin->scrollpos -= cnum;
    }
    else {
        dwin->scrollpos = 0;
        dwin->drawall = TRUE;
    }
    
    if (dwin->scrollline > lnum) 
        dwin->scrollline -= lnum;
    else 
        dwin->scrollline = 0;

    if (dwin->lastseenline > lnum) 
        dwin->lastseenline -= lnum;
    else 
        dwin->lastseenline = 0;

    if (dwin->scrollline > dwin->numlines - dwin->height)
        dwin->scrollline = dwin->numlines - dwin->height;
    if (dwin->scrollline < 0)
        dwin->scrollline = 0;
#endif
}

void win_textbuffer_place_cursor(window_t *win, int *xpos, int *ypos)
{
//    window_textbuffer_t *dwin = win->data;

    if (win->line_request) {
        /* figure out where the input cursor is. */
#if 0
        long lx = find_line_by_pos(dwin, dwin->incurs);
        if (lx < 0 || lx - dwin->scrollline < 0) {
            *ypos = 0;
            *xpos = 0;
        }
        else if (lx - dwin->scrollline >= dwin->height) {
            *ypos = dwin->height - 1;
            *xpos = dwin->width - 1;
        }
        else {
            *ypos = lx - dwin->scrollline;
            *xpos = wcswidth(dwin->chars + dwin->lines[lx].pos, dwin->incurs - dwin->lines[lx].pos);
            if (*xpos >= dwin->width)
                *xpos = dwin->width-1
        }
#endif
    }
    else {
#if 0
        /* put the cursor at the end of the text. */
        long lx = dwin->numlines - 1;
        if (lx < 0 || lx - dwin->scrollline < 0) {
            *ypos = 0;
            *xpos = 0;
        }
        else if (lx - dwin->scrollline >= dwin->height) {
            *ypos = dwin->height - 1;
            *xpos = dwin->width - 1;
        }
        else {
            *ypos = lx - dwin->scrollline;
            *xpos = wcswidth(dwin->chars + dwin->lines[lx].pos, dwin->lines[lx].len);
            if (*xpos >= dwin->width)
                *xpos = dwin->width-1;
        }
#endif
    }
}

void win_textbuffer_set_paging(window_t *win, int forcetoend)
{
}

/* Prepare the window for line input. */
void win_textbuffer_init_line(window_t *win, void *buf, int unicode, 
    int maxlen, int initlen)
{
    window_textbuffer_t *dwin = win->data;
    win->style = style_Input;
    dwin->numchars = 0; // bcs
    dwin->inbuf = buf;
    dwin->inunicode = unicode;
    dwin->inmax = maxlen;
    dwin->infence = dwin->numchars;
    dwin->incurs = dwin->numchars;
    dwin->origstyle = win->style;
#if 0
    set_last_run(dwin, win->style);
    dwin->historypos = dwin->historypresent;
#endif
    
    if (initlen) {
        import_input_line(dwin, dwin->inbuf, dwin->inunicode, initlen);
    }
    if (gli_register_arr) {
        char *typedesc = (dwin->inunicode ? "&+#!Iu" : "&+#!Cn");
        dwin->inarrayrock = (*gli_register_arr)(dwin->inbuf, maxlen, typedesc);
    }
}

/* Abort line input, storing whatever's been typed so far. */
void win_textbuffer_cancel_line(window_t *win, event_t *ev)
{
    long len;
    void *inbuf;
    int inmax, inunicode;
    gidispatch_rock_t inarrayrock;
    window_textbuffer_t *dwin = win->data;

    if (!dwin->inbuf)
        return;

    inbuf = dwin->inbuf;
    inmax = dwin->inmax;
    inarrayrock = dwin->inarrayrock;
    inunicode = dwin->inunicode;

    len = dwin->charssize - dwin->infence;

    /* Store in event buffer. */
        
    if (len > inmax)
        len = inmax;
    len = iphone_peek_inputline(&dwin->chars[dwin->infence], len);
        
    export_input_line(inbuf, inunicode, len, &dwin->chars[dwin->infence]);

    if (win->echostr) {
        if ( inunicode )
            gli_stream_echo_line_uni(win->echostr, inbuf, len);
        else
            gli_stream_echo_line(win->echostr, inbuf, len);
    }
        
    win->style = dwin->origstyle;
//    set_last_run(dwin, win->style);

    ev->type = evtype_LineInput;
    ev->win = win;
    ev->val1 = len;
    
    win->line_request = FALSE;
    dwin->inbuf = NULL;
    dwin->inmax = 0;
    
    //win_textbuffer_putchar(win, L'\n');

    if (gli_unregister_arr) {
        char *typedesc = (inunicode ? "&+#!Iu" : "&+#!Cn");
        (*gli_unregister_arr)(inbuf, inmax, typedesc, inarrayrock);
    }
}

static void import_input_line(window_textbuffer_t *dwin, void *buf, 
    int unicode, long len)
{
    /* len will be nonzero. */

    if (unicode) {
        if (dwin->owner->iphone_glkViewNum != -1)
            iphone_set_input_line(buf, len);
        //put_text(dwin, buf, len, dwin->incurs, 0);
    }
    else {
        int ix;
        wchar_t *cx = (wchar_t *)malloc((len+1) * sizeof(wchar_t));
        for (ix=0; ix<len; ix++) {
            cx[ix] = UCS(((char *)buf)[ix]);
        }
        cx[ix] = 0;
        if (dwin->owner->iphone_glkViewNum != -1)
            iphone_set_input_line(cx, len);
        //put_text(dwin, cx, len, dwin->incurs, 0);
        free(cx);
    }
}

/* Clone in gtw_grid.c */
static void export_input_line(void *buf, int unicode, long len, wchar_t *chars)
{
    int ix;

    if (!unicode) {
        for (ix=0; ix<len; ix++) {
            glui32 val = wchar_to_glui32(chars[ix]);
            ((char *)buf)[ix] = Lat(val);
        }
    }
    else {
        for (ix=0; ix<len; ix++) {
            glui32 val = wchar_to_glui32(chars[ix]);
            ((glui32 *)buf)[ix] = val;
        }
    }
}

/* Keybinding functions. */

/* Any key, during character input. Ends character input. */
void gcmd_buffer_accept_key(window_t *win, glui32 arg)
{
    win->char_request = FALSE; 
    arg = gli_input_from_native(arg);
    gli_event_store(evtype_CharInput, win, arg, 0);
}

/* Return or enter, during line input. Ends line input. */
void gcmd_buffer_accept_line(window_t *win, glui32 arg)
{
    long len;
//    wchar_t *cx;
    void *inbuf;
    int inmax, inunicode;
    gidispatch_rock_t inarrayrock;
    window_textbuffer_t *dwin = win->data;

    if (!dwin->inbuf)
        return;
    
    inbuf = dwin->inbuf;
    inmax = dwin->inmax;
    inarrayrock = dwin->inarrayrock;
    inunicode = dwin->inunicode;

    len = dwin->numchars - dwin->infence;

    /* Store in event buffer. */
        
    if (len > inmax)
        len = inmax;
        
    export_input_line(inbuf, inunicode, len, &dwin->chars[dwin->infence]);

    if (win->echostr) {
        if ( inunicode )
            gli_stream_echo_line_uni(win->echostr, inbuf, len);
        else
            gli_stream_echo_line(win->echostr, inbuf, len);
    }
    
    win->style = dwin->origstyle;
//    set_last_run(dwin, win->style);

    gli_event_store(evtype_LineInput, win, len, 0);
    win->line_request = FALSE;
    dwin->inbuf = NULL;
    dwin->inmax = 0;
        
    win_textbuffer_putchar(win, L'\n');

    if (gli_unregister_arr) {
        char *typedesc = (inunicode ? "&+#!Iu" : "&+#!Cn");
        (*gli_unregister_arr)(inbuf, inmax, typedesc, inarrayrock);
    }
}

/* Any regular key, during line input. */
void gcmd_buffer_insert_key(window_t *win, glui32 arg)
{
    window_textbuffer_t *dwin = win->data;
    wchar_t ch = glui32_to_wchar(arg);
    
    if (!dwin->inbuf)
        return;

    put_text(dwin, &ch, 1, dwin->incurs, 0);

//bcs    updatetext(dwin);
}

/* Cursor movement keys, during line input. */
void gcmd_buffer_move_cursor(window_t *win, glui32 arg)
{
//    window_textbuffer_t *dwin = win->data;
}

/* Delete keys, during line input. */
void gcmd_buffer_delete(window_t *win, glui32 arg)
{
//    window_textbuffer_t *dwin = win->data;
//    updatetext(dwin);
}

/* Command history, during line input. */
void gcmd_buffer_history(window_t *win, glui32 arg)
{
//    window_textbuffer_t *dwin = win->data;
//    updatetext(dwin);
}

/* Scrolling keys, at all times. */
void gcmd_buffer_scroll(window_t *win, glui32 arg)
{
}

GLK_STYLE_HINTS win_textbuffer_styleattrs[style_NUMSTYLES];

void win_textbuffer_stylehint_set(glui32 styl, glui32 hint, glsi32 val)
{
    if (styl < style_NUMSTYLES) {
//      fd("BUFF styl: %ld, hint: %ld, val: %lX", styl, hint, val);
        switch (hint) {
            case stylehint_Indentation:
                win_textbuffer_styleattrs[styl].indentation = val;
                win_textbuffer_styleattrs[styl].styleSetMask |= kGlkStyleIndentationMask;
            break;
            case stylehint_ParaIndentation:
                win_textbuffer_styleattrs[styl].paraIndentation = val;            
                win_textbuffer_styleattrs[styl].styleSetMask |= kGlkStyleParaIndentationMask;
            break;
            case stylehint_Justification:
                win_textbuffer_styleattrs[styl].justification = val;
                win_textbuffer_styleattrs[styl].styleSetMask |= kGlKStyleJustificationMask;
            break;
            case stylehint_Size:
                win_textbuffer_styleattrs[styl].size = val;
                win_textbuffer_styleattrs[styl].styleSetMask |= kGlkStyleSizeMask;
            break;
            case stylehint_Weight:
                win_textbuffer_styleattrs[styl].weight = val;
                win_textbuffer_styleattrs[styl].styleSetMask |= kGlkStyleWeightMask;
            break;
            case stylehint_Oblique:
                win_textbuffer_styleattrs[styl].oblique = val;
                win_textbuffer_styleattrs[styl].styleSetMask |= kGlkStyleObliqueMask;
            break;
            case stylehint_Proportional:
                win_textbuffer_styleattrs[styl].proportional = val;
                win_textbuffer_styleattrs[styl].styleSetMask |= kGlkStyleProportionalMask;
            break;
            case stylehint_TextColor:
                win_textbuffer_styleattrs[styl].textColor = val;
                win_textbuffer_styleattrs[styl].styleSetMask |= kGlkStyleTextColorMask;
            break;
            case stylehint_BackColor:
                win_textbuffer_styleattrs[styl].backColor = val;
                win_textbuffer_styleattrs[styl].styleSetMask |= kGlKStyleBackColorMask;
            break;
            case stylehint_ReverseColor:
                win_textbuffer_styleattrs[styl].reverseColor = val;
                win_textbuffer_styleattrs[styl].styleSetMask |= kGlKStyleRevertColorMask;
            break;
        }
    }
}

void win_textbuffer_stylehint_clear(glui32 styl, glui32 hint)
{
    if (styl < style_NUMSTYLES) {
        switch (hint) {
            case stylehint_Indentation:
                win_textbuffer_styleattrs[styl].styleSetMask &= ~kGlkStyleIndentationMask;
            break;
            case stylehint_ParaIndentation:
                win_textbuffer_styleattrs[styl].styleSetMask &= ~kGlkStyleParaIndentationMask;
            break;
            case stylehint_Justification:
                win_textbuffer_styleattrs[styl].styleSetMask &= ~kGlKStyleJustificationMask;
            break;
            case stylehint_Size:
                win_textbuffer_styleattrs[styl].styleSetMask &= ~kGlkStyleSizeMask;
            break;
            case stylehint_Weight:
                win_textbuffer_styleattrs[styl].styleSetMask &= ~kGlkStyleWeightMask;
            break;
            case stylehint_Oblique:
                win_textbuffer_styleattrs[styl].styleSetMask &= ~kGlkStyleObliqueMask;
            break;
            case stylehint_Proportional:
                win_textbuffer_styleattrs[styl].styleSetMask &= ~kGlkStyleProportionalMask;
            break;
            case stylehint_TextColor:
                win_textbuffer_styleattrs[styl].styleSetMask &= ~kGlkStyleTextColorMask;
            break;
            case stylehint_BackColor:
                win_textbuffer_styleattrs[styl].styleSetMask &= ~kGlKStyleBackColorMask;
            break;
            case stylehint_ReverseColor:
                win_textbuffer_styleattrs[styl].styleSetMask &= ~kGlKStyleRevertColorMask;
            break;
        }
    }
}

glui32 win_textbuffer_stylehint_get(window_t *win, glui32 styl, glui32 hint)
{
    window_textbuffer_t *dwin = win->data;

    if (styl < style_NUMSTYLES) {
        switch (hint) {
            case stylehint_Indentation:
            case stylehint_ParaIndentation:
            case stylehint_Size:
            case stylehint_Weight:
            case stylehint_Oblique:
                return 0;
                break;
            case stylehint_Justification:
                if (dwin->hints[styl].styleSetMask & kGlkStyleProportionalMask)
                    return dwin->hints[styl].justification;
                else
                    return 0;
                break;
            case stylehint_Proportional:
                if (dwin->hints[styl].styleSetMask & kGlkStyleProportionalMask)
                    return dwin->hints[styl].proportional;
                else
                    return BAD_STYLE;
            break;
            case stylehint_TextColor:
                if (dwin->hints[styl].styleSetMask & kGlkStyleTextColorMask)
                    return dwin->hints[styl].textColor;
                else
                    return BAD_STYLE;
            break;
            case stylehint_BackColor:
                if (dwin->hints[styl].styleSetMask & kGlKStyleBackColorMask)
                    return dwin->hints[styl].backColor;
                else
                    return BAD_STYLE;
            break;
            case stylehint_ReverseColor:
                if (dwin->hints[styl].styleSetMask & kGlKStyleRevertColorMask)
                    return dwin->hints[styl].reverseColor;
                else
                    return BAD_STYLE;
            break;
        }
    }
    return BAD_STYLE;
}

void win_textbuffer_set_stylehints(window_t *win, GLK_STYLE_HINTS *hints)
{
    int i;
     
    if ((glui32)win == STYLEHINT_TEXT_BUFFER) {
        for (i = 0; i < style_NUMSTYLES; i++) {
            win_textbuffer_styleattrs[i] = hints[i];
        }
    } else {
       window_textbuffer_t *dwin = win->data;
        for (i = 0; i < style_NUMSTYLES; i++) {
            dwin->hints[i] = hints[i];
        }
    }
}

void win_textbuffer_get_stylehints(window_t *win, GLK_STYLE_HINTS *hints)
{
    int i;
    
    if ((glui32)win == STYLEHINT_TEXT_BUFFER) {
        for (i = 0; i < style_NUMSTYLES; i++) {
            hints[i] = win_textbuffer_styleattrs[i];
        }
    } else {
        window_textbuffer_t *dwin = win->data;
        for (i = 0; i < style_NUMSTYLES; i++) {
            hints[i] = dwin->hints[i];
        }
    }
}

glui32 win_textbuffer_style_distinguish(window_t *win, glui32 styl1, glui32 styl2)
{
#if 0
    window_textbuffer_t *dwin = win->data;

    GLK_STYLE_HINTS *hints1, *hints2;
    unsigned short st1, st2;
    
    if (styl1 >= style_Normal && styl1 < style_NUMSTYLES && styl2 >= style_Normal && styl2 < style_NUMSTYLES) {
        // check basic params
        st1 = os_translate_style(styl1, win->fid);
        st2 = os_translate_style(styl2, win->fid);
        if (st1 != st2)
            return TRUE;
        // check colors
        hints1 = dwin->hints + styl1;
        hints2 = dwin->hints + styl2;
        
        if (hints1->textColor_set || hints2->textColor_set) {
            if (hints1->textColor != hints2->textColor)
                return TRUE;
        }
        
        if (hints1->backColor_set || hints2->backColor_set) {
            if (hints1->backColor != hints2->backColor)
                return TRUE;
        }
        
        if (hints1->reverseColor_set || hints2->reverseColor_set) {
            if (hints1->reverseColor != hints2->reverseColor)
                return TRUE;
        }
    }
#endif
    return FALSE;
}

