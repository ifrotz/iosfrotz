/* $Header: d:/cvsroot/tads/TADS2/H_IX86.H,v 1.2 1999/05/17 02:52:12 MJRoberts Exp $ */

/* 
 *   Copyright (c) 1998, 2002 Michael J. Roberts.  All Rights Reserved.
 *   
 *   Please see the accompanying license file, LICENSE.TXT, for information
 *   on using and copying this software.  
 */
/*
Name
  h_arm32.h - hardware definitions for 32-bit ARM processors
Function
  These definitions are for 32-bit ARM CPUs.  (Note: for
  64-bit ARM hardware, use h_arm64.h instead.  Don't use this file
  for non-Intel platforms, as it assumes Intel byte order and type
  sizes.)
Notes

Modified
  09/04/2016 Craig Smith, created based on MR's 32-bit H_IX86 file
*/

#ifndef H_ARM32_H
#define H_ARM32_H

/* round a size to worst-case alignment boundary */
#define osrndsz(s) (((s)+3) & ~3)

/* round a pointer to worst-case alignment boundary */
#define osrndpt(p) ((uchar *)((((unsigned long)(p)) + 3) & ~3))

/* read unaligned portable unsigned 2-byte value, returning int */
#define osrp2(p) ((int)*(unsigned short *)(p))

/* read unaligned portable signed 2-byte value, returning int */
#define osrp2s(p) ((int)*(short *)(p))

/* write int to unaligned portable 2-byte value */
#define oswp2(p, i) (*(unsigned short *)(p)=(unsigned short)(i))
#define oswp2s(p, i) oswp2(p, i)

/* read unaligned portable 4-byte value, returning unsigned long */
#define osrp4(p) (*(unsigned long *)(p))
#define osrp4s(p) (*(long *)(p))

/* write long to unaligned portable 4-byte value */
#define oswp4(p, l) (*(long *)(p)=(l))
#define oswp4s(p, l) oswp4(p, l)

/* read float from portable 4-byte buffer (IEEE 754-2008 format) */
float osrpfloat(const void *p);

/* write float to portable 4-byte buffer (IEEE 754-2008 format) */
void oswpfloat(void *p, float f);

/* write double to portable 8-byte buffer (IEEE 754-2008 format) */
double osrpdouble(const void *p);

/* read double from portable 8-byte buffer (IEEE 754-2008 format) */
void oswpdouble(void *p, double d);

#endif /* H_ARM32_H */

