// $Id: memory.c,v 1.11 2004/01/25 21:04:19 iain Exp $

#include "git.h"
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

const git_uint8 * gInitMem;
git_uint8 * gMem;

git_uint32 gRamStart;
git_uint32 gExtStart;
git_uint32 gEndMem;
git_uint32 gOriginalEndMem;

void initMemory (const git_uint8 * gamefile, git_uint32 size)
{
	// Make sure we have at least enough
	// data for the standard glulx header.

	if (size < 36)
		fatalError("This file is too small to be a valid glulx gamefile");
	
	gInitMem = gamefile;

	// Check the magic number. From the spec:
	//     * Magic number: 47 6C 75 6C, which is to say ASCII 'Glul'.

	if (read32 (gInitMem + 0) != 0x476c756c)
		fatalError("This is not a glulx game file");

	// Load the correct values for ramstart, extstart and endmem.

	gRamStart = read32 (gInitMem + 8);
	gExtStart = read32 (gInitMem + 12);
	gOriginalEndMem = gEndMem = read32 (gInitMem + 16);

	// Make sure the values are sane.

    if (gRamStart < 36)
	    fatalError ("Bad header (RamStart is too low)");
        
    if (gRamStart > size)
	    fatalError ("Bad header (RamStart is bigger than the entire gamefile)");
        
    if (gExtStart > size)
	    fatalError ("Bad header (ExtStart is bigger than the entire gamefile)");
        
    if (gExtStart < gRamStart)
	    fatalError ("Bad header (ExtStart is lower than RamStart)");
        
    if (gEndMem < gExtStart)
	    fatalError ("Bad header (EndMem is lower than ExtStart)");
        
	if (gRamStart & 255)
	    fatalError ("Bad header (RamStart is not a multiple of 256)");

	if (gExtStart & 255)
	    fatalError ("Bad header (ExtStart is not a multiple of 256)");

	if (gEndMem & 255)
	    fatalError ("Bad header (EndMem is not a multiple of 256)");

	// Allocate the RAM. We'll duplicate the last few bytes of ROM
	// here so that reads which cross the ROM/RAM boundary don't fail.

	gMem = malloc (gEndMem);
        if (gMem == NULL)
	    fatalError ("Failed to allocate game RAM");

	// Copy the initial memory contents.
	memcpy (gMem, gInitMem, gExtStart);

	// Zero out the extended RAM.
	memset (gMem + gExtStart, 0, gEndMem - gExtStart);
}

int verifyMemory ()
{
    git_uint32 checksum = 0;

    git_uint32 n;
    for (n = 0 ; n < gExtStart ; n += 4)
        checksum += read32 (gInitMem + n);
    
    checksum -= read32 (gInitMem + 32);
    return (checksum == read32 (gInitMem + 32)) ? 0 : 1;
}

int resizeMemory (git_uint32 newSize, int isInternal)
{
    git_uint8* newMem;
    
    if (newSize == gEndMem)
        return 0; // Size is not changed.
    if (!isInternal && heap_is_active())
        fatalError ("Cannot resize Glulx memory space while heap is active.");
    if (newSize < gOriginalEndMem)
        fatalError ("Cannot resize Glulx memory space smaller than it started.");
    if (newSize & 0xFF)
        fatalError ("Can only resize Glulx memory space to a 256-byte boundary.");
    
    newMem = realloc(gMem, newSize);
    if (!newMem)
    {	
        return 1; // Failed to extend memory.
    }
    if (newSize > gEndMem)
        memset (newMem + gEndMem, 0, newSize - gEndMem);

    gMem = newMem;
    gEndMem = newSize;
    return 0;
}

void resetMemory (git_uint32 protectPos, git_uint32 protectSize)
{
    git_uint32 protectEnd = protectPos + protectSize;
    git_uint32 i;

    // Deactivate the heap (if it was active).
    heap_clear();

    gEndMem = gOriginalEndMem;
      
    // Copy the initial contents of RAM.
    for (i = gRamStart; i < gExtStart; ++i)
    {
        if (i >= protectEnd || i < protectPos)
            gMem [i] = gInitMem [i];
    }

    // Zero out the extended RAM.
    for (i = gExtStart; i < gEndMem; ++i)
    {
        if (i >= protectEnd || i < protectPos)
            gMem [i] = 0;
    }
}

void shutdownMemory ()
{
    // We didn't allocate the ROM, so we
    // only need to dispose of the RAM.
    
    free (gMem);
    
    // Zero out all our globals.
    
    gRamStart = gExtStart = gEndMem = gOriginalEndMem = 0;
    gInitMem = gMem = NULL;
}

void memReadError (git_uint32 address)
{
    fatalError ("Out-of-bounds memory access");
}

void memWriteError (git_uint32 address)
{
    fatalError ("Out-of-bounds memory access");
}

int glulxDictWordCmp(const void *a, const void *b) {
    const char *k = (const char*)a;
    int l = strlen(k);
    if (l > 9)
        l = 9;
    return strncasecmp(k, (const char*)b, l);
}

// Glulx doesn't store the location of the dictionary in the header, but Inform 6 always stores it at
// the end of memory, in a well known format that hasn't ever changed, so try to detect it.
// Dict entries are 16 bytes, beginning with 0x60, followed by 9 byte word, 2 byte flags, 4 bytes padding.
// An int32 number of entries is stored before the first entry.  After the last entry, which is the last
// non-padding data in the game file, the game is padded with zeroes up to a multiple of 256 bytes.

extern unsigned char *memmap;
extern glui32 origendmem;

int glulxCompleteWord(const char *word, char *result) {
    int status = 2; // 2=not found, 1=ambiguous match, 0=full match. Same as ZMachine frotz complete func.
    *result = '\0';
    const unsigned char *memoryBegin = gInitMem, *memoryEnd = memoryBegin + gOriginalEndMem - 1, *p;
    if (!gInitMem || !gOriginalEndMem) {
        memoryBegin = memmap;
        memoryEnd = memoryBegin + origendmem - 1;
    }
    if (!memoryBegin)
        return status;
    if (!word || !word[0] || !word[1])
        return status;
    if (memoryBegin && memoryBegin < memoryEnd) {
        static glui32 checksumCache, endgamefileCache;
        static const git_uint8 *dictStartCache = NULL;
        static int dictWordCountCache = 0, worddiffCache = 0;

        const unsigned char *endMem = memoryEnd;
        int dictWordCount = 0;
        int worddiff = 0;
        const git_uint8 *dictStart = NULL;

        glui32 checksum = read32(memoryBegin + 32), endgamefile = read32(memoryBegin + 12);
        if (checksum == checksumCache && endgamefile == endgamefileCache) {
            dictWordCount = dictWordCountCache;
            worddiff = worddiffCache;
            dictStart = dictStartCache;
        } else {
            checksumCache = checksum;
            endgamefileCache = endgamefile;

            if (memoryBegin[36]=='I') {
                p = endMem;
                const unsigned char *barrier = endMem - 256 - 16;
                const unsigned char *stringTable = memoryBegin + read32(memoryBegin + 28);
                
                if (barrier < stringTable)
                    barrier = stringTable;
                while (p > barrier) {
                    if (*p == 0x60 && p[-1]==0x00)
                        break;
                    --p;
                }
                if (p <= barrier)
                    return status;
                worddiff = 16;
                barrier = stringTable;
                while (*p == 0x60) {
                    p -= worddiff;
                    ++dictWordCount;
                }
                p += 12;
                glui32 nEntries = read32(p);
                if (nEntries == dictWordCount) {
                    //printf ("dict entries %d, word '%s'\n", nEntries, word);
                    p += 5;
                    dictStart = p;
                } // else something wrong; we're probably misinterpreting memory
            } else if (memoryBegin[5] == 0x02) {
                const unsigned char *startFuncAddr = memoryBegin + read32(memoryBegin + 24);
                const unsigned char *ramStart = memoryBegin + read32(memoryBegin + 8);
                if (startFuncAddr < memoryEnd && ramStart < memoryEnd && startFuncAddr < ramStart) {
                    p = startFuncAddr;
                    while (p < ramStart - 64) {
                        if (*p == 0xe0 && p[22]==0 && p[24]==0xe0 && p[46]==0 && p[48]==0xe0) {
                            worddiff = 24;
                            break;
                        } else if (*p == 0xe0 && p[14]==0 && p[16]==0xe0 && p[30]==0 && p[32]==0xe0) {
                            worddiff = 16;
                            break;
                        }
                        ++p;
                    }
                    if (worddiff != 0) {
                        dictStart = p+1;
                        while (p < ramStart - 64 && *p == 0xe0) {
                            p += worddiff;
                            ++dictWordCount;
                        }
                    }
                }
            }
            dictWordCountCache = dictWordCount;
            worddiffCache = worddiff;
            dictStartCache = dictStart;
        }
        if (!dictStart || !worddiff)
            return status;

        p = bsearch(word, dictStart, dictWordCount, worddiff, glulxDictWordCmp);
        if (!p)
            return status;
        while (p >= dictStart && glulxDictWordCmp(word, p)==0)
            p -= worddiff;
        p += worddiff;
        const char *firstMatch = (const char*)p, *lastMatch = firstMatch;
        int i = (p - dictStart) / worddiff;
        for (; i < dictWordCount; ++i, p+=worddiff) {
            if (glulxDictWordCmp(word, p)!=0)
                break;
            //printf ("word: %s flags %04x\n", p, memRead16(p+9-gRom));
            lastMatch = (const char*)p;
        }
        int maxwordlen = worddiff == 24 ? 10 : 9;
        if (firstMatch == lastMatch) {
            strncpy(result, firstMatch, maxwordlen);
            result[maxwordlen] = 0;
            status = 0;
        }
        else {
            int l = 0;
            while (l < maxwordlen && firstMatch[l]==lastMatch[l])
                l++;
            strncpy(result, firstMatch, l);
            result[l] = 0;
            status = 1;
        }
        if (status < 2) {
            char *sl = result;
            int allUpper = 1;
            while (*sl != '\0') {
                if (!isupper(*sl))
                    allUpper = 0;
                ++sl;
            }
            sl = result;
            if (allUpper) {
                while (*sl != '\0') {
                    if (isupper(*sl))
                        *sl = tolower(*sl);
                    ++sl;
                }
            }
        }
        
    }
    return status;
}
