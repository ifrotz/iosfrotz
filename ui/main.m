#import <UIKit/UIKit.h>
#import "FrotzAppDelegate.h"
#include <locale.h>

int main(int argc, char **argv)
{
    os_init_setup(); // todo: move this into frotz-terp-specific section but called only once

    @autoreleasepool {

        NSString* resources = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"locale"];
        static char path_locale[1024];
        strcpy(path_locale, [resources fileSystemRepresentation]);
        setenv("PATH_LOCALE", path_locale, 1);
        setlocale(LC_CTYPE, "en_US.UTF-8");

        UIApplicationMain(argc, argv, nil, @"FrotzAppDelegate");
    }
    fflush(stdout);
    fflush(stderr);

    return 1;
}
