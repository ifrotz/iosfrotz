// $Id: memory.c,v 1.11 2004/01/25 21:04:19 iain Exp $

#include "git.h"
#include <stdlib.h>
#include <string.h>

const git_uint8 * gRom;
git_uint8 * gRam;

git_uint32 gRamStart;
git_uint32 gExtStart;
git_uint32 gEndMem;
git_uint32 gOriginalEndMem;

#define RAM_OVERLAP 8

void initMemory (const git_uint8 * gamefile, git_uint32 size)
{
	// Make sure we have at least enough
	// data for the standard glulx header.

	if (size < 36)
		fatalError("This file is too small to be a valid glulx gamefile");
	
	// Set up a basic environment that will
	// let us inspect the header.

	gRom = gamefile;
	gRamStart = 36;

	// Check the magic number. From the spec:
	//     * Magic number: 47 6C 75 6C, which is to say ASCII 'Glul'.

	if (memRead32 (0) != 0x476c756c)
		fatalError("This is not a glulx game file");

	// Load the correct values for ramstart, extstart and endmem.
	// (Load ramstart last because it's required by memRead32 --
	// if we get a wonky ramstart, the other reads could fail.)

	gOriginalEndMem = gEndMem = memRead32 (16);
	gExtStart = memRead32 (12);
	gRamStart = memRead32 (8);

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

	gRamStart -= RAM_OVERLAP; // Adjust RAM boundary to include some ROM.

	gRam = malloc (gEndMem - gRamStart);
    if (gRam == NULL)
        fatalError ("Failed to allocate game RAM");

	gRam -= gRamStart;

	// Copy the initial contents of RAM.
	memcpy (gRam + gRamStart, gRom + gRamStart, gExtStart - gRamStart);

	// Zero out the extended RAM.
	memset (gRam + gExtStart, 0, gEndMem - gExtStart);

	gRamStart += RAM_OVERLAP; // Restore boundary to its previous value.
}

int verifyMemory ()
{
    git_uint32 checksum = 0;

    git_uint32 n;
    for (n = 0 ; n < gExtStart ; n += 4)
        checksum += read32 (gRom + n);
    
    checksum -= read32 (gRom + 32);
    return (checksum == read32 (gRom + 32)) ? 0 : 1;
}

int resizeMemory (git_uint32 newSize, int isInternal)
{
    git_uint8* newRam;
    
    if (newSize == gEndMem)
        return 0; // Size is not changed.
    if (!isInternal && heap_is_active())
        fatalError ("Cannot resize Glulx memory space while heap is active.");
    if (newSize < gOriginalEndMem)
        fatalError ("Cannot resize Glulx memory space smaller than it started.");
    if (newSize & 0xFF)
        fatalError ("Can only resize Glulx memory space to a 256-byte boundary.");
    
    gRamStart -= RAM_OVERLAP; // Adjust RAM boundary to include some ROM.
    newRam = realloc(gRam + gRamStart, newSize - gRamStart);
    if (!newRam)
    {	
        gRamStart += RAM_OVERLAP; // Restore boundary to its previous value.
        return 1; // Failed to extend memory.
    }
    if (newSize > gEndMem)
        memset (newRam + gEndMem - gRamStart, 0, newSize - gEndMem);

    gRam = newRam - gRamStart;
    gEndMem = newSize;
    gRamStart += RAM_OVERLAP; // Restore boundary to its previous value.
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
            gRam [i] = gRom [i];
    }

    // Zero out the extended RAM.
    for (i = gExtStart; i < gEndMem; ++i)
    {
        if (i >= protectEnd || i < protectPos)
            gRam [i] = 0;
    }
}

void shutdownMemory ()
{
    // We didn't allocate the ROM, so we
    // only need to dispose of the RAM.
    
    free (gRam + gRamStart - RAM_OVERLAP);
    
    // Zero out all our globals.
    
    gRamStart = gExtStart = gEndMem = gOriginalEndMem = 0;
    gRom = gRam = NULL;
}

git_uint32 memReadError (git_uint32 address)
{
    fatalError ("Out-of-bounds memory access");
    return 0;
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
    return strncmp(k, (const char*)b, l);
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
    const unsigned char *memoryBegin = gRom, *memoryEnd = memoryBegin + gOriginalEndMem - 1;
    if (!gRom || !gOriginalEndMem) {
        memoryBegin = memmap;
        memoryEnd = memoryBegin + origendmem - 1;
    }
    if (!memoryBegin)
        return status;
    if (!word || !word[0] || !word[1])
        return status;
    if (memoryBegin && memoryBegin < memoryEnd) {
        const unsigned char *endMem = memoryEnd, *p = endMem;
        const unsigned char *barrier = endMem - 256 - 16;
        const unsigned char *stringTable = memoryBegin + read32(memoryBegin + 28);
        int dictWordCount = 0;

        if (barrier < stringTable)
            barrier = stringTable;
        while (p > barrier) {
            if (*p == 0x60 && p[-1]==0x00)
                break;
            --p;
        }
        if (p <= barrier)
            return status;
        
        barrier = stringTable;
        while (*p == 0x60) {
            p -= 16;
            ++dictWordCount;
        }
        p += 12;
        glui32 nEntries = read32(p);
        if (nEntries != dictWordCount)
            return status; // something wrong; we're probably misinterpreting memory
        //printf ("dict entries %d, word '%s'\n", nEntries, word);
        p += 5;
        const git_uint8 *dictStart = p;
        p = bsearch(word, dictStart, nEntries, 16, glulxDictWordCmp);
        if (!p)
            return status;
        while (p >= dictStart && glulxDictWordCmp(word, p)==0)
            p -= 16;
        p += 16;
        const char *firstMatch = (const char*)p, *lastMatch = firstMatch;
        int i = (p - dictStart) / 16;
        for (; i < nEntries; ++i, p+=16) {
            if (glulxDictWordCmp(word, p)!=0)
                break;
            //printf ("word: %s flags %04x\n", p, memRead16(p+9-gRom));
            lastMatch = (const char*)p;
        }
        if (firstMatch == lastMatch) {
            strncpy(result, firstMatch, 9);
            result[9] = 0;
            status = 0;
        }
        else {
            int l = 0;
            while (l < 9 && firstMatch[l]==lastMatch[l])
                l++;
            strncpy(result, firstMatch, l);
            result[l] = 0;
            status = 1;
        }
    }
    return status;
}
