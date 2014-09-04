/* gtstream.c: Stream objects
 for GlkIOS, iPhone/IOS implementation of the Glk API.
 Designed by Andrew Plotkin <erkyrath@eblong.com>
 http://www.eblong.com/zarf/glk/index.html
 */

#include "gtoption.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include "glk.h"
#include "glkios.h"
#include "gi_blorb.h"
#include "iphone_frotz.h"
#include "RichTextStyle.h"

/* This implements pretty much what any Glk implementation needs for 
 stream stuff. Memory streams, file streams (using stdio functions), 
 and window streams (which print through window functions in other
 files.) A different implementation would change the window stream
 stuff, but not file or memory streams. (Unless you're on a 
 wacky platform like the Mac and want to change stdio to native file 
 functions.) 
 */

static stream_t *gli_streamlist = NULL; /* linked list of all streams */
static stream_t *gli_currentstr = NULL; /* the current output stream */

stream_t *gli_new_stream(int type, int readable, int writable, 
                         glui32 rock)
{
    stream_t *str = (stream_t *)malloc(sizeof(stream_t));
    if (!str)
        return NULL;
    
    str->magicnum = MAGIC_STREAM_NUM;
    str->type = type;
    str->rock = rock;
    
    str->unicode = FALSE;
    
    str->win = NULL;

    str->file = NULL;
    str->fileRef = NULL;
    str->lastop = 0;
    /* for strtype_Resource */
    str->isbinary = FALSE;

    str->buf = NULL;
    str->bufptr = NULL;
    str->bufend = NULL;
    str->bufeof = NULL;
    str->ubuf = NULL;
    str->ubufptr = NULL;
    str->ubufend = NULL;
    str->ubufeof = NULL;
    str->buflen = 0;
    
    str->readcount = 0;
    str->writecount = 0;
    str->readable = readable;
    str->writable = writable;
    str->arrayrock.ptr = NULL;
    str->store = 0;
    
    str->prev = NULL;
    str->next = gli_streamlist;
    gli_streamlist = str;
    if (str->next) {
        str->next->prev = str;
    }
    
    if (gli_register_obj)
        str->disprock = (*gli_register_obj)(str, gidisp_Class_Stream);
    else
        str->disprock.ptr = NULL;
    
    return str;
}

void gli_delete_stream(stream_t *str)
{
    stream_t *prev, *next;
    
    if (str == gli_currentstr) {
        gli_currentstr = NULL;
    }
    
    gli_windows_unechostream(str);
    
    str->magicnum = 0;
    
    switch (str->type) {
        case strtype_Window:
            /* nothing necessary; the window is already being closed */
            break;
        case strtype_Memory: 
            if (gli_unregister_arr) {
                /* This could be a char array or a glui32 array. */
                char *typedesc = (str->unicode ? "&+#!Iu" : "&+#!Cn");
                void *buf = (str->unicode ? (void*)str->ubuf : (void*)str->buf);
                (*gli_unregister_arr)(buf, str->buflen, typedesc,
                                      str->arrayrock);
            }
            break;
        case strtype_Resource:
            /* nothing necessary; the array belongs to gi_blorb.c. */
            break;
        case strtype_File:
            /* close the FILE */
            fclose(str->file);
            str->file = NULL;
            str->lastop = 0;
            break;
    }
    
    if (gli_unregister_obj) {
        (*gli_unregister_obj)(str, gidisp_Class_Stream, str->disprock);
        str->disprock.ptr = NULL;
    }
    
    prev = str->prev;
    next = str->next;
    str->prev = NULL;
    str->next = NULL;
    
    if (prev)
        prev->next = next;
    else
        gli_streamlist = next;
    if (next)
        next->prev = prev;
    
    free(str);
}

void gli_stream_fill_result(stream_t *str, stream_result_t *result)
{
    if (!result)
        return;
    
    result->readcount = str->readcount;
    result->writecount = str->writecount;
}

void glk_stream_close(stream_t *str, stream_result_t *result)
{
    if (!str) {
        gli_strict_warning(L"stream_close: invalid ref.");
        return;
    }
    
    if (str->type == strtype_Window) {
        gli_strict_warning(L"stream_close: cannot close window stream");
        return;
    }
    
    gli_stream_fill_result(str, result);
    gli_delete_stream(str);
}

void gli_streams_close_all()
{
    /* This is used only at shutdown time; it closes file streams (the
     only ones that need finalization.) */
    stream_t *str, *strnext;
    
    str=gli_streamlist;
    while (str) {
        strnext = str->next;
        
        if (str->type == strtype_File) {
            gli_delete_stream(str);
        }
        
        str = strnext;
    }
}

strid_t glk_stream_open_memory(char *buf, glui32 buflen, glui32 fmode, 
                               glui32 rock)
{
    stream_t *str;
    
    if (fmode != filemode_Read 
        && fmode != filemode_Write 
        && fmode != filemode_ReadWrite) {
        gli_strict_warning(L"stream_open_memory: illegal filemode");
        return 0;
    }
    
    str = gli_new_stream(strtype_Memory, 
                         (fmode != filemode_Write), 
                         (fmode != filemode_Read), 
                         rock);
    if (!str) {
        gli_strict_warning(L"stream_open_memory: unable to create stream.");
        return 0;
    }
    
    if (buf && buflen) {
        str->buf = (unsigned char *)buf;
        str->bufptr = (unsigned char *)buf;
        str->buflen = buflen;
        str->bufend = str->buf + str->buflen;
        if (fmode == filemode_Write)
            str->bufeof = (unsigned char *)buf;
        else
            str->bufeof = str->bufend;
        if (gli_register_arr) {
            str->arrayrock = (*gli_register_arr)(buf, buflen, "&+#!Cn");
        }
    }
    
    return str;
}

stream_t *gli_stream_open_window(window_t *win)
{
    stream_t *str;
    
    str = gli_new_stream(strtype_Window, FALSE, TRUE, 0);
    if (!str)
        return NULL;
    
    str->win = win;
    
    return str;
}

strid_t glk_stream_open_file(fileref_t *fref, glui32 fmode,
                             glui32 rock)
{
    stream_t *str;
    char modestr[16];
    FILE *fl;
    
    if (!fref || !fref->filename || !fref->filename[0]) {
        gli_strict_warning(L"stream_open_file: invalid fileref ref.");
        return 0;
    }
    
    /* The spec says that Write, ReadWrite, and WriteAppend create the
     file if necessary. However, fopen(filename, "r+") doesn't create
     a file. So we have to pre-create it in the ReadWrite and
     WriteAppend cases. (We use "a" so as not to truncate, and "b" 
     because we're going to close it immediately, so it doesn't matter.) */

    /* Another Unix quirk: in r+ mode, you're not supposed to flip from
       reading to writing or vice versa without doing an fseek. We will
       track the most recent operation (as lastop) -- Write, Read, or
       0 if either is legal next. */

    if (fmode == filemode_ReadWrite || fmode == filemode_WriteAppend) {
        fl = fopen(fref->filename, "ab");
        if (!fl) {
            gli_strict_warning(L"stream_open_file: unable to open file.");
            return 0;
        }
        
        fclose(fl);
    }
    
    switch (fmode) {
        case filemode_Write:
            strcpy(modestr, "w");
            break;
        case filemode_Read:
            strcpy(modestr, "r");
            break;
        case filemode_ReadWrite:
            strcpy(modestr, "r+");
            break;
        case filemode_WriteAppend:
            /* Can't use "a" here, because then fseek wouldn't work.
             Instead we use "r+" and then fseek to the end. */
            strcpy(modestr, "r+");
            break;
    }
    
    if (!fref->textmode)
        strcat(modestr, "b");
    
    fl = fopen(fref->filename, modestr);
    if (!fl) {
        gli_strict_warning(L"stream_open_file: unable to open file.");
        return 0;
    }
    if (fref->textmode)
        setlinebuf(fl);
    
    if (fmode == filemode_WriteAppend) {
        fseek(fl, 0, 2); /* ...to the end. */
    }
    
    str = gli_new_stream(strtype_File, 
                         (fmode == filemode_Read || fmode == filemode_ReadWrite), 
                         !(fmode == filemode_Read), 
                         rock);
    if (!str) {
        gli_strict_warning(L"stream_open_file: unable to create stream.");
        fclose(fl);
        return 0;
    }
    
    str->file = fl;
    str->fileRef = fref;
    str->lastop = 0;

    return str;
}

#ifdef GLK_MODULE_UNICODE

strid_t glk_stream_open_memory_uni(glui32 *ubuf, glui32 buflen, glui32 fmode, 
                                   glui32 rock)
{
    stream_t *str;
    
    if (fmode != filemode_Read 
        && fmode != filemode_Write 
        && fmode != filemode_ReadWrite) {
        gli_strict_warning(L"stream_open_memory_uni: illegal filemode");
        return NULL;
    }
    
    str = gli_new_stream(strtype_Memory, 
                         (fmode != filemode_Write), 
                         (fmode != filemode_Read), 
                         rock);
    if (!str) {
        gli_strict_warning(L"stream_open_memory_uni: unable to create stream.");
        return NULL;
    }
    
    str->unicode = TRUE;
    
    if (ubuf && buflen) {
        str->ubuf = ubuf;
        str->ubufptr = ubuf;
        str->buflen = buflen;
        str->ubufend = str->ubuf + str->buflen;
        if (fmode == filemode_Write)
            str->ubufeof = ubuf;
        else
            str->ubufeof = str->ubufend;
        if (gli_register_arr) {
            str->arrayrock = (*gli_register_arr)(ubuf, buflen, "&+#!Iu");
        }
    }
    
    return str;
}

strid_t glk_stream_open_file_uni(fileref_t *fref, glui32 fmode,
                                 glui32 rock)
{
    strid_t str = glk_stream_open_file(fref, fmode, rock);
    /* Unlovely, but it works in this library */
    str->unicode = TRUE;
    return str;
}

#endif /* GLK_MODULE_UNICODE */

#ifdef GLK_MODULE_RESOURCE_STREAM

strid_t glk_stream_open_resource(glui32 filenum, glui32 rock)
{
    strid_t str;
    int isbinary;
    giblorb_err_t err;
    giblorb_result_t res;
    giblorb_map_t *map = giblorb_get_resource_map();
    if (!map)
        return 0; /* Not running from a blorb file */

    err = giblorb_load_resource(map, giblorb_method_Memory, &res, giblorb_ID_Data, filenum);
    if (err)
        return 0; /* Not found, or some other error */

    /* We'll use the in-memory copy of the chunk data as the basis for
       our new stream. It's important to not call chunk_unload() until
       the stream is closed (and we won't).

       This will be memory-hoggish for giant data chunks, but I don't
       expect giant data chunks at this point. A more efficient model
       would be to use the file on disk, but this requires some hacking
       into the file stream code (we'd need to open a new FILE*) and
       I don't feel like doing that. */

    if (res.chunktype == giblorb_ID_TEXT)
        isbinary = FALSE;
    else if (res.chunktype == giblorb_ID_BINA
        || res.chunktype == giblorb_make_id('F', 'O', 'R', 'M'))
        isbinary = TRUE;
    else
        return 0; /* Unknown chunk type */

    str = gli_new_stream(strtype_Resource,
        TRUE, FALSE, rock);
    if (!str) {
        gli_strict_warning(L"stream_open_resource: unable to create stream.");
        return NULL;
    }

    str->isbinary = isbinary;
    
    if (res.data.ptr && res.length) {
        str->buf = (unsigned char *)res.data.ptr;
        str->bufptr = (unsigned char *)res.data.ptr;
        str->buflen = res.length;
        str->bufend = str->buf + str->buflen;
        str->bufeof = str->bufend;
    }
    
    return str;
}

strid_t glk_stream_open_resource_uni(glui32 filenum, glui32 rock)
{
    strid_t str;
    int isbinary;
    giblorb_err_t err;
    giblorb_result_t res;
    giblorb_map_t *map = giblorb_get_resource_map();
    if (!map)
        return 0; /* Not running from a blorb file */

    err = giblorb_load_resource(map, giblorb_method_Memory, &res, giblorb_ID_Data, filenum);
    if (err)
        return 0; /* Not found, or some other error */

    if (res.chunktype == giblorb_ID_TEXT)
        isbinary = FALSE;
    else if (res.chunktype == giblorb_ID_BINA
        || res.chunktype == giblorb_make_id('F', 'O', 'R', 'M'))
        isbinary = TRUE;
    else
        return 0; /* Unknown chunk type */

    str = gli_new_stream(strtype_Resource,
        TRUE, FALSE, rock);
    if (!str) {
        gli_strict_warning(L"stream_open_resource_uni: unable to create stream.");
        return NULL;
    }
    
    str->unicode = TRUE;
    str->isbinary = isbinary;

    /* We have been handed an array of bytes. (They're big-endian
       four-byte chunks, or perhaps a UTF-8 byte sequence, rather than
       native-endian four-byte integers). So we drop it into buf,
       rather than ubuf -- we'll have to do the translation in the
       get() functions. */

    if (res.data.ptr && res.length) {
        str->buf = (unsigned char *)res.data.ptr;
        str->bufptr = (unsigned char *)res.data.ptr;
        str->buflen = res.length;
        str->bufend = str->buf + str->buflen;
        str->bufeof = str->bufend;
    }

    return str;
}

#endif /* GLK_MODULE_RESOURCE_STREAM */

strid_t gli_stream_open_pathname(char *pathname, int writemode,
    int textmode, glui32 rock)
{
    char modestr[16];
    stream_t *str;
    FILE *fl;

    if (!writemode)
        strcpy(modestr, "r");
    else
        strcpy(modestr, "w");
    if (!textmode)
        strcat(modestr, "b");
    
    fl = fopen(pathname, modestr);
    if (!fl) {
        return 0;
    }
    
    str = gli_new_stream(strtype_File, 
                         !writemode, writemode, rock);
    if (!str) {
        fclose(fl);
        return 0;
    }
    
    str->file = fl;
    str->fileRef = NULL;
    str->lastop = 0;
    
    return str;
}

strid_t glk_stream_iterate(strid_t str, glui32 *rock)
{
    if (!str) {
        str = gli_streamlist;
    }
    else {
        str = str->next;
    }
    
    if (str) {
        if (rock)
            *rock = str->rock;
        return str;
    }
    
    if (rock)
        *rock = 0;
    return NULL;
}

glui32 glk_stream_get_rock(stream_t *str)
{
    if (!str) {
        gli_strict_warning(L"stream_get_rock: invalid ref.");
        return 0;
    }
    
    return str->rock;
}

void gli_stream_set_current(stream_t *str)
{
    gli_currentstr = str;
}

void glk_stream_set_current(stream_t *str)
{
    gli_stream_set_current(str);
}

strid_t glk_stream_get_current()
{
    return gli_currentstr;
}

void glk_stream_set_position(stream_t *str, glsi32 pos, glui32 seekmode)
{
    if (!str) {
        gli_strict_warning(L"stream_set_position: invalid ref");
        return;
    }
    
    switch (str->type) {
        case strtype_Memory:
        case strtype_Resource:
            if (!str->unicode || str->type == strtype_Resource) {
                if (seekmode == seekmode_Current) {
                    pos = (str->bufptr - str->buf) + pos;
                }
                else if (seekmode == seekmode_End) {
                    pos = (str->bufeof - str->buf) + pos;
                }
                else {
                    /* pos = pos */
                }
                if (pos < 0)
                    pos = 0;
                if (pos > (str->bufeof - str->buf))
                    pos = (str->bufeof - str->buf);
                str->bufptr = str->buf + pos;
            }
            else {
                if (seekmode == seekmode_Current) {
                    pos = (str->ubufptr - str->ubuf) + pos;
                }
                else if (seekmode == seekmode_End) {
                    pos = (str->ubufeof - str->ubuf) + pos;
                }
                else {
                    /* pos = pos */
                }
                if (pos < 0)
                    pos = 0;
                if (pos > (str->ubufeof - str->ubuf))
                    pos = (str->ubufeof - str->ubuf);
                str->ubufptr = str->ubuf + pos;
            }
            break;
        case strtype_Window:
            /* do nothing; don't pass to echo stream */
            break;
        case strtype_File:
            /* Either reading or writing is legal after an fseek. */
            str->lastop = 0;
            if (str->unicode) {
                /* Use 4 here, rather than sizeof(glui32). */
                pos *= 4;
            }
            fseek(str->file, pos, 
                  ((seekmode == seekmode_Current) ? 1 :
                   ((seekmode == seekmode_End) ? 2 : 0)));
            break;
    }   
}

glui32 glk_stream_get_position(stream_t *str)
{
    if (!str) {
        gli_strict_warning(L"stream_get_position: invalid ref");
        return 0;
    }
    
    switch (str->type) {
        case strtype_Memory:
        case strtype_Resource:
            if (!str->unicode || str->type == strtype_Resource) {
                return (str->bufptr - str->buf);
            }
            else {
                return (str->ubufptr - str->ubuf);
            }
        case strtype_File:
            if (!str->unicode) {
                return ftell(str->file);
            }
            else {
                /* Use 4 here, rather than sizeof(glui32). */
                return ftell(str->file) / 4;
            }
        case strtype_Window:
        default:
            return 0;
    }   
}

static void gli_stream_ensure_op(stream_t *str, glui32 op)
{
    /* We have to do an fseek() between reading and writing. This will
       only come up for ReadWrite or WriteAppend files. */
    if (str->lastop != 0 && str->lastop != op) {
        long pos = ftell(str->file);
        fseek(str->file, pos, SEEK_SET);
    }
    str->lastop = op;
}

static void gli_put_char(stream_t *str, unsigned char ch)
{
    if (!str || !str->writable)
        return;
    
    str->writecount++;
    
    switch (str->type) {
        case strtype_Memory:
            if (!str->unicode) {
                if (str->bufptr < str->bufend) {
                    *(str->bufptr) = ch;
                    str->bufptr++;
                    if (str->bufptr > str->bufeof)
                        str->bufeof = str->bufptr;
                }
            }
            else {
                if (str->ubufptr < str->ubufend) {
                    *(str->ubufptr) = (glui32)ch;
                    str->ubufptr++;
                    if (str->ubufptr > str->ubufeof)
                        str->ubufeof = str->ubufptr;
                }
            }
            break;
        case strtype_Window:
            if (str->win->line_request) {
                gli_strict_warning(L"put_char: window has pending line request");
                ///// str->win->line_request = 0;
                //break;
            }
            gli_window_put_char(str->win, UCS(ch));
            if (str->win->echostr)
                gli_put_char(str->win->echostr, glui32_to_wchar(UCS(ch)));
            break;
        case strtype_File:
            gli_stream_ensure_op(str, filemode_Write);
            /* Really, if the stream was opened in text mode, we ought to do 
             character-set conversion here. As it is we're printing a
             file of Latin-1 characters. */
            if (!str->unicode) {
                putc(ch, str->file);
            }
            else {
                /* cheap big-endian stream */
                putc(0, str->file);
                putc(0, str->file);
                putc(0, str->file);
                putc(ch, str->file);
            }
            break;
        case strtype_Resource:
            /* resource streams are never writable */
            break;
    }
}

#ifdef GLK_MODULE_UNICODE

void gli_put_char_uni(stream_t *str, glui32 ch)
{
    if (!str || !str->writable)
        return;
    
    str->writecount++;
    
    switch (str->type) {
        case strtype_Memory:
            if (!str->unicode) {
                if (ch >= 0x100)
                    ch = '?';
                if (str->bufptr < str->bufend) {
                    *(str->bufptr) = ch;
                    str->bufptr++;
                    if (str->bufptr > str->bufeof)
                        str->bufeof = str->bufptr;
                }
            }
            else {
                if (str->ubufptr < str->ubufend) {
                    *(str->ubufptr) = ch;
                    str->ubufptr++;
                    if (str->ubufptr > str->ubufeof)
                        str->ubufeof = str->ubufptr;
                }
            }
            break;
        case strtype_Window:
            if (str->win->line_request) {
                gli_strict_warning(L"put_char_uni: window has pending line request");
                str->win->line_request = 0;
//                break;
            }
            gli_window_put_char(str->win, ch);
            if (str->win->echostr)
                gli_put_char_uni(str->win->echostr, ch);
            break;
        case strtype_File:
            gli_stream_ensure_op(str, filemode_Write);
            if (!str->unicode) {
                if (ch >= 0x100)
                    ch = '?';
                putc(ch, str->file);
            }
            else {
                /* cheap big-endian stream */
                putc(((ch >> 24) & 0xFF), str->file);
                putc(((ch >> 16) & 0xFF), str->file);
                putc(((ch >>  8) & 0xFF), str->file);
                putc( (ch        & 0xFF), str->file);
            }
            break;
        case strtype_Resource:
            /* resource streams are never writable */
            break;
    }
}

#endif /* GLK_MODULE_UNICODE */

static void gli_put_buffer(stream_t *str, char *buf, glui32 len)
{
    char *cx;
    glui32 lx;
    
    if (!str || !str->writable)
        return;
    
    str->writecount += len;
    
    switch (str->type) {
        case strtype_Memory:
            if (!str->unicode) {
                if (str->bufptr >= str->bufend) {
                    len = 0;
                }
                else {
                    if (str->bufptr + len > str->bufend) {
                        lx = (str->bufptr + len) - str->bufend;
                        if (lx < len)
                            len -= lx;
                        else
                            len = 0;
                    }
                }
                if (len) {
                    memcpy(str->bufptr, buf, len);
                    str->bufptr += len;
                    if (str->bufptr > str->bufeof)
                        str->bufeof = str->bufptr;
                }
            }
            else {
                if (str->ubufptr >= str->ubufend) {
                    len = 0;
                }
                else {
                    if (str->ubufptr + len > str->ubufend) {
                        lx = (str->ubufptr + len) - str->ubufend;
                        if (lx < len)
                            len -= lx;
                        else
                            len = 0;
                    }
                }
                if (len) {
                    for (lx=0; lx<len; lx++) {
                        *str->ubufptr = (unsigned char)(buf[lx]);
                        str->ubufptr++;
                    }
                    if (str->ubufptr > str->ubufeof)
                        str->ubufeof = str->ubufptr;
                }
            }
            break;
        case strtype_Window:
            if (str->win->line_request) {
                gli_strict_warning(L"put_buffer: window has pending line request");
                str->win->line_request = 0;
                //break;
            }
            for (lx=0, cx=buf; lx<len; lx++, cx++) {
                gli_window_put_char(str->win, UCS(*cx));
            }
            if (str->win->echostr)
                gli_put_buffer(str->win->echostr, buf, len);
            break;
        case strtype_File:
            gli_stream_ensure_op(str, filemode_Write);
            /* Really, if the stream was opened in text mode, we ought to do
             character-set conversion here. As it is we're printing a
             file of Latin-1 characters. */
            if (!str->unicode) {
                fwrite((unsigned char *)buf, 1, len, str->file);
            }
            else {
                /* cheap big-endian stream */
                for (lx=0; lx<len; lx++) {
                    unsigned char ch = ((unsigned char *)buf)[lx];
                    putc(((ch >> 24) & 0xFF), str->file);
                    putc(((ch >> 16) & 0xFF), str->file);
                    putc(((ch >>  8) & 0xFF), str->file);
                    putc( (ch        & 0xFF), str->file);
                }
            }
            break;
        case strtype_Resource:
            /* resource streams are never writable */
            break;
    }
}

static void gli_set_style(stream_t *str, glui32 val)
{
    int istyle = 0;
    if (!str || !str->writable)
        return;
    
    if (val >= style_NUMSTYLES)
        val = style_Normal;
    
    switch (str->type) {
        case strtype_Window:
            str->win->style = val;
            unsigned int weight = gli_stylehint_get(str->win, val, stylehint_Weight);
            unsigned int oblique = gli_stylehint_get(str->win, val, stylehint_Oblique);
            unsigned int proportional = gli_stylehint_get(str->win, val, stylehint_Proportional);

            if (oblique || val == style_Emphasized || val == style_Note)
                istyle |= kFTItalic;
            if (val == style_Alert)
                istyle |= kFTBold; // kFTReverse;
            if (weight || val == style_Header || val == style_Subheader || val == style_Input)
                istyle |= kFTBold;
            if (!proportional || val == style_Preformatted) // || val == style_BlockQuote)
                istyle |= kFTFixedWidth;

            if (str->win->type == wintype_TextBuffer) {
                unsigned int just = gli_stylehint_get(str->win, val, stylehint_Justification);
                if (just == stylehint_just_Centered)
                    istyle |= kFTCentered;
                else if (just == stylehint_just_RightFlush)
                    istyle |= kFTRightJust;
                iphone_set_text_attribs(str->win->iphone_glkViewNum, istyle, -1, TRUE);
                
                unsigned int textColor = gli_stylehint_get(str->win, val, stylehint_TextColor);
                unsigned int bgColor = gli_stylehint_get(str->win, val, stylehint_BackColor);

                iphone_glk_set_text_colors(str->win->iphone_glkViewNum, textColor, bgColor);
                //printf("stc v %d style %d text %x bg %x\n", str->win->iphone_glkViewNum, val, textColor, bgColor);
            }
            if (str->win->echostr && str->win->echostr != str)
                gli_set_style(str->win->echostr, val);
            break;
    }
}

void gli_stream_echo_line(stream_t *str, char *buf, glui32 len)
{
    /* This is only used to echo line input to an echo stream. See
     the line input methods in gtw_grid and gtw_buf. */
    gli_put_buffer(str, buf, len);
    gli_put_char(str, '\n');
}

#ifdef GLK_MODULE_UNICODE

void gli_stream_echo_line_uni(stream_t *str, glui32 *buf, glui32 len)
{
    glui32 ix;
    /* This is only used to echo line input to an echo stream. See
     glk_select(). */
    for (ix=0; ix<len; ix++) {
        gli_put_char_uni(str, buf[ix]);
    }
    gli_put_char_uni(str, L'\n');
}

#else

void gli_stream_echo_line_uni(stream_t *str, glui32 *buf, glui32 len)
{
    gli_strict_warning(L"stream_echo_line_uni: called with no Unicode line request");
}

#endif /* GLK_MODULE_UNICODE */

static glsi32 gli_get_char(stream_t *str, int want_unicode)
{
    if (!str || !str->readable)
        return -1;
    
    switch (str->type) {
        case strtype_Resource:
            if (str->unicode) {
                glui32 ch;
                if (str->isbinary) {
                    /* cheap big-endian stream */
                    if (str->bufptr >= str->bufend)
                        return -1;
                    ch = *(str->bufptr);
                    str->bufptr++;
                    if (str->bufptr >= str->bufend)
                        return -1;
                    ch = (ch << 8) | (*(str->bufptr) & 0xFF);
                    str->bufptr++;
                    if (str->bufptr >= str->bufend)
                        return -1;
                    ch = (ch << 8) | (*(str->bufptr) & 0xFF);
                    str->bufptr++;
                    if (str->bufptr >= str->bufend)
                        return -1;
                    ch = (ch << 8) | (*(str->bufptr) & 0xFF);
                    str->bufptr++;
                }
                else {
                    /* slightly less cheap UTF8 stream */
                    glui32 val0, val1, val2, val3;
                    if (str->bufptr >= str->bufend)
                        return -1;
                    val0 = *(str->bufptr);
                    str->bufptr++;
                    if (val0 < 0x80) {
                        ch = val0;
                    }
                    else {
                        if (str->bufptr >= str->bufend)
                            return -1;
                        val1 = *(str->bufptr);
                        str->bufptr++;
                        if ((val1 & 0xC0) != 0x80)
                            return -1;
                        if ((val0 & 0xE0) == 0xC0) {
                            ch = (val0 & 0x1F) << 6;
                            ch |= (val1 & 0x3F);
                        }
                        else {
                            if (str->bufptr >= str->bufend)
                                return -1;
                            val2 = *(str->bufptr);
                            str->bufptr++;
                            if ((val2 & 0xC0) != 0x80)
                                return -1;
                            if ((val0 & 0xF0) == 0xE0) {
                                ch = (((val0 & 0xF)<<12)  & 0x0000F000);
                                ch |= (((val1 & 0x3F)<<6) & 0x00000FC0);
                                ch |= (((val2 & 0x3F))    & 0x0000003F);
                            }
                            else if ((val0 & 0xF0) == 0xF0) {
                                if (str->bufptr >= str->bufend)
                                    return -1;
                                val3 = *(str->bufptr);
                                str->bufptr++;
                                if ((val3 & 0xC0) != 0x80)
                                    return -1;
                                ch = (((val0 & 0x7)<<18)   & 0x1C0000);
                                ch |= (((val1 & 0x3F)<<12) & 0x03F000);
                                ch |= (((val2 & 0x3F)<<6)  & 0x000FC0);
                                ch |= (((val3 & 0x3F))     & 0x00003F);
                            }
                            else {
                                return -1;
                            }
                        }
                    }
                }
                str->readcount++;
                if (!want_unicode && ch >= 0x100)
                    return '?';
                return (glsi32)ch;
            }
            /* for text streams, fall through to memory case */
        case strtype_Memory:
            if (!str->unicode) {
                if (str->bufptr < str->bufend) {
                    unsigned char ch;
                    ch = *(str->bufptr);
                    str->bufptr++;
                    str->readcount++;
                    return ch;
                }
                else {
                    return -1;
                }
            }
            else {
                if (str->ubufptr < str->ubufend) {
                    glui32 ch;
                    ch = *(str->ubufptr);
                    str->ubufptr++;
                    str->readcount++;
                    if (!want_unicode && ch >= 0x100)
                        return '?';
                    return ch;
                }
                else {
                    return -1;
                }
            }
        case strtype_File: 
            if (!str->unicode) {
                int res;
                res = getc(str->file);
                if (res != -1) {
                    str->readcount++;
                    /* Really, if the stream was opened in text mode, we ought
                     to do character-set conversion here. */
                    return (glsi32)res;
                }
                else {
                    return -1;
                }
            }
            else {
                /* cheap big-endian stream */
                int res;
                glui32 ch;
                res = getc(str->file);
                if (res == -1)
                    return -1;
                ch = (res & 0xFF);
                res = getc(str->file);
                if (res == -1)
                    return -1;
                ch = (ch << 8) | (res & 0xFF);
                res = getc(str->file);
                if (res == -1)
                    return -1;
                ch = (ch << 8) | (res & 0xFF);
                res = getc(str->file);
                if (res == -1)
                    return -1;
                ch = (ch << 8) | (res & 0xFF);
                str->readcount++;
                if (!want_unicode && ch >= 0x100)
                    return '?';
                return (glsi32)ch;
            }
        case strtype_Window:
        default:
            return -1;
    }
}

static glui32 gli_get_buffer(stream_t *str, char *cbuf, glui32 *ubuf,
                             glui32 len)
{
    if (!str || !str->readable)
        return 0;
    
    switch (str->type) {
        case strtype_Resource:
            if (str->unicode) {
                glui32 count = 0;
                while (count < len) {
                    glui32 ch;
                    if (str->isbinary) {
                        /* cheap big-endian stream */
                        if (str->bufptr >= str->bufend)
                            break;
                        ch = *(str->bufptr);
                        str->bufptr++;
                        if (str->bufptr >= str->bufend)
                            break;
                        ch = (ch << 8) | (*(str->bufptr) & 0xFF);
                        str->bufptr++;
                        if (str->bufptr >= str->bufend)
                            break;
                        ch = (ch << 8) | (*(str->bufptr) & 0xFF);
                        str->bufptr++;
                        if (str->bufptr >= str->bufend)
                            break;
                        ch = (ch << 8) | (*(str->bufptr) & 0xFF);
                        str->bufptr++;
                    }
                    else {
                        /* slightly less cheap UTF8 stream */
                        glui32 val0, val1, val2, val3;
                        if (str->bufptr >= str->bufend)
                            break;
                        val0 = *(str->bufptr);
                        str->bufptr++;
                        if (val0 < 0x80) {
                            ch = val0;
                        }
                        else {
                            if (str->bufptr >= str->bufend)
                                break;
                            val1 = *(str->bufptr);
                            str->bufptr++;
                            if ((val1 & 0xC0) != 0x80)
                                break;
                            if ((val0 & 0xE0) == 0xC0) {
                                ch = (val0 & 0x1F) << 6;
                                ch |= (val1 & 0x3F);
                            }
                            else {
                                if (str->bufptr >= str->bufend)
                                    break;
                                val2 = *(str->bufptr);
                                str->bufptr++;
                                if ((val2 & 0xC0) != 0x80)
                                    break;
                                if ((val0 & 0xF0) == 0xE0) {
                                    ch = (((val0 & 0xF)<<12)  & 0x0000F000);
                                    ch |= (((val1 & 0x3F)<<6) & 0x00000FC0);
                                    ch |= (((val2 & 0x3F))    & 0x0000003F);
                                }
                                else if ((val0 & 0xF0) == 0xF0) {
                                    if (str->bufptr >= str->bufend)
                                        break;
                                    val3 = *(str->bufptr);
                                    str->bufptr++;
                                    if ((val3 & 0xC0) != 0x80)
                                        break;
                                    ch = (((val0 & 0x7)<<18)   & 0x1C0000);
                                    ch |= (((val1 & 0x3F)<<12) & 0x03F000);
                                    ch |= (((val2 & 0x3F)<<6)  & 0x000FC0);
                                    ch |= (((val3 & 0x3F))     & 0x00003F);
                                }
                                else {
                                    break;
                                }
                            }
                        }
                    }
                    if (cbuf) {
                        if (ch >= 0x100)
                            cbuf[count] = '?';
                        else
                            cbuf[count] = ch;
                    }
                    else {
                        ubuf[count] = ch;
                    }
                    count++;
                }
                str->readcount += count;
                return count;
            }
            /* for text streams, fall through to memory case */
        case strtype_Memory:
            if (!str->unicode) {
                if (str->bufptr >= str->bufend) {
                    len = 0;
                }
                else {
                    if (str->bufptr + len > str->bufend) {
                        glui32 lx;
                        lx = (str->bufptr + len) - str->bufend;
                        if (lx < len)
                            len -= lx;
                        else
                            len = 0;
                    }
                }
                if (len) {
                    if (cbuf) {
                        memcpy(cbuf, str->bufptr, len);
                    }
                    else {
                        glui32 lx;
                        for (lx=0; lx<len; lx++) {
                            ubuf[lx] = (unsigned char)str->bufptr[lx];
                        }
                    }
                    str->bufptr += len;
                    if (str->bufptr > str->bufeof)
                        str->bufeof = str->bufptr;
                }
            }
            else {
                if (str->ubufptr >= str->ubufend) {
                    len = 0;
                }
                else {
                    if (str->ubufptr + len > str->ubufend) {
                        glui32 lx;
                        lx = (str->ubufptr + len) - str->ubufend;
                        if (lx < len)
                            len -= lx;
                        else
                            len = 0;
                    }
                }
                if (len) {
                    glui32 lx, ch;
                    if (cbuf) {
                        for (lx=0; lx<len; lx++) {
                            ch = str->ubufptr[lx];
                            if (ch >= 0x100)
                                ch = '?';
                            cbuf[lx] = ch;
                        }
                    }
                    else {
                        for (lx=0; lx<len; lx++) {
                            ubuf[lx] = str->ubufptr[lx];
                        }
                    }
                    str->ubufptr += len;
                    if (str->ubufptr > str->ubufeof)
                        str->ubufeof = str->ubufptr;
                }
            }
            str->readcount += len;
            return len;
        case strtype_File:
            gli_stream_ensure_op(str, filemode_Read);
            if (!str->unicode) {
                if (cbuf) {
                    glui32 res;
                    res = fread(cbuf, 1, len, str->file);
                    /* Really, if the stream was opened in text mode, we ought
                     to do character-set conversion here. */
                    str->readcount += res;
                    return res;
                }
                else {
                    glui32 lx;
                    for (lx=0; lx<len; lx++) {
                        int res;
                        glui32 ch;
                        res = getc(str->file);
                        if (res == -1)
                            break;
                        ch = (res & 0xFF);
                        str->readcount++;
                        ubuf[lx] = ch;
                    }
                    return lx;
                }
            }
            else {
                glui32 lx;
                for (lx=0; lx<len; lx++) {
                    int res;
                    glui32 ch;
                    res = getc(str->file);
                    if (res == -1)
                        break;
                    ch = (res & 0xFF);
                    res = getc(str->file);
                    if (res == -1)
                        break;
                    ch = (ch << 8) | (res & 0xFF);
                    res = getc(str->file);
                    if (res == -1)
                        break;
                    ch = (ch << 8) | (res & 0xFF);
                    res = getc(str->file);
                    if (res == -1)
                        break;
                    ch = (ch << 8) | (res & 0xFF);
                    str->readcount++;
                    if (cbuf) {
                        if (ch >= 0x100)
                            ch = '?';
                        cbuf[lx] = ch;
                    }
                    else {
                        ubuf[lx] = ch;
                    }
                }
                return lx;
            }
        case strtype_Window:
        default:
            return 0;
    }
}

static glui32 gli_get_line(stream_t *str, char *cbuf, glui32 *ubuf, 
                           glui32 len)
{
    glui32 lx;
    int gotnewline;
    
    if (!str || !str->readable)
        return 0;
    
    switch (str->type) {
        case strtype_Resource:
            if (len == 0)
                return 0;
            len -= 1; /* for the terminal null */
            if (str->unicode) {
                glui32 count = 0;
                while (count < len) {
                    glui32 ch;
                    if (str->isbinary) {
                        /* cheap big-endian stream */
                        if (str->bufptr >= str->bufend)
                            break;
                        ch = *(str->bufptr);
                        str->bufptr++;
                        if (str->bufptr >= str->bufend)
                            break;
                        ch = (ch << 8) | (*(str->bufptr) & 0xFF);
                        str->bufptr++;
                        if (str->bufptr >= str->bufend)
                            break;
                        ch = (ch << 8) | (*(str->bufptr) & 0xFF);
                        str->bufptr++;
                        if (str->bufptr >= str->bufend)
                            break;
                        ch = (ch << 8) | (*(str->bufptr) & 0xFF);
                        str->bufptr++;
                    }
                    else {
                        /* slightly less cheap UTF8 stream */
                        glui32 val0, val1, val2, val3;
                        if (str->bufptr >= str->bufend)
                            break;
                        val0 = *(str->bufptr);
                        str->bufptr++;
                        if (val0 < 0x80) {
                            ch = val0;
                        }
                        else {
                            if (str->bufptr >= str->bufend)
                                break;
                            val1 = *(str->bufptr);
                            str->bufptr++;
                            if ((val1 & 0xC0) != 0x80)
                                break;
                            if ((val0 & 0xE0) == 0xC0) {
                                ch = (val0 & 0x1F) << 6;
                                ch |= (val1 & 0x3F);
                            }
                            else {
                                if (str->bufptr >= str->bufend)
                                    break;
                                val2 = *(str->bufptr);
                                str->bufptr++;
                                if ((val2 & 0xC0) != 0x80)
                                    break;
                                if ((val0 & 0xF0) == 0xE0) {
                                    ch = (((val0 & 0xF)<<12)  & 0x0000F000);
                                    ch |= (((val1 & 0x3F)<<6) & 0x00000FC0);
                                    ch |= (((val2 & 0x3F))    & 0x0000003F);
                                }
                                else if ((val0 & 0xF0) == 0xF0) {
                                    if (str->bufptr >= str->bufend)
                                        break;
                                    val3 = *(str->bufptr);
                                    str->bufptr++;
                                    if ((val3 & 0xC0) != 0x80)
                                        break;
                                    ch = (((val0 & 0x7)<<18)   & 0x1C0000);
                                    ch |= (((val1 & 0x3F)<<12) & 0x03F000);
                                    ch |= (((val2 & 0x3F)<<6)  & 0x000FC0);
                                    ch |= (((val3 & 0x3F))     & 0x00003F);
                                }
                                else {
                                    break;
                                }
                            }
                        }
                    }
                    if (cbuf) {
                        if (ch >= 0x100)
                            cbuf[count] = '?';
                        else
                            cbuf[count] = ch;
                    }
                    else {
                        ubuf[count] = ch;
                    }
                    count++;
                    if (ch == '\n')
                        break;
                }
                if (cbuf)
                    cbuf[count] = '\0';
                else
                    ubuf[count] = '\0';
                str->readcount += count;
                return count;
            }
            /* for text streams, fall through to memory case */
        case strtype_Memory:
            if (len == 0)
                return 0;
            len -= 1; /* for the terminal null */
            if (!str->unicode) {
                if (str->bufptr >= str->bufend) {
                    len = 0;
                }
                else {
                    if (str->bufptr + len > str->bufend) {
                        lx = (str->bufptr + len) - str->bufend;
                        if (lx < len)
                            len -= lx;
                        else
                            len = 0;
                    }
                }
                gotnewline = FALSE;
                if (cbuf) {
                    for (lx=0; lx<len && !gotnewline; lx++) {
                        cbuf[lx] = str->bufptr[lx];
                        gotnewline = (cbuf[lx] == '\n');
                    }
                    cbuf[lx] = '\0';
                }
                else {
                    for (lx=0; lx<len && !gotnewline; lx++) {
                        ubuf[lx] = (unsigned char)str->bufptr[lx];
                        gotnewline = (ubuf[lx] == '\n');
                    }
                    ubuf[lx] = '\0';
                }
                str->bufptr += lx;
            }
            else {
                if (str->ubufptr >= str->ubufend) {
                    len = 0;
                }
                else {
                    if (str->ubufptr + len > str->ubufend) {
                        lx = (str->ubufptr + len) - str->ubufend;
                        if (lx < len)
                            len -= lx;
                        else
                            len = 0;
                    }
                }
                gotnewline = FALSE;
                if (cbuf) {
                    for (lx=0; lx<len && !gotnewline; lx++) {
                        glui32 ch;
                        ch = str->ubufptr[lx];
                        if (ch >= 0x100)
                            ch = '?';
                        cbuf[lx] = ch;
                        gotnewline = (ch == '\n');
                    }
                    cbuf[lx] = '\0';
                }
                else {
                    for (lx=0; lx<len && !gotnewline; lx++) {
                        glui32 ch;
                        ch = str->ubufptr[lx];
                        ubuf[lx] = ch;
                        gotnewline = (ch == '\n');
                    }
                    ubuf[lx] = '\0';
                }
                str->ubufptr += lx;
            }
            str->readcount += lx;
            return lx;
        case strtype_File:
            gli_stream_ensure_op(str, filemode_Read);
            if (!str->unicode) {
                if (cbuf) {
                    char *res;
                    res = fgets(cbuf, len, str->file);
                    /* Really, if the stream was opened in text mode, we ought
                     to do character-set conversion here. */
                    if (!res) {
                        return 0;
                    }
                    else {
                        lx = strlen(cbuf);
                        str->readcount += lx;
                        return lx;
                    }
                }
                else {
                    glui32 lx;
                    if (len == 0)
                        return 0;
                    len -= 1; /* for the terminal null */
                    gotnewline = FALSE;
                    for (lx=0; lx<len && !gotnewline; lx++) {
                        int res;
                        glui32 ch;
                        res = getc(str->file);
                        if (res == -1)
                            break;
                        ch = (res & 0xFF);
                        str->readcount++;
                        ubuf[lx] = ch;
                        gotnewline = (ch == '\n');
                    }
                    ubuf[lx] = '\0';
                    return lx;
                }
            }
            else {
                glui32 lx;
                if (len == 0)
                    return 0;
                len -= 1; /* for the terminal null */
                gotnewline = FALSE;
                for (lx=0; lx<len && !gotnewline; lx++) {
                    int res;
                    glui32 ch;
                    res = getc(str->file);
                    if (res == -1)
                        break;
                    ch = (res & 0xFF);
                    res = getc(str->file);
                    if (res == -1)
                        break;
                    ch = (ch << 8) | (res & 0xFF);
                    res = getc(str->file);
                    if (res == -1)
                        break;
                    ch = (ch << 8) | (res & 0xFF);
                    res = getc(str->file);
                    if (res == -1)
                        break;
                    ch = (ch << 8) | (res & 0xFF);
                    str->readcount++;
                    if (cbuf) {
                        if (ch >= 0x100)
                            ch = '?';
                        cbuf[lx] = ch;
                    }
                    else {
                        ubuf[lx] = ch;
                    }
                    gotnewline = (ch == '\n');
                }
                if (cbuf)
                    cbuf[lx] = '\0';
                else 
                    ubuf[lx] = '\0';
                return lx;
            }
        case strtype_Window:
        default:
            return 0;
    }
}

void glk_put_char(unsigned char ch)
{
    gli_put_char(gli_currentstr, ch);
}

void glk_put_char_stream(stream_t *str, unsigned char ch)
{
    if (!str) {
        gli_strict_warning(L"put_char_stream: invalid ref");
        return;
    }
    gli_put_char(str, ch);
}

void glk_put_string(char *s)
{
    gli_put_buffer(gli_currentstr, s, strlen(s));
}

void glk_put_string_stream(stream_t *str, char *s)
{
    if (!str) {
        gli_strict_warning(L"put_string_stream: invalid ref");
        return;
    }
    gli_put_buffer(str, s, strlen(s));
}

void glk_put_buffer(char *buf, glui32 len)
{
    gli_put_buffer(gli_currentstr, buf, len);
}

void glk_put_buffer_stream(stream_t *str, char *buf, glui32 len)
{
    if (!str) {
        gli_strict_warning(L"put_string_stream: invalid ref");
        return;
    }
    gli_put_buffer(str, buf, len);
}

#ifdef GLK_MODULE_UNICODE

void glk_put_char_uni(glui32 ch)
{
    gli_put_char_uni(gli_currentstr, ch);
}

void glk_put_char_stream_uni(stream_t *str, glui32 ch)
{
    if (!str) {
        gli_strict_warning(L"put_char_stream: invalid ref");
        return;
    }
    gli_put_char_uni(str, ch);
}

void glk_put_string_uni(glui32 *us)
{
    int len = 0;
    glui32 val;
    
    while (1) {
        val = us[len];
        if (!val)
            break;
        gli_put_char_uni(gli_currentstr, val);
        len++;
    }
}

void glk_put_string_stream_uni(stream_t *str, glui32 *us)
{
    int len = 0;
    glui32 val;
    
    if (!str) {
        gli_strict_warning(L"put_string_stream: invalid ref");
        return;
    }
    
    while (1) {
        val = us[len];
        if (!val)
            break;
        gli_put_char_uni(str, val);
        len++;
    }
}

void glk_put_buffer_uni(glui32 *buf, glui32 len)
{
    glui32 ix;
    for (ix=0; ix<len; ix++) {
        gli_put_char_uni(gli_currentstr, buf[ix]);
    }
}

void glk_put_buffer_stream_uni(stream_t *str, glui32 *buf, glui32 len)
{
    glui32 ix;
    if (!str) {
        gli_strict_warning(L"put_string_stream: invalid ref");
        return;
    }
    for (ix=0; ix<len; ix++) {
        gli_put_char_uni(str, buf[ix]);
    }
}

glsi32 glk_get_char_stream_uni(strid_t str)
{
    if (!str) {
        gli_strict_warning(L"get_char_stream_uni: invalid ref");
        return -1;
    }
    return gli_get_char(str, 1);
}

glui32 glk_get_buffer_stream_uni(strid_t str, glui32 *buf, glui32 len)
{
    if (!str) {
        gli_strict_warning(L"get_buffer_stream_uni: invalid ref");
        return -1;
    }
    return gli_get_buffer(str, NULL, buf, len);
}

glui32 glk_get_line_stream_uni(strid_t str, glui32 *buf, glui32 len)
{
    if (!str) {
        gli_strict_warning(L"get_line_stream_uni: invalid ref");
        return -1;
    }
    return gli_get_line(str, NULL, buf, len);
}

#endif /* GLK_MODULE_UNICODE */

void glk_set_style(glui32 val)
{
    gli_set_style(gli_currentstr, val);
}

void glk_set_style_stream(stream_t *str, glui32 val)
{
    if (!str) {
        gli_strict_warning(L"set_style_stream: invalid ref");
        return;
    }
    gli_set_style(str, val);
}

glsi32 glk_get_char_stream(stream_t *str)
{
    if (!str) {
        gli_strict_warning(L"get_char_stream: invalid ref");
        return -1;
    }
    return gli_get_char(str, 0);
}

glui32 glk_get_line_stream(stream_t *str, char *buf, glui32 len)
{
    if (!str) {
        gli_strict_warning(L"get_line_stream: invalid ref");
        return -1;
    }
    return gli_get_line(str, buf, NULL, len);
}

glui32 glk_get_buffer_stream(stream_t *str, char *buf, glui32 len)
{
    if (!str) {
        gli_strict_warning(L"get_buffer_stream: invalid ref");
        return -1;
    }
    return gli_get_buffer(str, buf, NULL, len);
}

#ifdef GLK_MODULE_HYPERLINKS
void glk_set_hyperlink(glui32 linkval)
{
    glk_set_hyperlink_stream(gli_currentstr, linkval);
}
#endif


