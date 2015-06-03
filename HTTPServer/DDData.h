#import <Foundation/Foundation.h>

@interface NSData (DDData)

@property (nonatomic, readonly, copy) NSData *md5Digest;

@property (nonatomic, readonly, copy) NSData *sha1Digest;

@property (nonatomic, readonly, copy) NSString *hexStringValue;

@property (nonatomic, readonly, copy) NSString *base64Encoded;
@property (nonatomic, readonly, copy) NSData *base64Decoded;

@end
