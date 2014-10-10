#include <stdio.h>
#include <strings.h>
#include <stdlib.h>
#include <time.h>
#include <sys/time.h>
#include "glk.h"
#include "glkios.h"

/* This file is copied directly from the cheapglk package. */

#ifdef GLK_MODULE_DATETIME

/* Copy a POSIX tm structure to a glkdate. */
static void gli_date_from_tm(glkdate_t *date, struct tm *tm)
{
    date->year = 1900 + tm->tm_year;
    date->month = 1 + tm->tm_mon;
    date->day = tm->tm_mday;
    date->weekday = tm->tm_wday;
    date->hour = tm->tm_hour;
    date->minute = tm->tm_min;
    date->second = tm->tm_sec;
}

/* Copy a glkdate to a POSIX tm structure. 
   This is used in the "glk_date_to_..." functions, which are supposed
   to normalize the glkdate. We're going to rely on the mktime() / 
   timegm() functions to do that -- except they don't handle microseconds.
   So we'll have to do that normalization here, adjust the tm_sec value,
   and return the normalized number of microseconds.
*/
static glsi32 gli_date_to_tm(glkdate_t *date, struct tm *tm)
{
    glsi32 microsec;

    bzero(tm, sizeof(*tm));
    tm->tm_year = date->year - 1900;
    tm->tm_mon = date->month - 1;
    tm->tm_mday = date->day;
    tm->tm_wday = date->weekday;
    tm->tm_hour = date->hour;
    tm->tm_min = date->minute;
    tm->tm_sec = date->second;
    microsec = date->microsec;

    if (microsec >= 1000000) {
        tm->tm_sec += (microsec / 1000000);
        microsec = microsec % 1000000;
    }
    else if (microsec < 0) {
        microsec = -1 - microsec;
        tm->tm_sec -= (1 + microsec / 1000000);
        microsec = 999999 - (microsec % 1000000);
    }

    return microsec;
}

/* Convert a Unix timestamp, along with a microseconds value, to
   a glktimeval. 
*/
static void gli_timestamp_to_time(time_t timestamp, glsi32 microsec, 
    glktimeval_t *time)
{
    if (sizeof(timestamp) <= 4) {
        /* This platform has 32-bit time, but we can't do anything
           about that. Hope it's not 2038 yet. */
        if (timestamp >= 0)
            time->high_sec = 0;
        else
            time->high_sec = -1;
        time->low_sec = timestamp;
    }
    else {
        /* The cast to int64_t shouldn't be necessary, but it
           suppresses a pointless warning in the 32-bit case.
           (Remember that we won't be executing this line in the
           32-bit case.) */
        time->high_sec = (((int64_t)timestamp) >> 32) & 0xFFFFFFFF;
        time->low_sec = timestamp & 0xFFFFFFFF;
    }

    time->microsec = microsec;
}

/* Divide a Unix timestamp by a (positive) value. */
static glsi32 gli_simplify_time(time_t timestamp, glui32 factor)
{
    /* We want to round towards negative infinity, which takes a little
       bit of fussing. */
    if (timestamp >= 0) {
        return timestamp / (time_t)factor;
    }
    else {
        return -1 - (((time_t)-1 - timestamp) / (time_t)factor);
    }
}

void glk_current_time(glktimeval_t *time)
{
    struct timeval tv;

    if (gettimeofday(&tv, NULL)) {
        gli_timestamp_to_time(0, 0, time);
        gli_strict_warning(L"current_time: gettimeofday() failed.");
        return;
    }

    gli_timestamp_to_time(tv.tv_sec, tv.tv_usec, time);
}

glsi32 glk_current_simple_time(glui32 factor)
{
    struct timeval tv;

    if (factor == 0) {
        gli_strict_warning(L"current_simple_time: factor cannot be zero.");
        return 0;
    }

    if (gettimeofday(&tv, NULL)) {
        gli_strict_warning(L"current_simple_time: gettimeofday() failed.");
        return 0;
    }

    return gli_simplify_time(tv.tv_sec, factor);
}

void glk_time_to_date_utc(glktimeval_t *time, glkdate_t *date)
{
    time_t timestamp;
    struct tm tm;

    timestamp = time->low_sec;
    if (sizeof(timestamp) > 4) {
        timestamp += ((int64_t)time->high_sec << 32);
    }

    gmtime_r(&timestamp, &tm);

    gli_date_from_tm(date, &tm);
    date->microsec = time->microsec;
}

void glk_time_to_date_local(glktimeval_t *time, glkdate_t *date)
{
    time_t timestamp;
    struct tm tm;

    timestamp = time->low_sec;
    if (sizeof(timestamp) > 4) {
        timestamp += ((int64_t)time->high_sec << 32);
    }

    localtime_r(&timestamp, &tm);

    gli_date_from_tm(date, &tm);
    date->microsec = time->microsec;
}

void glk_simple_time_to_date_utc(glsi32 time, glui32 factor, 
    glkdate_t *date)
{
    time_t timestamp = (time_t)time * factor;
    struct tm tm;

    gmtime_r(&timestamp, &tm);

    gli_date_from_tm(date, &tm);
    date->microsec = 0;
}

void glk_simple_time_to_date_local(glsi32 time, glui32 factor, 
    glkdate_t *date)
{
    time_t timestamp = (time_t)time * factor;
    struct tm tm;

    localtime_r(&timestamp, &tm);

    gli_date_from_tm(date, &tm);
    date->microsec = 0;
}

void glk_date_to_time_utc(glkdate_t *date, glktimeval_t *time)
{
    time_t timestamp;
    struct tm tm;
    glsi32 microsec;

    microsec = gli_date_to_tm(date, &tm);
    /* The timegm function is not standard POSIX. If it's not available
       on your platform, try setting the env var "TZ" to "", calling
       mktime(), and then resetting "TZ". */
    timestamp = timegm(&tm);

    gli_timestamp_to_time(timestamp, microsec, time);
}

void glk_date_to_time_local(glkdate_t *date, glktimeval_t *time)
{
    time_t timestamp;
    struct tm tm;
    glsi32 microsec;

    microsec = gli_date_to_tm(date, &tm);
    tm.tm_isdst = -1;
    timestamp = mktime(&tm);

    gli_timestamp_to_time(timestamp, microsec, time);
}

glsi32 glk_date_to_simple_time_utc(glkdate_t *date, glui32 factor)
{
    time_t timestamp;
    struct tm tm;

    if (factor == 0) {
        gli_strict_warning(L"date_to_simple_time_utc: factor cannot be zero.");
        return 0;
    }

    gli_date_to_tm(date, &tm);
    /* The timegm function is not standard POSIX. If it's not available
       on your platform, try setting the env var "TZ" to "", calling
       mktime(), and then resetting "TZ". */
    timestamp = timegm(&tm);

    return gli_simplify_time(timestamp, factor);
}

glsi32 glk_date_to_simple_time_local(glkdate_t *date, glui32 factor)
{
    time_t timestamp;
    struct tm tm;

    if (factor == 0) {
        gli_strict_warning(L"date_to_simple_time_local: factor cannot be zero.");
        return 0;
    }

    gli_date_to_tm(date, &tm);
    tm.tm_isdst = -1;
    timestamp = mktime(&tm);

    return gli_simplify_time(timestamp, factor);
}


#endif /* GLK_MODULE_DATETIME */
