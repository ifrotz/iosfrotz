/* This file implements some of the functions described in
 * tads2/osifc.h.  We don't need to implement them all, as most of them
 * are provided by tads2/osnoui.c and tads2/osgen3.c.
 *
 * This file implements the "portable" subset of these functions;
 * functions that depend upon curses/ncurses are defined in oscurses.cc.
 */
#if 1 //zzzz
#include "common.h"
#include "osstzprs.h"


#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <stdarg.h>
#include <time.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/param.h>
#include <setjmp.h>
#ifdef HAVE_LANGINFO_CODESET
#include <langinfo.h>
#endif
#ifdef HAVE_GLOB_H
#include <glob.h>
#endif

#include "os.h"
#ifdef RUNTIME
// We utilize the Tads 3 Unicode character mapping facility even for
// Tads 2 (only in the interpreter).
#include "charmap.h"
// Need access to command line options: globalApp->options. Only at
// runtime - compiler uses different mechanism for command line
// options.
//#include "frobtadsapp.h"
#endif // RUNTIME

extern "C" void safe_strcpy(char *dst, size_t dstlen, const char *src);

/* Duplicate a file hand.e
 */
osfildef* osfdup(osfildef *orig, const char *mode)
{
    char realmode[5];
    char *p = realmode;
    const char *m;
    
    /* verify that there aren't any unrecognized mode flags */
    for (m = mode ; *m != '\0' ; ++m)
    {
        if (strchr("rw+bst", *m) == 0)
            return 0;
    }
    
    /* figure the read/write mode - translate r+ and w+ to r+ */
    if ((mode[0] == 'r' || mode[0] == 'w') && mode[1] == '+')
        *p++ = 'r', *p++ = '+';
    else if (mode[0] == 'r')
        *p++ = 'r';
    else if (mode[0] == 'w')
        *p++ = 'w';
    else
        return 0;
    
    /* end the mode string */
    *p = '\0';
    
    /* duplicate the handle in the given mode */
    return fdopen(dup(fileno(orig)), mode);
    return NULL;
}

/* Create a directory.
 */
int
os_mkdir( const char* dir, int create_parents )
{
    if (dir[0] == '\0')
        return true;

    // Copy the directory name to a new string so we can strip any trailing
    // path seperators.
    size_t len = strlen(dir);
    char* tmp = new char[len + 1];
    strncpy(tmp, dir, len);
    while (tmp[len - 1] == OSPATHCHAR)
        --len;
    tmp[len] = '\0';

    // If we're creating intermediate diretories, and the path contains
    // multiple elements, recursively create the parent directories first.
    if (create_parents and strchr(tmp, OSPATHCHAR) != 0) {
        char par[OSFNMAX];

        // Extract the parent path.
        os_get_path_name(par, sizeof(par), tmp);

        // If the parent doesn't already exist, create it recursively.
        if (osfacc(par) != 0 and not os_mkdir(par, true)) {
            delete[] tmp;
            return false;
        }
    }

    // Create the directory.
    int ret = mkdir(tmp, S_IRWXU | S_IRWXG | S_IRWXO);
    delete[] tmp;
    return ret == 0;
}

/* Remove a directory.
 */
int
os_rmdir( const char *dir )
{
    return rmdir(dir) == 0;
}

/* Get a file's mode/type.  This returns the same information as
 * the 'mode' member of os_file_stat_t from os_file_stat(), so we
 * simply call that routine and return the value.
 */
int
osfmode( const char *fname, int follow_links, unsigned long *mode,
         unsigned long* attr )
{
    os_file_stat_t s;
    int ok;
    if ((ok = os_file_stat(fname, follow_links, &s)) != false) {
        if (mode != NULL)
            *mode = s.mode;
        if (attr != NULL)
            *attr = s.attrs;
    }
    return ok;
}

/* Get full stat() information on a file.
 *
 * TODO: Windows implementation for mingw.
 */
int
os_file_stat( const char *fname, int follow_links, os_file_stat_t *s )
{
    struct stat buf;
    if ((follow_links ? stat(fname, &buf) : lstat(fname, &buf)) != 0)
        return false;

    s->sizelo = (uint32_t)(buf.st_size & 0xFFFFFFFF);
    s->sizehi = sizeof(buf.st_size) > 4
                ? (uint32_t)((buf.st_size >> 32) & 0xFFFFFFFF)
                : 0;
    s->cre_time = buf.st_ctime;
    s->mod_time = buf.st_mtime;
    s->acc_time = buf.st_atime;
    s->mode = buf.st_mode;
    s->attrs = 0;

    if (os_get_root_name(fname)[0] == '.') {
        s->attrs |= OSFATTR_HIDDEN;
    }

    // If we're the owner, check if we have read/write access.
    if (geteuid() == buf.st_uid) {
        if (buf.st_mode & S_IRUSR)
            s->attrs |= OSFATTR_READ;
        if (buf.st_mode & S_IWUSR)
            s->attrs |= OSFATTR_WRITE;
        return true;
    }

    // Check if one of our groups matches the file's group and if so, check
    // for read/write access.

    // Also reserve a spot for the effective group ID, which might
    // not be included in the list in our next call.
    int grpSize = getgroups(0, NULL) + 1;
    // Paranoia.
    if (grpSize > NGROUPS_MAX or grpSize < 0)
        return false;
    gid_t* groups = new gid_t[grpSize];
    if (getgroups(grpSize - 1, groups + 1) < 0) {
        delete[] groups;
        return false;
    }
    groups[0] = getegid();
    int i;
    for (i = 0; i < grpSize and buf.st_gid != groups[i]; ++i)
        ;
    delete[] groups;
    if (i < grpSize) {
        if (buf.st_mode & S_IRGRP)
            s->attrs |= OSFATTR_READ;
        if (buf.st_mode & S_IWGRP)
            s->attrs |= OSFATTR_WRITE;
        return true;
    }

    // We're neither the owner of the file nor do we belong to its
    // group.  Check whether the file is world readable/writable.
    if (buf.st_mode & S_IROTH)
        s->attrs |= OSFATTR_READ;
    if (buf.st_mode & S_IWOTH)
        s->attrs |= OSFATTR_WRITE;
    return true;
}

/* Manually resolve a symbolic link.
 */
int
os_resolve_symlink( const char *fname, char *target, size_t target_size )
{
    // get the stat() information for the *undereferenced* link; if
    // it's not actually a link, there's nothing to resolve
    struct stat buf;
    if (lstat(fname, &buf) != 0 or (buf.st_mode & S_IFLNK) == 0)
        return false;

    // read the link contents (maxing out at the buffer size)
    size_t copylen = (size_t)buf.st_size;
    if (copylen > target_size - 1)
        copylen = target_size - 1;
    if (readlink(fname, target, copylen) < 0)
        return false;

    // null-terminate the result and return success
    target[copylen] = '\0';
    return true;
}
#endif // zzzz

/* Get the current system high-precision timer.
 *
 * We provide four (4) implementations of this function:
 *
 *   1. clock_gettime() is available
 *   2. gettimeofday() is available
 *   3. ftime() is available
 *   4. Neither is available - fall back to time()
 *
 * Note that HAVE_CLOCK_GETTIME, HAVE_GETTIMEOFDAY and HAVE_FTIME are
 * mutually exclusive; if one of them is defined, the others aren't.  No
 * need for #else here.
 *
 * Although not required by the TADS VM, these implementations will
 * always return 0 on the first call.
 */
#ifdef HAVE_CLOCK_GETTIME
// The system has the clock_gettime() function.
long
os_get_sys_clock_ms( void )
{
    // We need to remember the exact time this function has been
    // called for the first time, and use that time as our
    // zero-point.  On each call, we simply return the difference
    // in milliseconds between the current time and our zero point.
    static struct timespec zeroPoint;

    // Did we get the zero point yet?
    static bool initialized = false;

    // Not all systems provide a monotonic clock; check if it's
    // available before falling back to the global system-clock.  A
    // monotonic clock is guaranteed not to change while the system
    // is running, so we prefer it over the global clock.
    static const clockid_t clockType =
#ifdef HAVE_CLOCK_MONOTONIC
        CLOCK_MONOTONIC;
#else
        CLOCK_REALTIME;
#endif
    // We must get the current time in each call.
    struct timespec currTime;

    // Initialize our zero-point, if not already done so.
    if (not initialized) {
        clock_gettime(clockType, &zeroPoint);
        initialized = true;
    }

    // Get the current time.
    clock_gettime(clockType, &currTime);

    // Note that tv_nsec contains *nano*seconds, not milliseconds,
    // so we need to convert it; a millisec is 1.000.000 nanosecs.
    return (currTime.tv_sec - zeroPoint.tv_sec) * 1000
         + (currTime.tv_nsec - zeroPoint.tv_nsec) / 1000000;
}

/* Get the time since the Unix Epoch in seconds and nanoseconds.
 */
void
os_time_ns( os_time_t *seconds, long *nanoseconds )
{
    // Get the current time.
    static const clockid_t clockType = CLOCK_REALTIME;
    struct timespec currTime;
    clock_gettime(clockType, &currTime);

    // return the data
    *seconds = currTime.tv_sec;
    *nanoseconds = currTime.tv_nsec;
}
#endif // HAVE_CLOCK_GETTIME

#ifdef HAVE_GETTIMEOFDAY
/* Get the time since the Unix Epoch in seconds and nanoseconds.
 */
void
os_time_ns( os_time_t *seconds, long *nanoseconds )
{
    // get the time
    struct timezone bogus = {0, 0};
    struct timeval currTime;
    gettimeofday(&currTime, &bogus);

    // return the data, converting milliseconds to nanoseconds
    *seconds = currTime.tv_sec;
    *nanoseconds = currTime.tv_usec * 1000;
}
#endif // HAVE_GETTIMEOFDAY

/* Open a directory search.
 */
int os_open_dir(const char *dirname, osdirhdl_t *hdl)
{
    return (*hdl = opendir(dirname)) != NULL;
}

/* Read the next result in a directory search.
 */
int os_read_dir(osdirhdl_t hdl, char *buf, size_t buflen)
{
    // Read the next directory entry - if we've exhausted the search,
    // return failure.
    struct dirent *d = readdir(hdl);
    if (d == 0)
        return false;

    // return this entry
    safe_strcpy(buf, buflen, d->d_name);
    return true;
}

/* Close a directory search.
 */
void os_close_dir(osdirhdl_t hdl)
{
    closedir(hdl);
}


/* Determine if the given filename refers to a special file.
 *
 * tads2/osnoui.c defines its own version when MSDOS is defined.
 */
#ifndef MSDOS
os_specfile_t
os_is_special_file( const char* fname )
{
    // We also check for "./" and "../" instead of just "." and
    // "..".  (We use OSPATHCHAR instead of '/' though.)
    const char selfWithSep[3] = {'.', OSPATHCHAR, '\0'};
    const char parentWithSep[4] = {'.', '.', OSPATHCHAR, '\0'};
    if ((strcmp(fname, ".") == 0) or (strcmp(fname, selfWithSep) == 0)) return OS_SPECFILE_SELF;
    if ((strcmp(fname, "..") == 0) or (strcmp(fname, parentWithSep) == 0)) return OS_SPECFILE_PARENT;
    return OS_SPECFILE_NONE;
}
#endif

#define TRUE 1
#define FALSE 0
#define ispathchar(c) \
((c) == OSPATHCHAR || ((c) != 0 && strchr(OSPATHALT, c) != 0))

/* ------------------------------------------------------------------------ */
/*
 *   Safe strcpy
 */
void safe_strcpyl(char *dst, size_t dstlen,
                  const char *src, size_t srclen)
{
    size_t copylen;
    
    /* do nothing if there's no output buffer */
    if (dst == 0 || dstlen == 0)
        return;
    
    /* do nothing if the source and destination buffers are the same */
    if (dst == src)
        return;
    
    /* use an empty string if given a null string */
    if (src == 0)
        src = "";
    
    /*
     *   figure the copy length - use the smaller of the actual string size
     *   or the available buffer size, minus one for the null terminator
     */
    copylen = srclen;
    if (copylen > dstlen - 1)
        copylen = dstlen - 1;
    
    /* copy the string (or as much as we can) */
    memcpy(dst, src, copylen);
    
    /* null-terminate it */
    dst[copylen] = '\0';
}

void safe_strcpy(char *dst, size_t dstlen, const char *src)
{
    safe_strcpyl(dst, dstlen, src, src != 0 ? strlen(src) : 0);
}

/* Canonicalize a path: remove ".." and "." relative elements.
 * (Copied from tads2/osnoui.c)
 */
static void
canonicalize_path(char *path)
{
    char *p;
    char *start;
    
    /* keep going until we're done */
    for (start = p = path ; ; ++p)
    {
        /* if it's a separator, note it and process the path element */
        if (*p == '\\' || *p == '/' || *p == '\0')
        {
            /*
             *   check the path element that's ending here to see if it's a
             *   relative item - either "." or ".."
             */
            if (p - start == 1 && *start == '.')
            {
                /*
                 *   we have a '.' element - simply remove it along with the
                 *   path separator that follows
                 */
                if (*p == '\\' || *p == '/')
                    memmove(start, p + 1, strlen(p+1) + 1);
                else if (start > path)
                    *(start - 1) = '\0';
                else
                    *start = '\0';
            }
            else if (p - start == 2 && *start == '.' && *(start+1) == '.')
            {
                char *prv;
                
                /*
                 *   we have a '..' element - find the previous path element,
                 *   if any, and remove it, along with the '..' and the
                 *   subsequent separator
                 */
                for (prv = start ;
                     prv > path && (*(prv-1) != '\\' || *(prv-1) == '/') ;
                     --prv) ;
                
                /* if we found a separator, remove the previous element */
                if (prv > start)
                {
                    if (*p == '\\' || *p == '/')
                        memmove(prv, p + 1, strlen(p+1) + 1);
                    else if (start > path)
                        *(start - 1) = '\0';
                    else
                        *start = '\0';
                }
            }
            
            /* note the start of the next element */
            start = p + 1;
        }
        
        /* stop at the end of the string */
        if (*p == '\0')
            break;
    }
}

/*
*   General path builder for os_build_full_path() and os_combine_paths().
*   The two versions do the same work, except that the former canonicalizes
*   the result (resolving "." and ".." in the last element, for example),
*   while the latter just builds the combined path literally.
*/
#if !defined(OSNOUI_OMIT_OS_BUILD_FULL_PATH) && !defined(OSNOUI_OMIT_OS_COMBINE_PATHS)
static void build_path(char *fullpathbuf, size_t fullpathbuflen,
                       const char *path, const char *filename, int canon)
{
    size_t plen, flen;
    int add_sep;
    
    /* presume we'll copy the entire path */
    plen = strlen(path);
    
#ifdef MSDOS
    /*
     *   On DOS, there's a special case involving root paths without drive
     *   letters.  If the filename starts with a slash, but doesn't look like
     *   a UNC-style name (\\MACHINE\NAME), it's an absolute path on a
     *   relative drive.  This means that we need to copy the drive letter or
     *   UNC prefix from 'path' and add the root path from 'filename'.
     */
    if ((filename[0] == '\\' || filename[0] == '/')
        && !(filename[1] == '\\' && filename[1] == '/'))
    {
        const char *p;
        
        /*
         *   'filename' is a root path without a drive letter.  Determine if
         *   'path' starts with a drive letter or a UNC path.
         */
        if (isalpha(path[0]) && path[1] == ':')
        {
            /* drive letter */
            plen = 2;
        }
        else if ((path[0] == '\\' || path[0] == '/')
                 && (path[1] == '\\' || path[1] == '/'))
        {
            /*
             *   UNC-style name - copy the whole \\MACHINE\PATH part.  Look
             *   for the first path separator after the machine name...
             */
            for (p = path + 2 ; *p != '\0' && *p != '\\' && *p != '/' ; ++p) ;
            
            /* ...now look for the next path separator after that */
            if (*p != '\0')
                for (++p ; *p != '\0' && *p != '\\' && *p != '/' ; ++p) ;
            
            /* copy everything up to but not including the second separator */
            plen = p - path;
        }
        else
        {
            /*
             *   we have a root path on the filename side, but no drive
             *   letter or UNC prefix on the path side, so there's nothing to
             *   add to the filename
             */
            plen = 0;
        }
    }
    
    /*
     *   There's a second special case for DOS.  If the filename has a drive
     *   letter with a relative path (e.g., "d:asdf" - no leading backslash),
     *   we can't apply any of the path.  This sort of path isn't absolute,
     *   in that it depends upon the working directory on the drive, but it's
     *   also not relative, in that it does specify a full directory rather
     *   than a path fragment to add to a root path.
     */
    if (isalpha(filename[0]) && filename[1] == ':'
        && filename[2] != '\\' && filename[2] != '/')
    {
        /* the file has a drive letter - we can't combine it with the path */
        plen = 0;
    }
#endif
    
    /* if the filename is an absolute path already, leave it as is */
    if (os_is_file_absolute(filename))
        plen = 0;
    
    /*
     *   Note whether we need to add a separator.  If the path prefix ends in
     *   a separator, don't add another; otherwise, add the standard system
     *   separator character.
     *
     *   Don't add a separator if the path is completely empty, since this
     *   simply means that we want to use the current directory.
     */
    add_sep = (plen != 0 && path[plen] == '\0' && !ispathchar(path[plen-1]));
    
    /* copy the path to the full path buffer, limiting to the buffer length */
    if (plen > fullpathbuflen - 1)
        plen = fullpathbuflen - 1;
    memcpy(fullpathbuf, path, plen);
    
    /* add the path separator if necessary (and if there's room) */
    if (add_sep && plen + 2 < fullpathbuflen)
        fullpathbuf[plen++] = OSPATHCHAR;
    
    /* add the filename after the path, if there's room */
    flen = strlen(filename);
    if (flen > fullpathbuflen - plen - 1)
        flen = fullpathbuflen - plen - 1;
    memcpy(fullpathbuf + plen, filename, flen);
    
    /* add a null terminator */
    fullpathbuf[plen + flen] = '\0';
    
    /* if desired, canonicalize the result */
    if (canon)
        canonicalize_path(fullpathbuf);
}
#endif

/*
 *   Build a combined path, returning the literal combination without
 *   resolving any relative links.
 */
#ifndef OSNOUI_OMIT_OS_COMBINE_PATHS
void os_combine_paths(char *fullpathbuf, size_t fullpathbuflen,
                      const char *path, const char *filename)
{
    /* build the path, without any canonicalization */
    build_path(fullpathbuf, fullpathbuflen, path, filename, FALSE);
}
#endif


/* Resolve symbolic links in a path.  It's okay for 'buf' and 'path'
 * to point to the same buffer if you wish to resolve a path in place.
 */
static void
resolve_path( char *buf, size_t buflen, const char *path )
{
    // Starting with the full path string, try resolving the path with
    // realpath().  The tricky bit is that realpath() will fail if any
    // component of the path doesn't exist, but we need to resolve paths
    // for prospective filenames, such as files or directories we're
    // about to create.  So if realpath() fails, remove the last path
    // component and try again with the remainder.  Repeat until we
    // can resolve a real path, or run out of components to remove.
    // The point of this algorithm is that it will resolve as much of
    // the path as actually exists in the file system, ensuring that
    // we resolve any links that affect the path.  Any portion of the
    // path that doesn't exist obviously can't refer to a link, so it
    // will be taken literally.  Once we've resolved the longest prefix,
    // tack the stripped portion back on to form the fully resolved
    // path.

    // make a writable copy of the path to work with
    size_t pathl = strlen(path);
    char *mypath = new char[pathl + 1];
    memcpy(mypath, path, pathl + 1);

    // start at the very end of the path, with no stripped suffix yet
    char *suffix = mypath + pathl;
    char sl = '\0';

    // keep going until we resolve something or run out of path
    for (;;)
    {
        // resolve the current prefix, allocating the result
        char *rpath = realpath(mypath, 0);

        // un-split the path
        *suffix = sl;

        // if we resolved the prefix, return the result
        if (rpath != 0)
        {
            // success - if we separated a suffix, reattach it
            if (*suffix != '\0')
            {
                // reattach the suffix (the part after the '/')
                for ( ; *suffix == '/' ; ++suffix) ;
                os_build_full_path(buf, buflen, rpath, suffix);
            }
            else
            {
                // no suffix, so we resolved the entire path
                safe_strcpy(buf, buflen, rpath);
            }

            // done with the resolved path
            free(rpath);

            // ...and done searching
            break;
        }

        // no luck with realpath(); search for the '/' at the end of the
        // previous component in the path 
        for ( ; suffix > mypath && *(suffix-1) != '/' ; --suffix) ;

        // skip any redundant slashes
        for ( ; suffix > mypath && *(suffix-1) == '/' ; --suffix) ;

        // if we're at the root element, we're out of path elements
        if (suffix == mypath)
        {
            // we can't resolve any part of the path, so just return the
            // original path unchanged
            safe_strcpy(buf, buflen, mypath);
            break;
        }

        // split the path here into prefix and suffix, and try again
        sl = *suffix;
        *suffix = '\0';
    }

    // done with our writable copy of the path
    delete [] mypath;
}

/* Is the given file in the given directory?
 */
int
os_is_file_in_dir( const char* filename, const char* path,
                   int allow_subdirs, int match_self )
{
    char filename_buf[OSFNMAX], path_buf[OSFNMAX];
    size_t flen, plen;

    // Absolute-ize the filename, if necessary.
    if (not os_is_file_absolute(filename)) {
        os_get_abs_filename(filename_buf, sizeof(filename_buf), filename);
        filename = filename_buf;
    }

    // Absolute-ize the path, if necessary.
    if (not os_is_file_absolute(path)) {
        os_get_abs_filename(path_buf, sizeof(path_buf), path);
        path = path_buf;
    }

    // Canonicalize the paths, to remove .. and . elements - this will make
    // it possible to directly compare the path strings.  Also resolve it
    // to the extent possible, to make sure we're not fooled by symbolic
    // links.
    safe_strcpy(filename_buf, sizeof(filename_buf), filename);
    canonicalize_path(filename_buf);
    resolve_path(filename_buf, sizeof(filename_buf), filename_buf);
    filename = filename_buf;

    safe_strcpy(path_buf, sizeof(path_buf), path);
    canonicalize_path(path_buf);
    resolve_path(path_buf, sizeof(path_buf), path_buf);
    path = path_buf;

    // Get the length of the filename and the length of the path.
    flen = strlen(filename);
    plen = strlen(path);

    // If the path ends in a separator character, ignore that.
    if (plen > 0 and path[plen-1] == '/')
        --plen;

    // if the names match, return true if and only if we're matching the
    // directory to itself
    if (plen == flen && memcmp(filename, path, flen) == 0)
        return match_self;

    // Check that the filename has 'path' as its path prefix.  First, check
    // that the leading substring of the filename matches 'path', ignoring
    // case.  Note that we need the filename to be at least two characters
    // longer than the path: it must have a path separator after the path
    // name, and at least one character for a filename past that.
    if (flen < plen + 2 or memcmp(filename, path, plen) != 0)
        return false;

    // Okay, 'path' is the leading substring of 'filename'; next make sure
    // that this prefix actually ends at a path separator character in the
    // filename.  (This is necessary so that we don't confuse "c:\a\b.txt"
    // as matching "c:\abc\d.txt" - if we only matched the "c:\a" prefix,
    // we'd miss the fact that the file is actually in directory "c:\abc",
    // not "c:\a".)
    if (filename[plen] != '/')
        return false;

    // We're good on the path prefix - we definitely have a file that's
    // within the 'path' directory or one of its subdirectories.  If we're
    // allowed to match on subdirectories, we already have our answer
    // (true).  If we're not allowed to match subdirectories, we still have
    // one more check, which is that the rest of the filename is free of
    // path separator charactres.  If it is, we have a file that's directly
    // in the 'path' directory; otherwise it's in a subdirectory of 'path'
    // and thus isn't a match.
    if (allow_subdirs) {
        // Filename is in the 'path' directory or one of its
        // subdirectories, and we're allowed to match on subdirectories, so
        // we have a match.
        return true;
    }

    // We're not allowed to match subdirectories, so scan the rest of
    // the filename for path separators.  If we find any, the file is
    // in a subdirectory of 'path' rather than directly in 'path'
    // itself, so it's not a match.  If we don't find any separators,
    // we have a file directly in 'path', so it's a match.
    const char* p;
    for (p = filename; *p != '\0' and *p != '/' ; ++p)
        ;

    // If we reached the end of the string without finding a path
    // separator character, it's a match .
    return *p == '\0';
}


/* Get the absolute path for a given filename.
 */
int
os_get_abs_filename( char* buf, size_t buflen, const char* filename )
{
    // If the filename is already absolute, copy it; otherwise combine
    // it with the working directory.
    if (os_is_file_absolute(filename))
    {
        // absolute - copy it as-is
        safe_strcpy(buf, buflen, filename);
    }
    else
    {
        // combine it with the working directory to get the path
        char pwd[OSFNMAX];
        if (getcwd(pwd, sizeof(pwd)) != 0)
            os_build_full_path(buf, buflen, pwd, filename);
        else
            safe_strcpy(buf, buflen, filename);
    }

    // canonicalize the result
    canonicalize_path(buf);

    // Try getting the canonical path from the OS (allocating the
    // result buffer).
    char* newpath = realpath(filename, 0);
    if (newpath != 0) {
        // Copy the output (truncating if it's too long).
        safe_strcpy(buf, buflen, newpath);
        free(newpath);
        return true;
    }

    // realpath() failed, but that's okay - realpath() only works if the
    // path refers to an existing file, but it's valid for callers to
    // pass non-existent filenames, such as names of files they're about
    // to create, or hypothetical paths being used for comparison
    // purposes or for future use.  Simply return the canonical path
    // name we generated above.
    return true;
}


/* ------------------------------------------------------------------------ */
/*
 * Get the file system roots.  Unix has the lovely unified namespace with
 * just the one root, /, so this is quite simple.
 */
size_t os_get_root_dirs(char *buf, size_t buflen)
{
    static const char ret[] = { '/', 0, 0 };
    
    // if there's room, copy the root string "/" and an extra null
    // terminator for the overall list
    if (buflen >= sizeof(ret))
        memcpy(buf, ret, sizeof(ret));

    // return the required size
    return sizeof(ret);
}


/* ------------------------------------------------------------------------ */
/*
 *   Define the version of memcmp to use for comparing filename path elements
 *   for equality.  For case-sensitive file systems, use memcmp(); for
 *   systems that ignore case, use memicmp().
 */
#if 1 || defined(MSDOS) || defined(T_WIN32) || defined(DJGPP) || defined(MSOS2)
# define fname_memcmp memicmp
#elif defined(UNIX)
# define fname_memcmp memcmp
#endif


/*
 *   Get the next earlier element of a path
 */
static const char *prev_path_ele(const char *start, const char *p,
                                 size_t *ele_len)
{
    int cancel = 0;
    const char *dotdot = 0;
    
    /* if we're at the start of the string, there are no more elements */
    if (p == start)
        return 0;
    
    /* keep going until we find a suitable element */
    for (;;)
    {
        const char *endp;
        
        /*
         *   If we've reached the start of the string, it means that we have
         *   ".."'s that canceled out every earlier element of the string.
         *   If the cancel count is non-zero, it means that we have one or
         *   more ".."'s that are significant (in that they cancel out
         *   relative elements before the start of the string).  If the
         *   cancel count is zero, it means that we've exactly canceled out
         *   all remaining elements in the string.
         */
        if (p == start)
        {
            *ele_len = (dotdot != 0 ? 2 : 0);
            return dotdot;
        }
        
        /*
         *   back up through any adjacent path separators before the current
         *   element, so that we're pointing to the first separator after the
         *   previous element
         */
        for ( ; p != start && ispathchar(*(p-1)) ; --p) ;
        
        /*
         *   If we're at the start of the string, this is an absolute path.
         *   Treat it specially by returning a zero-length initial element.
         */
        if (p == start)
        {
            *ele_len = 0;
            return p;
        }
        
        /* note where the current element ends */
        endp = p;
        
        /* now back up to the path separator before this element */
        for ( ; p != start && !ispathchar(*(p-1)) ; --p) ;
        
        /*
         *   if this is ".", skip it, since this simply means that this
         *   element matches the same folder as the previous element
         */
        if (endp - p == 1 && p[0] == '.')
            continue;
        
        /*
         *   if this is "..", it cancels out the preceding non-relative
         *   element; up the cancel count and keep searching
         */
        if (endp - p == 2 && p[0] == '.' && p[1] == '.')
        {
            /* up the cancel count */
            ++cancel;
            
            /* if this is the first ".." we've encountered, note it */
            if (dotdot == 0)
                dotdot = p;
            
            /* keep searching */
            continue;
        }
        
        /*
         *   This is an ordinary path element, not a relative "." or ".."
         *   link.  If we have a non-zero cancel count, we're still working
         *   on canceling out elements from ".."'s we found later in the
         *   string.
         */
        if (cancel != 0)
        {
            /* this absorbs one level of cancellation */
            --cancel;
            
            /*
             *   if that's the last cancellation, we've absorbed all ".."
             *   effects, so the last ".." we found is no longer significant
             */
            if (cancel == 0)
                dotdot = 0;
            
            /* keep searching */
            continue;
        }
        
        /* this item isn't canceled out by a "..", so it's our winner */
        *ele_len = endp - p;
        return p;
    }
}


/*
 *   Compare two paths for equality
 */
int os_file_names_equal(const char *a, const char *b)
{
    /* start at the end of each name and work backwards */
    const char *pa = a + strlen(a), *pb = b + strlen(b);
    
    /* keep going until we reach the start of one or the other path */
    for (;;)
    {
        size_t lena, lenb;
        
        /* get the next earlier element of each path */
        pa = prev_path_ele(a, pa, &lena);
        pb = prev_path_ele(b, pb, &lenb);
        
        /* if one or the other ran out, we're done */
        if (pa == 0 || pb == 0)
        {
            /* the paths match if they ran out at the same time */
            return pa == pb;
        }
        
        /* if the two elements don't match, return unequal */
        if (lena != lenb || fname_memcmp(pa, pb, lena) != 0)
            return FALSE;
    }
}

#define USE_GENRAND 1

/* ------------------------------------------------------------------------ */
/*
 *   ISAAC random number generator.  This is a small, fast, cryptographic
 *   quality random number generator that we use internally for some generic
 *   purposes:
 *
 *   - for os_gen_temp_filename(), we use it to generate a GUID-style random
 *   filename
 *
 *   - for our generic implementation of os_gen_rand_bytes(), we use it as
 *   the source of the random bytes
 */

/*
 *   include ISAAC if we're using our generic temporary filename generator
 *   with long filenames, or we're using our generic os_gen_rand_bytes()
 */
#if !defined(OSNOUI_OMIT_TEMPFILE) && (defined(T_WIN32) || !defined(MSDOS))
#define INCLUDE_ISAAC
#endif
#ifdef USE_GENRAND
#define INCLUDE_ISAAC
#endif

#ifdef INCLUDE_ISAAC
/*
 *   ISAAC random number generator implementation, for generating
 *   GUID-strength random temporary filenames
 */
#define ISAAC_RANDSIZL   (8)
#define ISAAC_RANDSIZ    (1<<ISAAC_RANDSIZL)
static struct isaacctx
{
    /* RNG context */
    unsigned long cnt;
    unsigned long rsl[ISAAC_RANDSIZ];
    unsigned long mem[ISAAC_RANDSIZ];
    unsigned long a;
    unsigned long b;
    unsigned long c;
} *S_isaacctx;

#define _isaac_rand(r) \
((r)->cnt-- == 0 ? \
(isaac_gen_group(r), (r)->cnt=ISAAC_RANDSIZ-1, (r)->rsl[(r)->cnt]) : \
(r)->rsl[(r)->cnt])
#define isaac_rand() _isaac_rand(S_isaacctx)

#define isaac_ind(mm,x)  ((mm)[(x>>2)&(ISAAC_RANDSIZ-1)])
#define isaac_step(mix,a,b,mm,m,m2,r,x) \
{ \
x = *m;  \
a = ((a^(mix)) + *(m2++)) & 0xffffffff; \
*(m++) = y = (isaac_ind(mm,x) + a + b) & 0xffffffff; \
*(r++) = b = (isaac_ind(mm,y>>ISAAC_RANDSIZL) + x) & 0xffffffff; \
}

#define isaac_mix(a,b,c,d,e,f,g,h) \
{ \
a^=b<<11; d+=a; b+=c; \
b^=c>>2;  e+=b; c+=d; \
c^=d<<8;  f+=c; d+=e; \
d^=e>>16; g+=d; e+=f; \
e^=f<<10; h+=e; f+=g; \
f^=g>>4;  a+=f; g+=h; \
g^=h<<8;  b+=g; h+=a; \
h^=a>>9;  c+=h; a+=b; \
}

/* generate the group of numbers */
static void isaac_gen_group(struct isaacctx *ctx)
{
    unsigned long a;
    unsigned long b;
    unsigned long x;
    unsigned long y;
    unsigned long *m;
    unsigned long *mm;
    unsigned long *m2;
    unsigned long *r;
    unsigned long *mend;
    
    mm = ctx->mem;
    r = ctx->rsl;
    a = ctx->a;
    b = (ctx->b + (++ctx->c)) & 0xffffffff;
    for (m = mm, mend = m2 = m + (ISAAC_RANDSIZ/2) ; m<mend ; )
    {
        isaac_step(a<<13, a, b, mm, m, m2, r, x);
        isaac_step(a>>6,  a, b, mm, m, m2, r, x);
        isaac_step(a<<2,  a, b, mm, m, m2, r, x);
        isaac_step(a>>16, a, b, mm, m, m2, r, x);
    }
    for (m2 = mm; m2<mend; )
    {
        isaac_step(a<<13, a, b, mm, m, m2, r, x);
        isaac_step(a>>6,  a, b, mm, m, m2, r, x);
        isaac_step(a<<2,  a, b, mm, m, m2, r, x);
        isaac_step(a>>16, a, b, mm, m, m2, r, x);
    }
    ctx->b = b;
    ctx->a = a;
}

static void isaac_init(unsigned long *rsl)
{
    static int inited = FALSE;
    int i;
    unsigned long a;
    unsigned long b;
    unsigned long c;
    unsigned long d;
    unsigned long e;
    unsigned long f;
    unsigned long g;
    unsigned long h;
    unsigned long *m;
    unsigned long *r;
    struct isaacctx *ctx;
    
    /* allocate the context if we don't already have it set up */
    if ((ctx = S_isaacctx) == 0)
        ctx = S_isaacctx = (struct isaacctx *)malloc(sizeof(struct isaacctx));
    
    /*
     *   If we're already initialized, AND the caller isn't re-seeding with
     *   explicit data, we're done.
     */
    if (inited && rsl == 0)
        return;
    inited = TRUE;
    
    ctx->a = ctx->b = ctx->c = 0;
    m = ctx->mem;
    r = ctx->rsl;
    a = b = c = d = e = f = g = h = 0x9e3779b9;         /* the golden ratio */
    
    /* scramble the initial settings */
    for (i = 0 ; i < 4 ; ++i)
    {
        isaac_mix(a, b, c, d, e, f, g, h);
    }
    
    /*
     *   if they sent in explicit initialization bytes, use them; otherwise
     *   seed the generator with truly random bytes from the system
     */
    if (rsl != 0)
        memcpy(ctx->rsl, rsl, sizeof(ctx->rsl));
    else
        os_gen_rand_bytes((unsigned char *)ctx->rsl, sizeof(ctx->rsl));
    
    /* initialize using the contents of ctx->rsl[] as the seed */
    for (i = 0 ; i < ISAAC_RANDSIZ ; i += 8)
    {
        a += r[i];   b += r[i+1]; c += r[i+2]; d += r[i+3];
        e += r[i+4]; f += r[i+5]; g += r[i+6]; h += r[i+7];
        isaac_mix(a, b, c, d, e, f, g, h);
        m[i] = a;   m[i+1] = b; m[i+2] = c; m[i+3] = d;
        m[i+4] = e; m[i+5] = f; m[i+6] = g; m[i+7] = h;
    }
    
    /* do a second pass to make all of the seed affect all of m */
    for (i = 0 ; i < ISAAC_RANDSIZ ; i += 8)
    {
        a += m[i];   b += m[i+1]; c += m[i+2]; d += m[i+3];
        e += m[i+4]; f += m[i+5]; g += m[i+6]; h += m[i+7];
        isaac_mix(a, b, c, d, e, f, g, h);
        m[i] = a;   m[i+1] = b; m[i+2] = c; m[i+3] = d;
        m[i+4] = e; m[i+5] = f; m[i+6] = g; m[i+7] = h;
    }
    
    /* fill in the first set of results */
    isaac_gen_group(ctx);
    
    /* prepare to use the first set of results */
    ctx->cnt = ISAAC_RANDSIZ;
}
#endif /* INCLUDE_ISAAC */


/* ------------------------------------------------------------------------ */
/*
 *   Generic implementation of os_gen_rand_bytes().  This can be used when
 *   the operating system doesn't have a native source of true randomness,
 *   but prefereably only as a last resort - see below for why.
 *
 *   This generator uses ISAAC to generate the bytes, seeded by the system
 *   time.  This algorithm isn't nearly as good as using a native OS-level
 *   randomness source, since any decent OS API will have access to
 *   considerably more sources of true entropy.  In a portable setting, we
 *   have very little in the way of true randomness available.  The most
 *   reliable portable source of randomness is the system clock; if it has
 *   resolution in the millisecond range, this gives us roughly 10-12 bits of
 *   real entropy if we assume that the user is running the program manually,
 *   in that there should be no pattern to the exact program start time -
 *   even a series of back-to-back runs would be pretty random in the part of
 *   the time below about 1 second.  We *might* also be able to get a little
 *   randomness from the memory environment, such as the current stack
 *   pointer, the state of the malloc() allocator as revealed by the address
 *   of a newly allocated block, the contents of uninitialized stack
 *   variables and uninitialized malloc blocks, and the contents of the
 *   system registers as saved by setjmp.  These memory settings are not
 *   entirely likely to vary much from one run to the next: most modern OSes
 *   virtualize the process environment to such an extent that each fresh run
 *   will start with exactly the same initial memory environment, including
 *   the stack address and malloc heap configuration.
 *
 *   We make the most of these limited entropy sources by using them to seed
 *   an ISAAC RNG, then generating the returned random bytes via ISAAC.
 *   ISAAC's design as a cryptographic RNG means that it thoroughly mixes up
 *   the meager set of random bits we hand it, so the bytes returned will
 *   statistically look nice and random.  However, don't be fooled into
 *   thinking that this magnifies the basic entropy we have as inputs - it
 *   doesn't.  If we only have 10-12 bits of entropy from the timer, and
 *   everything else is static, our byte sequence will represent 10-12 bits
 *   of entropy scattered around through a large set of mathematically (and
 *   deterministically) derived bits.  The danger is that the "birthday
 *   problem" dictates that with 12 bits of variation from one run to the
 *   next, we'd have a good chance of seeing a repeat of the *exact same byte
 *   sequence* within about 100 runs.  This is why it's so much better to
 *   customize this routine using a native OS mechanism whenever possible.
 */

#ifdef USE_GENRAND

void os_gen_rand_bytes(unsigned char *buf, size_t buflen)
{
    union
    {
        unsigned long r[ISAAC_RANDSIZ];
        struct
        {
            unsigned long r1[15];
            jmp_buf env;
        } o;
    } r;
    void *p, *q;
    
    /*
     *   Seed ISAAC with what little entropy we have access to in a generic
     *   cross-platform implementation:
     *
     *   - the current wall-clock time
     *.  - the high-precision (millisecond) system timer
     *.  - the current stack pointer
     *.  - an arbitrary heap pointer obtained from malloc()
     *.  - whatever garbage is in the random heap pointer from malloc()
     *.  - whatever random garbage is in the rest of our stack buffer 'r'
     *.  - the contents of system registers from 'setjmp'
     *
     *   The millisecond timer is by far the most reliable source of real
     *   entropy we have available.  The wall clock time doesn't vary quickly
     *   enough to produce more than a few bits of entropy from run to run;
     *   all of the memory factors could be absolutely deterministic from run
     *   to run, depending on how thoroughly the OS virtualizes the process
     *   environment at the start of a run.  For example, some systems clear
     *   memory pages allocated to a process, as a security measure to
     *   prevent old data from one process from becoming readable by another
     *   process.  Some systems virtualize the memory space such that the
     *   program is always loaded at the same virtual address, always has its
     *   stack at the same virtual address, etc.
     *
     *   Note that we try to add some variability to our malloc heap probing,
     *   first by making the allocation size vary according to the low bits
     *   of the system millisecond timer, then by doing a second allocation
     *   to take into account the effect of the randomized size of the first
     *   allocation.  This should avoid getting the exact same results every
     *   time we run, even if the OS arranges for the heap to have exactly
     *   the same initial layout with every run, since our second malloc will
     *   have initial conditions that vary according to the size our first
     *   malloc.  This arguably doesn't introduce a lot of additional real
     *   entropy, since we're already using the system timer directly in the
     *   calculation anyway: in a sufficiently predictable enough heap
     *   environment, our two malloc() calls will yield the same results for
     *   a given timer value, so we're effectively adding f(timer) for some
     *   deterministic function f(), which is the same in terms of additional
     *   real entropy as just adding the timer again, which is the same as
     *   adding nothing.
     */
    r.r[0] = (unsigned long)time(0);
    r.r[1] = (unsigned long)os_get_sys_clock_ms();
    r.r[2] = (unsigned long)buf;
    r.r[3] = (unsigned long)&buf;
    p = malloc((size_t)(os_get_sys_clock_ms() & 1023) + 17);
    r.r[4] = (unsigned long)p;
    r.r[5] = *(unsigned long *)p;
    r.r[6] = *((unsigned long *)p + 10);
    q = malloc(((size_t)p & 1023) + 19);
    r.r[7] = (unsigned long)p;
    r.r[8] = *(unsigned long *)p;
    r.r[9] = *((unsigned long *)p + 10);
    setjmp(r.o.env);
    
    free(p);
    free(q);
    
    /* initialize isaac with our seed data */
    isaac_init(r.r);
    
    /* generate random bytes from isaac to fill the buffer */
    while (buflen > 0)
    {
        unsigned long n;
        size_t copylen;
        
        /* generate a number */
        n = isaac_rand();
        
        /* copy it into the buffer */
        copylen = buflen < sizeof(n) ? buflen : sizeof(n);
        memcpy(buf, &n, copylen);
        
        /* advance our buffer pointer */
        buf += copylen;
        buflen -= copylen;
    }
}

#endif /* USE_GENRAND */

/*
 *   Generate a name for a temporary file.  This is the long filename
 *   version, suitable only for platforms that can handle filenames of at
 *   least 45 characters in just the root name portion.  For systems with
 *   short filenames (e.g., MS-DOS, this must use a different algorithm - see
 *   the MSDOS section below for a fairly portable "8.3" implementation.
 */
int os_gen_temp_filename(char *buf, size_t buflen)
{
    char tmpdir[OSFNMAX], fname[50];
    
    /* get the system temporary directory */
    os_get_tmp_path(tmpdir);
    
    /* seed ISAAC with random data from the system */
    isaac_init(0);
    
    /*
     *   Generate a GUID-strength random filename.  ISAAC is a cryptographic
     *   quality RNG, so the chances of collisions with other filenames
     *   should be effectively zero.
     */
    sprintf(fname, "TADS-%08lx-%08lx-%08lx-%08lx.tmp",
            isaac_rand(), isaac_rand(), isaac_rand(), isaac_rand());
    
    /* build the full path */
    os_build_full_path(buf, buflen, tmpdir, fname);
    
    /* success */
    return TRUE;
}

#if 0
/*
 *   Convert an OS filename path to a relative URL
 */
void os_cvt_dir_url(char *result_buf, size_t result_buf_size,
                    const char *src_path)
{
    char *dst = result_buf;
    const char *src = src_path;
    size_t rem = result_buf_size;
    
#if defined(TURBO) || defined(DJGPP) || defined(MICROSOFT) || defined(MSOS2)
    /*
     *   If there's a DOS/Windows drive letter, start with the drive letter
     *   and leading '\', if present, as a separate path element.  If it's a
     *   UNC-style path, add the UNC \\MACHINE\SHARE as the first element.
     *
     *   In either case, we'll leave the source pointer positioned at the
     *   rest of the path after the drive root or UNC share, which means
     *   we're pointing to the relative portion of the path that follows.
     *   The normal algorithm will simply convert this to a relative URL that
     *   will be tacked on to the absolute root URL portion that we generate
     *   here, so we'll have the correct overall format.
     */
    if (isalpha(src[0]) && src[1] == ':')
    {
        /* start with /X: */
        cvtaddchar(&dst, &rem, '/');
        cvtaddchars(&dst, &rem, src, 2);
        src += 2;
        
        /*
         *   if it's just "X:" and not "X:\", translate it to "X:." to make
         *   it explicit that we're talking about the working directory on X:
         */
        if (*src != '\\' && *src != '/')
            cvtaddchars(&dst, &rem, "./", 2);
    }
    else if ((src[0] == '\\' || src[0] == '/')
             && (src[1] == '\\' || src[1] == '/'))
    {
        const char *p;
        
        /*
         *   UNC-style path.  Find the next separator to get the end of the
         *   machine name.
         */
        for (p = src + 2 ; *p != '\0' && *p != '/' && *p != '\\' ; ++p) ;
        
        /* start with /\\MACHINE */
        cvtaddchar(&dst, &rem, '/');
        cvtaddchars(&dst, &rem, src, p - src);
        
        /* skip to the path separator */
        src = p;
    }
#endif /* DOS */
    
    /*
     *   Run through the source buffer, copying characters to the output
     *   buffer.  If we encounter a path separator character, replace it with
     *   a forward slash.
     */
    for ( ; *src != '\0' && rem > 1 ; ++dst, ++src, --rem)
    {
        /*
         *   If this is a local path separator character, replace it with the
         *   URL-style path separator character.  Otherwise, copy it
         *   unchanged.
         */
        if (strchr(OSPATHURL, *src) != 0)
        {
            /* add the URL-style path separator instead of the local one */
            *dst = '/';
        }
        else
        {
            /* add the character unchanged */
            *dst = *src;
        }
    }
    
    /* remove any trailing separators (unless the whole path is "/") */
    while (dst > result_buf + 1 && *(dst-1) == '/')
        --dst;
    
    /* add a null terminator */
    *dst = '\0';
}

/*
 *   Convert a relative URL to a relative file system path name
 */
#ifndef OSNOUI_OMIT_OS_CVT_URL_DIR
void os_cvt_url_dir(char *result_buf, size_t result_buf_size,
                    const char *src_url)
{
    char *dst = result_buf;
    const char *src = src_url;
    size_t rem = result_buf_size;
    
    /*
     *   check for an absolute path
     */
#if defined(TURBO) || defined(DJGPP) || defined(MICROSOFT) || defined(MSOS2)
    if (*src == '/')
    {
        const char *p;
        int is_drive, is_unc = FALSE;
        
        /* we have an absolute path - find the end of the first element */
        for (p = ++src ; *p != '\0' && *p != '/' ; ++p) ;
        
        /* check to see if it looks like a drive letter */
        is_drive = (isalpha(src[0]) && src[1] == ':'
                    && (p - src == 2
                        || (p - src == 3 && src[2] == '.')));
        
        /* check to see if it looks like a UNC-style path */
        is_unc = (src[0] == '\\' && src[1] == '\\');
        
        /*
         *   if it's a drive letter or UNC path, it's a valid Windows root
         *   path element - copy it exactly, then decode the rest of the path
         *   as a simple relative path relative to this root
         */
        if (is_drive || is_unc)
        {
            /* it's a drive letter or drive root path - copy it exactly */
            cvtaddchars(&dst, &rem, src, p - src);
            
            /*
             *   if it's an X:. path, remove the . and the following path
             *   separator
             */
            if (is_drive && p - src == 3 && src[2] == '.')
            {
                /* undo the '.' */
                --dst;
                ++rem;
                
                /* skip the '/' if present */
                if (*p == '/')
                    ++p;
            }
            
            /* skip to the '/' */
            src = p;
        }
        else
        {
            /*
             *   It's not a valid DOS root element, so make this a
             *   non-drive-letter root path, converting the first element as
             *   a directory name.
             */
            cvtaddchar(&dst, &rem, '\\');
        }
    }
    else if (isalpha(src[0]) && src[1] == ':')
    {
        /*
         *   As a special case, assume that a path starting with "X:" (where
         *   X is any letter) is a Windows/DOS drive letter prefix.  This
         *   doesn't fit our new (as of Jan 2012) rules for converting paths
         *   to URLs, but it's what older versions did, so it provides
         *   compatibility.  There's a small price for this compatibility,
         *   which is that it's possible in principle for a Unix relative
         *   path to look the same way - you could have a Unix directory
         *   called "c:", so "c:/dir" would be a valid relative path.  But
         *   it's extremely uncommon for Unix users to use colons in
         *   directory names for a couple of reasons; one is that it creates
         *   interop problems because practically every other file system
         *   treats ':' as a special syntax element, and the other is that
         *   ':' is conventionally used on Unix itself as a delimiter in path
         *   lists, so while it isn't formally a special character in file
         *   names, it's effectively a special character.
         */
        cvtaddchars(&dst, &rem, src, 2);
        src += 2;
    }
#endif
    
    /*
     *   Run through the source buffer, copying characters to the output
     *   buffer.  If we encounter a '/', convert it to a path separator
     *   character.
     */
    for ( ; *src != '\0' && rem > 1 ; ++src, ++dst, --rem)
    {
        /*
         *   replace slashes with path separators; expand '%' sequences; copy
         *   all other characters unchanged
         */
        if (*src == '/')
        {
            /* change '/' to the local path separator */
            *dst = OSPATHCHAR;
        }
        else if ((unsigned char)*src < 32
#if defined(TURBO) || defined(DJGPP) || defined(MICROSOFT) || defined(MSOS2)
                 || strchr("*+?=[]\\&|\":<>", *src) != 0
#endif
                 )
        {
            *dst = '_';
        }
        else
        {
            /* copy this character unchanged */
            *dst = *src;
        }
    }
    
    /* add a null terminator and we're done */
    *dst = '\0';
}
#endif // 0


/* ------------------------------------------------------------------------ */
/* Get a special directory path.
 *
 * If env. variables exist, they always override the compile-time
 * defaults.
 *
 * We ignore the argv parameter, since on Unix binaries aren't stored
 * together with data on disk.
 */
void
os_get_special_path( char* buf, size_t buflen, const char* argv0, int id )
{
    const char* res;
    switch (id) {
      case OS_GSP_T3_RES:
        res = getenv("T3_RESDIR");
        if (res == 0 or res[0] == '\0') {
            res = T3_RES_DIR;
        }
        break;

      case OS_GSP_T3_INC:
        res = getenv("T3_INCDIR");
        if (res == 0 or res[0] == '\0') {
            res = T3_INC_DIR;
        }
        break;

      case OS_GSP_T3_LIB:
        res = getenv("T3_LIBDIR");
        if (res == 0 or res[0] == '\0') {
            res = T3_LIB_DIR;
        }
        break;

      case OS_GSP_T3_USER_LIBS:
        // There's no compile-time default for user libs.
        res = getenv("T3_USERLIBDIR");
        break;

      case OS_GSP_T3_SYSCONFIG:
        res = getenv("T3_CONFIG");
        if (res == 0 and argv0 != 0) {
            os_get_path_name(buf, buflen, argv0);
            return;
        }
        break;

      case OS_GSP_LOGFILE:
        res = getenv("T3_LOGDIR");
        if (res == 0 or res[0] == '\0') {
            res = T3_LOG_FILE;
        }
        break;

      default:
        // TODO: We could print a warning here to inform the
        // user that we're outdated.
        res = 0;
    }
    if (res != 0) {
        // Only use the detected path if it exists and is a
        // directory.
        struct stat inf;
        int statRet = stat(res, &inf);
        if (statRet == 0 and (inf.st_mode & S_IFMT) == S_IFDIR) {
            strncpy(buf, res, buflen - 1);
            return;
        }
    }
    // Indicate failure.
    buf[0] = '\0';
}

/* Generate a filename for a character-set mapping file.
 *
 * Follow DOS convention: start with the current local charset
 * identifier, then the internal ID, and the suffix ".tcp".  No path
 * prefix, which means look in current directory.  This is what we
 * want, because mapping files are supposed to be distributed with a
 * game, not with the interpreter.
 */
void
os_gen_charmap_filename( char* filename, char* internal_id, char* /*argv0*/ )
{
    char mapname[32];

    os_get_charmap(mapname, OS_CHARMAP_DISPLAY);

    // Theoretically, we can get mapname so long that with 4-letter
    // internal id and 4-letter extension '.tcp' it will be longer
    // than OSFNMAX. Highly unlikely, but...
    size_t len = strlen(mapname);
    if (len > OSFNMAX - 9) len = OSFNMAX - 9;

    memcpy(filename, mapname, len);
    strcat(filename, internal_id);
    strcat(filename, ".tcp");
}


/* Receive notification that a character mapping file has been loaded.
 */
void
os_advise_load_charmap( char* /*id*/, char* /*ldesc*/, char* /*sysinfo*/ )
{
}


/* T3 post-load UI initialization.  This is a hook provided by the T3
 * VM to allow the UI layer to do any extra initialization that depends
 * upon the contents of the loaded game file.  We don't currently need
 * any extra initialization here.
 */
#ifdef RUNTIME
void
os_init_ui_after_load( class CVmBifTable*, class CVmMetaTable* )
{
    // No extra initialization required.
}
#endif


/* Get the full filename (including directory path) to the executable
 * file, given the argv[0] parameter passed into the main program.
 *
 * On Unix, you can't tell what the executable's name is by just looking
 * at argv, so we always indicate failure.  No big deal though; this
 * information is only used when the interpreter's executable is bundled
 * with a game, and we don't support this at all.
 */
int
os_get_exe_filename( char*, size_t, const char* )
{
    return false;
}

/* Generate the name of the character set mapping table for Unicode
 * characters to and from the given local character set.
 */
void
os_get_charmap( char* mapname, int charmap_id )
{
    const char* charset = 0;  // Character set name.

#if 0 // def RUNTIME
    // If there was a command line option, it takes precedence.
    // User knows better, so do not try to modify his setting.
    if (globalApp->options.characterSet[0] != '\0') {
        // One charset for all.
        strncpy(mapname, globalApp->options.characterSet, 32);
        return;
    }
#endif

    // There is absolutely no robust way to determine the local
    // character set.  Roughly speaking, we have three options:
    //
    // Use nl_langinfo() function.  Not always available.
    //
    // Use setlocale(LC_CTYPE, NULL).  This only works if user set
    // locale which is actually installed on the machine, or else
    // it will return NULL.  But we don't need locale, we just need
    // to know what the user wants.
    //
    // Manually look up environment variables LC_ALL, LC_CTYPE and
    // LANG.
    //
    // However, not a single one will provide us with a reliable
    // name of local character set.  There is no standard way to
    // name charsets.  For a single set we can get almost anything:
    // Windows-1251, Win-1251, CP1251, CP-1251, ru_RU.CP1251,
    // ru_RU.CP-1251, ru_RU.CP_1251...  And the only way is to
    // maintain a database of aliases.

#if HAVE_LANGINFO_CODESET
    charset = nl_langinfo(CODESET);
#else
    charset = getenv("LC_CTYPE");
    if (charset == 0 or charset[0] == '\0') {
        charset = getenv("LC_ALL");
        if (charset == 0 or charset[0] == '\0') {
            charset = getenv("LANG");
        }
    }
#endif

    if (charset == 0) {
        strcpy(mapname, "us-ascii");
    } else {
        strcpy(mapname, get_charset_alias(charset));
    }
    return;
}

#endif // 0

/* Translate a character from the HTML 4 Unicode character set to the
 * current character set used for display.
 *
 * Note that this function is used only by Tads 2.  Tads 3 does mappings
 * automatically.
 *
 * We omit this implementation when not compiling the interpreter (in
 * which case os_xlat_html4 will have been defined as an empty macro in
 * osfrobtads.h).  We do this because we don't want to introduce any
 * TADS 3 dependencies upon the TADS 2 compiler, which should compile
 * regardless of whether the TADS 3 sources are available or not.
 */
#if 0 // ndef os_xlat_html4
void
os_xlat_html4( unsigned int html4_char, char* result, size_t result_buf_len )
{
    // HTML 4 characters are Unicode.  Tads 3 provides just the
    // right mapper: Unicode to ASCII.  We make it static in order
    // not to create a mapper on each call and save CPU cycles.
    static CCharmapToLocalASCII mapper;
    result[mapper.map_char(html4_char, result, result_buf_len)] = '\0';
}
#endif


/* =====================================================================
 *
 * Functions needed by the debugger build of frob (frobd).
 */
#ifdef VM_DEBUGGER
/* Print to the debugger console.
 */
void
os_dbg_printf( const char *fmt, ... )
{ }
#endif

#if 0
/* ------------------------------------------------------------------------ */
/*
 *   none of the banner functions are useful in plain stdio mode
 */
void *os_banner_create(void *parent, int where, void *other, int wintype,
                       int align, int siz, int siz_units, unsigned long style)
{
    return 0;
}

void os_banner_delete(void *banner_handle)
{
}

void os_banner_orphan(void *banner_handle)
{
}

void os_banner_disp(void *banner_handle, const char *txt, size_t len)
{
}

void os_banner_flush(void *banner_handle)
{
}

void os_banner_set_size(void *banner_handle, int siz, int siz_units,
                        int is_advisory)
{
}

void os_banner_size_to_contents(void *banner_handle)
{
}

void os_banner_start_html(void *banner_handle)
{
}

void os_banner_end_html(void *banner_handle)
{
}

void os_banner_set_attr(void *banner_handle, int attr)
{
}

void os_banner_set_color(void *banner_handle, os_color_t fg, os_color_t bg)
{
}

void os_banner_set_screen_color(void *banner_handle, os_color_t color)
{
}

void os_banner_clear(void *banner_handle)
{
}

int os_banner_get_charwidth(void *banner_handle)
{
    return 0;
}

int os_banner_get_charheight(void *banner_handle)
{
    return 0;
}

int os_banner_getinfo(void *banner_handle, os_banner_info_t *info)
{
    return FALSE;
}

void os_banner_goto(void *banner_handle, int row, int col)
{
}
#endif // 0

void os_init_ui_after_load(class CVmBifTable *, class CVmMetaTable *)
{
}
