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
#include "iphone_frotz.h"

/* This code implements filerefs as they work in a stdio system: a
    fileref contains a pathname, a text/binary flag, and a file
    type.
*/

/* Linked list of all filerefs */
static fileref_t *gli_filereflist = NULL; 

#define BUFLEN (256)

static char workingdir[BUFLEN] = ".";
static char lastsavename[BUFLEN] = "game.sav";
static char lastscriptname[BUFLEN] = "script.txt";
static char lastcmdname[BUFLEN] = "commands.txt";
static char lastdataname[BUFLEN] = "file.dat";

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

frefid_t glk_fileref_create_temp(glui32 usage, glui32 rock)
{
    char *filename;
    fileref_t *fref;
    
    /* This is a pretty good way to do this on Unix systems. On Macs,
        it's pretty bad, but this library won't be used on the Mac 
        -- I hope. I have no idea about the DOS/Windows world. */
        
    filename = tmpnam(NULL);
    
    fref = gli_new_fileref(filename, usage, rock);
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
    char buf2[BUFLEN];
    int len;
    char *cx;
    
    len = strlen(name);
    if (len > BUFLEN-1)
        len = BUFLEN-1;
    
    /* Take out all '/' characters, and make sure the length is greater 
        than zero. Again, this is the right behavior in Unix. 
        DOS/Windows might want to take out '\' instead, unless the
        stdio library converts slashes for you. They'd also want to trim 
        to 8 characters. Remember, the overall goal is to make a legal 
        platform-native filename, without any extra directory 
        components.
       Suffixes are another sore point. Really, the game program 
        shouldn't have a suffix on the name passed to this function. So
        in DOS/Windows, this function should chop off dot-and-suffix,
        if there is one, and then add a dot and a three-letter suffix
        appropriate to the file type (as gleaned from the usage 
        argument.)
    */
    
    memcpy(buf, name, len);
    if (len == 0) {
        buf[0] = 'X';
        len++;
    }
    buf[len] = '\0';
    
    for (cx=buf; *cx; cx++) {
        if (*cx == '/')
            *cx = '-';
    }
    
    if (len + 1 + strlen(workingdir) >= BUFLEN) {
        gli_strict_warning(L"fileref_create_by_name: filename too long.");
        return NULL;
    }
    sprintf(buf2, "%s/%s", workingdir, buf);

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
//    glui32 response;
    
    switch (usage & fileusage_TypeMask) {
        case fileusage_SavedGame:
            prompt = "Enter saved game";
            lastbuf = lastsavename;
            break;
        case fileusage_Transcript:
            prompt = "Enter transcript file";
            lastbuf = lastscriptname;
            break;
        case fileusage_InputRecord:
            prompt = "Enter command record file";
            lastbuf = lastcmdname;
            break;
        case fileusage_Data:
        default:
            prompt = "Enter data file";
            lastbuf = lastdataname;
            break;
    }
    
    if (fmode == filemode_Read)
        prompt2 = "to load";
    else
        prompt2 = "to store";
    
    sprintf(newbuf, "%s %s: ", prompt, prompt2);

    ix =  iphone_prompt_file_name(buf, "", fmode == filemode_Read ? 0 : 1 /*FILE_SAVE*/);

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
    
    strcat(lastsavename, ".sav");
    strcat(lastscriptname, ".txt");
    strcat(lastdataname, ".dat");
}

