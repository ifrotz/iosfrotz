#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/errno.h>
#include <unistd.h>

#import "FTPServ.h"
#import "iphone_frotz.h"

#include <CFNetwork/CFNetServices.h>

typedef unsigned short UInt16;
typedef int Int32;
typedef short Int16;

// this holds error message reported to the client
char *sExtra;
char zzbuf[256];

void logMessage(char *x) {
    NSLog(@"%s", x);
}

// shortcuts to change button captions
#define showStatus(x) logMessage(x)
#define showExtra(x)  logMessage(x)

@implementation	FTPSession

// write a status line to the client

-(int)sendResponse:(NSFileHandle*)conn buf:(const char *)buf {
    char obuf[BUFSIZE];
    strncpy(obuf, buf, sizeof(outbuf)-3);
    strcat(obuf, "\r\n");
    int len = strlen(obuf);
    int sock = [conn fileDescriptor];
#if 0
    fd_set writefds, errorfds;
    struct timeval tv;
    tv.tv_sec = 0;
    tv.tv_usec = 400000;
    
    FD_ZERO(&writefds);
    FD_ZERO(&errorfds);
    FD_SET(sock, &writefds);
    FD_SET(sock, &errorfds);
    
    do {
        int rval = select(sock + 1, NULL, &writefds, &errorfds, &tv);
        if (rval < 0)
            continue;
        if (FD_ISSET(sock, &errorfds)) {
            len = -1;
            break;
        }
        if (FD_ISSET(sock, &writefds)) {
            FD_CLR(sock, &writefds);
            len = write(sock, obuf, len);
        } else {
            len = -1;
            break;
        }
    } while (1);
    select(sock + 1, NULL, &writefds, &errorfds, &tv);
#endif
    NSData *data = [NSData dataWithBytes: obuf length:len];
    @try {
        [conn writeData: data];
    }
    @catch (NSException *e) {
        NSLog(@"caught ex in sendresp");
        len = -1;
    }
    usleep(250000);
	
    NSLog(@"sock %d: sendingResponse:%s", sock, obuf);
    return len;
}

-(NSFileHandle*) connectBack {
    int csock;
    struct sockaddr_in connTo;
    int tries = 0;
    
    if (m_pasvPort > 0) {
        NSLog(@"connect back m_pasvPort %d", m_pasvPort);
        while (m_pasvSock <= 0 && tries++ < 400) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow: 0.005]];
        }
        NSLog(@"connect back m_pasvSock %d, tries %d", m_pasvSock, tries);
        return m_incomingConnection; // m_pasvSock;
    }
    
    csock = socket (AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (csock < 0) {
        showExtra(sExtra = "400 error opening stream socket");
        return nil;
    }
    
    connTo.sin_family = AF_INET;
    connTo.sin_addr.s_addr = htonl(m_serveHost);
    connTo.sin_port = htons(m_servePort);
    memset(connTo.sin_zero, 8, 0);
    
    if (connect (csock, (struct sockaddr *)&connTo, sizeof connTo) < 0) {
        sprintf(bufa, sExtra = "403 error connecting: %d", errno);
        showExtra(bufa);
        return nil;
    }
    showExtra(sExtra = "connected back");
    
    return [[NSFileHandle alloc] initWithFileDescriptor:csock closeOnDealloc:YES];
}

// concatenate path ato to x, put the result in buffer dst
// remove .. and . if necessary

-(int)generateAbsolute: (char *)wd suffix:(char *)subpath buffer:(char *)localDestPath userDestPath:(char*)userPath isWrite:(BOOL)isWrite {
    int l, k, m;
    char tempPath[BUFSIZE];
    const char *localRootPath = [m_rootPath cStringUsingEncoding: NSASCIIStringEncoding];
    if (*subpath == '-')
        *subpath = 0;
    if (*wd==0 && *subpath== 0)
        subpath = "/";
    if(subpath[0] == '/') {
        strcpy(localDestPath, localRootPath);
        if (userPath)
            strcpy(userPath, subpath);
        strcat(localDestPath, subpath);
        if (access(localDestPath, R_OK)!=0) {
            if (userPath)
                strcpy(userPath, wd);
            strcpy(localDestPath, wd);
            return -1;
        }
        return 0;
    }
    l = strlen(wd);
    
    if(l + strlen(subpath) > BUFSIZE)
        sprintf(tempPath, "/");
    else
        sprintf(tempPath, "%s%s%s", wd, l > 0 && wd[l-1] == '/' ? "" : "/", subpath);
    
    k = 0; m = 0;
    while(1) {
        if(tempPath[k] == '/') {
            if(tempPath[k+1] == '.' && tempPath[k+2] == 0 || tempPath[k+1] == '.' && tempPath[k+2] == '/') {
                k+=2; continue;
            }
            if(tempPath[k+1] == '.' && tempPath[k+2] == '.' && (tempPath[k+3] == 0 || tempPath[k+3] == '/')) {
                k+=3;
                do
                {m--;}
                while(m > 0 && tempPath[m] != '/');
                if(m < 0)
                    m = 0;
                continue;
            }
        }
        tempPath[m++] = tempPath[k];
        if(tempPath[k++] == 0)
            break;
    }
    if(tempPath[0] == 0) {tempPath[0] = '/'; tempPath[1] = 0;}
    if (userPath)
        strcpy(userPath, tempPath);
    sprintf(localDestPath, "%s%s", localRootPath, tempPath);
    if (!isWrite && access(localDestPath, R_OK)!=0) {
        if (userPath)
            strcpy(userPath, wd);
        sprintf(localDestPath, "%s%s", localRootPath, wd);
        return -1;
    }
    
    
    return 0;
}

BOOL isHiddenFile(NSString *file) {
    return ([file isEqualToString: @"metadata.plist"] || [file isEqualToString: @"storyinfo.plist"] || [file isEqualToString: @"dbcache.plist"]
            || [file isEqualToString: @".DS_Store"]
            || [file isEqualToString: @kFrotzOldAutoSaveFile] || [file isEqualToString: @kFrotzAutoSavePListFile]
            || [file isEqualToString: @kFrotzAutoSaveActiveFile]
            || [file isEqualToString:@"Splashes"] || [file hasPrefix: @"release_"]);
}

// given FTP path name, split it into volRefNum (card identifier) and 
// name2 (directory on the card)

// create the directory listing (and send it)
-(void) createListForDirectory:(NSString *)dirStr {
    //int sock = m_socket;
    //int csock;
    NSFileHandle *csock = [self connectBack];
    if(!csock) {
        sprintf(bufa, sExtra = "403 Unable to connect back to host (error=%d)", errno);
        perror("error");
        
        [self sendResponse: m_commandConnection buf:bufa];
        [m_commandConnection closeFile];
        
        return;
    }
    
    int ret = [self sendResponse: m_commandConnection buf:"150 Here comes the directory listing."];
    
    NSFileManager *defaultManager = [NSFileManager defaultManager];
    NSArray *fileList = [defaultManager directoryContentsAtPath: dirStr];
    struct timeval now;
    gettimeofday(&now, NULL);
    for (NSString *file in fileList) {
        if (ret < 0)
            break;
        NSString *path = [dirStr stringByAppendingPathComponent: file];
        char tbuf[1024], timebuf[32], userbuf[16], groupbuf[16];
        struct stat statbuf;
        stat([path UTF8String], &statbuf);
        if (isHiddenFile(file))
            continue;
        const char *f = [file UTF8String];
        time_t sec = statbuf.st_mtimespec.tv_sec;
        sprintf(timebuf, "%s", ctime(&sec)+4);
        if (now.tv_sec - sec > 5184000)
            strcpy(timebuf + 7, timebuf + 15);
        if (statbuf.st_uid==501)
            sprintf(userbuf, "mobile");
        else if (statbuf.st_uid==0)
            sprintf(userbuf, "root");
        else sprintf(userbuf, "%8d", statbuf.st_uid);
        if (statbuf.st_gid==501)
            sprintf(groupbuf, "mobile");
        else if (statbuf.st_gid==0)
            sprintf(groupbuf, "root");
        else sprintf(groupbuf, "%8d",statbuf.st_gid);
        sprintf(tbuf, "%s%s%s%s%s%s%s%s%s%s %3d %8s %8s %8d %-12.12s %s", 
                (statbuf.st_mode & S_IFDIR) ? "d":"-", 
                (statbuf.st_mode & 0400) ? "r":"-", (statbuf.st_mode & 0200) ? "w":"-", (statbuf.st_mode & 0100) ? "x":"-",
                (statbuf.st_mode & 0040) ? "r":"-", (statbuf.st_mode & 0020) ? "w":"-", (statbuf.st_mode & 0010) ? "x":"-",
                (statbuf.st_mode & 0004) ? "r":"-", (statbuf.st_mode & 0002) ? "w":"-", (statbuf.st_mode & 0001) ? "x":"-",	    
                (int)statbuf.st_nlink, userbuf, groupbuf, (int)statbuf.st_size, timebuf, f);
        ret = [self sendResponse: csock buf: tbuf];
    }
    if (m_pasvSock > 0) {
        NSLog(@"closeconn1 %d", [m_incomingConnection fileDescriptor]);
        [m_incomingConnection closeFile];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:m_incomingConnection];
        [m_incomingConnection release];
        m_pasvSock = 0; //aaa-1;
        m_incomingConnection = nil;
        if (ret < 0) {
            NSLog(@"error writing response; closing command connection %d", [m_commandConnection fileDescriptor]);
            [[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:m_commandConnection];
            [m_commandConnection closeFile];
        }
        
    } else {
        //close(csock);
        [csock release];
    }
    
    [self sendResponse: m_commandConnection buf:"226 Directory sent OK."];
}

// create the short directory listing (and send it)
-(void) createNListForDirectory:(NSString *)dirStr {
    //int sock = m_socket;
    //int csock;
    NSFileHandle *csock = [self connectBack];
    if(!csock) {
        sprintf(bufa, sExtra = "403 Unable to connect back to host (error=%d)", errno);
        
        [self sendResponse: m_commandConnection buf: bufa];
        return;
    }
    [self sendResponse: m_commandConnection buf: "150 Here comes the directory listing."];
    
    NSFileManager *defaultManager = [NSFileManager defaultManager];
    NSArray *fileList = [defaultManager directoryContentsAtPath: dirStr];
    for (NSString *file in fileList) {
        if (isHiddenFile(file))
            continue;
        const char *f = [file UTF8String];
        if (f)
            [self sendResponse:csock buf:f];
    }
    if (m_pasvSock > 0) {
        NSLog(@"closeconn2 %d", [m_incomingConnection fileDescriptor]);
        [m_incomingConnection closeFile];
        m_pasvSock = 0; //aaa-1;
    } else {
        [csock release];
        //close(csock);
    }
    [self sendResponse: m_commandConnection buf:  "226 Directory sent OK."];
}

-(void) retrieveFile:(char *)fname {
    char filebuf[16384];
    int totalBytesSent = 0;
    //int sock = m_socket;
    //int csock;
    
    showStatus("Retrieving a file...");
    showExtra(fname);
    
    NSFileHandle *csock = [self connectBack];
    if(!csock) {
        [self sendResponse: m_commandConnection buf: "550 Unable to connect back for retrieve"];
        return;
	}
    
    FILE *f = NULL;
    
    struct stat statbuf;
    stat(fname, &statbuf);
    if (statbuf.st_mode & S_IFDIR) {
    	[self sendResponse: m_commandConnection buf: "550 That's a directory, doofus."];
        goto errOut;
    }
    f = fopen(fname, "r");
    if (f) {
        [self sendResponse: m_commandConnection buf: "125 Here you are."];
        UInt32 bytes;
        int t;
        int bytesSent;
        
        while (!feof(f)) {
            bytes = fread (filebuf, 1, sizeof(filebuf), f);
            
            if (bytes == 0) {
                showExtra("file retrieved successfully");
                break;
            }
            bytesSent = 0;
            while(bytesSent < bytes) {
                NSData *data = [NSData dataWithBytes:filebuf+bytesSent length:bytes-bytesSent];
                [csock writeData: data]; t = bytes-bytesSent;
                //		t = write(csock, filebuf + bytesSent, bytes - bytesSent);
                if(t < 0) {
                    sprintf(bufa, "retrieve: %d/%d", t, errno);
                    showExtra(bufa);
                    break;
                }
                bytesSent += t;
                totalBytesSent += t;
            }
        }
        fclose(f);
        NSLog(@"retrieveFile: %d bytes sent\n", totalBytesSent);
        
        [self sendResponse: m_commandConnection buf: "226 File sent OK."];
    }
    else {
        [self sendResponse: m_commandConnection buf:  "550 File not found."];
        showExtra("Could not open file for sending");
    }
errOut:
    if (m_pasvSock > 0) {
    	NSLog(@"closeconn3 %d", [m_incomingConnection fileDescriptor]);
        [m_incomingConnection closeFile];
        m_pasvSock = 0; //aaa-1;
    } else {
        [csock release];
        //	close(csock);
    }
}

// user wants to store a file on FTP
-(void) storeFile:(char *)fname {
    //    char filebuf[16384];
    //int sock = m_socket;
    //int csock;
    
    showStatus("Storing a file...");
    showExtra(fname);
    
    NSFileHandle *csock = [self connectBack];
    if(!csock) {
        [self sendResponse: m_commandConnection buf: "550 Unable to connect back for put"];
        return;
    }
    
    BOOL err = NO;
    FILE *f = NULL;
    
    f = fopen(fname, "w+");
    if(f) {
        m_saveFile = f;
        [self sendResponse: m_commandConnection buf:"125 Gimme the file please."];
        return;
#if 0
        while(1) {
            int t = read(csock, filebuf, sizeof(filebuf));
            if(t > 0) {
                if (fwrite(filebuf, 1, t, f) < t) {
                    err = YES;
                    showExtra("store: error writing");
                    break;
                }
            }
            else {
                showExtra("file stored successfully");
                break;
            }
            
        }
        fclose(f);
#endif
    } else
        err = YES;
    if (err)
        [self sendResponse: m_commandConnection buf: "550 Unable to write file."];
    else
        [self sendResponse: m_commandConnection buf:"226 File transfer successful."];
    if (m_pasvSock > 0) {
        NSLog(@"closeconn4 %d", [m_incomingConnection fileDescriptor]);
        [m_incomingConnection closeFile];
        m_pasvSock = 0; //aaa-1;
    } else {
        [csock release];
        //	close(csock);
    }
}

// compare buf to command name t
int isCmd(char *buf, char *t) {
    while(*buf || *t) {
        if(toupper(*buf) != toupper(*t)) return false;
        buf++; t++;
    }
    if(*buf) return false;
    if(*t) return false;
    return true;
}

// parse the "PORT" command

void parseHostAndPort(int sock, char *param, unsigned int *host, int *port) {
    char tab[8];
    int val = 0;
    int idx = 0;
    int len = strlen(param);
    int k;
    for(k=0; k<=len; k++) {
        if(param[k] >= '0' && param[k] <= '9') {
            val *= 10;
            val += param[k]-'0';
        }
        else tab[idx++] = val, val = 0;
    }
    *host = ntohl(*((UInt32*) tab));
    *port = ntohs(*((UInt16*) (tab+4)));
    // todo: use ntohl/ntohs instead
}

-(int) startPassiveListener:(unsigned int *)host  port:(int *)port {
    //    *host = 0;
    *port = 0;
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd <= 0)
        return -1;
    
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, (void *)&yes, (socklen_t)sizeof(yes));
    
    // bind
    struct sockaddr_in addr;
    bzero(&addr, sizeof(addr));
    addr.sin_len    = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port   = htons(0);
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    
    if (bind(fd, (struct sockaddr*)(&addr), (socklen_t)sizeof(addr)) != 0) {
        close(fd);
        NSLog(@"failed bind %d", fd);
        return -1;
    }
    
    if (listen(fd, 5) != 0) {
        close(fd);
        NSLog(@"failed listen %d", fd);
        return -1;
    }
    
    socklen_t len = (socklen_t)sizeof(addr);
    if (getsockname(fd, (struct sockaddr*)(&addr), &len) == 0) {
        //	*host = ntohl(addr.sin_addr.s_addr);
        *port = ntohs(addr.sin_port);
    } else {
        close(fd);
        return -1;
    }
    
    NSFileHandle *listenHandle =  [[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
    if (!listenHandle) {
        *port = 0;
        close(fd);
        return -1;
    }
    
    // setup notifications for connects
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(passiveDataConnectionReceived:) name:NSFileHandleConnectionAcceptedNotification object:listenHandle];
    [listenHandle acceptConnectionInBackgroundAndNotify];
    //    [listenHandle release]; //???
    return fd;
}

// handle the command
-(void )acceptCommand:(int)sock fromBuffer:(char *)buf {
    char responseBuf[BUFSIZE];
    int p = 0;
    char *param;
    
    while(buf[p] && buf[p] != ' ')
        p++;
    if(buf[p] == ' ') {
        param = buf+p+1;
        buf[p] = 0;
    }
    else
        param = "";
    
    if(isCmd(buf, "USER")) {
        m_loggedIn = YES;
        if(m_loggedIn) [self sendResponse: m_commandConnection buf: "230 Login successful."];
        else [self sendResponse: m_commandConnection buf:"530 Login not successful."];
	}
    else if(isCmd(buf, "PASS"))
        [self sendResponse: m_commandConnection buf: "230 Login successful."];
    else if(isCmd(buf, "TYPE"))
        [self sendResponse: m_commandConnection buf: "200 OK"];
    else if(isCmd(buf, "MODE"))
        [self sendResponse: m_commandConnection buf: "200 OK"];
    else if(isCmd(buf, "STRU"))
        [self sendResponse: m_commandConnection buf: "200 OK"];
    else if(isCmd(buf, "SYST"))
        [self sendResponse: m_commandConnection buf: "215 UNIX Type: L8"];
    else if(isCmd(buf, "PWD")) {
        sprintf(buf1, "257 \"%s\" is cwd", cwd && *cwd ? cwd : "/");
        [self sendResponse: m_commandConnection buf:buf1];
	}
    else if(m_loggedIn && isCmd(buf, "CWD")) {
        if ([self generateAbsolute: cwd suffix:param buffer:bufa userDestPath:cwd isWrite:NO] < 0)
            [self sendResponse: m_commandConnection buf: "550 No such file or directory."];
        else
            [self sendResponse: m_commandConnection buf: "250 OK"];
    }
    else if(m_loggedIn && isCmd(buf, "CDUP")) {
        if ([self generateAbsolute: cwd suffix: ".." buffer:bufa userDestPath:cwd isWrite:NO] < 0)
            [self sendResponse: m_commandConnection buf: "550 No such file or directory."];
        else
            [self sendResponse: m_commandConnection buf: "200 OK"];
    }
    else if(isCmd(buf, "PORT")) {
        parseHostAndPort(sock, param, &m_serveHost, &m_servePort);
        [self sendResponse: m_commandConnection buf: "200 PORT command successful."];
    }
    else if(m_loggedIn && isCmd(buf, "LIST")) {
        [self generateAbsolute:cwd suffix:param buffer:bufa userDestPath:nil isWrite:NO];
        [self createListForDirectory: [NSString stringWithUTF8String: bufa]];
        //	[self performSelector:@selector(createListForDirectory:) withObject: [NSString stringWithUTF8String: bufa] afterDelay:0.1];
    }
    else if(m_loggedIn && isCmd(buf, "NLST")) {
        [self generateAbsolute:cwd suffix:param buffer:bufa userDestPath:nil isWrite:NO];
        [self createNListForDirectory: [NSString stringWithUTF8String: bufa]];
        //	[self performSelector:@selector(createNListForDirectory:) withObject: [NSString stringWithUTF8String: bufa] afterDelay:0.1];
    }
    else if(m_loggedIn && isCmd(buf, "RETR")) {
        [self generateAbsolute:cwd suffix:param buffer:bufa userDestPath:nil isWrite:NO];
        [self retrieveFile: bufa];
    }
    else if(m_loggedIn && isCmd(buf, "STOR")) {
        [self generateAbsolute:cwd suffix:param buffer:bufa userDestPath:nil isWrite:YES];
        [self storeFile: bufa];
    }
    else if(m_loggedIn && (isCmd(buf, "DELE") || isCmd(buf, "RMD"))) {
        [self generateAbsolute:cwd suffix:param buffer:bufa userDestPath:nil isWrite:NO];
        NSFileManager *defaultManager = [NSFileManager defaultManager];
        NSError *error;
        if ([defaultManager removeItemAtPath: [NSString stringWithUTF8String: bufa] error: &error])
            [self sendResponse: m_commandConnection buf: "250 Deleted."];
        else [self sendResponse: m_commandConnection buf:"550 File could not be deleted."];
    }
    else if(m_loggedIn && isCmd(buf, "MKD")) {
        //	int err = -1;
        //	[self generateAbsolute:cwd suffix:param buffer:bufa userDestPath:nil isWrite:YES];
        //	if(err == 0) [self sendResponse: m_commandConnection buf: "250 Directory created."];
        //	else
	    [self sendResponse: m_commandConnection buf:"550 Unable to create directory."];
    }
    else if(isCmd(buf, "QUIT")) {
        [self sendResponse: m_commandConnection buf: "221 OK" ];
        // todo: close
    }
    else if(isCmd(buf, "FEAT")) {
        [self sendResponse: m_commandConnection buf:"211 Nothing up my sleeve."];
        // todo: close
    }
    else if(isCmd(buf, "NOOP")) {
        [self sendResponse: m_commandConnection buf: "200 OK"];
        // todo: close
    }
    else if(isCmd(buf, "PASV")) {
        m_pasvPort = 0;
        int fd = [self startPassiveListener: &m_pasvHost  port:&m_pasvPort];
        if (fd > 0)
            sprintf(responseBuf, "227 Entering Passive Mode. (%d,%d,%d,%d,%d,%d)", (m_pasvHost>>24)&0xff, (m_pasvHost>>16)&0xff, (m_pasvHost>>8)&0xff, m_pasvHost&0xff,
                    (m_pasvPort>>8)&0xff, m_pasvPort&0xff);
        else
            sprintf(responseBuf, "500 Unable to bottom");
        [self sendResponse: m_commandConnection buf:responseBuf];
        // todo: close
    }
    else {
        showExtra(buf);
        [self sendResponse: m_commandConnection buf:"500 Unknown command."];
    }
}

- (void)commandDataAvailableNotification:(NSNotification *)notification {
    NSFileHandle *connectionHandle = [notification object];                                  
    NSDictionary *userInfo = [notification userInfo];
    NSData *readData = [userInfo objectForKey:NSFileHandleNotificationDataItem];
    
    char buf[BUFSIZE];
    int cpos = 0;
    
    int sock = m_socket;
    int k, t;
    assert(m_commandConnection == connectionHandle);
	
    if (m_socket < 0 || !readData)
        return;
    
    t = [readData length];
    strncpy(buf, [readData bytes], t);
    buf[t] = 0;
    if(t > 0){
        for(k=0; k<t; k++) {
            if(buf[k] == '\n' || buf[k] == '\r') {
                if(cpos) {
                    cmdbuf[cpos] = 0;
                    NSLog(@"sock %d got cmd: %s\n", m_socket, cmdbuf);
                    [self acceptCommand:sock fromBuffer: cmdbuf];
                }
                cpos = 0;
            }
            else {
                if(cpos < BUFSIZE)
                    cmdbuf[cpos++] = buf[k];
            }
        }
        @try {
            [connectionHandle readInBackgroundAndNotify];
        }
        @catch (NSException *e) {
            NSLog(@"cmd socket %d caught except", sock);
            [[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:connectionHandle];
            [m_commandConnection release];
            m_commandConnection = nil;
            m_socket = 0; //aaa-1;
            [self release];
        }
    }
    else {
        NSLog(@"cmd socket %d gotdata %d length, closing", m_socket, t);
#if 0
        [[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:connectionHandle];
        [connectionHandle closeFile];
        [m_commandConnection release];
        m_commandConnection = nil;
        m_socket = -1;
        [self release];
#endif
    }
}

-(void)passiveDataConnectionReceived:(NSNotification *)aNotification {
    //NSFileHandle * 
    m_incomingConnection = [[aNotification userInfo] objectForKey:NSFileHandleNotificationFileHandleItem];
    
    int msgsock = [m_incomingConnection fileDescriptor];
    m_pasvSock = msgsock;
    
    struct sockaddr_in addr;
    socklen_t len = (socklen_t)sizeof(addr);
    if (getsockname(msgsock, (struct sockaddr*)(&addr), &len) == 0) {
        m_pasvHost = ntohl(addr.sin_addr.s_addr);
    }
    
    [m_incomingConnection retain];
    NSLog(@"got passive connection host %x, sock %d", m_pasvHost, m_pasvSock);
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self
               selector:@selector(dataAvailableNotification:)
                   name:NSFileHandleReadCompletionNotification
                 object:m_incomingConnection];
    [m_incomingConnection readInBackgroundAndNotify];
}

- (void)dataAvailableNotification:(NSNotification *)notification {
    NSFileHandle *connectionHandle = [notification object];                                  
    NSDictionary *userInfo = [notification userInfo];
    NSData *readData = [userInfo objectForKey:NSFileHandleNotificationDataItem];
    int len = [readData length];
    BOOL err = NO;
    if (len > 0) {
        NSLog(@"connForSock %d pasvgotdata %d bytes", [connectionHandle fileDescriptor], len);
        if (m_saveFile) {
            if (fwrite([readData bytes], 1, len, m_saveFile) < len) {
                err = YES;
                len = 0;
                showExtra("store: error writing");
            }
        }
        if (!err)
            [connectionHandle readInBackgroundAndNotify];
    }
    if (len == 0) {
        NSLog(@"connForSock %d pasvgotdata %d len, closing\n", [connectionHandle fileDescriptor], len);
        if (m_saveFile) {
            fclose(m_saveFile);
            m_saveFile = NULL;
            if (err)
                [self sendResponse: m_commandConnection buf:"550 Unable to write file."];
            else
                [self sendResponse: m_commandConnection buf: "226 File transfer successful."];
        }
        [[NSNotificationCenter defaultCenter] removeObserver:self name:/*NSFileHandleReadCompletionNotification*/nil object:connectionHandle];
        [connectionHandle closeFile];
        [connectionHandle release]; //???
        m_pasvSock = 0; //aaa -1;
        m_incomingConnection = nil;
    }
}

-(id)initWithConnection:(NSFileHandle*)incomingConnection rootPath:(NSString*)rootPath {
    if ((self = [self init])) {
        m_socket = 0; //aaa-1;   
        m_csocket = 0; //aaa-1;
        
        m_servePort = 0;
        m_serveHost = 0;
        
        m_pasvHost = 0;
        m_pasvPort = 0;
        m_pasvSock = 0;//aaa-1;
        
        m_saveFile = NULL;
        
        m_rootPath = rootPath;
        m_commandConnection = [incomingConnection retain];
        m_socket = [m_commandConnection fileDescriptor];
        
        struct sockaddr_in addr;
        socklen_t len = (socklen_t)sizeof(addr);
        if (getsockname(m_socket, (struct sockaddr*)(&addr), &len) == 0) {
            m_pasvHost = ntohl(addr.sin_addr.s_addr);
        }
        
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self
                   selector:@selector(commandDataAvailableNotification:)
                       name:NSFileHandleReadCompletionNotification
                     object:m_commandConnection];
        m_loggedIn = YES;
        NSLog(@"got control connection host %x, sock %d", m_pasvHost, m_socket);
        [self sendResponse: m_commandConnection buf: "220 Frotz File Transfer Server " IPHONE_FROTZ_VERS ". Login with any user name."];
        [m_commandConnection readInBackgroundAndNotify];
        
    }
    return self;
}
@end

@implementation  FTPServer

-(void)connectionReceived:(NSNotification *)aNotification {
    NSFileHandle * incomingConnection = [[aNotification userInfo] objectForKey:NSFileHandleNotificationFileHandleItem];
    [[aNotification object] acceptConnectionInBackgroundAndNotify];
    
    [[FTPSession alloc] initWithConnection: incomingConnection rootPath:m_rootPath];
    // will release itself
    
}

-(id)initWithRootPath:(NSString*)rootPath {
    signal(SIGPIPE, SIG_IGN);
    if ((self = [self init])) {
        m_rootPath = [rootPath retain];
    }
    return self;
}

-(BOOL)start:(NSError**)error {
    if (error)
        *error = nil;
    m_listenSocket = socket(AF_INET, SOCK_STREAM, 0);
    NSInteger startFailureCode = 0;
    if (m_listenSocket <= 0) {
        startFailureCode = errno;
        goto startFailed;
    }
    int port = FTPPORT;
    // enable address reuse quicker after we are done w/ our socket
    int yes = 1;
    setsockopt(m_listenSocket, SOL_SOCKET, SO_REUSEADDR, (void *)&yes, (socklen_t)sizeof(yes));
    // bind
    struct sockaddr_in addr;
    bzero(&addr, sizeof(addr));
    addr.sin_len    = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port   = htons(port);
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(m_listenSocket, (struct sockaddr*)(&addr), (socklen_t)sizeof(addr)) != 0) {
        startFailureCode = errno;
        goto startFailed;
    }
    
    // collect the port back out
    if (port == 0) {
        socklen_t len = (socklen_t)sizeof(addr);
        if (getsockname(m_listenSocket, (struct sockaddr*)(&addr), &len) == 0) {
            port = ntohs(addr.sin_port);
        }
    }
    
    // tell it to listen for connections
    if (listen(m_listenSocket, 5) != 0) {
        startFailureCode = errno;
        goto startFailed;
    }
    
    // now use a filehandle to accept connections
    m_listenHandle = [[NSFileHandle alloc] initWithFileDescriptor:m_listenSocket closeOnDealloc:YES];
    if (m_listenHandle == nil) {
        startFailureCode = ENOMEM;
        goto startFailed;
    }
    
    
    m_netService = [[NSNetService alloc] initWithDomain:@"local." type:@"_ftp._tcp." name:@"FrotzFTP" port:port];
    [m_netService setDelegate:self];
	
    if(m_netService && m_listenHandle) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(connectionReceived:) name:NSFileHandleConnectionAcceptedNotification object:m_listenHandle];
        [m_listenHandle acceptConnectionInBackgroundAndNotify];
        [m_netService publish];
    }
    
    return YES;
    
startFailed:
    {
        NSError *err = [NSError errorWithDomain:NSPOSIXErrorDomain code:startFailureCode ? startFailureCode : ENETDOWN userInfo: nil];
        if (error)
            *error = err;
    }
    if (m_netService) {
        [m_netService stop];
        [m_netService release];
        m_netService = nil;
    }
    if (m_listenHandle) {
        [m_listenHandle release];
        m_listenHandle = nil;
    }
    if (m_listenSocket > 0) {
        close(m_listenSocket);
        NSLog(@"failed start server %d", m_listenSocket);
        m_listenSocket = 0;
    }
    return NO;
}

-(BOOL) isRunning {
    return m_listenSocket > 0;
}

-(void)dealloc {
    [m_rootPath release];
    m_rootPath = nil;
    [super dealloc];
}

-(BOOL)shutdown {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [m_netService stop];
    [m_netService release];
    [m_listenHandle release];
    close(m_listenSocket);
    m_listenSocket = -1;
    m_netService = nil;
    m_listenHandle = nil;
    return YES;
}

@end
