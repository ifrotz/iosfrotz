/* gtfref.c: File reference objects
        for GlkIOS, iPhone/IOS implementation, curses.h implementation of the Glk API.
    Designed by Andrew Plotkin <erkyrath@eblong.com>
    http://www.eblong.com/zarf/glk/index.html
*/

#include "gtoption.h"
#include <wchar.h> /* for mbstate_t */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h> /* for unlink() */
#include <sys/stat.h> /* for stat() */
#include "glk.h"
#include "glkios.h"
#include "iosfrotz.h"

/* This code implements filerefs as they work in a stdio system: a
    fileref contains a pathname, a text/binary flag, and a file
    type.
*/

/* Linked list of all filerefs */
static fileref_t *gli_filereflist = NULL; 

#define BUFLEN (256)

static char workingdir[BUFLEN] = ".";
static char lastsavename[BUFLEN] = "game.sav"; // .glksave
static char lastscriptname[BUFLEN] = "script.txt";
static char lastcmdname[BUFLEN] = "commands.txt";
static char lastdataname[BUFLEN] = "file.glkdata";

extern char SAVE_PATH[];

fileref_t *gli_new_fileref(char *filename, glui32 usage, glui32 rock)
{
    fileref_t *fref = (fileref_t *)malloc(sizeof(fileref_t));
    if (!fref)
        return NULL;
    
    fref->magicnum = MAGIC_FILEREF_NUM;
    fref->rock = rock;
    
    if (*filename=='/') {
        fref->filename = malloc(1 + strlen(filename));
        strcpy(fref->filename, filename);
    } else {
        fref->filename = malloc(2 + strlen(SAVE_PATH) + strlen(filename));
        sprintf(fref->filename, "%s/%s", SAVE_PATH, filename);
    }
    
    fref->textmode = ((usage & fileusage_TextMode) != 0);
    fref->filetype = (usage & fileusage_TypeMask);
    
    fref->prev = NULL;
    fref->next = gli_filereflist;
    gli_filereflist = fref;
    if (fref->next) {
        fref->next->prev = fref;
    }
    
    if (gli_register_obj)
        fref->disprock = (*gli_register_obj)(fref, gidisp_Class_Fileref);

    return fref;
}

void gli_delete_fileref(fileref_t *fref)
{
    fileref_t *prev, *next;
    
    if (gli_unregister_obj)
        (*gli_unregister_obj)(fref, gidisp_Class_Fileref, fref->disprock);
        
    fref->magicnum = 0;
    
    if (fref->filename) {
        free(fref->filename);
        fref->filename = NULL;
    }
    
    prev = fref->prev;
    next = fref->next;
    fref->prev = NULL;
    fref->next = NULL;

    if (prev)
        prev->next = next;
    else
        gli_filereflist = next;
    if (next)
        next->prev = prev;
    
    free(fref);
}

void glk_fileref_destroy(fileref_t *fref)
{
    if (!fref) {
        gli_strict_warning(L"fileref_destroy: invalid ref");
        return;
    }
    gli_delete_fileref(fref);
}

static char *gli_suffix_for_usage(glui32 usage)
{
    switch (usage & fileusage_TypeMask) {
        case fileusage_Data:
            return ".glkdata";
        case fileusage_SavedGame:
            return ".sav"; // ".glksave";
        case fileusage_Transcript:
        case fileusage_InputRecord:
            return ".txt";
        default:
            return "";
    }
}

frefid_t glk_fileref_create_temp(glui32 usage, glui32 rock)
{
    char *filename;
    fileref_t *fref = NULL;
    
    /* This is a pretty good way to do this on Unix systems. On Macs,
        it's pretty bad, but this library won't be used on the Mac 
        -- I hope. I have no idea about the DOS/Windows world. */
    filename = iphone_get_temp_filename();
    if (filename) {
        fref = gli_new_fileref(filename, usage, rock);
        free(filename);
    }
    if (!fref) {
        gli_strict_warning(L"fileref_create_temp: unable to create fileref.");
        return NULL;
    }
    
    return fref;
}

frefid_t glk_fileref_create_from_fileref(glui32 usage, frefid_t oldfref,
    glui32 rock)
{
    fileref_t *fref; 

    if (!oldfref) {
        gli_strict_warning(L"fileref_create_from_fileref: invalid ref");
        return NULL;
    }

    fref = gli_new_fileref(oldfref->filename, usage, rock);
    if (!fref) {
        gli_strict_warning(L"fileref_create_from_fileref: unable to create fileref.");
        return NULL;
    }
    
    return fref;
}

frefid_t glk_fileref_create_by_name(glui32 usage, char *name,
    glui32 rock)
{
    fileref_t *fref;
    char buf[BUFLEN];
    char buf2[2*BUFLEN+10];
    int len;
    char *cx;
    char *suffix;
    
    /* The new spec recommendations: delete all characters in the
       string "/\<>:|?*" (including quotes). Truncate at the first
       period. Change to "null" if there's nothing left. Then append
       an appropriate suffix: ".glkdata", ".glksave", ".txt".
    */

    for (cx=name, len=0; (*cx && *cx!='.' && len<BUFLEN-1); cx++) {
        switch (*cx) {
            case '"':
            case '\\':
            case '/':
            case '>':
            case '<':
            case ':':
            case '|':
            case '?':
            case '*':
                break;
            default:
                buf[len++] = *cx;
        }
      }
      buf[len] = '\0';

    if (len == 0) {
        strcpy(buf, "null");
        len = strlen(buf);
    }
    
    suffix = gli_suffix_for_usage(usage);
    sprintf(buf2, "%s/%s%s", workingdir, buf, suffix);

    fref = gli_new_fileref(buf2, usage, rock);
    if (!fref) {
        gli_strict_warning(L"fileref_create_by_name: unable to create fileref.");
        return NULL;
    }
    
    return fref;
}

frefid_t glk_fileref_create_by_prompt(glui32 usage, glui32 fmode,
    glui32 rock)
{
    fileref_t *fref;
//    struct stat sbuf;
    char buf[BUFLEN], newbuf[BUFLEN];
    char *cx;
    int ix, val;
    char *prompt, *prompt2, *lastbuf;
    int ipflag = FILE_RESTORE;
    
    switch (usage & fileusage_TypeMask) {
        case fileusage_SavedGame:
            prompt = "Enter saved game";
            ipflag = fmode == filemode_Read ? FILE_RESTORE : FILE_SAVE;
            lastbuf = lastsavename;
            break;
        case fileusage_Transcript:
            prompt = "Enter transcript file";
            ipflag = FILE_SCRIPT;
            lastbuf = lastscriptname;
            break;
        case fileusage_InputRecord:
            prompt = "Enter command record file";
            ipflag = fmode == filemode_Read ? FILE_PLAYBACK : FILE_RECORD;
            lastbuf = lastcmdname;
            break;
        case fileusage_Data:
        default:
            prompt = "Enter data file";
            ipflag = fmode == filemode_Read ? FILE_LOAD_AUX : FILE_SAVE_AUX;
            lastbuf = lastdataname;
            break;
    }
    
    if (fmode == filemode_Read)
        prompt2 = "to load";
    else
        prompt2 = "to store";
    
    sprintf(newbuf, "%s %s: ", prompt, prompt2);

    ix =  iphone_prompt_file_name(buf, "", ipflag);

    if (!ix) {
        /* The player cancelled input. */
        return NULL;
    }
    val = strlen(buf);
    
    while (val 
        && (buf[val-1] == '\n' 
            || buf[val-1] == '\r' 
            || buf[val-1] == ' '))
        val--;
    buf[val] = '\0';
   
    for (cx = buf; *cx == ' '; cx++) { }
    
    val = strlen(cx);
    if (!val) {
        /* The player just hit return. */
        return NULL;
    }

    if (cx[0] == '/') {
        strcpy(newbuf, cx);
        cx = newbuf;
    }
    else {
        if (strlen(workingdir) + 1 + strlen(cx) >= BUFLEN) {
            gli_strict_warning(L"fileref_create_by_name: filename too long.");
            return NULL;
        }
        sprintf(newbuf, "%s/%s", workingdir, cx);
        cx = newbuf + strlen(workingdir) + 1;
    }

    strcpy(lastbuf, cx);

    fref = gli_new_fileref(newbuf, usage, rock);
    if (!fref) {
        gli_strict_warning(L"fileref_create_by_prompt: unable to create fileref.");
        return NULL;
    }
    
    return fref;
}

frefid_t glk_fileref_iterate(fileref_t *fref, glui32 *rock)
{
    if (!fref) {
        fref = gli_filereflist;
    }
    else {
        fref = fref->next;
    }
    
    if (fref) {
        if (rock)
            *rock = fref->rock;
        return fref;
    }
    
    if (rock)
        *rock = 0;
    return NULL;
}

glui32 glk_fileref_get_rock(fileref_t *fref)
{
    if (!fref) {
        gli_strict_warning(L"fileref_get_rock: invalid ref.");
        return 0;
    }
    
    return fref->rock;
}

glui32 glk_fileref_does_file_exist(fileref_t *fref)
{
    struct stat buf;
    
    if (!fref) {
        gli_strict_warning(L"fileref_does_file_exist: invalid ref");
        return FALSE;
    }
    
    /* This is sort of Unix-specific, but probably any stdio library
        will implement at least this much of stat(). */
    
    if (stat(fref->filename, &buf))
        return 0;
    
    if (S_ISREG(buf.st_mode))
        return 1;
    else
        return 0;
}

void glk_fileref_delete_file(fileref_t *fref)
{
    if (!fref) {
        gli_strict_warning(L"fileref_delete_file: invalid ref");
        return;
    }
    
    /* If you don't have the unlink() function, obviously, change it
        to whatever file-deletion function you do have. */
        
    unlink(fref->filename);
}

/* This should only be called from startup code. */
void glkunix_set_base_file(char *filename)
{
    int ix;
    
    for (ix=strlen(filename)-1; ix >= 0; ix--) 
        if (filename[ix] == '/')
            break;

    if (ix >= 0) {
        /* There is a slash. */
        strncpy(workingdir, filename, ix);
        workingdir[ix] = '\0';
        ix++;
    }
    else {
        /* No slash, just a filename. */
        ix = 0;
    }

    strcpy(lastsavename, filename+ix);
    for (ix=strlen(lastsavename)-1; ix >= 0; ix--) 
        if (lastsavename[ix] == '.') 
            break;
    if (ix >= 0)
        lastsavename[ix] = '\0';
    strcpy(lastscriptname, lastsavename);
    strcpy(lastdataname, lastsavename);

    strcat(lastsavename, gli_suffix_for_usage(fileusage_SavedGame));
    strcat(lastscriptname, gli_suffix_for_usage(fileusage_Transcript));
    strcat(lastdataname, gli_suffix_for_usage(fileusage_Data));
}

