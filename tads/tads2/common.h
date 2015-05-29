#ifndef COMMON_H
#define COMMON_H

#define HAVE_CONFIG_H 1

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

/* ushort, uint, and ulong are usually in <sys/types.h>
 */
#ifdef HAVE_SYS_TYPES_H
#include <sys/types.h>
#endif

/* Check for the existence of uchar, ushort, uint and ulong and define
 * the appropriate OS_*_DEFINED macros.
 */
#ifdef __cplusplus
#ifdef CXX_UCHAR_DEFINED
#define OS_UCHAR_DEFINED
#endif
#ifdef CXX_USHORT_DEFINED
#define OS_USHORT_DEFINED
#endif
#ifdef CXX_UINT_DEFINED
#define OS_UINT_DEFINED
#endif
#ifdef CXX_ULONG_DEFINED
#define OS_ULONG_DEFINED
#endif
#else /* !__cplusplus */
#ifdef C_UCHAR_DEFINED
#define OS_UCHAR_DEFINED
#endif
#ifdef C_USHORT_DEFINED
#define OS_USHORT_DEFINED
#endif
#ifdef C_UINT_DEFINED
#define OS_UINT_DEFINED
#endif
#ifdef C_ULONG_DEFINED
#define OS_ULONG_DEFINED
#endif
#endif /* __cplusplus */

/* The intention is to work around a bug on old systems where we cannot
 * include both <time.h> and <sys/time.h>.  Anyway, for now, this does
 * not work, since the TADS base code includes <time.h> on its own.
 * This may be fixed in the future though.
 */
#ifdef __cplusplus
extern "C" {
#endif
#if TIME_WITH_SYS_TIME
# include <sys/time.h>
# include <time.h>
#else
# if HAVE_SYS_TIME_H
#  include <sys/time.h>
# else
#  include <time.h>
# endif
#endif
#ifdef __cplusplus
}
#endif

#ifdef __cplusplus

/* Define the "and", "or" and "not" keywords if the C++ compiler lacks
 * them.  Normally, if just one of them is available, the others are
 * too.  But there is no harm in checking them individually.  We only
 * define them when compiling C++, since a) these keywords are not valid
 * in C and b) some C compilers define them either for convenience or to
 * support C99.
 */
#ifndef HAVE_AND_KEYWORD
#define and &&
#endif
#ifndef HAVE_OR_KEYWORD
#define or ||
#endif
#ifndef HAVE_NOT_KEYWORD
#define not !
#endif

/* For casting, C++ code should *not* use X_cast<type>(value) but rather
 * X_cast(type)(value).  If the compiler supports the X_cast keywords,
 * we define the X_cast macros to use the right syntax.  If not, we make
 * them use old-style syntax.
 */
#ifdef HAVE_STATIC_CAST
#define static_cast(a) static_cast<a>
#else
#define static_cast(a) (a)
#endif

#ifdef HAVE_DYNAMIC_CAST
#define dynamic_cast(a) dynamic_cast<a>
#else
#define dynamic_cast(a) (a)
#endif

#ifdef HAVE_REINTERPRET_CAST
#define reinterpret_cast(a) reinterpret_cast<a>
#else
#define reinterpret_cast(a) (a)
#endif

#ifndef HAVE_BOOL
/* The C++ compiler lacks "bool".  Define it.  We do not use macros for
 * this; with an enum and typedef we always have the same type-safety as
 * with a compiler that has native bool-support.  Implicit casts to
 * "int" still work as they should.
 */
enum booleanValues { false, true };
typedef enum booleanValues bool;
#endif

#endif /* __cplusplus */

#endif /* COMMON_H */
