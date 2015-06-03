//
//  iphoneLibTestViewController.h
//  iphoneLibTest
//
//  Created by Richard Dearlove on 23/10/2008.
//  Copyright DiddySoft 2008. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "NetworkController.h"

@class FtpServer;

@interface iphoneLibTestViewController : UIViewController {
	FtpServer	*theServer;
	NSString *baseDir;
}

@property (nonatomic, retain) FtpServer *theServer;
@property (nonatomic, copy) NSString *baseDir;

-(void)didReceiveFileListChanged;
- (void)stopFtpServer;

@end

