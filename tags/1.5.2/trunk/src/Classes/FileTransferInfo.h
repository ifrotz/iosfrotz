//
//  FileTransferInfo.h
//  Frotz
//
//  Created by Craig Smith on 8/29/08.
//  Copyright 2008 Craig Smith. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "FTPServ.h"
#import "HTTPServer/HTTPServer.h"
#import "FrotzSettings.h"
#import "FrotzCommonWebView.h"

@interface FileTransferInfo : FrotzCommonWebViewController {
    NSObject<FrotzSettingsStoryDelegate> *m_controller;
    UIWebView *m_webView;
    UIButton *m_startButton;
    FTPServer *m_ftpserv;
    HTTPServer *m_httpserv;
    BOOL m_running;
}
-(id)initWithController:(NSObject<FrotzSettingsStoryDelegate>*)controller;
-(void)toggleServer;
-(void)startServer;
-(void)stopServer;
-(BOOL)serverIsRunning;
-(NSString*)localIPAddress;
-(void)updateMessage;
@end

BOOL isHiddenFile(NSString *file);
