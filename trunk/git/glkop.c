// $Id: glkop.c,v 1.4 2004/12/22 14:33:40 iain Exp $

// glkop.c: Glulxe code for Glk API dispatching.
//  Designed by Andrew Plotkin <erkyrath@eblong.com>
//  http://www.eblong.com/zarf/glulx/index.html

/* This code is actually very general; it could work for almost any
   32-bit VM which remotely resembles Glulxe or the Z-machine in design.
   
   To be precise, we make the following assumptions:

   - An argument list is an array of 32-bit values, which can represent
     either integers or addresses.
   - We can read or write to a 32-bit integer in VM memory using the macros
     ReadMemory(addr) and WriteMemory(addr), where addr is an address
     taken from the argument list.
   - A character array is an actual array of bytes somewhere in terp
     memory, whose actual address can be computed by the macro
     AddressOfArray(addr). Again, addr is a VM address from the argument
     list.
   - An integer array is a sequence of integers somewhere in VM memory.
     The array can be turned into a C integer array by the macro
     CaptureIArray(addr, len), and released by ReleaseIArray().
     These macros are responsible for fixing byte-order and alignment
     (if the C ABI does not match the VM's). The passin, passout hints
     may be used to avoid unnecessary copying.
   - A Glk structure (such as event_t) is a set of integers somewhere
     in VM memory, which can be read and written with the macros
     ReadStructField(addr, fieldnum) and WriteStructField(addr, fieldnum).
     The fieldnum is an integer (from 0 to 3, for event_t.)
   - A VM string can be turned into a C-style string with the macro
     ptr = DecodeVMString(addr). After the string is used, this code
     calls ReleaseVMString(ptr), which should free any memory that
     DecodeVMString allocates.
   - A VM Unicode string can be turned into a zero-terminated array
     of 32-bit integers, in the same way, with DecodeVMUstring
     and ReleaseVMUstring.

     To work this code over for a new VM, just diddle the macros.
*/

#define Stk1(sp)   \
  (*((unsigned char *)(sp)))
#define Stk2(sp)   \
  (*((glui16 *)(sp)))
#define Stk4(sp)   \
  (*((glui32 *)(sp)))

#define StkW1(sp, vl)   \
  (*((unsigned char *)(sp)) = (unsigned char)(vl))
#define StkW2(sp, vl)   \
  (*((glui16 *)(sp)) = (glui16)(vl))
#define StkW4(sp, vl)   \
  (*((glui32 *)(sp)) = (glui32)(vl))


#define ReadMemory(addr)  \
    (((addr) == 0xffffffff) \
      ? (gStackPointer -= 1, Stk4(gStackPointer)) \
      : (memRead32(addr)))
#define WriteMemory(addr, val)  \
    if ((addr) == 0xffffffff) \
    { StkW4(gStackPointer, (val)); gStackPointer += 1;} \
	else memWrite32((addr), (val))
#define AddressOfArray(addr)  \
	((addr) < gRamStart ? (gRom + (addr)) : (gRam + (addr)))
#define AddressOfIArray(addr)  \
	((addr) < gRamStart ? (gRom + (addr)) : (gRam + (addr)))
#define CaptureIArray(addr, len, passin)  \
    (grab_temp_array(addr, len, passin))
#define ReleaseIArray(ptr, addr, len, passout)  \
    (release_temp_array(ptr, addr, len, passout))
#define ReadStructField(addr, fieldnum)  \
    (((addr) == 0xffffffff) \
      ? (gStackPointer -= 1, Stk4(gStackPointer)) \
      : (memRead32((addr)+(fieldnum)*4)))
#define WriteStructField(addr, fieldnum, val)  \
    if ((addr) == 0xffffffff) \
    { StkW4(gStackPointer, (val)); gStackPointer += 1;} \
	else memWrite32((addr)+(fieldnum)*4, (val))

#define glulx_malloc malloc
#define glulx_free free
#define glulx_random rand

#ifndef TRUE
#define TRUE 1
#endif
#ifndef FALSE
#define FALSE 0
#endif

#include "glk.h"
#include "git.h"
#include "gi_dispa.h"
#include "glkios.h"
#include "ipw_buf.h"
#include "ipw_graphics.h"
#include "iphone_frotz.h"

#include <stdlib.h>
#include <string.h>

static char * DecodeVMString (git_uint32 addr)
{
    glui32 end;
    char * data;
    char * c;
    
    // The string must be a C string.
    if (memRead8(addr) != 0xE0)
    {
        fatalError ("Illegal string type passed to Glk function");
    }
    addr += 1;
    
    end = addr;
    while (memRead8(end) != 0)
        ++end;
    
    data = glulx_malloc (end - addr + 1);
    if (data == NULL)
        fatalError ("Couldn't allocate string");

    c = data;
    while (addr < end)
        *c++ = memRead8(addr++);
    *c = 0;
    
    return data;
}

static glui32 * DecodeVMUstring (git_uint32 addr)
{
    glui32 end;
    glui32 * data;
    glui32 * c;
    
    // The string must be a Unicode string.
    if (memRead8(addr) != 0xE2)
    {
        fatalError ("Illegal string type passed to Glk function");
    }
    addr += 4;
    
    end = addr;
    while (memRead32(end) != 0)
        end += 4;
    
    data = glulx_malloc (end - addr + 4);
    if (data == NULL)
        fatalError ("Couldn't allocate string");

    c = data;
    while (addr < end)
    {
        *c++ = memRead32(addr);
        addr += 4;
    }
    *c = 0;
    
    return data;
}

static void ReleaseVMString (char * ptr)
{
    glulx_free (ptr);
}

static void ReleaseVMUstring (glui32 * ptr)
{
    glulx_free (ptr);
}

typedef struct dispatch_splot_struct {
  int numwanted;
  int maxargs;
  gluniversal_t *garglist;
  glui32 *varglist;
  int numvargs;
  glui32 *retval;
} dispatch_splot_t;

/* We maintain a linked list of arrays being used for Glk calls. It is
   only used for integer (glui32) arrays -- char arrays are handled in
   place. It's not worth bothering with a hash table, since most
   arrays appear here only momentarily. */

typedef struct arrayref_struct arrayref_t;
struct arrayref_struct {
  void *array;
  glui32 addr;
  glui32 elemsize;
  glui32 len; /* elements */
  int retained;
  arrayref_t *next;
};

static arrayref_t *arrays = NULL;

/* We maintain a hash table for each opaque Glk class. classref_t are the
    nodes of the table, and classtable_t are the tables themselves. */

typedef struct classref_struct classref_t;
struct classref_struct {
  void *obj;
  glui32 id;
  int bucknum;
  classref_t *next;
};

#define CLASSHASH_SIZE (31)
typedef struct classtable_struct {
  glui32 lastid;
  classref_t *bucket[CLASSHASH_SIZE];
} classtable_t;

/* The list of hash tables, for the git_classes. */
static int num_classes = 0;
classtable_t **git_classes = NULL;

static classtable_t *new_classtable(glui32 firstid);
static void *classes_get(int classid, glui32 objid);
static classref_t *classes_put(int classid, void *obj);
static void classes_remove(int classid, void *obj);

static gidispatch_rock_t glulxe_classtable_register(void *obj, 
  glui32 objclass);
static void glulxe_classtable_unregister(void *obj, glui32 objclass, 
  gidispatch_rock_t objrock);
static gidispatch_rock_t glulxe_retained_register(void *array,
  glui32 len, char *typecode);
static void glulxe_retained_unregister(void *array, glui32 len, 
  char *typecode, gidispatch_rock_t objrock);

static glui32 *grab_temp_array(glui32 addr, glui32 len, int passin);
static void release_temp_array(glui32 *arr, glui32 addr, glui32 len, int passout);

static void prepare_glk_args(char *proto, dispatch_splot_t *splot);
static void parse_glk_args(dispatch_splot_t *splot, char **proto, int depth,
  int *argnumptr, glui32 subaddress, int subpassin);
static void unparse_glk_args(dispatch_splot_t *splot, char **proto, int depth,
  int *argnumptr, glui32 subaddress, int subpassout);

/* init_dispatch():
   Set up the class hash tables and other startup-time stuff. 
*/
int git_init_dispatch()
{
  int ix;
    
  /* Allocate the class hash tables. */
  num_classes = gidispatch_count_classes();
  git_classes = (classtable_t **)glulx_malloc(num_classes 
    * sizeof(classtable_t *));
  if (!git_classes)
    return FALSE;
    
  for (ix=0; ix<num_classes; ix++) {
    git_classes[ix] = new_classtable((glulx_random() % (glui32)(101)) + 1);
    if (!git_classes[ix])
      return FALSE;
  }
    
  /* Set up the two callbacks. */
  gidispatch_set_object_registry(&glulxe_classtable_register, 
    &glulxe_classtable_unregister);
  gidispatch_set_retained_registry(&glulxe_retained_register, 
    &glulxe_retained_unregister);
    
  return TRUE;
}

/* perform_glk():
   Turn a list of Glulx arguments into a list of Glk arguments,
   dispatch the function call, and return the result. 
*/
glui32 git_perform_glk(glui32 funcnum, glui32 numargs, glui32 *arglist)
{
  glui32 retval = 0;

  switch (funcnum) {
    /* To speed life up, we implement commonly-used Glk functions
       directly -- instead of bothering with the whole prototype 
       mess. */

  case 0x0080: /* put_char */
    if (numargs != 1)
      goto WrongArgNum;
    glk_put_char(arglist[0] & 0xFF);
    break;
  case 0x0081: /* put_char_stream */
    if (numargs != 2)
      goto WrongArgNum;
    glk_put_char_stream(git_find_stream_by_id(arglist[0]), arglist[1] & 0xFF);
    break;
  case 0x00A0: /* char_to_lower */
    if (numargs != 1)
      goto WrongArgNum;
    retval = glk_char_to_lower(arglist[0] & 0xFF);
    break;
  case 0x00A1: /* char_to_upper */
    if (numargs != 1)
      goto WrongArgNum;
    retval = glk_char_to_upper(arglist[0] & 0xFF);
    break;

  WrongArgNum:
    fatalError("Wrong number of arguments to Glk function.");
    break;

  default: {
    /* Go through the full dispatcher prototype foo. */
    char *proto, *cx;
    dispatch_splot_t splot;
    int argnum;

    /* Grab the string. */
    proto = gidispatch_prototype(funcnum);
    if (!proto)
      fatalError("Unknown Glk function.");

    splot.varglist = arglist;
    splot.numvargs = numargs;
    splot.retval = &retval;

    /* The work goes in four phases. First, we figure out how many
       arguments we want, and allocate space for the Glk argument
       list. Then we go through the Glulxe arguments and load them 
       into the Glk list. Then we call. Then we go through the 
       arguments again, unloading the data back into Glulx memory. */

    /* Phase 0. */
    prepare_glk_args(proto, &splot);

    /* Phase 1. */
    argnum = 0;
    cx = proto;
    parse_glk_args(&splot, &cx, 0, &argnum, 0, 0);

    /* Phase 2. */
    gidispatch_call(funcnum, argnum, splot.garglist);

    /* Phase 3. */
    argnum = 0;
    cx = proto;
    unparse_glk_args(&splot, &cx, 0, &argnum, 0, 0);

    break;
  }
  }

  return retval;
}

/* read_prefix():
   Read the prefixes of an argument string -- the "<>&+:#!" chars. 
*/
static char *read_prefix(char *cx, int *isref, int *isarray,
  int *passin, int *passout, int *nullok, int *isretained, 
  int *isreturn)
{
  *isref = FALSE;
  *passin = FALSE;
  *passout = FALSE;
  *nullok = TRUE;
  *isarray = FALSE;
  *isretained = FALSE;
  *isreturn = FALSE;
  while (1) {
    if (*cx == '<') {
      *isref = TRUE;
      *passout = TRUE;
    }
    else if (*cx == '>') {
      *isref = TRUE;
      *passin = TRUE;
    }
    else if (*cx == '&') {
      *isref = TRUE;
      *passout = TRUE;
      *passin = TRUE;
    }
    else if (*cx == '+') {
      *nullok = FALSE;
    }
    else if (*cx == ':') {
      *isref = TRUE;
      *passout = TRUE;
      *nullok = FALSE;
      *isreturn = TRUE;
    }
    else if (*cx == '#') {
      *isarray = TRUE;
    }
    else if (*cx == '!') {
      *isretained = TRUE;
    }
    else {
      break;
    }
    cx++;
  }
  return cx;
}

/* prepare_glk_args():
   This reads through the prototype string, and pulls Floo objects off the
   stack. It also works out the maximal number of gluniversal_t objects
   which could be used by the Glk call in question. It then allocates
   space for them.
*/
static void prepare_glk_args(char *proto, dispatch_splot_t *splot)
{
  static gluniversal_t *garglist = NULL;
  static int garglist_size = 0;

  int ix;
  int numwanted, numvargswanted, maxargs;
  char *cx;

  cx = proto;
  numwanted = 0;
  while (*cx >= '0' && *cx <= '9') {
    numwanted = 10 * numwanted + (*cx - '0');
    cx++;
  }
  splot->numwanted = numwanted;

  maxargs = 0; 
  numvargswanted = 0; 
  for (ix = 0; ix < numwanted; ix++) {
    int isref, passin, passout, nullok, isarray, isretained, isreturn;
    cx = read_prefix(cx, &isref, &isarray, &passin, &passout, &nullok,
      &isretained, &isreturn);
    if (isref) {
      maxargs += 2;
    }
    else {
      maxargs += 1;
    }
    if (!isreturn) {
      if (isarray) {
        numvargswanted += 2;
      }
      else {
        numvargswanted += 1;
      }
    }
        
    if (*cx == 'I' || *cx == 'C') {
      cx += 2;
    }
    else if (*cx == 'Q') {
      cx += 2;
    }
    else if (*cx == 'S' || *cx == 'U') {
      cx += 1;
    }
    else if (*cx == '[') {
      int refdepth, nwx;
      cx++;
      nwx = 0;
      while (*cx >= '0' && *cx <= '9') {
        nwx = 10 * nwx + (*cx - '0');
        cx++;
      }
      maxargs += nwx; /* This is *only* correct because all structs contain
                         plain values. */
      refdepth = 1;
      while (refdepth > 0) {
        if (*cx == '[')
          refdepth++;
        else if (*cx == ']')
          refdepth--;
        cx++;
      }
    }
    else {
      fatalError("Illegal format string.");
    }
  }

  if (*cx != ':' && *cx != '\0')
    fatalError("Illegal format string.");

  splot->maxargs = maxargs;

  if (splot->numvargs != numvargswanted)
    fatalError("Wrong number of arguments to Glk function.");

  if (garglist && garglist_size < maxargs) {
    glulx_free(garglist);
    garglist = NULL;
    garglist_size = 0;
  }
  if (!garglist) {
    garglist_size = maxargs + 16;
    garglist = (gluniversal_t *)glulx_malloc(garglist_size 
      * sizeof(gluniversal_t));
  }
  if (!garglist)
    fatalError("Unable to allocate storage for Glk arguments.");

  splot->garglist = garglist;
}

/* parse_glk_args():
   This long and unpleasant function translates a set of Floo objects into
   a gluniversal_t array. It's recursive, too, to deal with structures.
*/
static void parse_glk_args(dispatch_splot_t *splot, char **proto, int depth,
  int *argnumptr, glui32 subaddress, int subpassin)
{
  char *cx;
  int ix, argx;
  int gargnum, numwanted;
  void *opref;
  gluniversal_t *garglist;
  glui32 *varglist;
  
  garglist = splot->garglist;
  varglist = splot->varglist;
  gargnum = *argnumptr;
  cx = *proto;

  numwanted = 0;
  while (*cx >= '0' && *cx <= '9') {
    numwanted = 10 * numwanted + (*cx - '0');
    cx++;
  }

  for (argx = 0, ix = 0; argx < numwanted; argx++, ix++) {
    char typeclass;
    int skipval;
    int isref, passin, passout, nullok, isarray, isretained, isreturn;
    cx = read_prefix(cx, &isref, &isarray, &passin, &passout, &nullok,
      &isretained, &isreturn);
    
    typeclass = *cx;
    cx++;

    skipval = FALSE;
    if (isref) {
      if (!isreturn && varglist[ix] == 0) {
        if (!nullok)
          fatalError("Zero passed invalidly to Glk function.");
        garglist[gargnum].ptrflag = FALSE;
        gargnum++;
        skipval = TRUE;
      }
      else {
        garglist[gargnum].ptrflag = TRUE;
        gargnum++;
      }
    }
    if (!skipval) {
      glui32 thisval;

      if (typeclass == '[') {

        parse_glk_args(splot, &cx, depth+1, &gargnum, varglist[ix], passin);

      }
      else if (isarray) {
        /* definitely isref */

        switch (typeclass) {
        case 'C':
          garglist[gargnum].array = (void*) AddressOfArray(varglist[ix]);
          gargnum++;
          ix++;
          garglist[gargnum].uint = varglist[ix];
          gargnum++;
          cx++;
          break;
        case 'I':
          garglist[gargnum].array = CaptureIArray(varglist[ix], varglist[ix+1], passin);
          gargnum++;
          ix++;
          garglist[gargnum].uint = varglist[ix];
          gargnum++;
          cx++;
          break;
        default:
          fatalError("Illegal format string.");
          break;
        }
      }
      else {
        /* a plain value or a reference to one. */

        if (isreturn) {
          thisval = 0;
        }
        else if (depth > 0) {
          /* Definitely not isref or isarray. */
          if (subpassin)
            thisval = ReadStructField(subaddress, ix);
          else
            thisval = 0;
        }
        else if (isref) {
          if (passin)
            thisval = ReadMemory(varglist[ix]);
          else
            thisval = 0;
        }
        else {
          thisval = varglist[ix];
        }

        switch (typeclass) {
        case 'I':
          if (*cx == 'u')
            garglist[gargnum].uint = (glui32)(thisval);
          else if (*cx == 's')
            garglist[gargnum].sint = (glsi32)(thisval);
          else
            fatalError("Illegal format string.");
          gargnum++;
          cx++;
          break;
        case 'Q':
          if (thisval) {
            opref = classes_get(*cx-'a', thisval);
            if (!opref) {
              fatalError("Reference to nonexistent Glk object.");
            }
          }
          else {
            opref = NULL;
          }
          garglist[gargnum].opaqueref = opref;
          gargnum++;
          cx++;
          break;
        case 'C':
          if (*cx == 'u') 
            garglist[gargnum].uch = (unsigned char)(thisval);
          else if (*cx == 's')
            garglist[gargnum].sch = (signed char)(thisval);
          else if (*cx == 'n')
            garglist[gargnum].ch = (char)(thisval);
          else
            fatalError("Illegal format string.");
          gargnum++;
          cx++;
          break;
        case 'S':
          garglist[gargnum].charstr = DecodeVMString(thisval);
          gargnum++;
          break;
#ifdef GLK_MODULE_UNICODE
        case 'U':
          garglist[gargnum].unicharstr = DecodeVMUstring(thisval);
	      gargnum++;
          break;
#endif
        default:
          fatalError("Illegal format string.");
          break;
        }
      }
    }
    else {
      /* We got a null reference, so we have to skip the format element. */
      if (typeclass == '[') {
        int numsubwanted, refdepth;
        numsubwanted = 0;
        while (*cx >= '0' && *cx <= '9') {
          numsubwanted = 10 * numsubwanted + (*cx - '0');
          cx++;
        }
        refdepth = 1;
        while (refdepth > 0) {
          if (*cx == '[')
            refdepth++;
          else if (*cx == ']')
            refdepth--;
          cx++;
        }
      }
      else if (typeclass == 'S' || typeclass == 'U') {
        /* leave it */
      }
      else {
        cx++;
      }
    }    
  }

  if (depth > 0) {
    if (*cx != ']')
      fatalError("Illegal format string.");
    cx++;
  }
  else {
    if (*cx != ':' && *cx != '\0')
      fatalError("Illegal format string.");
  }
  
  *proto = cx;
  *argnumptr = gargnum;
}

/* unparse_glk_args():
   This is about the reverse of parse_glk_args(). 
*/
static void unparse_glk_args(dispatch_splot_t *splot, char **proto, int depth,
  int *argnumptr, glui32 subaddress, int subpassout)
{
  char *cx;
  int ix, argx;
  int gargnum, numwanted;
  void *opref;
  gluniversal_t *garglist;
  glui32 *varglist;
  
  garglist = splot->garglist;
  varglist = splot->varglist;
  gargnum = *argnumptr;
  cx = *proto;

  numwanted = 0;
  while (*cx >= '0' && *cx <= '9') {
    numwanted = 10 * numwanted + (*cx - '0');
    cx++;
  }

  for (argx = 0, ix = 0; argx < numwanted; argx++, ix++) {
    char typeclass;
    int skipval;
    int isref, passin, passout, nullok, isarray, isretained, isreturn;
    cx = read_prefix(cx, &isref, &isarray, &passin, &passout, &nullok,
      &isretained, &isreturn);
    
    typeclass = *cx;
    cx++;

    skipval = FALSE;
    if (isref) {
      if (!isreturn && varglist[ix] == 0) {
        if (!nullok)
          fatalError("Zero passed invalidly to Glk function.");
        garglist[gargnum].ptrflag = FALSE;
        gargnum++;
        skipval = TRUE;
      }
      else {
        garglist[gargnum].ptrflag = TRUE;
        gargnum++;
      }
    }
    if (!skipval) {
      glui32 thisval = 0;

      if (typeclass == '[') {

        unparse_glk_args(splot, &cx, depth+1, &gargnum, varglist[ix], passout);

      }
      else if (isarray) {
        /* definitely isref */

        switch (typeclass) {
        case 'C':
          gargnum++;
          ix++;
          gargnum++;
          cx++;
          break;
        case 'I':
          ReleaseIArray(garglist[gargnum].array, varglist[ix], varglist[ix+1], passout);
          gargnum++;
          ix++;
          gargnum++;
          cx++;
          break;
        default:
          fatalError("Illegal format string.");
          break;
        }
      }
      else {
        /* a plain value or a reference to one. */

	if (isreturn || (depth > 0 && subpassout) || (isref && passout)) {
	  skipval = FALSE;
	}
	else {
	  skipval = TRUE;
	}

	switch (typeclass) {
	case 'I':
	  if (!skipval) {
	    if (*cx == 'u')
	      thisval = (glui32)garglist[gargnum].uint;
	    else if (*cx == 's')
	      thisval = (glui32)garglist[gargnum].sint;
	    else
	      fatalError("Illegal format string.");
	  }
	  gargnum++;
	  cx++;
	  break;
	case 'Q':
	  if (!skipval) {
	    opref = garglist[gargnum].opaqueref;
	    if (opref) {
	      gidispatch_rock_t objrock = 
		gidispatch_get_objrock(opref, *cx-'a');
	      thisval = ((classref_t *)objrock.ptr)->id;
	    }
	    else {
	      thisval = 0;
	    }
	  }
	  gargnum++;
	  cx++;
	  break;
	case 'C':
	  if (!skipval) {
	    if (*cx == 'u') 
	      thisval = (glui32)garglist[gargnum].uch;
	    else if (*cx == 's')
	      thisval = (glui32)garglist[gargnum].sch;
	    else if (*cx == 'n')
	      thisval = (glui32)garglist[gargnum].ch;
	    else
	      fatalError("Illegal format string.");
	  }
	  gargnum++;
	  cx++;
	  break;
	case 'S':
	  if (garglist[gargnum].charstr)
	    ReleaseVMString(garglist[gargnum].charstr);
          gargnum++;
          break;
#ifdef GLK_MODULE_UNICODE
        case 'U':
          if (garglist[gargnum].unicharstr)
            ReleaseVMUstring(garglist[gargnum].unicharstr);
	  gargnum++;
	  break;
#endif
	default:
	  fatalError("Illegal format string.");
	  break;
	}

        if (isreturn) {
          *(splot->retval) = thisval;
        }
        else if (depth > 0) {
          /* Definitely not isref or isarray. */
          if (subpassout)
          {
            WriteStructField(subaddress, ix, thisval);
          }
        }
        else if (isref) {
          if (passout)
          {
            WriteMemory(varglist[ix], thisval);
          }
        }
      }
    }
    else {
      /* We got a null reference, so we have to skip the format element. */
      if (typeclass == '[') {
        int numsubwanted, refdepth;
        numsubwanted = 0;
        while (*cx >= '0' && *cx <= '9') {
          numsubwanted = 10 * numsubwanted + (*cx - '0');
          cx++;
        }
        refdepth = 1;
        while (refdepth > 0) {
          if (*cx == '[')
            refdepth++;
          else if (*cx == ']')
            refdepth--;
          cx++;
        }
      }
      else if (typeclass == 'S' || typeclass == 'U') {
        /* leave it */
      }
      else {
        cx++;
      }
    }    
  }

  if (depth > 0) {
    if (*cx != ']')
      fatalError("Illegal format string.");
    cx++;
  }
  else {
    if (*cx != ':' && *cx != '\0')
      fatalError("Illegal format string.");
  }
  
  *proto = cx;
  *argnumptr = gargnum;
}

/* find_stream_by_id():
   This is used by some interpreter code which has to, well, find a Glk
   stream given its ID. 
*/
strid_t git_find_stream_by_id(glui32 objid)
{
  if (!objid)
    return NULL;

  /* Recall that class 1 ("b") is streams. */
  return classes_get(1, objid);
}

/* Build a hash table to hold a set of Glk objects. */
static classtable_t *new_classtable(glui32 firstid)
{
  int ix;
  classtable_t *ctab = (classtable_t *)glulx_malloc(sizeof(classtable_t));
  if (!ctab)
    return NULL;
    
  for (ix=0; ix<CLASSHASH_SIZE; ix++)
    ctab->bucket[ix] = NULL;
    
  ctab->lastid = firstid;
    
  return ctab;
}

/* Find a Glk object in the appropriate hash table. */
static void *classes_get(int classid, glui32 objid)
{
  classtable_t *ctab;
  classref_t *cref;
  if (classid < 0 || classid >= num_classes)
    return NULL;
  ctab = git_classes[classid];
  cref = ctab->bucket[objid % CLASSHASH_SIZE];
  for (; cref; cref = cref->next) {
    if (cref->id == objid)
      return cref->obj;
  }
  return NULL;
}

/* Put a Glk object in the appropriate hash table. */
static classref_t *classes_put(int classid, void *obj)
{
  int bucknum;
  classtable_t *ctab;
  classref_t *cref;
  if (classid < 0 || classid >= num_classes)
    return NULL;
  ctab = git_classes[classid];
  cref = (classref_t *)glulx_malloc(sizeof(classref_t));
  if (!cref)
    return NULL;
  cref->obj = obj;
  cref->id = ctab->lastid;
  ctab->lastid++;
  bucknum = cref->id % CLASSHASH_SIZE;
  cref->bucknum = bucknum;
  cref->next = ctab->bucket[bucknum];
  ctab->bucket[bucknum] = cref;
  return cref;
}

/* Delete a Glk object from the appropriate hash table. */
static void classes_remove(int classid, void *obj)
{
  classtable_t *ctab;
  classref_t *cref;
  classref_t **crefp;
  gidispatch_rock_t objrock;
  if (classid < 0 || classid >= num_classes)
    return;
  ctab = git_classes[classid];
  objrock = gidispatch_get_objrock(obj, classid);
  cref = objrock.ptr;
  if (!cref)
    return;
  crefp = &(ctab->bucket[cref->bucknum]);
  for (; *crefp; crefp = &((*crefp)->next)) {
    if ((*crefp) == cref) {
      *crefp = cref->next;
      if (!cref->obj) {
        fprintf(stderr, "attempt to free NULL object!\n");
      }
      cref->obj = NULL;
      cref->id = 0;
      cref->next = NULL;
      glulx_free(cref);
      return;
    }
  }
  return;
}

/* The object registration/unregistration callbacks that the library calls
    to keep the hash tables up to date. */
    
static gidispatch_rock_t glulxe_classtable_register(void *obj, 
  glui32 objclass)
{
  classref_t *cref;
  gidispatch_rock_t objrock;
  cref = classes_put(objclass, obj);
  objrock.ptr = cref;
  return objrock;
}

static void glulxe_classtable_unregister(void *obj, glui32 objclass, 
  gidispatch_rock_t objrock)
{
  classes_remove(objclass, obj);
}

static glui32 *grab_temp_array(glui32 addr, glui32 len, int passin)
{
  arrayref_t *arref = NULL;
  glui32 *arr = NULL;
  glui32 ix, addr2;

  if (len) {
    arr = (glui32 *)glulx_malloc(len * sizeof(glui32));
    arref = (arrayref_t *)glulx_malloc(sizeof(arrayref_t));
    if (!arr || !arref) 
      fatalError("Unable to allocate space for array argument to Glk call.");

    arref->array = arr;
    arref->addr = addr;
    arref->elemsize = 4;
    arref->retained = FALSE;
    arref->len = len;
    arref->next = arrays;
    arrays = arref;

    if (passin) {
      for (ix=0, addr2=addr; ix<len; ix++, addr2+=4) {
        arr[ix] = memRead32(addr2);
      }
    }
  }

  return arr;
}

static void release_temp_array(glui32 *arr, glui32 addr, glui32 len, int passout)
{
  arrayref_t *arref = NULL;
  arrayref_t **aptr;
  glui32 ix, val, addr2;

  if (arr) {
    for (aptr=(&arrays); (*aptr); aptr=(&((*aptr)->next))) {
      if ((*aptr)->array == arr)
        break;
    }
    arref = *aptr;
    if (!arref)
      fatalError("Unable to re-find array argument in Glk call.");
    if (arref->addr != addr || arref->len != len)
      fatalError("Mismatched array argument in Glk call.");

    if (arref->retained) {
      return;
    }

    *aptr = arref->next;
    arref->next = NULL;

    if (passout) {
      for (ix=0, addr2=addr; ix<len; ix++, addr2+=4) {
        val = arr[ix];
        memWrite32(addr2, val);
      }
    }
    glulx_free(arr);
    glulx_free(arref);
  }
}

gidispatch_rock_t glulxe_retained_register(void *array,
  glui32 len, char *typecode)
{
  gidispatch_rock_t rock;
  arrayref_t *arref = NULL;
  arrayref_t **aptr;

  if (typecode[4] != 'I' || array == NULL) {
    /* We only retain integer arrays. */
    rock.ptr = NULL;
    return rock;
  }

  for (aptr=(&arrays); (*aptr); aptr=(&((*aptr)->next))) {
    if ((*aptr)->array == array)
      break;
  }
  arref = *aptr;
  if (!arref)
    fatalError("Unable to re-find array argument in Glk call.");
  if (arref->elemsize != 4 || arref->len != len)
    fatalError("Mismatched array argument in Glk call.");

  arref->retained = TRUE;

  rock.ptr = arref;
  return rock;
}

void glulxe_retained_unregister(void *array, glui32 len, 
  char *typecode, gidispatch_rock_t objrock)
{
  arrayref_t *arref = NULL;
  arrayref_t **aptr;
  glui32 ix, addr2, val;

  if (typecode[4] != 'I' || array == NULL) {
    /* We only retain integer arrays. */
    return;
  }

  for (aptr=(&arrays); (*aptr); aptr=(&((*aptr)->next))) {
    if ((*aptr)->array == array)
      break;
  }
  arref = *aptr;
  if (!arref)
    fatalError("Unable to re-find array argument in Glk call.");
  if (arref != objrock.ptr)
    fatalError("Mismatched array reference in Glk call.");
  if (!arref->retained)
    fatalError("Unretained array reference in Glk call.");
  if (arref->elemsize != 4 || arref->len != len)
    fatalError("Mismatched array argument in Glk call.");

  for (ix=0, addr2=arref->addr; ix<arref->len; ix++, addr2+=4) {
    val = ((glui32 *)array)[ix];
    memWrite32(addr2, val);
  }
  glulx_free(array);
  glulx_free(arref);
}


//
// Glk Classes autosave/restore code based on CellarDoor (PalmOS) by Jeremy Bernstein
// Code below is from glk/glkop.c in CellarDoor 1.1.2 (GPLv2), with minor modifications.
//
///////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////


struct glk_window_autosave {
    glui32 magicnum;
    glui32 rock;
    glui32 type;
    
    grect_t bbox;

    int line_request;
    int line_request_uni;
    int char_request;
    int char_request_uni;

    glui32 style;
    glui32 size;
    glui32 method;
    glui32 splitwin;

    char *inbuf; // textbuffer type only
    int inmax;
};

#define kInvalidSplitWin (0xFFFFFFFF)


struct glk_stream_autosave {
    glui32 magicnum;
    glui32 rock;

    int type; /* file, window, or memory stream */
    int unicode; /* one-byte or four-byte chars? Not meaningful for windows */
    
    glui32 readcount, writecount;
    int readable, writable;
    
    /* for strtype_Window */
//    intptr_t win;

    unsigned char *buf;
    unsigned char *bufptr;
    unsigned char *bufend;
    unsigned char *bufeof;
    glui32 *ubuf;
    glui32 *ubufptr;
    glui32 *ubufend;
    glui32 *ubufeof;
    glui32 buflen;
};

struct glk_fileref_autosave {
    glui32 magicnum;
    glui32 rock;

//  char *filename; // ???
    int filetype;
    int textmode;
};

struct glk_winpair_autosave {
    int splitpos;
    int splitwidth; /* The width of the border. Zero or one. */

    glui32 dir; /* winmethod_Left, Right, Above, or Below */
    int vertical, backward; /* flags */
    glui32 division; /* winmethod_Fixed or winmethod_Proportional */

    glui32 size; /* size value */
    
    glui32 child1, child2; // child windows IDs
};

struct glk_wingraphics_autosave {
    int width, height;
    glui32 backcolor;
};

struct glk_object_save {
    glui32    type; // 0 = window, 1 = stream, 2 = file, 3 = sound, 0xFFFFFFFF = style
    glui32    id; // for style, this is the id of the owning window, or 0xFFFFFFF1 for buffer or 0xFFFFFFF2 for grid
    union {
        struct glk_window_autosave win;
        struct glk_stream_autosave str;
	struct glk_fileref_autosave fref;
	struct glk_winpair_autosave pair;
	struct glk_wingraphics_autosave gfx;
        GLK_STYLE_HINTS style[style_NUMSTYLES];
    } obj;
    int        iscurrent;
};

#define type_Style     0xFFFFFFFF
#define type_Pair      0xFFFFFFFE
#define type_Graphics  0xFFFFFFFD

typedef struct glk_object_save glk_object_save_t;

static void saveWin(window_t *win, struct glk_window_autosave *s) {
    s->magicnum = win->magicnum;
    s->rock = win->rock;
    s->type = win->type;

    s->bbox = win->bbox;

    s->line_request = win->line_request;
    s->line_request_uni = win->line_request_uni;
    s->char_request = win->char_request;
    s->char_request_uni = win->char_request_uni;

    if (win->type == wintype_TextBuffer) {
	window_textbuffer_t *wtb = (window_textbuffer_t*)win->data;
	s->inbuf = wtb->inbuf;
	s->inmax = wtb->inmax;
    } else {
	s->inbuf = NULL;
	s->inmax = 0;
    }
    s->style = win->style;
    s->size = win->size;
    s->method = win->method;
    s->splitwin = win->splitwin;
}

static void saveStream(stream_t *str, struct glk_stream_autosave *s) {
    s->magicnum = str->magicnum;
    s->rock = str->rock;

    s->type = str->type;
    s->unicode = str->type;
    
    s->readcount = str->readcount;
    s->writecount = str->writecount;
    s->readable = str->readable;
    s->writable = str->writable;

    s->buf = str->buf;
    s->bufptr = str->bufptr;
    s->bufend = str->bufend;
    s->bufeof = str->bufeof;
    s->ubuf = str->ubuf;
    s->ubufptr = str->ubufptr;
    s->ubufend = str->ubufend;
    s->ubufeof = str->ubufeof;

    s->buflen = str->buflen;
}

static void saveFRef(fileref_t *fref, struct glk_fileref_autosave *s) {
    s->magicnum = fref->magicnum;
    s->rock = fref->rock;
    s->filetype = fref->filetype;
    s->textmode = fref->textmode;
}

static void saveWinPair(window_pair_t *wp, struct glk_winpair_autosave *s) {
    s->splitpos = wp->splitpos;
    s->splitwidth = wp->splitwidth;

    s->dir = wp->dir;
    s->vertical = wp->vertical;
    s->backward = wp->backward;
    s->division = wp->division;

    s->size = wp->size;
    
    s->child1 = 0;
    s->child2 = 0;
}

static void saveWinGfx(window_graphics_t *wp, struct glk_wingraphics_autosave *s) {
    s->width = wp->width;
    s->height = wp->height;
    s->backcolor = wp->backcolor;
}

static void restoreWin(window_t *win, struct glk_window_autosave  *s) {
    win->magicnum = s->magicnum;
    win->rock = s->rock;
    win->type = s->type;

    win->bbox = s->bbox;

    win->line_request = s->line_request;
    win->line_request_uni = s->line_request_uni;
    win->char_request = s->char_request;
    win->char_request_uni = s->char_request_uni;

    win->style = s->style;
    win->size = s->size;
    win->method = s->method;
    win->splitwin = s->splitwin;
}

static glui32 classes_find_id_for_object(int classid, void *obj)
{
	classtable_t *ctab;
	classref_t *cref;
	int i;
	if (classid < 0 || classid >= num_classes)
		return -1;
	ctab = git_classes[classid];
	for (i = 0; i < CLASSHASH_SIZE; i++) {
		cref = ctab->bucket[i];
		for (; cref; cref = cref->next) {
			if (cref->obj == obj)
				return cref->id;
		}
	}
	return -1;
}

/* Find a Glk object in the appropriate hash table. */
static classref_t *classes_pop_cref(int classid, glui32 objid)
{
	classtable_t *ctab;
	classref_t *cref;
	if (classid < 0 || classid >= num_classes)
		return NULL;
	ctab = git_classes[classid];
	cref = ctab->bucket[objid % CLASSHASH_SIZE];
	for (; cref; cref = cref->next) {
		if (cref->id == objid) {
			classref_t **crefp;
			int bucknum;
			
			bucknum = cref->bucknum;
			crefp = &(ctab->bucket[bucknum]);
			for (; *crefp; crefp = &((*crefp)->next)) {
				if ((*crefp) == cref) {
					*crefp = cref->next;
					return cref;
				}
			}
			return cref;
		}
	}
	return NULL;
}

static void classes_push_cref(int classid, classref_t *cref)
{
	int bucknum;
	classtable_t *ctab;

	if (classid < 0 || classid >= num_classes)
		return;

	if (!cref)
		return;

	ctab = git_classes[classid];
	
	bucknum = cref->id % CLASSHASH_SIZE;
	cref->bucknum = bucknum;
	cref->next = ctab->bucket[bucknum];
	ctab->bucket[bucknum] = cref;
}

static void classes_denormalize_pointers(glui32 objclass, void *obj)
{
	if (objclass == gidisp_Class_Window) {
		struct glk_window_autosave *win = (struct glk_window_autosave *)obj;
		
		if (win->inbuf)	win->inbuf 	+= (glui32)gRam;

	} else if (objclass == gidisp_Class_Stream) {
		struct glk_stream_autosave *str = (struct glk_stream_autosave *)obj;

		if (str->buf)		str->buf     += (glui32)gRam;
		if (str->bufptr)	str->bufptr  += (glui32)gRam;
		if (str->bufend)	str->bufend  += (glui32)gRam;
		if (str->bufeof)	str->bufeof  += (glui32)gRam;

		if (str->ubuf)		str->ubuf    += (glui32)gRam;
		if (str->ubufptr)	str->ubufptr += (glui32)gRam;
		if (str->ubufend)	str->ubufend += (glui32)gRam;
		if (str->ubufeof)	str->ubufeof += (glui32)gRam;
	} else if (objclass == gidisp_Class_Fileref) {
		;
	} else if (objclass == gidisp_Class_Schannel) {
		;
	}
}

static void classes_normalize_pointers(glk_object_save_t *obj)
{

	if (obj->type == gidisp_Class_Window) {
		struct glk_window_autosave *win = &obj->obj.win;
		
		if (win->inbuf)	win->inbuf	-= (glui32)gRam;
		if (win->splitwin) {
			win->splitwin = classes_find_id_for_object(gidisp_Class_Window, (void *)win->splitwin);
		} else {
			win->splitwin = kInvalidSplitWin; // definitely an invalid id
		}
	} else if (obj->type == gidisp_Class_Stream) {
		struct glk_stream_autosave *str = &obj->obj.str;

		if (str->buf) 		str->buf     -= (glui32)gRam;
		if (str->bufptr)	str->bufptr  -= (glui32)gRam;
		if (str->bufend)	str->bufend  -= (glui32)gRam;
		if (str->bufeof)	str->bufeof  -= (glui32)gRam;

		if (str->ubuf)		str->ubuf    -= (glui32)gRam;
		if (str->ubufptr)	str->ubufptr -= (glui32)gRam;
		if (str->ubufend)	str->ubufend -= (glui32)gRam;
		if (str->ubufeof)	str->ubufeof -= (glui32)gRam;
	} else if (obj->type == gidisp_Class_Fileref) {
		;
	} else if (obj->type == gidisp_Class_Schannel) {
		;
	}
}

static glui32 classes_iter(glk_object_save_t **objs)
{
	classtable_t *ctab;
	classref_t *cref;
	glui32 num_classes;
	glui32 i,j,ct = 0;
	glk_object_save_t *o = NULL, *cur;
	
	window_t  *win;
	stream_t *str_cur = glk_stream_get_current();
	
	if (!objs)
	    return 0;
	
	*objs = NULL;

	num_classes = gidispatch_count_classes();
	ct = 0;
	for (i = 0; i < num_classes; i++) { // iterate everything quickly
		if ((ctab = git_classes[i])) {
			for (j = 0; j < CLASSHASH_SIZE; j++) {
				cref = ctab->bucket[j];
				for ( ; cref; cref = cref->next) {
					if (i == 0) {
					    window_t *win = (window_t *)cref->obj;
					    win->store = 0;
					} else if (i == 1) {
					    stream_t *str = (stream_t *)cref->obj;
					    str->store = 0;
					}
					ct++;
				}
			}
		}
	}
	if (!ct) return 0;
	
	// add entries for windows with styles/pair info + the two general styles
	win = NULL;
	while ((win = gli_window_iterate_backward(win, NULL))) {
		if (win->type == wintype_TextBuffer || win->type == wintype_TextGrid
		    || win->type == wintype_Pair || win->type == wintype_Graphics)
			ct++;
	}
	// leave off the last 2 in the event of no styles in use!
	if (gli_window_has_stylehints())
		ct += 2;
	
	o = glulx_malloc(sizeof(glk_object_save_t) * ct);
	if (!o) return 0;
	
	ct = 0;
	win = NULL;
	while ((win = gli_window_iterate_backward(win, NULL))) {
		cur = o + ct;
		memset(cur, 0, sizeof(glk_object_save_t));

		cur->type = gidisp_Class_Window;
		cur->id = classes_find_id_for_object(0, win);

		saveWin(win, &cur->obj.win);
		//!!!cur->obj.win = *win;
		win->store = TRUE;
		cur->iscurrent = FALSE; //(win == win_cur);
		classes_normalize_pointers(cur);

		ct++;
		// get stream for window
		if ((win->type == wintype_TextBuffer) || (win->type == wintype_TextGrid)) {

			// write STREAM chunk
			cur = o + ct;
			memset(cur, 0, sizeof(glk_object_save_t));
	
			cur->type = gidisp_Class_Stream;
			cur->id = classes_find_id_for_object(1, win->str);
			//!!!cur->obj.str = *win->str;
			
			saveStream(win->str, &cur->obj.str);
			win->str->store = TRUE;
			cur->iscurrent = (win->str == str_cur);
			classes_normalize_pointers(cur);
			ct++;

			// write STYLE chunk
			cur = o + ct;
			memset(cur, 0, sizeof(glk_object_save_t));

			cur->type = type_Style;
			cur->id = classes_find_id_for_object(0, win);

			GLK_STYLE_HINTS hints[style_NUMSTYLES];

			gli_window_get_stylehints(win, hints);
			memcpy(cur->obj.style, hints, sizeof(GLK_STYLE_HINTS) * style_NUMSTYLES);

			ct++;
		} else if (win->type == wintype_Pair) {
			window_pair_t *pairwin = (window_pair_t*)win->data;

			// write PAIR chunk
			cur = o + ct;
			memset(cur, 0, sizeof(glk_object_save_t));
			
			cur->type = type_Pair;
			cur->id = classes_find_id_for_object(0, win);

			//!!!cur->obj.pair = *((window_pair_t *)win->data);
			saveWinPair(pairwin, &cur->obj.pair);

			(window_pair_t *)&cur->obj.pair;
			// set the children to their ids so we can find the pair on reload
			cur->obj.pair.child1 = classes_find_id_for_object(gidisp_Class_Window, pairwin->child1);
			cur->obj.pair.child2 = classes_find_id_for_object(gidisp_Class_Window, pairwin->child2);
			//!!!classes_normalize_pointers(cur);

			ct++;
		} else if (win->type == wintype_Graphics) {
			// write GRAPHICS chunk
			cur = o + ct;
			memset(cur, 0, sizeof(glk_object_save_t));
			
			cur->type = type_Graphics;
			cur->id = classes_find_id_for_object(0, win);

			saveWinGfx((window_graphics_t *)win->data, &cur->obj.gfx);
			ct++;
		}
	}
	// now, iterate other classes; window streams should have already been accounted for, but we check this
	for (i = 0; i < num_classes; i++) {
		if ((ctab = git_classes[i])) {
			for (j = 0; j < CLASSHASH_SIZE; j++) {
				cref = ctab->bucket[j];
				for ( ; cref; cref = cref->next) {	
					if (i == 0) { // windows
						window_t *win = (window_t *)cref->obj;
						
						if (!win->store) {
							cur = o + ct;
							memset(cur, 0, sizeof(glk_object_save_t));

							cur->type = i;
							cur->id = cref->id;
						}
					} else {
						if (i == 1) { // streams
							stream_t *str = (stream_t *)cref->obj;

							if (!str->store) {
								cur = o + ct;
								memset(cur, 0, sizeof(glk_object_save_t));
								cur->type = i;
								cur->id = cref->id;

								//!!!cur->obj.str = *str;
								saveStream(str, &cur->obj.str);
								cur->iscurrent = (str == str_cur);
								classes_normalize_pointers(cur);
								ct++;
							}
						} else if (i == 2) {
							fileref_t *fref = (fileref_t *)cref->obj;
						
							cur = o + ct;
							memset(cur, 0, sizeof(glk_object_save_t));
							cur->type = i;
							cur->id = cref->id;

							//!!!cur->obj.fref = *fref;
							saveFRef(fref, &cur->obj.fref);
							classes_normalize_pointers(cur);
							ct++;
						} else if (i == 3) { // won't happen here
							;
						}
					}
				}
			}
		}
	}
	// 2 general styles

	if (gli_window_has_stylehints()) {
		GLK_STYLE_HINTS hints[style_NUMSTYLES];

		cur = o + ct;
		memset(cur, 0, sizeof(glk_object_save_t));
		cur->type = type_Style;
		cur->id = STYLEHINT_TEXT_BUFFER;

		gli_window_get_stylehints((winid_t)STYLEHINT_TEXT_BUFFER, hints);

		memcpy(cur->obj.style, hints, sizeof(GLK_STYLE_HINTS) * style_NUMSTYLES);
		ct++;

		cur = o + ct;
		memset(cur, 0, sizeof(glk_object_save_t));
		cur->type = type_Style;
		cur->id = STYLEHINT_TEXT_GRID;

		gli_window_get_stylehints((winid_t)STYLEHINT_TEXT_GRID, hints);

		memcpy(cur->obj.style, hints, sizeof(GLK_STYLE_HINTS) * style_NUMSTYLES);
		ct++;
	}

	*objs = o;
	return ct;
}

typedef struct _winid {
	window_t	*win;
	glui32		id;
} t_winid;

static git_sint32 classes_restore(glk_object_save_t *objects, glui32 objects_count)
{
	glk_object_save_t *cur;
	int found;
	classtable_t *ctab;
	classref_t *cref, *cref_id;
	int i, j;
	window_t *win = NULL, *splitwin = NULL;
	struct glk_window_autosave *foundwin = NULL;
	stream_t *str = NULL;
	struct glk_stream_autosave *foundstr = NULL;
	glui32 id;
	int winct = 0, winct2 = 0;
	t_winid winid[kMaxGlkViews];
	stream_t *cur_str = NULL;
	char errbuf[256];

	for (i = 0; i < kMaxGlkViews; i++) {
		winid[i].win = NULL;
		winid[i].id = 0;
	}

	for (i = 0; i < objects_count; i++) { 
		found = FALSE;
		// windows come first, in the correct order, alternated with their streams/hints
		cur = objects + i;
		// don't bother iterating through current - there are none at autoload
		if (cur->type == gidisp_Class_Window) {
			winct++;
			foundwin = &cur->obj.win;
			classes_denormalize_pointers(gidisp_Class_Window, foundwin);

			winid[winct-1].id = cur->id; // fill this in for a pair, too

			if (foundwin->type != wintype_Pair) {
				splitwin = NULL;
				if (foundwin->splitwin != kInvalidSplitWin) { // this had no splitwin going in
					for (j = 0; j < kMaxGlkViews; j++) {
						if (winid[j].id == foundwin->splitwin) {
							splitwin = winid[j].win;
							break;
						}
					}
				}
				win = (window_t *)glk_window_open(splitwin, foundwin->method, foundwin->size, foundwin->type, foundwin->rock);
				if (!win) {
					sprintf(errbuf, "\nCould not create %s window with id %ld. Aborting restore.\n", 
						foundwin->type == wintype_TextBuffer ? "textbuffer" : 
						foundwin->type == wintype_TextGrid ? "textgrid" : 
						foundwin->type == wintype_Blank ? "blank" : "graphics", (long)cur->id);
					iphone_win_puts(0, errbuf);
					return FALSE;
				}
				winid[winct-1].win = win;

				// check id, set id if necessary
				id = classes_find_id_for_object(gidisp_Class_Window, win);
				if (id != cur->id) {
					cref_id = classes_pop_cref(gidisp_Class_Window, id);
					cref_id->id = cur->id; // auto-awarding should ensure that an id has not been reused
					classes_push_cref(gidisp_Class_Window, cref_id);
				}
				win->line_request = foundwin->line_request;
				win->char_request = foundwin->char_request;
				win->line_request_uni = foundwin->line_request_uni;
				win->char_request_uni = foundwin->char_request_uni;
				if (foundwin->inbuf) {
					window_textbuffer_t *wtb = (window_textbuffer_t*)win->data;
					wtb->inbuf = foundwin->inbuf;
					wtb->inmax = foundwin->inmax;
				}
				found = TRUE;
			}
			if (found && (win->type == wintype_TextBuffer || win->type == wintype_TextGrid)) {
				// read STREAM chunk
				i++;
				cur = objects + i;
				if (cur->type != gidisp_Class_Stream) {
					sprintf(errbuf, "\nUnexpected window stream type. Aborting restore.\n", cur->type);
					iphone_win_puts(0, errbuf);
					return FALSE;
				} else {
					foundstr = &cur->obj.str;
					str = win->str;
				
					id = classes_find_id_for_object(gidisp_Class_Stream, str);
					if (id != cur->id) {
						cref_id = classes_pop_cref(gidisp_Class_Stream, id);
						cref_id->id = cur->id; // auto-awarding should verify that an id has not been reused
						classes_push_cref(gidisp_Class_Stream, cref_id);
					}
					classes_denormalize_pointers(gidisp_Class_Stream, foundstr);

					str->rock = foundstr->rock;
					str->readcount = foundstr->readcount;
					str->writecount = foundstr->writecount;
					str->readable = foundstr->readable;
					str->writable = foundstr->writable;
					if (!str->buf && foundstr->buf) {
						str->buf = foundstr->buf;
						str->bufptr = foundstr->bufptr;
						str->bufend = foundstr->bufend;
						str->bufeof = foundstr->bufeof;
						str->buflen = foundstr->buflen;
					}
					if (cur->iscurrent) {
						cur_str = str;
					}
				}
				// read STYLE chunk
				i++;
				cur = objects + i;
				if (cur->type != type_Style) {
					sprintf(errbuf, "\nUnexpected stream type %d. Aborting restore.\n", cur->type);
					iphone_win_puts(0, errbuf);
					return FALSE;
				} else {
					gli_window_set_stylehints(win, (GLK_STYLE_HINTS *)&cur->obj.style);
				}
				iphone_set_glk_default_colors(win->iphone_glkViewNum);
			} else if (found && win->type == wintype_Graphics) {
				if (i+1 < objects_count && objects[i+1].type == type_Graphics) {
					i++;
					cur = objects + i;
					window_graphics_t *wgp = (window_graphics_t*)win->data;
					wgp->width = cur->obj.gfx.width;
					wgp->height = cur->obj.gfx.height;
					wgp->backcolor = cur->obj.gfx.backcolor;
					iphone_set_background_color(win->iphone_glkViewNum, wgp->backcolor);
				}
			} else if (found && win->type == wintype_Pair) {
				// this will never happen
				i++;
			}
		} else if (cur->type == gidisp_Class_Stream) {
			break;
		} else if (cur->type == type_Pair) {
			struct glk_winpair_autosave *pairwin = &cur->obj.pair;
			// find the children; if they exist, make sure that this window is registered under the correct id
			glui32 id1 = (glui32)pairwin->child1;
			glui32 id2 = (glui32)pairwin->child2;
			window_t *win1 = NULL;
			window_t *win2 = NULL;

			for (j = 0; j < kMaxGlkViews; j++) {
				if (winid[j].id == id1) {
					win1 = winid[j].win;
				} else if (winid[j].id == id2) {
					win2 = winid[j].win;
				}
				if (win1 && win2) break;
			}
			if (win1 && win2) { // we found it
				// check id, set id if necessary
				id = classes_find_id_for_object(gidisp_Class_Window, win1->parent); // get the parent
				if (id != cur->id) {
					cref_id = classes_pop_cref(gidisp_Class_Window, id);
					cref_id->id = cur->id; // auto-awarding should ensure that an id has not been reused
					classes_push_cref(gidisp_Class_Window, cref_id);
				}
				// enter window in the window id list, so other windows can find it, too, if it's being used as a splitwin
				for (j = 0; j < kMaxGlkViews; j++) {
					if (winid[j].id == cur->id) {
						winid[j].win = win1->parent;
						break;
					}
				}
			}
		}
	}
	// verify window count
	if ((ctab = git_classes[gidisp_Class_Window])) {
		for (j = 0; j < CLASSHASH_SIZE; j++) {
			cref = ctab->bucket[j];
			for ( ; cref; cref = cref->next) {
				winct2++;
			}
		}
	}
	if (winct != winct2) {
		sprintf(errbuf, "\n[Autorestore warning: window count mismatch %d!=%d]\n", winct, winct2);
		iphone_win_puts(0, errbuf);		
	}

	// freakin' great, so let's re-iterate, simultaneously doing an iteration and compare

	// start over, verify all window ids, including pairs
	win = NULL;
	for (i = 0; i < objects_count; i++) { 
		// windows come first, in the correct order, alternated with their streams
		cur = objects + i;
		if (cur->type == gidisp_Class_Window) {
			foundwin = &cur->obj.win;

			win = gli_window_iterate_backward(win, NULL);
			if (win->type == foundwin->type) {
				win->rock = foundwin->rock;
				id = classes_find_id_for_object(gidisp_Class_Window, win);
				if (id != cur->id) {
					cref_id = classes_pop_cref(gidisp_Class_Window, id);
					cref_id->id = cur->id; // auto-awarding should verify that an id has not been reused
					classes_push_cref(gidisp_Class_Window, cref_id);
				}
				break;
			} else {
				iphone_win_puts(0, "\nCould not restore saved state. Sorry. Aborting restore.\n");
				return FALSE;
			}
			// restore RECT
			win->bbox = foundwin->bbox;

			if (win->type == wintype_TextBuffer || win->type == wintype_TextGrid) {
				// read STREAM chunk
				i++;
				cur = objects + i;
				if (cur->type != gidisp_Class_Stream) {
					iphone_win_puts(0, "\nMissing stream. Aborting restore.\n");
					return FALSE;
				} else {
					foundstr = &cur->obj.str;
					str = win->str;
				
					str->rock = foundstr->rock;
					id = classes_find_id_for_object(gidisp_Class_Stream, str);
					if (id != cur->id) {
						cref_id = classes_pop_cref(gidisp_Class_Stream, id);
						cref_id->id = cur->id; // auto-awarding should verify that an id has not been reused
						classes_push_cref(gidisp_Class_Stream, cref_id);
					}
				}
				// read STYLE chunk
				i++;
				cur = objects + i;
				if (cur->type != type_Style) {
					// style chunk is not where it should be
					iphone_win_puts(0, "\nMissing style chunk. Aborting restore.\n");
					return FALSE;
				}
			} else if (win->type == wintype_Pair) {
				// read PAIR chunk
				i++;
				cur = objects + i;
				
				if (cur->type != type_Pair) {
					iphone_win_puts(0, "\nCorrupt win pair. Aborting restore.\n");
					return FALSE;
				} else {
					struct glk_winpair_autosave *foundpair = &cur->obj.pair;
					window_pair_t *pair = (window_pair_t *)win->data;
					
					pair->splitpos = foundpair->splitpos;
					pair->splitwidth = foundpair->splitwidth;
					pair->dir = foundpair->dir;
					pair->vertical = foundpair->vertical;
					pair->backward = foundpair->backward;
					pair->size = foundpair->size;
				}
			}
		} else if (cur->type == gidisp_Class_Stream) { // now do the streams
			stream_t *tempstr;

			found = FALSE;
			foundstr = &cur->obj.str;
			
			if ((ctab = git_classes[gidisp_Class_Stream])) {
				for (j = 0; j < CLASSHASH_SIZE; j++) {
					cref = ctab->bucket[j];
					for ( ; cref; cref = cref->next) {						
						tempstr = (stream_t *)cref->obj;
						if (tempstr->type == foundstr->type && tempstr->rock == foundstr->rock) { // this id should be clearer
							id = classes_find_id_for_object(gidisp_Class_Stream, tempstr);
							if (id != cur->id) {
								cref_id = classes_pop_cref(gidisp_Class_Stream, id);
								cref_id->id = cur->id; // auto-awarding should verify that an id has not been reused
								classes_push_cref(gidisp_Class_Stream, cref_id);
							}
							classes_denormalize_pointers(gidisp_Class_Stream, foundstr);

							tempstr->rock = foundstr->rock;
							if (tempstr->type != strtype_File && !tempstr->buf && foundstr->buf) {
								tempstr->readcount = foundstr->readcount;
								tempstr->writecount = foundstr->writecount;
								tempstr->readable = foundstr->readable;
								tempstr->writable = foundstr->writable;
								tempstr->buf = foundstr->buf;
								tempstr->bufptr = foundstr->bufptr;
								tempstr->bufend = foundstr->bufend;
								tempstr->bufeof = foundstr->bufeof;
								tempstr->buflen = foundstr->buflen;
								if (cur->iscurrent) {
									cur_str = tempstr;
								}
							} else if (tempstr->type == strtype_File) {
								//fd("not touching file info for the moment");
							}
							found = TRUE;
							break;
						}
					}
					if (found)
						break;
				}
			}
			if (!found) {
				// we're here because nothing matched; make a new stream
				sprintf(errbuf, "\n[Autorestore warning: a stream of type %s is missing: id %d]\n",
					(cur->type == strtype_File) ? "strtype_File" : 
					(cur->type == strtype_Window) ? "strtype_Window" : 
					(cur->type == strtype_Memory) ? "strtype_Memory" : "UNKNOWN", (int)cur->id);
				iphone_win_puts(0, errbuf);
			}
		} else if (cur->type == gidisp_Class_Fileref) {
			iphone_win_puts(0, "\n[Autorestore warning: missing file stream]\n");
		} else if (cur->type == type_Style) {
			if (cur->id == STYLEHINT_TEXT_BUFFER) {
				gli_window_set_stylehints((winid_t)STYLEHINT_TEXT_BUFFER, (GLK_STYLE_HINTS *)&cur->obj.style);
			} else if (cur->id == STYLEHINT_TEXT_GRID) {
				gli_window_set_stylehints((winid_t)STYLEHINT_TEXT_GRID, (GLK_STYLE_HINTS *)&cur->obj.style);
			}
		}
	}
	// restore current output stream
	if (cur_str) {
		glk_stream_set_current(cur_str);
	}
	return TRUE;
}

#define FrotzGlkClassChunkVersionNum 0x01000001

void saveObjectClasses(int objectCount, void * objectsP) {
    char buffer[4];

    glk_put_string ("iFzA");

    write32 (buffer, objectCount * sizeof(glk_object_save_t));
    glk_put_buffer (buffer, 4);

    write32 (buffer, FrotzGlkClassChunkVersionNum);
    glk_put_buffer (buffer, 4);

    write32 (buffer, objectCount);
    glk_put_buffer (buffer, 4);

    glk_put_buffer ((char *) objectsP, objectCount*sizeof(glk_object_save_t));
}


git_sint32 saveToFileStrWithClasses (git_sint32 * base, git_sint32 * sp, strid_t fstr) {
    glk_object_save_t *objects = NULL;
    int objects_count = classes_iter(&objects);
    git_sint32 ret = saveToFileStrCore (base, sp, fstr, objects_count, objects, saveObjectClasses);
    free(objects);
    return ret;
}

git_sint32 restoreClassesChunk(strid_t file, git_uint32 chunkSize) {
    glk_object_save_t *objects;
    char buffer [4];

    glk_get_buffer_stream (file, buffer, 4);
    int versionNum = read32(buffer);

    if (versionNum == FrotzGlkClassChunkVersionNum) {
	glk_get_buffer_stream (file, buffer, 4);
	int objects_count = read32(buffer);

	objects = calloc(objects_count, sizeof(glk_object_save_t));
	glk_get_buffer_stream(file, (char *)objects, chunkSize);
	int status = classes_restore(objects, objects_count);
	free(objects);
	return status;
    } else {
	iphone_win_puts(0, "\n[Corrupt autosave - incorrect Glk Class Save version number]\n");
	return FALSE;
    }
}


