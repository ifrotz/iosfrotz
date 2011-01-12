#import <UIKit/UIKit.h>
#import "FrotzAppDelegate.h"

int iphone_main(int argc, char **argv)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    UIApplicationMain(argc, argv, nil, @"FrotzAppDelegate");

    [pool release];
    fflush(stdout);
    fflush(stderr);

    return 1;
}
