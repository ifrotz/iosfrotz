//
//  This class was created by Nonnus,
//  who graciously decided to share it with the CocoaHTTPServer community.
//

#import <Foundation/Foundation.h>
#import "HTTPConnection.h"


@interface MyHTTPConnection : HTTPConnection
{
	int dataStartIndex;
	NSMutableArray* multipartData;
	BOOL postHeaderOK;
	NSFileHandle *fileHandle;
	NSString *filename;
	NSString *partSeparator; 
	NSData *leftOverMatch;
}

- (BOOL)isBrowseable:(NSString *)path;
- (NSString *)createBrowseableIndex:(NSString *)path;
- (BOOL)supportsMethod:(NSString *)method atPath:(NSString *)relativePath;
- (void)prepareForBodyWithSize:(UInt64)contentLength;
- (void)doneWithBody;
- (NSObject<HTTPResponse> *)httpResponseForMethod:(NSString *)method URI:(NSString *)path;
- (void)processDataChunk:(NSData *)postDataChunk;
- (void)doneWithBody;
- (void)handlePostMultipartData:(NSData *)data;
@end