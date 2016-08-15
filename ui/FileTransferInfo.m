//
//  FileTransferInfo.m
//  Frotz
//
//  Created by Craig Smith on 8/29/08.
//  Copyright 2008 Craig Smith. All rights reserved.
//

#import "FileTransferInfo.h"
#import "TextViewExt.h"
#import "iosfrotz.h"
#import "StoryMainViewController.h"
#import "FrotzSettings.h"
#import "FrotzCommonWebView.h"

#import "FrotzHTTPConnection.h"

#include <arpa/inet.h>
#include <netdb.h>
#include <net/if.h> 
#include <ifaddrs.h>
#include <unistd.h>

BOOL isHiddenFile(NSString *file) {
    return ([file isEqualToString: @"metadata.plist"] || [file isEqualToString: @"storyinfo.plist"] || [file isEqualToString: @"dbcache.plist"]
            || [file isEqualToString: @".DS_Store"]
            || [file isEqualToString: @"alabstersettings"]
            || [file isEqualToString: @"bookmarks.plist"]
            || [file isEqualToString: @kFrotzOldAutoSaveFile] || [file isEqualToString: @kFrotzAutoSavePListFile]
            || [file isEqualToString: @kFrotzAutoSaveActiveFile]
            || [file isEqualToString:@"Splashes"] || [file isEqualToString: @"Inbox"] || [file hasPrefix: @"release_"]);
}


@implementation FileTransferInfo
@synthesize serverIsRunning = m_running;

- (instancetype)initWithController:(NSObject<FrotzSettingsStoryDelegate>*)controller {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        m_controller = controller;
        self.title = NSLocalizedString(@"File Transfer", @"");
    }
    return self;
}

-(void)updateButtonLocation {
    if (m_startButton && m_webView) {
        [m_startButton setFrame:
         CGRectMake([m_webView frame].size.width/2 - (gLargeScreenDevice ? 130:130),
                    gLargeScreenDevice ? 520:  [m_webView frame].size.height-64,
                    260, 48)];
    }
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return gLargeScreenDevice ? YES : interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {    // Notification of rotation ending.
    [self updateMessage];
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
    [self updateButtonLocation];
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    [super willRotateToInterfaceOrientation: toInterfaceOrientation duration:duration];
    if (m_startButton && m_webView)
        [self updateButtonLocation];
}

-(void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    if (m_startButton && m_webView)
        [self updateButtonLocation];
}

- (void)loadView {
    [super loadView];

    m_webView = [FrotzCommonWebViewController sharedWebView];
    
    m_startButton = [UIButton buttonWithType: UIButtonTypeRoundedRect];
    [m_startButton addTarget:self action:@selector(toggleServer) forControlEvents: UIControlEventTouchUpInside];
}

-(void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [m_webView removeFromSuperview];
    [m_webView setFrame: self.view.frame];
    [self.view addSubview: m_webView];
    [self updateButtonLocation];
    [m_webView addSubview: m_startButton];
    [self stopServer];
}

-(void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [m_startButton removeFromSuperview];
}

- (NSString *) localIPAddress
{
    //   NSLog(@"currentHost %@", [NSHost currentHost]);
    
    // Method 1
#if ! defined(IFT_ETHER)
#define IFT_ETHER 0x6/* Ethernet CSMACD */
#endif
    
    BOOL                  success;
    struct ifaddrs           * addrs;
    const struct ifaddrs     * cursor;
    NSString *addr = nil;
    
    success = getifaddrs(&addrs) == 0;
    if (success) {
        cursor = addrs;
        while (cursor != NULL) {
            if (cursor->ifa_addr->sa_family == AF_INET && (cursor->ifa_flags & IFF_LOOPBACK) == 0) {
                const char *name = cursor->ifa_name;
                if (name && name[0]=='e' && name[1]=='n') {
                    addr = @(inet_ntoa(((struct sockaddr_in *)cursor->ifa_addr)->sin_addr));
                    if (addr)
                        break;
                }
            }
            cursor = cursor->ifa_next;
        }
        freeifaddrs(addrs);
    }
    if (addr)
        return addr;
	
    // Method 2
    char baseHostName[256], hn[256];
    gethostname(baseHostName, 250);
    if (strstr(baseHostName, "."))
        strcpy(hn, baseHostName);
    else 
        sprintf(hn, "%s.local", baseHostName);
    struct hostent *host = gethostbyname(hn);
    if (host) {
        struct in_addr **list = (struct in_addr**)host->h_addr_list;
        int i = 0;
        while (list[i]) {
            struct in_addr ip = *list[i];
            if (ip.s_addr && ntohl(ip.s_addr) != INADDR_LOOPBACK)
                return @(inet_ntoa(ip));
            ++i;
        }
    }
    
    return nil;
}


-(void)updateMessage {
    NSString *httpUrlString = nil, *ftpUrlString = nil, *instructions = nil;
    if (!m_webView)
        return;
    NSString *addr = [self localIPAddress];
    if (m_running) {
        if (m_httpserv && [m_httpserv isRunning]) {
            httpUrlString = [NSString stringWithFormat:@"<center><large><em>Connect via web:</em><br/><b>http://%@:%d</b></large></center>", addr, [m_httpserv port]];
        } else {
            httpUrlString = @"<center><h4><i>HTTP server is not currently enabled.</i><h4></center><br/>";
        }
        if (m_ftpserv && [m_ftpserv isRunning]) {
            ftpUrlString = [NSString stringWithFormat:@"<center><large><em>Or via FTP:</em><br/><b>ftp://ftp@%@:%d</b></large></center>", addr, FTPPORT];
        } else {
            ftpUrlString = @"<center><h4><i>FTP server is not currently enabled.</i><h4></center><br/>";
        }
    	instructions =  [NSString stringWithFormat: @"<p>Just type one of the URLs shown below into the address bar of your "
                         "web browser/file explorer.  The http web address is easier to use and is recommended.</p>"];
                         //	"On a Mac, the Finder only provides read-only support for FTP, so try Cyberduck, or just type<br/>'<b>ftp&nbsp;%@&nbsp;%d</b>' from Terminal. "
                         //"</p> ", addr, FTPPORT];
    } else {
        httpUrlString = @"<br/><center><h4><i>File Server is not currently enabled.</i><h4></center><br/>";
        ftpUrlString = @"";
        if (addr)
            instructions = @"<p>Press the button below to start Frotz's File Server.  "
            "You can then connect to Frotz from other computers on the local network.";
        else {
            instructions = @"<p/><p><b>Sorry, you need to be on a Wi-Fi network to use File Transfer.</b><p/>";
            [m_startButton removeFromSuperview];
        }
    }
    int fontBase = 10 + (gLargeScreenDevice ? 6:0);
    NSString *message =  [NSString stringWithFormat: @
                          "<html><body>\n"
                          "<style type=\"text/css\">\n"
                          "h2 { font-size: %dpt; color:#cfcf00; }\n"
                          "h4 { font-size: %dpt; color:#cfcf00; margin-top: 0px;}\n"
                          "* { color:#ffffff; background: #555555 }\n"
                          "p { font-size:%dpt; }\n"
                          "em { font-sie: %dpt; color:#cfcf00; }\n"
                          "large { font-size:%dpt; color:#00c0c0; }\n"
                          "</style>\n"
                          "<h2>Copying Saved Games &amp; Story Files</h2>\n"
                          "<p>You can transfer saved games and stories from Frotz using a Web Browser or FTP client and load them on a computer using Zoom, WinFrotz, or other Z-machine apps"
                          " which support the standard \'Quetzal\' save game format. (Also see 'Dropbox Settings' for another way to share saved games.)</p><hr>"
                          "%@\n"
                          "<hr>%@\n%@\n"
                          "<br/>\n"
                          "</body>\n",
                          fontBase+3,fontBase+1,fontBase,fontBase,fontBase+3,
                          instructions, httpUrlString, ftpUrlString];
    //    [m_webView	setContentToHTMLString: message];
    [m_webView	loadHTMLString: message baseURL:nil];
}

-(void)startServer {
    NSError *error = nil;
    
    //    NSString *root = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES) objectAtIndex:0];
    
    if (!m_httpserv)
        m_httpserv = [HTTPServer new];
    if (m_httpserv) {
        [m_httpserv setType:@"_http._tcp."];
        [m_httpserv setConnectionClass:[FrotzHTTPConnection class]];
        [m_httpserv setPort: 8000];
        [m_httpserv setDocumentRoot: [m_controller rootPath]]; // [[NSURL fileURLWithPath: [m_controller rootPath]] absoluteString]];
        //[m_httpserv setDelegate: [m_controller storyBrowser]];
    }
    
    if (m_httpserv && [m_httpserv start:&error]) {
        NSLog(@"x %@ ", [self localIPAddress]);
    } else {
	    NSLog(@"Error starting HTTP Server: %@", error);
    }
#if UseNewFTPServer
    if (!m_ftpserv) {
        m_ftpserv = [[FtpServer alloc] initWithPort:FTPPORT withDir:[m_controller rootPath] notifyObject:self];
        m_ftpserv.changeRoot = YES;
    }
    if (m_ftpserv)
        [m_ftpserv startFtpServer];
#else
    if (!m_ftpserv)
        m_ftpserv = [[FTPServer alloc] initWithPort: FTPPORT rootPath: [m_controller rootPath]];
    if (m_ftpserv)
        [m_ftpserv start:&error];
#endif
    if (m_httpserv || m_ftpserv) {
        m_running = YES;
        [m_startButton setTitle: NSLocalizedString(@"Stop File Transfer Server",@"") forState: UIControlStateNormal];
        [m_startButton setTitleColor: [UIColor redColor] forState: UIControlStateNormal];
        [self updateMessage];
        [[UIApplication sharedApplication] setIdleTimerDisabled: YES]; 
    } else {
        [self stopServer];
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Unable to start FTP server"
                                                        message: error ? [error localizedFailureReason] : @"A network error occurred"
                                                       delegate:nil cancelButtonTitle:@"OK" otherButtonTitles: nil];
        [alert show];
    }
}

-(void)stopServer {
    if (m_httpserv)
        [m_httpserv stop];
#if UseNewFTPServer
    if (m_ftpserv)
        [m_ftpserv stopFtpServer];
#else
    if (m_ftpserv)
        [m_ftpserv shutdown];
#endif
    m_running = NO;
    [[UIApplication sharedApplication] setIdleTimerDisabled: NO]; 
    [m_startButton setTitle: NSLocalizedString(@"Start File Transfer Server",@"") forState: UIControlStateNormal];
    [m_startButton setTitleColor: [UIColor greenColor] forState: UIControlStateNormal];
    [self updateMessage];
}

-(void)toggleServer {
    if (m_running)
        [self stopServer];
    else
        [self startServer];
}

- (void)dealloc {
    if (m_httpserv || m_ftpserv)
        [self stopServer];
    m_ftpserv = nil;
    m_httpserv = nil;
    m_startButton = nil;
    
    [FrotzCommonWebViewController releaseSharedWebView];
    m_webView = nil;
}


@end
