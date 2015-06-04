
#import <Foundation/Foundation.h>

NSMutableArray *listOfZFilesInZIP(NSString *zipFileStr);
int extractOneFileFromZIP(NSString *zipFileStr, NSString *dirName, NSString *fileName);
int extractAllFilesFromZIP(NSString *zipFileStr, NSString *dirName);

typedef void (*ZipExtractCB)(const char *filename);
int extractAllFilesFromZIPWithCallback(NSString *zipFileStr, NSString *dirName, ZipExtractCB cb);


