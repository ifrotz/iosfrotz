//
//  iphoneLibTestAppDelegate.m
//  iphoneLibTest
//
//  Created by Richard Dearlove on 23/10/2008.
//  Copyright DiddySoft 2008. All rights reserved.
//

#import "iphoneLibTestAppDelegate.h"
#import "iphoneLibTestViewController.h"

@implementation iphoneLibTestAppDelegate

@synthesize window;
@synthesize viewController;


- (void)applicationDidFinishLaunching:(UIApplication *)application {    
    
    // Override point for customization after app launch    
    [window addSubview:viewController.view];
	NSLog(@"added subview");
    [window makeKeyAndVisible];
	

}


- (void)dealloc {
    [viewController release];
    [window release];
    [super dealloc];
}


@end
