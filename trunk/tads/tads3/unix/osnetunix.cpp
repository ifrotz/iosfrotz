/* Copyright (c) 2010 by Michael J. Roberts.  All Rights Reserved. */
/*
Name
  osnetunix.cpp - TADS OS networking and threading: Unix implementation
Function
  
Notes
  
Modified
  04/06/10 MJRoberts  - Creation
*/

#define NOCURL

#include <stdlib.h>
#include <string.h>
#include <poll.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <net/if.h>
#include <sys/ioctl.h>
#include <sys/times.h>
#include <unistd.h>
#include <time.h>
#include <stdio.h>

#ifndef NOCURL
#include <curl/curl.h>
#endif

#include "os.h"
#include "t3std.h"
#include "osifcnet.h"
#include "vmnet.h"
#include "vmfile.h"
#include "vmdatasrc.h"

/*
 *   To enable extra code for libcurl debugging, define this macro 
 */
// #define OSNU_CURL_DEBUG


/* 
 *   ignore a return value (to suppress superfluous gcc warn_unused_result
 *   warnings) 
 */
void IGNORE(int) { }



/*
 *   Thread attributes 
 */
pthread_attr_t G_thread_attr;

/*
 *   Master thread list 
 */
TadsThreadList *G_thread_list = 0;


/* ------------------------------------------------------------------------ */
/*
 *   Thread/event resource leak checking 
 */
#ifdef LEAK_CHECK
OS_Counter mutex_cnt(0), event_cnt(0), thread_cnt(0), spin_lock_cnt(0);
# define IF_LEAK_CHECK(x) x
#else
# define IF_LEAK_CHECK(x)
#endif

/* ------------------------------------------------------------------------ */
/*
 *   debug logging (for debugging purposes only)
 */
void oss_debug_log(const char *fmt, ...)
{
#if 0
    va_list args;
    va_start(args, fmt);
    char *str = t3vsprintf_alloc(fmt, args);
    va_end(args);

    time_t timer = time(0);
    struct tm *tblk = localtime(&timer);
    char *tmsg = asctime(tblk);
    size_t tmsgl = strlen(tmsg);
    if (tmsg > 0 && tmsg[tmsgl-1] == '\n')
        tmsg[--tmsgl] = '\0';

    FILE *fp = fopen("/var/log/frob/tadslog2.txt", "a");
    fprintf(fp, "[%s] %s\n", tmsg, str);
    fclose(fp);

    t3free(str);
#endif
}


/* ------------------------------------------------------------------------ */
/*
 *   Watchdog thread
 */

/* the watchdog quit event, as a global static */
OS_Event *OSS_Watchdog::quit_evt = 0;


/* ------------------------------------------------------------------------ */
/*
 *   Package initialization and termination 
 */

/*
 *   Initialize the networking and threading package 
 */
void os_net_init(TadsNetConfig *config)
{
    /* initialize the CURL (http client) library */
#ifndef NOCURL
    curl_global_init(0);
#endif
    /* set up the default thread attributes */
    pthread_attr_init(&G_thread_attr);
    pthread_attr_setdetachstate(&G_thread_attr, PTHREAD_CREATE_JOINABLE);

    /* create the master thread list */
    G_thread_list = new TadsThreadList();

    /* if desired, start the watchdog thread */
    if (config != 0
        && (config->match("watchdog", "yes")
            || config->match("watchdog", "on")))
    {
        /* launch the watchdog thread */
        OSS_Watchdog *wt = new OSS_Watchdog();
        if (!wt->launch())
            oss_debug_log("failed to launch watchdog thread");

        /* we're done with the thread object */
        wt->release_ref();
    }
}

/*
 *   Clean up the package in preparation for application exit 
 */
void os_net_cleanup()
{
    /* if there's a watchdog thread, tell it to terminate */
    if (OSS_Watchdog::quit_evt != 0)
        OSS_Watchdog::quit_evt->signal();

    /* 
     *   sleep for a short time to let any threads that are already almost
     *   done finish up their work 
     */
    usleep(10000);

    /* wait for threads to exit */
    G_thread_list->wait_all(500);

    /* done with the master thread list */
    G_thread_list->release_ref();

    /* check for system resource leaks */
    IF_LEAK_CHECK(printf("os_net_cleanup: mutexes=%ld, events=%ld, "
                         "threads=%ld, spin locks=%ld\n",
                         mutex_cnt.get(), event_cnt.get(),
                         thread_cnt.get(), spin_lock_cnt.get()));

    /* clean up the CURL library */
#ifndef NOCURL
    curl_global_cleanup();
#endif

    /* delete our thread attributes */
    pthread_attr_destroy(&G_thread_attr);
}

/* ------------------------------------------------------------------------ */
/*
 *   Local file selector dialog.  We don't currently implement a stand-alone
 *   Web UI mode on Unix platforms, so this is a no-op.  
 */
int osnet_askfile(const char *prompt, char *fname_buf, int fname_buf_len,
                  int prompt_type, int file_type)
{
    return OS_AFE_FAILURE;
}


/*
 *   Connect to the client UI.  A Web-based game calls this after starting
 *   its internal HTTP server, to send instructions back to the client on how
 *   the client UI can connect to the game.
 *   
 *   This Unix implementation currently only supports client/server mode.
 */
int osnet_connect_webui(VMG_ const char *addr, int port, const char *path,
                        char **errmsg)
{
    /* 
     *   Web server mode: our parent process is the conventional Web server
     *   running the php launch page.  The php launch page has a pipe
     *   connection to our stdout.  Send the start page information back to
     *   the php page simply by writing the information to stdout.  
     */
    printf("\nconnectWebUI:http://%s:%d%s\n", addr, port, path);
    fflush(stdout);

    /* success */
    *errmsg = 0;
    return TRUE;
}


/* ------------------------------------------------------------------------ */
/*
 *   Local host information 
 */

int os_get_hostname(char *buf, size_t buflen)
{
    /* ask the system for the host name */
    return !gethostname(buf, buflen);
}

int os_get_local_ip(char *buf, size_t buflen, const char *host)
{
    /* presume failure */
    int ok = FALSE;

    /* if the caller didn't provide a host name, look up the default */
    char hostbuf[128];
    if (host == 0 && !gethostname(hostbuf, sizeof(hostbuf)))
        host = hostbuf;

    /*
     *   Start by asking the system for the host name via gethostname(), then
     *   getting the IP addresses for the name.  The complication is that on
     *   many linux systems, this will only return 127.0.0.1, which isn't
     *   useful because that's only the local loopback address.  But we can
     *   at least try...  
     */
    if (host != 0)
    {
        /* get the address info for the host name */
        struct hostent *local_host = gethostbyname(buf);
        if (local_host != 0)
        {
            /* scan the IP addresses for this host name */
            for (char **al = local_host->h_addr_list ; *al != 0 ; ++al)
            {
                /* get the IP address */
                const char *ip = inet_ntoa(*(struct in_addr *)*al);
                
                /* if it's not a 127.0... address, use it */
                if (memcmp(ip, "127.0.", 6) != 0)
                {
                    /* this is an external address - return it */
                    lib_strcpy(buf, buflen, ip);
                    return TRUE;
                }
            }
        }
    }

    /*
     *   If we get this far, it means that gethostbyname() won't give us
     *   anything besides the useless 127.0.0.1 loopback address.  The next
     *   step is to open a socket and do some mucking around in its system
     *   structures via an ioctl to get a list of the network interfaces in
     *   the system.  
     */
    
    /* clear out the ioctl address structure */
    struct ifconf ifc;
    memset(&ifc, 0, sizeof(ifc));
    ifc.ifc_ifcu.ifcu_req = 0;
    ifc.ifc_len = 0;

    /* no socket yet */
    int s = -1;

    /*
     *   Open a socket (we don't need to bind it to anything; just open it),
     *   then do the SIOCGICONF ioctl on the socket to get its network
     *   interface information.  We need to do this in two passes: first we
     *   make a call with a null request (ifcu_req) buffer just to find out
     *   how much space we need for the buffer, then we allocate the buffer
     *   and make another call to fetch the data.  
     */
    if ((s = socket(AF_INET, SOCK_DGRAM, 0)) >= 0
        && ioctl(s, SIOCGIFCONF, &ifc) >= 0
        && (ifc.ifc_ifcu.ifcu_req = (struct ifreq *)t3malloc(ifc.ifc_len)) != 0
        && ioctl(s, SIOCGIFCONF, &ifc) >= 0)
    {
        /* figure the number of interfaces in the list  */
        int numif = ifc.ifc_len / sizeof(struct ifreq);

        /* iterate over the interfaces in the list */
        struct ifreq *r = ifc.ifc_ifcu.ifcu_req;
        for (int i = 0 ; i < numif ; ++i, ++r)
        {
            /* get the network address for this interface */
            struct sockaddr_in *sin = (struct sockaddr_in *)&r->ifr_addr;
            const char *ip = inet_ntoa(sin->sin_addr);

            /* if it's not a 127.0... address, return it */
            if (memcmp(ip, "127.0.", 6) != 0)
            {
                /* copy the result */
                lib_strcpy(buf, buflen, ip);

                /* success! - and no need to look any further */
                ok = TRUE;
                break;
            }
        }
    }

    /* if we allocated a result buffer, free it */
    if (ifc.ifc_ifcu.ifcu_req != 0)
        t3free(ifc.ifc_ifcu.ifcu_req);

    /* if we opened a socket, close it */
    if (s >= 0)
        close(s);

    /* return the status information */
    return ok;
}

/* ------------------------------------------------------------------------ */
/*
 *   Waitable object base class 
 */

/*
 *   Wait for the object with a timeout 
 */
int OS_Waitable::wait(unsigned long timeout)
{
    return get_event()->evt_wait(timeout);
}

/*
 *   Test the object state without blocking
 */
int OS_Waitable::test()
{
    return get_event()->evt_test();
}


/*
 *   Wait for multiple waitable objects
 */
int OS_Waitable::multi_wait(int cnt, OS_Waitable **objs,
                            unsigned long timeout)
{
    int i;
    int ret;
    struct timespec tm;
    
    /* figure the timeout, if applicable */
    if (timeout != OS_FOREVER)
        figure_timeout(&tm, timeout);
    
    /* create an event to represent the group wait */
    OS_Event group_evt(FALSE);
    
    /* add the group event as a subscriber to each individual event */
    for (i = 0 ; i < cnt ; ++i)
        objs[i]->get_event()->subscribe(&group_evt);
    
    /* now wait until we get an individual event */
    for (;;)
    {
        /* check to see if any individual event is fired yet */
        for (i = 0, ret = OSWAIT_ERROR ; i < cnt ; ++i)
        {
            /* if this event is fired, we have a winner */
            if (objs[i]->test())
            {
                /* this is the event that fired */
                ret = OSWAIT_EVENT + i;
                
                /* we only need one event, so stop looking */
                break;
            }
        }
        
        /* if we found a fired event, we're done */
        if (ret != OSWAIT_ERROR)
            break;
        
        /* 
         *   Since we didn't find a signaled event, wait for the group event.
         *   We subscribed to each individual event, so when any of the
         *   subject events are signaled, they'll also signal our group event
         *   object, waking us up from this wait, at which point we'll go
         *   back and look for which event was fired.  Note that if there's a
         *   timeout, we use the wait-with-timeout with the ending time we
         *   figured; otherwise we just use a simple indefinite wait.  
         */
        ret = (timeout != OS_FOREVER
               ? group_evt.evt_wait(&tm)
               : (group_evt.evt_wait(), OSWAIT_EVENT));
        
        /* 
         *   If the group event fired, continue with the loop, so that we go
         *   back and find which individual subject event fired.  Otherwise,
         *   we have a timeout or error, so in either case abort the wait and
         *   return the result to our caller.  
         */
        if (ret != OSWAIT_EVENT)
            break;
    }
    
    /* remove each subscription */
    for (i = 0 ; i < cnt ; ++i)
        objs[i]->get_event()->unsubscribe(&group_evt);
    
    /* return the result */
    return ret;
}

/* ------------------------------------------------------------------------ */
/*
 *   Socket monitor thread 
 */
class OS_Socket_Mon_Thread: public OS_Thread
{
public:
    OS_Socket_Mon_Thread(OS_CoreSocket *s)
    {
        /* keep a reference on our socket */
        this->s = s;
        s->add_ref();
    }

    ~OS_Socket_Mon_Thread()
    {
        /* we're done with the socket */
        s->release_ref();
    }

    /* main thread entrypoint */
    void thread_main()
    {
        /* create the quit notifier pipe */
        if (pipe(qpipe) == -1)
        {
            s->close();
            s->ready_evt->signal();
            return;
        }

        /* 
         *   add a cleanup handler: on exit, we need to signal the 'ready'
         *   event so that any other threads waiting for the socket will
         *   unblock 
         */
        oss_debug_log("starting socket monitor thread %lx", (long)tid);
        pthread_cleanup_push(thread_cleanup, this);

        /* loop as long as the socket is open */
        for (;;)
        {
            /* 
             *   Wait for the socket to go into blocking mode.  Unix doesn't
             *   have an "inverse select" function that blocks while the
             *   handle is unblocked, so we have to roll our own mechanism
             *   here, using a separate event set up for this purpose.  The
             *   socket signals this event each time it encounters an
             *   EWOULDBLOCK error in a send/recv. 
             */
            s->blocked_evt->wait();

#if 1
            /* 
             *   Wait for the socket to become ready.  Also poll the quit
             *   notification pipe, so that we'll wake up as soon as our
             *   socket has been closed locally.  
             */
            pollfd fd[2];
            fd[0].fd = s->s;
            fd[0].events = (s->wouldblock_sending ? POLLOUT : POLLIN | POLLPRI)
                           | POLLHUP;
            fd[1].fd = qpipe[0];
            fd[1].events = POLLIN;

            /* wait; if that fails, terminate the thread */
            if (poll(fd, 2, -1) < 0)
            {
                if (errno != EINTR)
                    break;
            }

            /* check to see if the socket is ready, or if it's been closed */
            if (fd[1].revents != 0)
            {
                /* quit event - exit the loop */
                break;
            }
            else if (fd[0].revents != 0)
            {
                /* ready - reset the 'blocked' event, and signal 'ready' */
                s->blocked_evt->reset();
                s->ready_evt->signal();
            }
            else
            {
                /* not ready - reset 'ready' and signal 'blocked' */
                s->ready_evt->reset();
                s->blocked_evt->signal();
            }
#else
            /* initialize a selection set for the socket */
            fd_set rfds, wfds;
            FD_ZERO(&rfds);
            FD_ZERO(&wfds);

            /* add the socket to the appropriate sets */
            FD_SET(s->s, s->wouldblock_sending ? &wfds : &rfds);

            /* wait for the socket to become ready */
            if (select(s->s + 1, &rfds, &wfds, 0, 0) <= 0)
                break;

            /* 
             *   if the socket has an exception, give up - the socket must
             *   have been closed or reset, in which case the monitor thread
             *   is no longer useful
             */
            if (FD_ISSET(s->s, &efds))
                break;

            /* if the socket selector fired, the socket is ready */
            if (FD_ISSET(s->s, &rfds) || FD_ISSET(s->s, &wfds))
            {
                /* reset the 'blocked' event, and signal 'ready' */
                s->blocked_evt->reset();
                s->ready_evt->signal();
            }
            else
            {
                /* reset 'ready' and signal 'blocked' */
                s->ready_evt->reset();
                s->blocked_evt->signal();
            }
#endif
        }

        /* pop and invoke the cleanup handler */
        pthread_cleanup_pop(TRUE);
    }

    /* notify the thread to shut down */
    void shutdown()
    {
        /* write the notification to the quit pipe */
        (void)write(qpipe[1], "Q", 1);
        s->blocked_evt->signal();
    }

private:
    static void thread_cleanup(void *ctx)
    {
        /* get the thread object (it's the context) */
        OS_Socket_Mon_Thread *t = (OS_Socket_Mon_Thread *)ctx;

        /* before exiting, let anyone waiting for us go */
        t->s->blocked_evt->signal();
        t->s->ready_evt->signal();
    }

    /* our socket */
    OS_CoreSocket *s;

    /* quit notification pipe, for sending a 'quit' signal to the thread */
    int qpipe[2];
};

/* ------------------------------------------------------------------------ */
/*
 *   Core Socket.  This is the base class for ordinary data channel sockets
 *   and listener sockets. 
 */

/* last incoming network event time */
time_t OS_CoreSocket::last_incoming_time = 0;

/*
 *   Destruction 
 */
OS_CoreSocket::~OS_CoreSocket()
{
    /* close the socket */
    close();

    /* release resources */
    if (ready_evt != 0)
        ready_evt->release_ref();
    if (blocked_evt != 0)
        blocked_evt->release_ref();
    if (mon_thread != 0)
        mon_thread->release_ref();
}

/*
 *   Close the socket 
 */
void OS_CoreSocket::close()
{
    /* close and forget the system socket */
    if (s != -1)
    {
        ::close(s);
        s = -1;
    }

    /* release our non-blocking status events */
    if (ready_evt != 0)
        ready_evt->signal();

    /* kill the monitor thread, if applicable; wait for it to exit */
    if (mon_thread != 0)
    {
        mon_thread->shutdown();
        mon_thread->wait();
    }
}

/*
 *   Set the socket to non-blocking mode 
 */
void OS_CoreSocket::set_non_blocking()
{
    /* if it's already in non-blocking mode, there's nothing to do */
    if (ready_evt != 0)
        return;

    /* set the system socket to non-blocking mode */
    fcntl(s, F_SETFL, O_NONBLOCK);

    /* 
     *   Create the "ready" event for the socket.  The monitor thread signals
     *   this event whenever select() shows that the socket is ready.  The
     *   send() and recv() methods reset this event whenever the underlying
     *   socket send/recv functions return EWOULDBLOCK.  Callers can thus
     *   wait on this event when they want to block until the socket is
     *   ready.
     *   
     *   The reason that callers would want an event object rather than just
     *   actually blocking on the socket call is that they can combine this
     *   event with others in a multi-wait, so that they'll stop blocking
     *   when the socket is ready OR another event fires, whichever comes
     *   first.
     *   
     *   This is a manual reset event because it follows the socket's
     *   readiness state - it doesn't reset on releasing a thread, but rather
     *   when the thread actually exhausts the socket buffer and would cause
     *   the socket to block again.  
     */
    ready_evt = new OS_Event(TRUE);

    /*
     *   Create the "blocked" event.  The send() and recv() methods signal
     *   this event when the underlying socket calls return EWOULDBLOCK.  The
     *   monitor thread waits on this event before calling select() on the
     *   socket, so that it doesn't loop endlessly when the socket is ready
     *   for an extended period.  Instead, the monitor thread blocks on this
     *   until the main thread encounters an EWOULDBLOCK error, at which
     *   point the monitor wakes up and performs a select(), which will then
     *   block until the socket becomes ready.  
     */
    blocked_evt = new OS_Event(TRUE);

    /* 
     *   Assume the socket starts out ready.  When the caller performs the
     *   first socket operation, they'll determine the actual state - if the
     *   send/recv succeed, it really was ready.  If EWOULDBLOCK is returned,
     *   we know that it wasn't ready, at which point we'll update both
     *   events so that the monitor thread can watch for eventual readiness. 
     */
    ready_evt->signal();

    /*
     *   Launch the monitor thread.  This thread synchronizes the state of
     *   the sock_evt event with the underlying socket state.  
     */
    mon_thread = new OS_Socket_Mon_Thread(this);
    mon_thread->launch();
}

/* ------------------------------------------------------------------------ */
/*
 *   HTTP Client 
 */

/* receive callback */
static size_t http_get_recv(void *ptr, size_t siz, size_t nmemb, void *stream)
{
    /* copy the received data to the caller's stream, if we have one */
    if (stream != 0)
    {
        /* cast the stream to our CVmDataSource type */
        CVmDataSource *reply = (CVmDataSource *)stream;
        
        /* 
         *   Copy the data to the buffer; if write() returns zero, it means
         *   we were successful; to indicate success to CURL, return the
         *   number of bytes written, which equals the number of bytes we
         *   were asked to write.  If write() returns non-zero, it's an
         *   error, which we indicate by returning 0 to CURL to say that we
         *   didn't successfully write any bytes.
         */
        size_t bytes = siz * nmemb;
        return reply->write(ptr, bytes) ? 0 : bytes;
    }
    else
    {
        /* there's no stream, so we didn't copy anything */
        return 0;
    }
}

/* send callback */
static size_t http_get_send(void *ptr, size_t siz, size_t nmemb, void *stream)
{
    /* copy the data from the stream to the buffer */
    if (stream != 0)
    {
        /* cast the stream to our payload item object */
        CVmDataSource *s = (CVmDataSource *)stream;

        /* read from the stream into the buffer */
        return s->readc(ptr, siz * nmemb);
    }
    else
    {
        /* there's no stream, so we didn't copy anything */
        return 0;
    }
}

/* header receive callback */
static size_t http_get_hdr(void *ptr, size_t siz, size_t nmemb, void *stream)
{
    /* get our stream object, properly cast */
    CVmMemorySource *hstream = (CVmMemorySource *)stream;

    /* write the header to the stream */
    if (hstream->write(ptr, siz * nmemb))
        return 0;

    /* success - we handled all of the bytes passed in */
    return siz * nmemb;
}


/*
 *   curl debug callback - curl invokes this to send us error information if
 *   anything goes wrong in a curl_easy_perform() call 
 */
#ifdef OSNU_CURL_DEBUG
static int curl_debug(CURL *h, curl_infotype infotyp,
                      char *info, size_t infolen, void *)
{
    if (infotyp == CURLINFO_TEXT)
        fprintf(stderr, "%.*s\n", (int)infolen, info);
    return 0;
}
#endif

/*
 *   Send an HTTP request as a client
 */
int OS_HttpClient::request(int opts,
                           const char *host, unsigned short portno,
                           const char *verb, const char *resource,
                           const char *send_headers, size_t send_headers_len,
                           OS_HttpPayload *payload,
                           CVmDataSource *reply, char **headers,
                           char **location, const char *ua)
{
    int ret = ErrOther;                                      /* result code */
#ifndef NOCURL
    char *url = 0;                                     /* full resource URL */
    CURL *h = 0;                              /* libcurl transaction handle */
    char *formbuf = 0;          /* application/x-www-form-urlencoded buffer */
    size_t formlen = 0;                           /* length of formbuf data */
    curl_httppost *formhead = 0;          /* multipart form field list head */
    curl_httppost *formtail = 0;          /* multipart form field list tail */
    CVmMemorySource *hstream = 0;    /* memory stream for capturing headers */
    curl_slist *hdr_slist = 0;    /* caller's headers, in curl slist format */
    
    /* initially clear the location, if applicable */
    if (location != 0)
        *location = 0;

    /* presume no headers */
    if (headers != 0)
        *headers = 0;

    /* figure the scheme */
    const char *scheme = ((opts & OptHTTPS) != 0 ? "https" : "http");

    /* set up a handle for the communications */
    h = curl_easy_init();

    /* if that failed, return failure */
    if (h == 0)
    {
        ret = ErrOther;
        goto done;
    }

    /* build the full URL */
    url = t3sprintf_alloc("%s://%s:%d%s", scheme, host, portno, resource);

    /* set up the connection to the resource */
    curl_easy_setopt(h, CURLOPT_URL, url);

    /* we don't want a progress meter or signals */
    curl_easy_setopt(h, CURLOPT_NOPROGRESS, (long)1);
    curl_easy_setopt(h, CURLOPT_NOSIGNAL, (long)1);

    /* set our write callback */
    curl_easy_setopt(h, CURLOPT_WRITEFUNCTION, http_get_recv);
    curl_easy_setopt(h, CURLOPT_WRITEDATA, reply);

    /* set our header write callback, if the caller wants the headers */
    if (headers != 0)
    {
        hstream = new CVmMemorySource(1024);
        curl_easy_setopt(h, CURLOPT_HEADERFUNCTION, http_get_hdr);
        curl_easy_setopt(h, CURLOPT_WRITEHEADER, hstream);
    }

    /* if there's a user agent string, send it along */
    if (ua != 0 && ua[0] != '\0')
        curl_easy_setopt(h, CURLOPT_USERAGENT, ua);

    /* set the verb */
    if (stricmp(verb, "GET") == 0)
    {
        /* this is the default verb - no libcurl option setting is needed */
    }
    else if (stricmp(verb, "POST") == 0 && payload != 0)
    {
        /* check for a multipart/formdata upload */
        if (payload->count_items() == 1
            && payload->get(0)->name[0] == '\0')
        {
            /* 
             *   We have exactly one file-type item, and the item has an
             *   empty name.  In this case, the caller has pre-encoded the
             *   content body, so we don't want to apply any further POST
             *   encoding; simply use the content exactly as given. 
             */

            /* get the file to send - this is the payload item's stream */
            CVmDataSource *stream = payload->get(0)->stream;

            /* set up the source data */
            curl_easy_setopt(h, CURLOPT_READFUNCTION, http_get_send);
            curl_easy_setopt(h, CURLOPT_READDATA, stream);
            curl_easy_setopt(h, CURLOPT_INFILESIZE, stream->get_size());
        }
        else if (payload->is_multipart())
        {
            /* we have file attachments - build a curl_httppost list */
            int cnt = payload->count_items();
            for (int i = 0 ; i < cnt ; ++i)
            {
                /* get this item */
                OS_HttpPayloadItem *item = payload->get(i);

                /* check the item type */
                if (item->stream != 0)
                {
                    /* this is a file upload field */
                    if (curl_formadd(
                        &formhead, &formtail,
                        CURLFORM_COPYNAME, item->name,
                        CURLFORM_FILENAME, item->val,
                        CURLFORM_CONTENTTYPE, item->mime_type,
                        CURLFORM_CONTENTSLENGTH, item->stream->get_size(),
                        CURLFORM_STREAM, item->stream,
                        CURLFORM_END))
                        goto done;

                    /* make sure we've set the read callback */
                    curl_easy_setopt(h, CURLOPT_READFUNCTION, http_get_send);
                }
                else
                {
                    /* this is a simple name/value pair */
                    if (curl_formadd(&formhead, &formtail,
                                     CURLFORM_COPYNAME, item->name,
                                     CURLFORM_COPYCONTENTS, item->val,
                                     CURLFORM_END))
                        goto done;
                }
            }

            /* set up the post with the field list */
            curl_easy_setopt(h, CURLOPT_POST, (long)1);
            curl_easy_setopt(h, CURLOPT_HTTPPOST, formhead);
        }
        else
        {
            /* it's a simple form - build the urlencoded form data */
            formbuf = payload->urlencode(formlen);

            /* set the form data */
            curl_easy_setopt(h, CURLOPT_POST, (long)1);
            curl_easy_setopt(h, CURLOPT_POSTFIELDS, formbuf);
            curl_easy_setopt(h, CURLOPT_POSTFIELDSIZE, (long)formlen);
        }
    }
    else if (stricmp(verb, "PUT") == 0
             && payload != 0
             && payload->count_items() == 1)
    {
        /* set the PUT verb */
        curl_easy_setopt(h, CURLOPT_UPLOAD, (long)1);

        /* get the file to send - this is the single payload item's stream */
        CVmDataSource *stream = payload->get(0)->stream;

        /* set up the source data */
        curl_easy_setopt(h, CURLOPT_READFUNCTION, http_get_send);
        curl_easy_setopt(h, CURLOPT_READDATA, stream);
        curl_easy_setopt(h, CURLOPT_INFILESIZE, (long)stream->get_size());
    }
    else 
    {
        /* it's not GET, POST, or PUT - we don't accept other verbs */
        curl_easy_cleanup(h);
        return ErrParams;
    }

    /* 
     *   if a location parameter was provided, the caller wants to get any
     *   redirect location returned, rather than following the redirect;
     *   otherwise they want us to follow redirects 
     */
    curl_easy_setopt(h, CURLOPT_FOLLOWLOCATION, (long)(location == 0));

    /* add the caller's custom headers, if provided */
    if (send_headers != 0)
    {
        /* add each header to the list */
        const char *p = send_headers;
        size_t rem = send_headers_len;
        while (rem != 0)
        {
            /* skip leading spaces */
            for ( ; rem != 0 && *p != '\r' && *p != '\n' && is_space(*p) ;
                 ++p, --rem) ;

            /* scan to the CR-LF */
            const char *h = p;
            for ( ; rem != 0 && !(rem >= 2 && memcmp(p, "\r\n", 2) == 0) ;
                 ++p, --rem) ;

            /* if the line isn't empty, add the header */
            if (p != h)
            {
                /* get a null-terminated copy of the header */
                char *hn = lib_copy_str(h, p - h);

                /* add the header */
                hdr_slist = curl_slist_append(hdr_slist, hn);

                /* done with the copy of the string */
                lib_free_str(hn);
            }

            /* skip the CR-LF */
            if (rem >= 2)
                p += 2, rem -= 2;
        }

        /* set the header list in curl */
        curl_easy_setopt(h, CURLOPT_HTTPHEADER, hdr_slist);
    }

    /* 
     *   To debug problems with CURL, enable the next two lines, which tell
     *   CURL to call curl_debug() with detailed status information as it
     *   goes through the curl_easy_perform() call.  The status information
     *   can be very helpful in tracking down problems.  You can look at the
     *   status calls to curl_debug() using gdb or by modifying curl_debug()
     *   (see above) to write to a log file or the like.
     */
#ifdef OSNU_CURL_DEBUG
    curl_easy_setopt(h, CURLOPT_VERBOSE, 1);
    curl_easy_setopt(h, CURLOPT_DEBUGFUNCTION, curl_debug);
#endif

    /* do the transfer */
    if (!curl_easy_perform(h))
    {
        /* get the HTTP response code */
        long http_stat;
        curl_easy_getinfo(h, CURLINFO_RESPONSE_CODE, &http_stat);

        /* the HTTP response code is the return value */
        ret = (int)http_stat;

        /* if they wanted redirect data, and we got redirect data, return it */
        if (location != 0 && http_stat == 301)
        {
            char *l = 0;
            curl_easy_getinfo(h, CURLINFO_REDIRECT_URL, &l);
            
            /* copy it back to the caller */
            *location = lib_copy_str(l);
        }

        /* if they wanted headers, return the headers */
        if (headers != 0)
        {
            /* get the size of the headers */
            size_t hlen = hstream->get_size();

            /* allocate space for a copy for the caller (with null byte) */
            *headers = new char[hlen + 1];

            /* copy the headers into the new buffer */
            hstream->seek(0, OSFSK_SET);
            hstream->read(*headers, hlen);

            /* add the null terminator */
            (*headers)[hlen] = '\0';
        }
    }

done:
    /* close the handle */
    if (h != 0)
        curl_easy_cleanup(h);

    /* delete the URL buffer */
    if (url != 0)
        lib_free_str(url);

    /* free the form data buffer */
    if (formbuf != 0)
        t3free(formbuf);

    /* delete the multipart form field list */
    if (formhead != 0)
        curl_formfree(formhead);

    /* delete the header capture stream */
    if (hstream != 0)
        delete hstream;

    /* free the header slist */
    if (hdr_slist != 0)
        curl_slist_free_all(hdr_slist);

    /* return the result code */
#endif // NOCURL

    return ret;
}

/* ------------------------------------------------------------------------ */
/*
 *   Thread 
 */

OS_Thread::OS_Thread()
{
    /* count it in the leak tracker */
    IF_LEAK_CHECK(thread_cnt.inc());

        /* we don't have a thread ID yet */
        tid_valid = FALSE;

    /* create the event to signal at thread completion */
    done_evt = new OS_Event(TRUE);

    /* add myself to the master thread list */
    G_thread_list->add(this);
}

OS_Thread::~OS_Thread()
{
        /* 
         *   Detach the thread.  We don't use 'join' to detect when the
         *   thread terminates; instead, we use our thread event.  This lets
         *   the operating system delete the thread resources (in particular,
         *   its stack memory) immediately when the thread exits, rather than
         *   waiting for a 'join' that might never come.  
         */
        if (tid_valid)
                pthread_detach(tid);

    /* release our 'done' event */
        done_evt->release_ref();

    /* clean up the master thread list for our deletion */
    if (G_thread_list != 0)
        G_thread_list->clean();

    /* count it for leak tracking */
    IF_LEAK_CHECK(thread_cnt.dec());
}

