#import <UIKit/UIKit.h>
#import "FrotzApplication.h"

int iphone_main(int argc, char **argv)
{
#if 0
    int fd = open("/tmp/frotz.log", O_CREAT|O_WRONLY|O_APPEND);
    dup2(fd, 1);
    dup2(fd, 2);
    close(fd);
#endif

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    UIApplicationMain(argc, argv, [FrotzApplication class]);

    fflush(stdout);
    fflush(stderr);

    return 1;
}
