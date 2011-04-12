//
//  FTPServ.h
//  Frotz
//
//  Created by Craig Smith on 9/24/08.
//  Copyright 2008-2010 Craig Smith. All rights reserved.
//


@interface FTPServer : NSObject <NSNetServiceDelegate> {
    int m_listenSocket;   // main connection
    NSString *m_rootPath;
    NSString *m_url;
    NSFileHandle *m_listenHandle;
    NSNetService *m_netService;
}
-(BOOL)isRunning;
-(id)initWithRootPath:(NSString*)rootPath;
-(BOOL)start:(NSError**)error;
-(BOOL)shutdown;
@end

#define FTPPORT 2121
#define BUFSIZE 1024

@interface FTPSession : NSObject {
    NSString *m_rootPath;
    int m_socket;   // main connection
    int m_csocket;  // secondary connection

    int m_servePort; // data link port
    unsigned int m_serveHost; // data link host

    unsigned int m_pasvHost;
    int m_pasvPort;
    int m_pasvSock;
    NSFileHandle *m_commandConnection;
    NSFileHandle *m_incomingConnection;
    BOOL m_loggedIn;

    FILE *m_saveFile;

    char outbuf[BUFSIZE];
    char cmdbuf[BUFSIZE];
    char cwd[BUFSIZE];
    char buf1[BUFSIZE];
    char buf2[BUFSIZE];
    char bufa[BUFSIZE];
}
-(int) sendResponse:(NSFileHandle*)conn buf:(const char *)buf;
-(NSFileHandle*) connectBack;
-(int) generateAbsolute: (char *)wd suffix:(char *)subpath buffer:(char *)localDestPath userDestPath:(char*)userPath isWrite:(BOOL)isWrite;
-(void) createListForDirectory:(NSString *)dirStr;
-(void) retrieveFile:(char *)fname;
-(void) storeFile:(char *)fname;

@end


