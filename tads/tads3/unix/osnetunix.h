/* Copyright (c) 2010 by Michael J. Roberts.  All Rights Reserved. */
/*
Name
  osnetunix.h - TADS networking and threading, Unix implementation
Function
  
Notes
  
Modified
  04/07/10 MJRoberts  - Creation
*/

#ifndef OSNETUNIX_H
#define OSNETUNIX_H


/* system headers */
#include <pthread.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/time.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <errno.h>
#include <math.h>
#include <ctype.h>
#include <fcntl.h>
#include <signal.h>
#include <stdarg.h>

/* true/false */
#ifndef TRUE
#define TRUE 1
#endif
#ifndef FALSE
#define FALSE 0
#endif

/* infinite timeout value */
#define OS_FOREVER  ((ulong)-1)

/* libcurl headers */
//#include <curl/curl.h>

/* OS X spinlocks */
#ifdef __APPLE__
#include <libkern/OSAtomic.h>
typedef OSSpinLock pthread_spinlock_t;
inline void pthread_spin_init(OSSpinLock* p, int) { *p=OS_SPINLOCK_INIT; }
inline void pthread_spin_destroy(OSSpinLock*) {}
#define pthread_spin_lock OSSpinLockLock
#define pthread_spin_unlock OSSpinLockUnlock
#endif

/* 
 *   Most Unix variants have at least one of SO_NOSIGPIPE or MSG_NOSIGNAL,
 *   and they seem to serve the same purpose everywhere, so if either is
 *   missing just define it away (i.e., define as 0, as these are bit flags).
 *   This doesn't handle the case where a system lacks *both*, but that seems
 *   to be rare, and the code necessary to work around it is messy enough
 *   that we're going to ignore the possibility.
 */
#ifdef SO_NOSIGPIPE
# ifndef MSG_NOSIGNAL
#   define MSG_NOSIGNAL 0
# endif
#else
# ifdef MSG_NOSIGNAL
#   define SO_NOSIGPIPE 0
# endif
#endif

/* include the base layer headers */
#include "osifcnet.h"

/* base TADS 3 header */
#include "t3std.h"

/* debug logging */
void oss_debug_log(const char *fmt, ...);


/* ------------------------------------------------------------------------ */
/*
 *   Most compilers provide atomic operation intrinsics, and C++-11 actually
 *   made them standard.  If we detect C++-11, we use std::atomic.  If not,
 *   we check for GCC and Clang intrinsic support (both new and legacy.)
 *   
 *   Using intrinsics is preferable to using a spinlock, since they translate
 *   to atomic machine instructions (if supported by the machine) and no
 *   locking is happening.
 *   
 *   It might look a bit redundant to check for the new intrinsics
 *   (__atomic_*) since they were introduced specifically for C++-11 support;
 *   if they are available, one would think that std::atomic is too.  But
 *   that's usually not the case.  In order to get to std::atomic, the
 *   compiler has to be explicitly told to enable support for C++-11 (through
 *   a command-line switch, usually "-std=c++11".)  In the future, C++-11
 *   will be the default in most compilers.  But as of now, it's not; neither
 *   in GCC nor in Clang.
 */
#ifndef __has_builtin
    /* compatibility with compilers other than Clang */
    #define __has_builtin(x) 0
#endif
#if __cplusplus >= 201103L
    #include <atomic>
    #define ATOMIC_TYPE(typ) std::atomic<typ>
    #define ATOMIC_INC_FETCH(var) (var.fetch_add(1, std::memory_order_relaxed) + 1)
    #define ATOMIC_DEC_FETCH(var) (var.fetch_sub(1, std::memory_order_relaxed) - 1)
#elif ((__GNUC__ > 4) || (__GNUC__ == 4 && __GNUC_MINOR__ >= 7)) \
      || (defined(__clang__) && __has_builtin(__atomic_add_fetch))
    #define ATOMIC_TYPE(typ) typ
    #define ATOMIC_INC_FETCH(var) (__atomic_add_fetch((&var), 1, __ATOMIC_RELAXED))
    #define ATOMIC_DEC_FETCH(var) (__atomic_sub_fetch((&var), 1, __ATOMIC_RELAXED))
#elif (__GNUC__ == 4 && __GNUC_MINOR__ >= 1) \
      || (defined(__clang__) && __has_builtin(__sync_add_and_fetch))
    #define ATOMIC_TYPE(typ) typ
    #define ATOMIC_INC_FETCH(var) (__sync_add_and_fetch((&var), 1))
    #define ATOMIC_DEC_FETCH(var) (__sync_sub_and_fetch((&var), 1))
#endif


/* ------------------------------------------------------------------------ */
/*
 *   Reference counter 
 */
class OS_Counter
{
public:
    OS_Counter(long c = 1)
        /*
         *   Avoid having this default-constructed, as that would complicate
         *   things in C++-11 (we would need to explicitly call an
         *   initializer before we can use the atomic type.)
         */
        : cnt(c)
    {
#ifndef ATOMIC_TYPE
        /* initialize the system spin lock, for serializing access */
        pthread_spin_init(&lock, PTHREAD_PROCESS_PRIVATE);
#endif
    }

#ifndef ATOMIC_TYPE
    ~OS_Counter()
    {
        /* destroy the system resources for the lock */
        pthread_spin_destroy(&lock);
    }
#endif

    /* get the current counter value */
    long get() const { return cnt; }

    /* 
     *   Increment/decrement.  These return the post-update result; the
     *   operation must be atomic, so that the return value is the result of
     *   this increment or decrement only, even if another thread
     *   concurrently makes another update.  
     */
    long inc()
    {
#ifdef ATOMIC_TYPE
        return ATOMIC_INC_FETCH(cnt);
#else
        /* do the inc-and-fetch with a spin lock to make it atomic */
        pthread_spin_lock(&lock);
        long newval = ++cnt;
        pthread_spin_unlock(&lock);

        /* return the updated value */
        return newval;
#endif
    }

    long dec()
    {
#ifdef ATOMIC_TYPE
        return ATOMIC_DEC_FETCH(cnt);
#else
        /* do the dec-and-fetch with a spin lock to make it atomic */
        pthread_spin_lock(&lock);
        long newval = --cnt;
        pthread_spin_unlock(&lock);

        /* return the updated value */
        return newval;
#endif
    }

private:
#ifdef ATOMIC_TYPE
    /* reference count */
    ATOMIC_TYPE(long) cnt;
#else
    /* reference count */
    long cnt;

    /* spin lock to protect the counter against concurrent access */
    pthread_spinlock_t lock;
#endif
};


/* ------------------------------------------------------------------------ */
/*
 *   Remove the ATOMIC_TYPE macros - we only needed them to define the
 *   OS_Counter class, so we can keep them local to this section of the
 *   header to avoid any potential name conflicts.
 */
#ifdef ATOMIC_TYPE
# undef ATOMIC_TYPE
# undef ATOMIC_INC_FETCH
# undef ATOMIC_DEC_FETCH
#endif
#ifndef __clang__
# if __has_builtin == 0
#  undef __has_builtin
# endif
#endif

/* ------------------------------------------------------------------------ */
/*
 *   System resource leak tracking 
 */
#ifdef LEAK_CHECK
extern OS_Counter mutex_cnt, event_cnt, thread_cnt, spin_lock_cnt;
# define IF_LEAK_CHECK(x) x
#else
# define IF_LEAK_CHECK(x)
#endif


/* ------------------------------------------------------------------------ */
/*
 *   Include the reference-counted object header 
 */
#include "vmrefcnt.h"


/* ------------------------------------------------------------------------ */
/*
 *   Waitable objects 
 */

/* private structure: multi-wait subscriber link */
struct osu_waitsub
{
    osu_waitsub(class OS_Event *e, osu_waitsub *nxt)
    {
        this->e = e;
        this->nxt = nxt;
    }

    /* this event */
    class OS_Event *e;

    /* next subscriber in list */
    osu_waitsub *nxt;
};

/*
 *   Waitable object.  This is the base class for objects that can be used in
 *   a multi-object wait.  A waitable object has two states: unsignaled and
 *   signaled.  Waiting for the object blocks the waiting thread as long as
 *   the object is in the unsignaled state, and releases the thread (allows
 *   it to continue running) as soon as the object enters the signaled state.
 *   Waiting for an object that's already in the signaled state simply allows
 *   the calling thread to continue immediately without blocking.  
 */
class OS_Waitable
{
public:
    OS_Waitable() { }

    virtual ~OS_Waitable() { }

    /* 
     *   Wait for the object, with a maximum wait of 'timeout' milliseconds.
     *   Returns an OSWAIT_xxx code to indicate what happened.  
     */
    int wait(unsigned long timeout = OS_FOREVER);

    /*
     *   Test to see if the object is ready, without blocking.  Returns true
     *   if the object is ready, false if not.  If the object is ready,
     *   waiting for the object would immediately release the thread.
     *   
     *   Note that testing some types of objects "consumes" the ready state
     *   and resets the object to not-ready.  This is true of auto-reset
     *   event objects.  
     */
    int test();

    /*
     *   Wait for multiple objects.  This blocks until at least one event in
     *   the list is signaled, at which point it returns OSWAIT_OBJECT+N,
     *   where N is the array index in 'events' of the event that fired.  If
     *   the timeout (given in milliseconds) expires before any events fire,
     *   we return OSWAIT_TIMEOUT.  If the timeout is omitted, we wait
     *   indefinitely, blocking until one of the events fires.  
     */
    static int multi_wait(int cnt, OS_Waitable **objs,
                          unsigned long timeout = OS_FOREVER);

protected:
    /*
     *   Figure a timeout end time.  This adds the given timeout to the
     *   current system time to get the system time at the expiration of the
     *   timeout.  
     */
    static void figure_timeout(struct timespec *tm, unsigned long timeout)
    {
        /* figure the timeout interval in seconds */
        long sec = timeout / 1000UL;
        
        /* add the timeout to the current time */
        os_time_t cur_sec;
        long cur_nsec;
        os_time_ns(&cur_sec, &cur_nsec);
        cur_sec += sec;
        cur_nsec += (timeout % 1000UL) * 1000000L;
        if (cur_nsec > 999999999L)
        {
            cur_nsec -= 1000000000L;
            cur_sec++;
        }
        
        /* pass back the resulting timeout */
        tm->tv_sec = cur_sec;
        tm->tv_nsec = cur_nsec;
    }
    
    /*
     *   Get the associated event object.  For the unix implementation, all
     *   waitable objects are waitable by virtue of having associated event
     *   objects.  
     */
    virtual class OS_Event *get_event() = 0;
};

/* ------------------------------------------------------------------------ */
/*
 *   Event 
 */
class OS_Event: public CVmRefCntObj, public OS_Waitable
{
    friend class OS_Waitable;

public:
    OS_Event(int manual_reset)
    {
        /* remember the reset mode */
        this->manual_reset = manual_reset;

        /* initial state is not signaled (zero 'set's) */
        cnt = 0;

        /* initialize the system resources */
        pthread_cond_init(&cond, 0);
        pthread_mutex_init(&mutex, 0);

        /* no multi-wait subscribers yet */
        sub_head = sub_tail = 0;

        /* count it for leak tracking */
        IF_LEAK_CHECK(event_cnt.inc());
    }
    ~OS_Event()
    {
        /* release the system resources */
        pthread_mutex_destroy(&mutex);
        pthread_cond_destroy(&cond);

        /* count it for leak tracking */
        IF_LEAK_CHECK(event_cnt.dec());
    }

    /*
     *   Signal the event.  In the case of a manual-reset event, this
     *   releases all threads waiting for the event, and leaves the event in
     *   a signaled state until it's explicitly reset.  For an auto-reset
     *   event, this releases only one thread waiting for the event and then
     *   automatically resets the event.  
     */
    void signal()
    {
        /* acquire the mutex so we can modify the counter */
        pthread_mutex_lock(&mutex);

        /* increase the counter */
        cnt += 1;

        /* 
         *   Notify subscribers.  These are all ad hoc events created by
         *   multi_wait(), so there's no danger of a deadlock: they can't be
         *   subscribed in turn, so they'll never run through this code
         *   themselves.  Note that our subscriber list is protected by our
         *   own mutex, so the fact that we've acquired our mutex means that
         *   the list can't be updated while we're working.
         *   
         *   We'll simply notify all of our subscribers and let them sort out
         *   amongst themselves who gets the event.  For a manual-reset
         *   event, they'll all get it, at least as long as no one resets it
         *   before they all get CPU time.  For an auto-reset event, only one
         *   subscriber will get the event, since it will reset as soon as
         *   the first waiter gets CPU time.  But it still doesn't hurt to
         *   wake everyone: they'll just look at their subscribed events and
         *   see that none of them are in fact available, so they'll realize
         *   that they missed their window and go back into another wait.  
         */
        for (osu_waitsub *s = sub_head ; s != 0 ; s = s->nxt)
            s->e->signal();

        /* release the mutex */
        pthread_mutex_unlock(&mutex);

        /* set the condition */
        pthread_cond_signal(&cond);
    }

    /*
     *   Reset the event.  This has no effect for an auto-reset event. 
     */
    void reset()
    {
        /* this only applies to manual-reset events */
        if (manual_reset)
        {
            /* acquire the mutex so we can modify the counter */
            pthread_mutex_lock(&mutex);
            
            /* reset the counter to zero */
            cnt = 0;
            
            /* release the mutex */
            pthread_mutex_unlock(&mutex);
        }
    }

protected:
    /* we're obviously our own waitable event object */
    virtual class OS_Event *get_event() { return this; }

private:
    /*
     *   Wait for the event.  If the event is already in the signaled state,
     *   this returns immediately.  Otherwise, this blocks until another
     *   thread signals the event.  For an auto-reset event, the system
     *   immediately resets the event as soon as a thread is released.  
     */
    void evt_wait()
    {
        /* acquire the mutex */
        pthread_mutex_lock(&mutex);

        /* be sure to unlock the mutex on the way out */
        pthread_cleanup_push(evt_wait_cleanup, this);

        /* wait for the count to come up positive */
        while (cnt <= 0)
        {
            /* wait for the condition */
            if (pthread_cond_wait(&cond, &mutex) && errno != EINTR)
                break;
        }

        /* if it's an auto-reset event, reduce the counter */
        if (!manual_reset)
            cnt -= 1;

        /* clean up (release the mutex) */
        pthread_cleanup_pop(TRUE);
    }

    /* on the way out of an event wait, release our mutex */
    static void evt_wait_cleanup(void *ctx)
    {
        pthread_mutex_unlock(&((OS_Event *)ctx)->mutex);
    }

    /*
     *   Wait for the event with a timeout, given in milliseconds.  This
     *   works the same way as wait(), but if the timeout expires before the
     *   event is signaled, this aborts the wait and returns OSWAIT_TIMEOUT.
     *   If the event is signaled before the timeout expires, we return with
     *   OSWAIT_EVENT.  
     */
    int evt_wait(unsigned long timeout)
    {
        /* if the timeout is "forever", use the untimed wait */
        if (timeout == OS_FOREVER)
        {
            evt_wait();
            return OSWAIT_EVENT;
        }
        
        /* figure the ending time for the wait */
        struct timespec tm;
        figure_timeout(&tm, timeout);

        /* do the wait */
        return evt_wait(&tm);
    }

    /*
     *   Wait for the event with a timeout, given as an ending time in terms
     *   of the system clock.  
     */
    int evt_wait(const struct timespec *tm)
    {
        int rc = 0;

        /* acquire the mutex */
        pthread_mutex_lock(&mutex);

        /* be sure we unlock the mutex on the way out */
        pthread_cleanup_push(evt_wait_cleanup, this);

        /* wait until we get a positive counter or the timeout expires */
        while (cnt <= 0)
        {
            /* wait for it */
            if ((rc = pthread_cond_timedwait(&cond, &mutex, tm)) != 0
                && errno != EINTR)
                break;
        }

        /* if the wait succeeded, and it's an auto-reset event, update the count */
        if (rc == 0 && !manual_reset)
            cnt -= 1;

        /* clean up (release the mutex) */
        pthread_cleanup_pop(TRUE);

        /* interpret the results */
        return (rc == 0 ? OSWAIT_EVENT :
                rc == ETIMEDOUT ? OSWAIT_TIMEOUT :
                OSWAIT_ERROR);
    }

    /*
     *   Test the event, without blocking.  This returns true if the event is
     *   in the signaled state, false if not.  
     */
    int evt_test()
    {
        /* acquire the mutex */
        pthread_mutex_lock(&mutex);

        /* if the counter is positive, the condition is signaled for us */
        int signaled = (cnt > 0);

        /* if it's signaled, and it's auto-reset, consume one count */
        if (signaled && !manual_reset)
            cnt -= 1;

        /* release the mutex */
        pthread_mutex_unlock(&mutex);

        /* return the signal status */
        return signaled;
    }

    /*
     *   Subscribe a multi-wait event object.  This adds the object to our
     *   list of multi-wait events that will be notified when this event
     *   fires.  This will wake up the multi-waiters, so that they can
     *   determine whether to wake up from their overall wait.  
     */
    void subscribe(OS_Event *e)
    {
        /* acquire the mutex while we're working */
        pthread_mutex_lock(&mutex);

        /* create and link in the new subscriber link */
        osu_waitsub *sub = new osu_waitsub(e, 0);

        /* 
         *   Link it at the end of our current list.  This naturally causes
         *   round-robin dispatch if we have multiple subscribers waiting for
         *   an auto-reset event.  The first member of the list will be the
         *   first to get the signal and thus the first to wake up
         *   (presumably - it could depend on the OS scheduling policy, but
         *   in practice it seems to work this way on Linux).  When it awakes
         *   it will unsubscribe, leaving the next subscriber as the head of
         *   the list.  If the same caller that awoke does some work and then
         *   turns around and multi-waits for the same event again, it'll go
         *   to the end of the list, so it won't get the signal again until
         *   the others that were already in the list ahead of it get their
         *   chance.  
         */
        if (sub_tail != 0)
            sub_tail->nxt = sub;
        else
            sub_head = sub;
        sub_tail = sub;

        /* release the mutex */
        pthread_mutex_unlock(&mutex);
    }

    /*
     *   Unsubscribe a multi-wait event object. 
     */
    void unsubscribe(OS_Event *e)
    {
        /* acquire the mutex while we're working */
        pthread_mutex_lock(&mutex);

        /* scan our list for the given event */
        osu_waitsub *cur, *prv;
        for (prv = 0, cur = sub_head ; cur != 0 ; prv = cur, cur = cur->nxt)
        {
            /* if this is the one we're looking for, unlink it */
            if (cur->e == e)
            {
                /* unlink this item */
                if (prv != 0)
                    prv->nxt = cur->nxt;
                else
                    sub_head = cur->nxt;

                /* if it's the tail, move back the tail */
                if (cur == sub_tail)
                    sub_tail = prv;

                /* done searching */
                break;
            }
        }

        /* release the mutex */
        pthread_mutex_unlock(&mutex);
    }

    /* 
     *   Is this a manual-reset event?  True means that this is a manual
     *   event: signaling the event will release all threads waiting for the
     *   event, and the event will remain signaled until it's explicitly
     *   cleared.  False means that this is an auto-reset event: signaling
     *   the event releases only ONE thread waiting for the event, and as
     *   soon as the thread is released, the system automatically clears the
     *   event, so no more threads will be released until the next signal.  
     */
    int manual_reset;

    /* the signal count */
    int cnt;

    /* the condition object */
    pthread_cond_t cond;

    /* the system mutex object */
    pthread_mutex_t mutex;

    /* head of our list of multi-wait subscribers */
    osu_waitsub *sub_head, *sub_tail;
};

/* ------------------------------------------------------------------------ */
/*
 *   Mutex.  
 */
class OS_Mutex: public CVmRefCntObj
{
public:
    OS_Mutex()
    {
        /* count it for leak tracking */
        IF_LEAK_CHECK(mutex_cnt.inc());

        /* initialize it */
        pthread_mutex_init(&h, 0);
    }

    ~OS_Mutex()
    {
        /* destroy the system resources */
        pthread_mutex_destroy(&h);

        /* count it for leak tracking */
        IF_LEAK_CHECK(mutex_cnt.dec());
    }

    /*
     *   Lock the mutex.  Blocks until the mutex is available.
     */
    void lock() { pthread_mutex_lock(&h); }

    /*
     *   Test the mutex: if the mutex is available, locks the mutex and
     *   returns true; if not, returns false.  Doesn't block in either case.
     *   On a 'true' return, the mutex is locked, so the caller must unlock
     *   it when done.
     */
    int test() { return pthread_mutex_trylock(&h) == 0; }

    /*
     *   Unlock the mutex.  This can only be used after a successful lock()
     *   or test().  This releases our lock and makes the mutex available to
     *   other threads.
     */
    void unlock() { pthread_mutex_unlock(&h); }

private:
    /* the underlying system mutex data */
    pthread_mutex_t h;
};


/* ------------------------------------------------------------------------ */
/* 
 *   Socket error indicator - returned from OS_Socket::send() and recv() if
 *   an error occurs, in lieu of a valid length value.  
 */
#define OS_SOCKET_ERROR  (-1)

/*
 *   Error values for OS_Socket::last_error().  
 */
#define OS_EWOULDBLOCK  EWOULDBLOCK                /* send/recv would block */
#define OS_ECONNRESET   ECONNRESET              /* connection reset by peer */
#define OS_ECONNABORTED ECONNABORTED      /* connection aborted on this end */

/* ------------------------------------------------------------------------ */
/*
 *   Socket.  This is a thin layer implementing the same model as the Unix
 *   socket API.  Windows provides a socket library of its own, but it's
 *   quite idiosyncratic, so we can't just write code directly to the
 *   standard Unix API.  
 */
class OS_CoreSocket: public CVmRefCntObj, public OS_Waitable
{
    friend class OS_Socket_Mon_Thread;

public:
    OS_CoreSocket()
    {
        /* no socket yet */
        s = -1;

        /* no error yet */
        err = 0;

        /* no non-blocking-mode thread yet */
        ready_evt = 0;
        blocked_evt = 0;
        mon_thread = 0;
        wouldblock_sending = FALSE;
    }

    ~OS_CoreSocket();

    /* 
     *   Set the socket to non-blocking mode.  In this mode, a read/write on
     *   the socket will immediately with an error code if the socket's data
     *   buffer is empty on read or full on write.  By default, these calls
     *   "block": they don't return until at least one byte is available to
     *   read or there's buffer space for all of the data being written.
     */
    void set_non_blocking();

    /*
     *   In non-blocking mode, the caller must manually reset the socket's
     *   event waiting status after each successful wait.  
     */
    void reset_event() { }

    /* 
     *   Get the last error for a send/receive operation.  Returns an OS_Exxx
     *   value.  
     */
    int last_error() const { return err; }

    /* close the socket */
    void close();

    /*
     *   Get the IP address for the given host.  The return value is an
     *   allocated buffer that the caller must delete with 'delete[]'.  If
     *   the host IP address is unavailable, returns null.  
     */
    static char *get_host_ip(const char *hostname)
    {
        /* 
         *   if no host name was specified, get the default local host name
         *   from the environment 
         */
        if (hostname == 0 || hostname[0] == '\0')
        {
            hostname = getenv("HOSTNAME");
            if (hostname == 0)
                return 0;
        }

        /* get the host entry for our local host name */
        struct hostent *local_host = gethostbyname(hostname);
        if (local_host == 0)
            return 0;

        /* get the IP address from the host entry structure */
        const char *a =
            inet_ntoa(*(struct in_addr *)local_host->h_addr_list[0]);
        if (a == 0)
            return 0;

        /* make an allocated copy of the buffer for the caller */
        char *buf = new char[strlen(a) + 1];
        strcpy(buf, a);

        /* return the allocated copy */
        return buf;
    }

    /*
     *   Get the IP address for our side (the local side) of the socket.
     *   'ip' receives an allocated string with the IP address string in
     *   decimal notation ("192.168.1.15").  We fill in 'port' with the local
     *   port number of the socket.  Returns true on success, false on
     *   failure.  If we return success, the caller is responsible for
     *   freeing the allocated 'ip' string via t3free().  
     */
    int get_local_addr(char *&ip, int &port)
    {
        socklen_t len;
        struct sockaddr_storage addr;

        /* get the local socket information */
        len = sizeof(addr);
        getsockname(s, (struct sockaddr *)&addr, &len);

        /* parse the address */
        return parse_addr(addr, len, ip, port);
    }

    /*
     *   Get the IP address for the network peer to which we're connected.
     *   'ip' receives an allocated string with the IP address string in
     *   decimal notation ("192.168.1.15").  We fill in 'port' with the port
     *   number on the remote host.  Returns true on success, false on
     *   failure.  If we return success, the caller is responsible for
     *   freeing the allocated 'ip' string via t3free().  
     */
    int get_peer_addr(char *&ip, int &port)
    {
        socklen_t len;
        struct sockaddr_storage addr;

        /* get the peer name */
        len = sizeof(addr);
        getpeername(s, (struct sockaddr *)&addr, &len);

        /* parse the address */
        return parse_addr(addr, len, ip, port);
    }

    /* 
     *   System time (as returned by time()) of last incoming network
     *   activity.  The watchdog thread (if enabled) uses this to make sure
     *   that the bytecode program is actually serving a client, and
     *   terminate the program if it appears to be running without a client
     *   for an extended period.
     */
    static time_t last_incoming_time;

protected:
    /* create a socket object wrapping an existing system socket */
    OS_CoreSocket(int s)
    {
        this->s = s;
        err = 0;
        ready_evt = 0;
        blocked_evt = 0;
        wouldblock_sending = FALSE;
    }

    /* 
     *   Get the waitable event.  A caller who's waiting for the socket wants
     *   to know when the socket is ready, so use the 'ready' event as the
     *   socket wait event.  
     */
    virtual class OS_Event *get_event() { return ready_evt; }

    /* parse an address */
    int parse_addr(struct sockaddr_storage &addr, int len,
                   char *&ip, int &port)
    {
        char ipstr[INET6_ADDRSTRLEN];

        /* presume failure */
        ip = 0;
        port = 0;

        /* check the protocol family */
        if (addr.ss_family == AF_INET)
        {
            /* get the address information */
            struct sockaddr_in *s = (struct sockaddr_in *)&addr;
            port = ntohs(s->sin_port);
            inet_ntop(AF_INET, &s->sin_addr, ipstr, sizeof ipstr);

            /* allocate the IP string and return success */
            ip = lib_copy_str(ipstr);
            return TRUE;
        }
        else if (addr.ss_family == AF_INET6)
        {
            struct sockaddr_in6 *s = (struct sockaddr_in6 *)&addr;
            port = ntohs(s->sin6_port);
            inet_ntop(AF_INET6, &s->sin6_addr, ipstr, sizeof ipstr);

            /* allocate the IP string and return success */
            ip = lib_copy_str(ipstr);
            return TRUE;
        }
        else
        {
            /* we don't handle other families */
            return FALSE;
        }
    }


    /* our underlying system socket handle */
    int s;

    /* last send/receive error */
    int err;

    /* 
     *   for non-blocking sockets, the recv/send direction of the last
     *   EWOULDBLOCK: true means send, false means recv 
     */
    int wouldblock_sending;

    /* 
     *   The non-blocking status events.  The 'ready' event is signaled
     *   whenever select() shows that the socket is ready, meaning that a
     *   recv() or send() will be able to read/write at least one byte
     *   without blocking.  The 'blocked' event is the opposite: it's
     *   signaled whenever a recv() or send() gets an EWOULDBLOCK error,
     *   indicating that the socket is blocked until more data arrive in or
     *   depart from the buffer.
     *   
     *   The 'ready' event is maintained by a separate monitor thread that we
     *   create when the socket is placed into non-blocking mode.
     *   
     *   We need both events because we don't have a way of waiting for an
     *   event to become unsignaled.  So we need to signal these two states
     *   independently via separate event objects.  
     */
    OS_Event *ready_evt;
    OS_Event *blocked_evt;

    /* non-blocking status monitor thread */
    class OS_Socket_Mon_Thread *mon_thread;
};

/* ------------------------------------------------------------------------ */
/*
 *   Data socket 
 */
class OS_Socket: public OS_CoreSocket
{
    friend class OS_Listener;

public:
    /* 
     *   Send bytes.  Returns the number of bytes sent, or OS_SOCKET_ERROR if
     *   an error occurs.  
     */
    int send(const char *buf, size_t len)
    {
        /* send the bytes and note the result */
        int ret = ::send(s, buf, len, MSG_NOSIGNAL);

        /* 
         *   If an error occurred, note it.  Treat EAGAIN as equivalent to
         *   EWOULDBLOCK.  
         */
        err = (ret < 0 ? (errno == EAGAIN ? EWOULDBLOCK : errno) : 0);

        /* on EWOULDBLOCK, set the blocking status indicators */
        if (err == EWOULDBLOCK)
        {
            /* the wouldblock direction is 'send' */
            wouldblock_sending = TRUE;
            
            /* set the events for blocking mode */
            ready_evt->reset();
            blocked_evt->signal();
        }

        /* return the result */
        return ret;
    }

    /* 
     *   Receive bytes.  Returns the number of bytes received, or
     *   OS_SOCKET_ERROR if an error occurs.  
     */
    int recv(char *buf, size_t len)
    {
        /* read the bytes and note the result */
        int ret = ::recv(s, buf, len, MSG_NOSIGNAL);

        /* 
         *   If an error occurred, note it.  Treat EAGAIN as equivalent to
         *   EWOULDBLOCK. 
         */
        err = (ret < 0 ? (errno == EAGAIN ? EWOULDBLOCK : errno) : 0);

        /* on EWOULDBLOCK, set the blocking status indicators */
        if (err == EWOULDBLOCK)
        {
            /* the wouldblock direction is 'receive' */
            wouldblock_sending = FALSE;

            /* set the events for blocking mode */
            ready_evt->reset();
            blocked_evt->signal();
        }

        /* if we successfully received data, this is incoming activity */
        if (err == 0)
            last_incoming_time = time(0);
        
        /* return the result */
        return ret;
    }

protected:
    /* create an OS_Socket object to wrap an existing system socket handle */
    OS_Socket(int s) : OS_CoreSocket(s) { }

    ~OS_Socket() { }
};

/* ------------------------------------------------------------------------ */
/*
 *   Listener.  This class represents a network listener socket, which is
 *   used to wait for and accept new incoming connections from clients.  
 */
class OS_Listener: public OS_CoreSocket
{
public:
    /* 
     *   Construction.  This sets up the object, but doesn't open a listener
     *   port.  Call open() to actually open the port.  
     */
    OS_Listener() { }

    /* destructor - free resources */
    ~OS_Listener() { }

    /* 
     *   Open the listener on the given port number.  This can be used to
     *   create a server on a well-known port, but it has the drawback that
     *   ports can't be shared, so this will fail if another process is
     *   already using the same port number.
     *   
     *   Returns true on success, false on failure.  
     */
    int open(const char *hostname, unsigned short port_num)
    {
        /* create our socket */
        s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
        if (s == -1)
            return FALSE;

        /* bind to the given host address */
        char *ip = get_host_ip(hostname);
        if (ip == 0)
            return FALSE;

        /* 
         *   set up the address request structure to bind to the requested
         *   port on the local address we just figured 
         */
        struct sockaddr_in saddr;
        saddr.sin_family = PF_INET;
        saddr.sin_addr.s_addr = inet_addr(ip);
        saddr.sin_port = htons(port_num);
        memset(saddr.sin_zero, 0, sizeof(saddr.sin_zero));

        /* done with the IP address */
        delete [] ip;

        /* try binding */
        if (bind(s, (sockaddr *)&saddr, sizeof(saddr)))
            return FALSE;

        /* put the socket into the 'listening' state */
        if (listen(s, SOMAXCONN))
            return FALSE;

        /* success */
        return TRUE;
    }

    /*
     *   Open the listener port, with the port number assigned by the system.
     *   The system will select an available port and assign it to this
     *   listener, so this avoids contention for specific port numbers.
     *   However, it requires some separate means of communicating the port
     *   number to clients, since there's no way for them to know the port
     *   number in advance.
     *   
     *   Returns true on success, false on failure.  
     */
    int open(const char *hostname) { return open(hostname, 0); }

    /*
     *   Accept the next incoming connection.  If the listener is in blocking
     *   mode (the default), and there are no pending requests, this blocks
     *   until the next pending request arrives.  In non-blocking mode, this
     *   returns immediately with a null socket if no requests are pending,
     *   and last_error() indicates OS_EWOULDBLOCK.  
     */
    OS_Socket *accept()
    {
        /* accept a connection on the underlying system socket */
        struct sockaddr_in addr;
        socklen_t addrlen = sizeof(addr);
        int snew = ::accept(s, (sockaddr *)&addr, &addrlen);

        /* check to see if we got a socket */
        if (snew != -1)
        {
            /* success - clear the error memory */
            err = 0;

            /* this counts as incoming network activity - note the time */
            last_incoming_time = time(0);

            /* 
             *   Set the "linger" option on close.  This helps ensure that we
             *   transmit any error response to a request that causes the
             *   server thread to abort.  Without this option, winsock will
             *   sometimes terminate the connection before transmitting the
             *   final response.  
             */
            struct linger ls = { TRUE, 1 };
            setsockopt(snew, SOL_SOCKET, SO_LINGER, (char *)&ls, sizeof(ls));

            /* 
             *   Turn off SIGPIPE signals on this socket - we deal with
             *   disconnections via error returns on send() rather than
             *   signals.  Note that this setting only applies to some Unix
             *   varieties; we'll do it only if SO_NOSIGPIPE is defined
             *   locally.  
             */
#ifdef SO_NOSIGPIPE
            int nsp = 1;
            setsockopt(snew, SOL_SOCKET, SO_NOSIGPIPE,
                       (char *)&nsp, sizeof(nsp));
#endif

            /*
             *   Disable the Nagle algorithm for this socket to minimize
             *   transmit latency.  With the Nagle algorithm in effect,
             *   whenever the program sends a small packet (via ::send(),
             *   e.g.), the TCP layer queues the bytes but doesn't send them
             *   out on the network immediately; instead, it waits a little
             *   while to see if another ::send() quickly follows, in which
             *   case the bytes from the first ::send() can be combined with
             *   those from the second to form one larger packet.  This
             *   continues until the maximum packet size is reached or a
             *   timeout expires, at which point the queued bytes are finally
             *   sent out on the network.  This automatic buffering and
             *   coalescing behavior is beneficial to many appliations,
             *   because there's some overhead associated with each packet;
             *   coalescing multiple small ::send()'s into one large packet
             *   reduces this packet overhead.  However, it's detrimental to
             *   programs like TADS that tend to send a series of small
             *   messages that need to be acknowledged individually before
             *   the next can be sent.  The Nagle algorithm's delay in this
             *   case manifests as pure latency, since the additional bytes
             *   being waited for never arrive, so the original small packet
             *   must be sent out after all - but not until the Nagle
             *   algorithm delay expires, whereas with Nagle turned off, it's
             *   sent out immediately.
             */
            int tcpflag = 1;
            setsockopt(snew, IPPROTO_TCP, TCP_NODELAY,
                       (char *)&tcpflag, sizeof(tcpflag));
 
            /* wrap the socket in an OS_Socket and return the object */
            return new OS_Socket(snew);
        }
        else
        {
            /* failed - remember the system error code */
            err = (errno == EAGAIN ? EWOULDBLOCK : errno);

            /* on EWOULDBLOCK, set the blocking status indicators */
            if (err == EWOULDBLOCK)
            {
                /* the wouldblock direction for listen is 'receive' */
                wouldblock_sending = FALSE;

                /* set the events for blocking mode */
                ready_evt->reset();
                blocked_evt->signal();
            }
            
            /* return failure */
            return 0;
        }
    }

protected:
};

/* ------------------------------------------------------------------------ */
/*
 *   Thread.  Callers subclass this to define the thread entrypoint routine.
 */
class OS_Thread: public CVmWeakRefable, public OS_Waitable
{
    friend class TadsThreadList;
    
public:
    OS_Thread();
    virtual ~OS_Thread();

    /* 
     *   Launch the thread.  Returns true on success, false on failure.  
     */
    int launch()
    {
        /* default thread attributes */
        extern pthread_attr_t G_thread_attr;

        /*
         *   The initial reference for our caller, which constructed this
         *   object.  Add a second reference on behalf of the new thread that
         *   we're launching - it has a reference to 'this' as its thread
         *   context object.  
         */
        add_ref();

        /* create the thread */
        int err = pthread_create(&tid, &G_thread_attr, &sys_thread_main, this);

        /* check for errors */
        if (err != 0)
        {
            /* 
             *   The launch failed, so release the reference we created for
             *   the thread - there actually will be no thread to take over
             *   that reference.  
             */
            release_ref();

            /* signal the 'done' event immediately */
            done_evt->signal();

            /* not launched */
            return FALSE;
        }
        else
        {
            /* launched successfully - mark the thread ID as valid */
            tid_valid = TRUE;

            /* indicate success */
            return TRUE;
        }
    }

#if 0
    /*
     *   Cancel the thread.
     *   
     *   [This method is currently disabled because of problems that appear
     *   with some versions of Linux and/or gcc - it's not clear who's at
     *   fault, but there appears to be a known bug where pthread_cancel()
     *   fails to trigger cleanup handlers in the target thread.  This method
     *   was only used in one place, which was to kill the monitor thread
     *   associated with a non-blocking socket when the socket was closed.
     *   That's now handled instead via a message through a pipe, so no code
     *   currently uses the routine, and we've #if'd it out to make sure that
     *   no new code uses it without being aware of the cleanup handler bug.
     *   If it becomes desirable to re-enable the routine at some point, we
     *   need to first make sure that there's a solution to the cleanup
     *   handler bug, since that will cause unexpected behavior on platforms
     *   where the bug occurs.]
     */
    void cancel_thread(int wait = FALSE)
    {
        /* request cancellation of the pthreads thread */
        if (tid_valid)
            pthread_cancel(tid);

        /* if desired, wait for the thrad */
        if (wait)
            done_evt->wait();
    }
#endif

    /*
     *   Thread entrypoint routine.  Callers must subclass this class and
     *   provide a concrete definition for this method.  This method is
     *   called at thread entry.  
     */
    virtual void thread_main() = 0;

protected:
    /* get the waitable event */
    virtual class OS_Event *get_event() { return done_evt; }

    /* 
     *   Static entrypoint.  This is the routine the system calls directly;
     *   we then invoke the virtual method with the subclassed thread main. 
     */
    static void *sys_thread_main(void *ctx)
    {
        /* set up our cleanup routine */
        pthread_cleanup_push(sys_thread_cleanup, ctx);
        
        /* the context is the thread structure */
        OS_Thread *t = (OS_Thread *)ctx;

        /* launch the real thread and remember the result code */
        t->thread_main();

        /* pop and invoke the cleanup handler */
        pthread_cleanup_pop(TRUE);

        /* return a dummy result code */
        return 0;
    }

    /*
     *   Cleanup entrypoint.  The system pthreads package invokes this when
     *   our thread exits, either by returning from the main thread
     *   entrypoint routine or via a cancellation request.  At exit, we
     *   release the thread's reference on the OS_Thread object, and we
     *   signal the thread's 'done' event to indicate that the thread has
     *   terminated.  
     */
    static void sys_thread_cleanup(void *ctx)
    {
        /* the context is the thread structure */
        OS_Thread *t = (OS_Thread *)ctx;

        /* before we release our ref on the thread, save its done event */
        OS_Event *done_evt = t->done_evt;
        done_evt->add_ref();

        /* release the thread's reference on the thread structure */
        t->release_ref();

        /* the thread has now truly exited - signal the termination event */
        done_evt->signal();
        done_evt->release_ref();
    }

    /* system thread ID */
    int tid_valid;
    pthread_t tid;

    /* end-of-thread event */
    OS_Event *done_evt;
};

/* master thread list global */
extern class TadsThreadList *G_thread_list;


/* ------------------------------------------------------------------------ */
/*
 *   Watchdog thread.  This is an optional system thread that monitors the
 *   program's activity, and terminates the program if it appears to be
 *   either inactive or looping.  When TADS is running as a network server
 *   that's open to anyone's bytecode programs, we can't count on the
 *   underlying bytecode program being well-behaved.  The watchdog thread
 *   handles some common problem areas:
 *   
 *   - If the bytecode program has a bug that gets it stuck in an infinite
 *   loop, it will consume as much CPU time as it's given, which will bring
 *   other processes on the server to a crawl.  The watchdog checks
 *   periodically to see if our process has been consuming a disproportionate
 *   amount of CPU time over a recent interval, and will terminate the
 *   process if so.  This will also shut down programs that are intentionally
 *   (not buggily) doing CPU-intensive computations for long stretches, but
 *   this is a reasonable policy anyway: shared TADS game servers are meant
 *   for interactive games, and if someone wants to run heavy-duty number
 *   crunching, they really shouldn't be using a shared game server for it.
 *   
 *   - If the bytecode program has a long period without any network requests
 *   from clients, it probably has a bug in its internal session management
 *   code.  On a public server, a given interpreter session is meant to run
 *   only as long as it's actively being used by a client.  The standard TADS
 *   web server library has an internal watchdog that monitors for client
 *   activity, and shuts itself down after a period of inactivity.  However,
 *   we can't count on every bytecode program using the standard library, and
 *   even those that do could have bugs (in the library itself or in user
 *   code) that prevent the internal inactivity watchdog from working
 *   properly.  So, our system watchdog thread serves as a backup here; if we
 *   don't see any incoming client network requests for an extended period,
 *   we'll assume that the program no longer has any job to do, so we'll shut
 *   it down.  Note that a bytecode program could be intentionally running as
 *   a continuous service, e.g., acting as a web server; but that's really an
 *   abuse of a public TADS server, since a continuously resident process
 *   takes up a lot of memory that's meant to be shared with other users.  So
 *   we don't care whether the bytecode program is running without clients
 *   due to bugs or by design; in either case we want to shut it down.
 *   
 *   The system administrator enables the watchdog thread by putting the
 *   variable "watchdog = yes" in the tadsweb.config file.
 */

/* the statistics we collect each time the watchdog wakes up */
struct watchdog_stats
{
    /* total user CPU time used as of this interval, in seconds */
    clock_t cpu_time;

    /* wall clock time (time() value) as of this interval, in seconds */
    time_t wall_time;
};

/*
 *   Watchdog thread object class 
 */
class OSS_Watchdog: public OS_Thread
{
public:
    OSS_Watchdog()
    {
        /* create our 'quit' event object */
        quit_evt = new OS_Event(TRUE);

        /* we haven't collected any statistics yet */
        cnt = 0;
        idx = 0;

        /* 
         *   Initialize the last incoming network activity time to the
         *   current time.  We haven't actually seen any network activity
         *   yet, of course, but what we're really interested in is the
         *   interval, and it's not meaningful to talk about an interval
         *   longer than we've been running.
         */
        OS_CoreSocket::last_incoming_time = time(0);
    }

    ~OSS_Watchdog()
    {
        /* we're done with our 'quit' event */
        quit_evt->release_ref();
    }

    virtual void thread_main()
    {
        oss_debug_log("watchdog thread started");
        
        /* loop until our 'quit' event has fired */
        while (!quit_evt->test())
        {
            /* wake up every 10 seconds, or when the 'quit' event fires */
            if (quit_evt->wait(10000) == OSWAIT_TIMEOUT)
            {
                /* 
                 *   That timed out, so it's time for another watchdog check.
                 *   First, update the timers. 
                 */
                stats[idx].cpu_time = clock() / CLOCKS_PER_SEC;
                stats[idx].wall_time = time(0);

                /* bump the statistics counters */
                ++cnt;
                if (++idx >= NSTATS)
                    idx = 0;

                /* 
                 *   If we've collected enough statistics, do our checks.  We
                 *   need at least 60 seconds of trailing data, and we wake
                 *   up every 10 seconds, so we need at least seven samples
                 *   (#0 is 0 seconds ago, #1 is 10 seconds ago, ... #6 is 60
                 *   seconds ago, hence we need 0-6 = 7 samples).
                 */
                if (cnt >= 7)
                {
                    /* get the last and the 60-seconds-ago stats */
                    const watchdog_stats *cur = get_stats(0);
                    const watchdog_stats *prv = get_stats(6);

                    /* calculate the percentage of CPU time */
                    double cpu_pct = ((double)(cur->cpu_time - prv->cpu_time))
                                     / (cur->wall_time - prv->wall_time);

                    /* calculate the time since the last network event */
                    time_t time_since_net =
                        cur->wall_time - OS_CoreSocket::last_incoming_time;

                    /*
                     *   Check for termination conditions:
                     *   
                     *   1.  If we've consumed 40% or higher CPU over the
                     *   last minute, we're probably stuck in a loop; we
                     *   might also be running an intentionally
                     *   compute-intensive program, which isn't a bug but is
                     *   an abuse of a shared server, so in either case kill
                     *   the program.  (We're not worried about short bursts
                     *   of high CPU usage, which is why we average over a
                     *   fairly long real-time period.)
                     *   
                     *   2.  If we haven't seen any incoming network activity
                     *   in 6 minutes, the program is probably idle and
                     *   should probably have noticed that and shut itself
                     *   down already, so it might have a bug in its internal
                     *   inactivity monitor.  It could also be intentionally
                     *   running as a continuous service, but that's abusive
                     *   on a shared server because it uses memory that's
                     *   meant to be shared.  In either case, shut it down.
                     */
                    if (cpu_pct >= 0.4)
                    {
                        oss_debug_log("watchdog terminating process due to "
                                      "high CPU usage (cpu_pct = %0.2ld%%)",
                                      cpu_pct);
                        kill(getpid(), 9);
                    }
                    if (time_since_net > 6*60)
                    {
                        oss_debug_log("watchdog terminating process due to "
                                      "network inactivity (time_since_net"
                                      " = %ld seconds)", (long)time_since_net);
                        kill(getpid(), 9);
                    }
                }
            }
        }
    }

    /* the watchdog thread 'quit' event */
    static OS_Event *quit_evt;

private:
    /* number of times we've collected statistics */
    int cnt;

    /* next statistics write index */
    int idx;

    /* 
     *   Statistics array.  We keep records for the latest NSTATS iterations.
     *   idx points to the next element to write, so idx-1 is the last one we
     *   wrote, and so on.  The array is circular, so the actual array index
     *   of element i is i % NSTATS. 
     */
    static const int NSTATS = 10;
    watchdog_stats stats[NSTATS];

    /* 
     *   get the nth most recent stats entry - 0 is the latest entry, 1 is
     *   the second older entry, etc 
     */
    const watchdog_stats *get_stats(int i) const
    {
        /* 
         *   idx points to the next to write, so idx-1 is the latest entry,
         *   idx-2 is the second entry, etc 
         */
        i = idx - 1 - i;

        /* the array is circular, so adjust for wrapping */
        if (i < 0)
            i += NSTATS;

        /* return the element */
        return &stats[i];
    }
};


#endif /* OSNETUNIX_H */
