//
//  FileTransferInfo.h
//  Frotz
//
//  Created by Craig Smith on 8/29/08.
//  Copyright 2008 Craig Smith. All rights reserved.
//
#import <UIKit/UIKit.h>

#import "iosfrotz.h"

#if UseNewFTPServer
#import "FtpServer.h"
#else
#import "FTPServ.h"
#endif
#import "../../HTTPServer/HTTPServer.h"
#import "FrotzSettings.h"
#import "FrotzCommonWebView.h"

#define FTPPORT 2121

@interface FileTransferInfo : FrotzCommonWebViewController {
    NSObject<FrotzSettingsStoryDelegate> *m_controller;
    UIWebView *m_webView;
    UIButton *m_startButton;
#if UseNewFTPServer
    FtpServer *m_ftpserv;
#else
    FTPServer *m_ftpserv;
#endif
    HTTPServer *m_httpserv;
    BOOL m_running;
}
-(instancetype)initWithController:(NSObject<FrotzSettingsStoryDelegate>*)controller NS_DESIGNATED_INITIALIZER;
-(void)toggleServer;
-(void)startServer;
-(void)stopServer;
@property (nonatomic, readonly) BOOL serverIsRunning;
@property (nonatomic, readonly, copy) NSString *localIPAddress;
-(void)updateMessage;
@end

BOOL isHiddenFile(NSString *file);
