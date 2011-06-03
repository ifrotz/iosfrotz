#import <UIKit/UIKit.h>
#import "FrotzAppDelegate.h"
#include <locale.h>

int iphone_main(int argc, char **argv)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    NSString *localeStr = [[NSLocale currentLocale] localeIdentifier];
    setlocale(LC_CTYPE, [localeStr UTF8String]); // for wchar routines use by glk libs

    UIApplicationMain(argc, argv, nil, @"FrotzAppDelegate");

    [pool release];
    fflush(stdout);
    fflush(stderr);

    return 1;
}
