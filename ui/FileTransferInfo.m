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
        CGSize cgSize = [m_webView frame].size;
        [m_startButton setFrame:
         CGRectMake(cgSize.width/2 - (gLargeScreenDevice ? 130:130),
                    gLargeScreenDevice ? 520: (cgSize.height > cgSize.width) ? cgSize.height-64 : cgSize.height-48,
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

-(void)viewDidAppear:(BOOL)animated {
    [self updateButtonLocation];
    [m_webView addSubview: m_startButton];
    [self updateMessage];
}

-(void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [m_webView removeFromSuperview];
    [m_webView setFrame: self.view.frame];
    [self.view addSubview: m_webView];
    [self updateButtonLocation];
    [self stopServer];
}

-(void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [m_startButton removeFromSuperview];
}

#define IOS_CELLULAR    @"pdp_ip0"
#define IOS_WIFI        @"en0"
#define IOS_VPN         @"utun0"
#define IP_ADDR_IPv4    @"ipv4"
#define IP_ADDR_IPv6    @"ipv6"

- (NSString *)getIPAddress:(BOOL)preferIPv4 isIPV6:(BOOL*)isIPV6
{
    NSArray *searchArray = preferIPv4 ?
    @[ // IOS_VPN @"/" IP_ADDR_IPv4, IOS_VPN @"/" IP_ADDR_IPv6,
       IOS_WIFI @"/" IP_ADDR_IPv4, IOS_WIFI @"/" IP_ADDR_IPv6,
       // IOS_CELLULAR @"/" IP_ADDR_IPv4, IOS_CELLULAR @"/" IP_ADDR_IPv6
       ] :
    @[ // IOS_VPN @"/" IP_ADDR_IPv6, IOS_VPN @"/" IP_ADDR_IPv4,
       IOS_WIFI @"/" IP_ADDR_IPv6, IOS_WIFI @"/" IP_ADDR_IPv4,
       // IOS_CELLULAR @"/" IP_ADDR_IPv6, IOS_CELLULAR @"/" IP_ADDR_IPv4
       ] ;

    NSDictionary *addresses = [self getIPAddresses];
//    NSLog(@"addresses: %@", addresses);
    if (isIPV6)
        *isIPV6 = NO;
    __block NSString *address;
    [searchArray enumerateObjectsUsingBlock:^(NSString *key, NSUInteger idx, BOOL *stop)
     {
         address = addresses[key];
         if(address) {
             *stop = YES;
             if ([key hasSuffix: IP_ADDR_IPv6]) {
                 if (isIPV6)
                     *isIPV6 = YES;
             }
         }
     } ];
    return address;
}

- (NSDictionary *)getIPAddresses
{
    NSMutableDictionary *addresses = [NSMutableDictionary dictionaryWithCapacity:8];
    
    // retrieve the current interfaces - returns 0 on success
    struct ifaddrs *interfaces;
    if(!getifaddrs(&interfaces)) {
        // Loop through linked list of interfaces
        struct ifaddrs *interface;
        for(interface=interfaces; interface; interface=interface->ifa_next) {
            if(!(interface->ifa_flags & IFF_UP) /* || (interface->ifa_flags & IFF_LOOPBACK) */ ) {
                continue; // deeply nested code harder to read
            }
            const struct sockaddr_in *addr = (const struct sockaddr_in*)interface->ifa_addr;
            char addrBuf[ MAX(INET_ADDRSTRLEN, INET6_ADDRSTRLEN) ];
            if(addr && (addr->sin_family==AF_INET || addr->sin_family==AF_INET6)) {
                NSString *name = [NSString stringWithUTF8String:interface->ifa_name];
                NSString *type;
                if(addr->sin_family == AF_INET) {
                    if(inet_ntop(AF_INET, &addr->sin_addr, addrBuf, INET_ADDRSTRLEN)) {
                        type = IP_ADDR_IPv4;
                        NSString *key = [NSString stringWithFormat:@"%@/%@", name, type];
                        if (strstr(addrBuf, "169.254.") != addrBuf) // ignore self-assigned
                            addresses[key] = [NSString stringWithUTF8String:addrBuf];
                    }
                } else {
                    const struct sockaddr_in6 *addr6 = (const struct sockaddr_in6*)interface->ifa_addr;
                    if(inet_ntop(AF_INET6, &addr6->sin6_addr, addrBuf, INET6_ADDRSTRLEN)) {
                        type = IP_ADDR_IPv6;
                        NSString *key = [NSString stringWithFormat:@"%@/%@", name, type];
                        addresses[key] = [NSString stringWithFormat:@"[%s]", addrBuf];
                    }
                }
            }
        }
        // Free memory
        freeifaddrs(interfaces);
    }
    return [addresses count] ? addresses : nil;
}

-(void)updateMessage {
    NSString *httpUrlString = @"", *ftpUrlString = @"", *instructions = nil;
    BOOL isIPV6 = NO;
    BOOL smallScreen = NO;
    CGSize cgSize = m_webView.frame.size;
    if (!m_webView)
        return;
    char baseHostName[256] = { 0 };
    if (gethostname(baseHostName, sizeof(baseHostName)-1) == 0 && *baseHostName && strstr(baseHostName, ".")==NULL)
        strcat(baseHostName, ".local");
    if (cgSize.width * cgSize.height < 320 * 500)
        smallScreen = YES;
    NSString *addr = [self getIPAddress:YES isIPV6:&isIPV6];
    if (addr && m_running) {
        if (m_httpserv && [m_httpserv isRunning]) {
            NSString *bjname = [m_httpserv name];
            if (bjname && [bjname length] > 0)
                bjname = [NSString stringWithFormat: @" to Bonjour service </em><b>%@</b><em>, or using:", bjname];
            else
                bjname = @":";
            NSString *urlString = *baseHostName ? [NSString stringWithFormat:@"<b>http://%s:%d</b> <em> or </em>", baseHostName, [m_httpserv port]] : @"";
            if ([addr length] > 40 || isIPV6)
                addr = [NSString stringWithFormat: @"<small>%@</small>", addr];
            urlString = [NSString stringWithFormat:@"%@<b>http://%@:%d</b>", urlString, addr, [m_httpserv port]];
            httpUrlString = [NSString stringWithFormat:@"<center><large><em>Connect via web%@</em><br/>%@</large></center>", bjname, urlString];
            instructions =  [NSString stringWithFormat: @"<p>Just type the URL shown below into the address bar of your "
                             "web browser/file explorer, or connect using Bonjour.</p>"];
        } else {
            httpUrlString = @"<center><h4><i>HTTP server is not currently enabled.</i><h4></center><br/>";
        }
        if (m_ftpserv && !isIPV6 && [m_ftpserv isRunning]) {
            ftpUrlString = [NSString stringWithFormat:@"<center><large><em>Or via FTP:</em> <b>ftp://ftp@%@:%d </b></large></center>", addr, FTPPORT];
            if (instructions)
                instructions =  [NSString stringWithFormat: @"<p>Just type one of the URLs shown below into the address bar of your "
                             "web browser/file explorer.  The Bonjour/web address is easier to use and is recommended.</p>"];
        } else if (!isIPV6) {
            ftpUrlString = @"<center><h4><i>FTP server is not currently enabled.</i><h4></center><br/>";
        }
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
    int fontBase = 12 + (smallScreen ? -2:0) + (gLargeScreenDevice ? 6:0);
    NSString *message =  [NSString stringWithFormat: @
                          "<html><body>\n"
                          "<style type=\"text/css\">\n"
                          "h2 { font-size: %dpt; color:#cfcf00; }\n"
                          "h4 { font-size: %dpt; color:#cfcf00; margin-top: 0px;}\n"
                          "* { color:#ffffff; background: #555555 }\n"
                          "p { font-size:%dpt; }\n"
                          "em { font-size: %dpt; color:#cfcf00; }\n"
                          "large { font-size:%dpt; color:#00c0c0; }\n"
                          "small { font-size:%dpt; }\n"
                          "</style>\n"
                          "<h2>Copying Saved Games &amp; Story Files</h2>\n"
                          "<p>You can transfer saved games and stories from Frotz using a Web Browser or FTP client and load them on a computer using Zoom, WinFrotz, or other Z-machine apps"
                          " which support the standard \'Quetzal\' save game format. (Also see 'Dropbox Settings' for another way to share saved games.)</p><hr>"
                          "%@\n"
                          "<hr>%@\n%@\n"
                          "<br/>\n"
                          "</body>\n",
                          fontBase+3,fontBase+1,fontBase,fontBase,fontBase+2, fontBase-2,
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
        [m_httpserv setName: @"Frotz"];
        [m_httpserv setType:@"_http._tcp."];
        [m_httpserv setConnectionClass:[FrotzHTTPConnection class]];
        [m_httpserv setPort: 8000];
        [m_httpserv setDocumentRoot: [m_controller rootPath]]; // [[NSURL fileURLWithPath: [m_controller rootPath]] absoluteString]];
        //[m_httpserv setDelegate: [m_controller storyBrowser]];
    }
    
    if (!m_httpserv || ![m_httpserv start:&error]) {
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
