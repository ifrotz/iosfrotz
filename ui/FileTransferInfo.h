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
#import "../HTTPServer/Core/HTTPServer.h"
#import "FrotzSettings.h"
#import "FrotzCommonWebView.h"

#define FTPPORT 2121

NS_ASSUME_NONNULL_BEGIN

@interface FileTransferInfo : FrotzCommonWebViewController {
    NSObject<FrotzSettingsStoryDelegate> *m_controller;
    FrotzWebView *m_webView;
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
-(instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
-(instancetype)initWithCoder:(NSCoder *)aDecoder NS_UNAVAILABLE;
-(void)toggleServer;
-(void)startServer;
-(void)stopServer;
@property (nonatomic, readonly) BOOL serverIsRunning;
@property (nonatomic, readonly, copy, nullable) NSString *localIPAddress;
-(void)updateMessage;
@end

BOOL isHiddenFile(NSString *file);

NS_ASSUME_NONNULL_END
