//
//  iphoneLibTestAppDelegate.h
//  iphoneLibTest
//
//  Created by Richard Dearlove on 23/10/2008.
//  Copyright DiddySoft 2008. All rights reserved.
//

#import <UIKit/UIKit.h>


@class iphoneLibTestViewController;

@interface iphoneLibTestAppDelegate : NSObject <UIApplicationDelegate> {
    UIWindow *window;
    iphoneLibTestViewController *viewController;

}

@property (nonatomic, retain) IBOutlet UIWindow *window;
@property (nonatomic, retain) IBOutlet iphoneLibTestViewController *viewController;

@end

