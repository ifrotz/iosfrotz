/*
   Routines for listing and extracting .z? files from a .zip archive.
    
   This file is a modification of miniunz.c, still present in
   its unmodified form in this directory but not used in the iFrotz
   project.

   miniunz.c is copyright (C) 1998-2005 Gilles Vollant
*/


#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <errno.h>
#include <fcntl.h>

#ifdef unix
# include <unistd.h>
# include <utime.h>
# include <sys/stat.h>
#else
# include <direct.h>
# include <io.h>
#endif

#include "unzip.h"
#include "extractzfromz.h"

#define CASESENSITIVITY (0)
#define WRITEBUFFERSIZE (8192)
#define MAXFILENAME (256)

int mymkdir(const char* dirname)
{
    int ret = mkdir (dirname,0775);
    return ret;
}

int makedir (const char *newdir)
{
  char *buffer ;
  char *p;
  int  len = (int)strlen(newdir);

  if (len <= 0)
    return 0;

  buffer = (char*)malloc(len+1);
  strcpy(buffer,newdir);

  if (buffer[len-1] == '/') {
    buffer[len-1] = '\0';
  }
  if (mymkdir(buffer) == 0)
    {
      free(buffer);
      return 1;
    }

  p = buffer+1;
  while (1)
    {
      char hold;

      while(*p && *p != '\\' && *p != '/')
        p++;
      hold = *p;
      *p = 0;
      if ((mymkdir(buffer) == -1) && (errno == ENOENT))
        {
          printf("couldn't create directory %s\n",buffer);
          free(buffer);
          return 0;
        }
      if (hold == 0)
        break;
      *p++ = hold;
    }
  free(buffer);
  return 1;
}


NSMutableArray *do_list(unzFile uf)
{
    uLong i;
    unz_global_info gi;
    int err;
    NSMutableArray *zList = [[[NSMutableArray alloc] init] autorelease];

    err = unzGetGlobalInfo (uf,&gi);
    if (err!=UNZ_OK)
	return nil;
    for (i=0;i<gi.number_entry;i++)
    {
        char filename_inzip[256];
        unz_file_info file_info;
        err = unzGetCurrentFileInfo(uf,&file_info,filename_inzip,sizeof(filename_inzip),NULL,0,NULL,0);
        if (err!=UNZ_OK)
        {
            printf("error %d with zipfile in unzGetCurrentFileInfo\n",err);
            break;
        }
	NSString *fileStr = [NSString stringWithUTF8String: filename_inzip];
	NSString *ext = [[fileStr pathExtension] lowercaseString];
	if ([ext isEqualToString: @"z2"] ||
        [ext isEqualToString: @"z3"] ||
	    [ext isEqualToString: @"z4"]||
	    [ext isEqualToString: @"z5"] ||
	    [ext isEqualToString: @"z8"] ||
	    [ext isEqualToString: @"dat"] ||
	    [ext isEqualToString: @"zlb"] ||
	    [ext isEqualToString: @"blb"] ||
	    [ext isEqualToString: @"ulx"] ||
	    [ext isEqualToString: @"gblorb"] ||
	    [ext isEqualToString: @"zblorb"]) {
	    [zList addObject: fileStr];
	}
        if ((i+1)<gi.number_entry)
        {
            err = unzGoToNextFile(uf);
            if (err!=UNZ_OK)
            {
                printf("error %d with zipfile in unzGoToNextFile\n",err);
                break;
            }
        }
    }

    return zList;
}


int do_extract_currentfile(
    unzFile uf,
    const int* popt_extract_without_path,
    const char *out_path,
    const char* password)
{
    char filename_inzip[256];
    char* filename_withoutpath;
    char* p;
    int err=UNZ_OK;
    FILE *fout=NULL;
    void* buf;
    uInt size_buf;

    unz_file_info file_info;
    err = unzGetCurrentFileInfo(uf,&file_info,filename_inzip,sizeof(filename_inzip),NULL,0,NULL,0);

    if (err!=UNZ_OK)
    {
        printf("error %d with zipfile in unzGetCurrentFileInfo\n",err);
        return err;
    }

    size_buf = WRITEBUFFERSIZE;
    buf = (void*)malloc(size_buf);
    if (buf==NULL)
    {
        printf("Error allocating memory\n");
        return UNZ_INTERNALERROR;
    }

    p = filename_withoutpath = filename_inzip;
    while ((*p) != '\0')
    {
        if (((*p)=='/') || ((*p)=='\\'))
            filename_withoutpath = p+1;
        p++;
    }

    if ((*filename_withoutpath)=='\0')
    {
        if ((*popt_extract_without_path)==0)
        {
            printf("creating directory: %s\n",filename_inzip);
            mymkdir(filename_inzip);
        }
    }
    else
    {
        const char* write_filename;
        int skip=0;

	if (out_path)
	    write_filename = out_path;
        else if ((*popt_extract_without_path)==0)
            write_filename = filename_inzip;
        else
            write_filename = filename_withoutpath;

        err = unzOpenCurrentFilePassword(uf,password);
        if (err!=UNZ_OK)
        {
            printf("error %d with zipfile in unzOpenCurrentFilePassword\n",err);
        }

 
        if ((skip==0) && (err==UNZ_OK))
        {
            fout=fopen(write_filename,"wb");

            /* some zipfile don't contain directory alone before file */
            if ((fout==NULL) && ((*popt_extract_without_path)==0) &&
                                (filename_withoutpath!=(char*)filename_inzip))
            {
                char c=*(filename_withoutpath-1);
                *(filename_withoutpath-1)='\0';
                makedir(write_filename);
                *(filename_withoutpath-1)=c;
                fout=fopen(write_filename,"wb");
            }

            if (fout==NULL)
            {
                printf("error opening %s\n",write_filename);
            }
        }

        if (fout!=NULL)
        {
            printf(" extracting: %s\n",write_filename);

            do
            {
                err = unzReadCurrentFile(uf,buf,size_buf);
                if (err<0)
                {
                    printf("error %d with zipfile in unzReadCurrentFile\n",err);
                    break;
                }
                if (err>0)
                    if (fwrite(buf,err,1,fout)!=1)
                    {
                        printf("error in writing extracted file\n");
                        err=UNZ_ERRNO;
                        break;
                    }
            }
            while (err>0);
            if (fout)
                    fclose(fout);

        }

        if (err==UNZ_OK)
        {
            err = unzCloseCurrentFile (uf);
            if (err!=UNZ_OK)
            {
                printf("error %d with zipfile in unzCloseCurrentFile\n",err);
            }
        }
        else
            unzCloseCurrentFile(uf); /* don't lose the error */
    }

    free(buf);
    return err;
}


int do_extract(
    unzFile uf,
    const char *dirname,
    int opt_extract_without_path,
    const char* password,
    ZipExtractCB cb)
{
    uLong i;
    unz_global_info gi;
    int err;
    char outpath[256];
    char filename_inzip[256];

    err = unzGetGlobalInfo (uf,&gi);
    if (err!=UNZ_OK)
        printf("error %d with zipfile in unzGetGlobalInfo \n",err);

    for (i=0;i<gi.number_entry;i++)
    {
        unz_file_info file_info;
        err = unzGetCurrentFileInfo(uf,&file_info,filename_inzip,sizeof(filename_inzip),NULL,0,NULL,0);
	if (err)
	    break;
	strcpy(outpath, dirname);
	strcat(outpath, "/");
	strcat(outpath, filename_inzip);
      
	if (cb)
	    (*cb)(outpath);
        if (do_extract_currentfile(uf,&opt_extract_without_path,outpath,
                                      password) != UNZ_OK)
            break;

        if ((i+1)<gi.number_entry)
        {
            err = unzGoToNextFile(uf);
            if (err!=UNZ_OK)
            {
                printf("error %d with zipfile in unzGoToNextFile\n",err);
                break;
            }
        }
    }

    return 0;
}

int do_extract_onefile(
    unzFile uf,
    const char *dirname,
    const char* filename,
    int opt_extract_without_path,
    const char* password)
{
    const char *lastCompName = strrchr(filename, '/');
    char outpath[256];

    if (lastCompName)
	++lastCompName;
    else
	lastCompName = filename;

    strcpy(outpath, dirname);
    strcat(outpath, "/");
    strcat(outpath, lastCompName);
    if (unzLocateFile(uf,filename,CASESENSITIVITY)!=UNZ_OK)
    {
        printf("file %s not found in the zipfile\n",filename);
        return 2;
    }

    if (do_extract_currentfile(uf,&opt_extract_without_path, outpath, 
                                      password) == UNZ_OK)
        return 0;
    else
        return 1;
}

int extractOneFileFromZIP(NSString *zipFileStr, NSString *dirName, NSString *fileName) {
    const char *zipfilename = [zipFileStr UTF8String];
    const char *dir = [dirName UTF8String];
    const char *file = [fileName UTF8String];
    unzFile uf = NULL;
    int ret = 1;

    if (zipfilename && *zipfilename && file && *file)
        uf = unzOpen(zipfilename);

    if (uf) {
	ret = do_extract_onefile(uf, dir, file, 1, NULL);
	unzCloseCurrentFile(uf);
    }
    return ret;
}

int extractAllFilesFromZIPWithCallback(NSString *zipFileStr, NSString *dirName, ZipExtractCB cb) {
    const char *zipfilename = [zipFileStr UTF8String];
    const char *dir = [dirName UTF8String];
    unzFile uf = NULL;
    int ret = 1;

    if (zipfilename && *zipfilename)
        uf = unzOpen(zipfilename);

    if (uf) { // dir???
	ret = do_extract(uf, dir, 1, NULL, cb);
	unzCloseCurrentFile(uf);
    }
    return ret;
}

int extractAllFilesFromZIP(NSString *zipFileStr, NSString *dirName) {
    return extractAllFilesFromZIPWithCallback(zipFileStr, dirName, NULL);
}

NSMutableArray *listOfZFilesInZIP(NSString *zipFileStr)
{
    const char *zipfilename = [zipFileStr UTF8String];
    unzFile uf = NULL;
    NSMutableArray *zList = nil;

    if (zipfilename && *zipfilename)
        uf = unzOpen(zipfilename);

    if (uf) {
	zList = do_list(uf);
	unzCloseCurrentFile(uf);
    }
    return zList;
}

