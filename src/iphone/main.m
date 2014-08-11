#import <UIKit/UIKit.h>
#import "FrotzAppDelegate.h"
#include <locale.h>

int iphone_main(int argc, char **argv)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    NSString* resources = [[[NSBundle mainBundle] resourcePath] stringByAppendingString:@"/locale"];
    static char path_locale[1024];
    strcpy(path_locale, [resources cStringUsingEncoding:NSASCIIStringEncoding]);
    setenv("PATH_LOCALE", path_locale, 1);
    setlocale(LC_CTYPE, "en_US.UTF-8");
    [pool drain];

    UIApplicationMain(argc, argv, nil, @"FrotzAppDelegate");
    [pool release];
    fflush(stdout);
    fflush(stderr);

    return 1;
}
