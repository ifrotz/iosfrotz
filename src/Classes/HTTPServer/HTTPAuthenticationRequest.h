#import <Foundation/Foundation.h>

#if TARGET_OS_IPHONE
// Note: You may need to add the CFNetwork Framework to your project
#import <CFNetwork/CFNetwork.h>
#endif


@interface HTTPAuthenticationRequest : NSObject
{
	BOOL isBasic;
	BOOL isDigest;
	
	NSString *base64Credentials;
	
	NSString *username;
	NSString *realm;
	NSString *nonce;
	NSString *uri;
	NSString *qop;
	NSString *nc;
	NSString *cnonce;
	NSString *response;
}
- (instancetype)initWithRequest:(CFHTTPMessageRef)request NS_DESIGNATED_INITIALIZER;

@property (nonatomic, getter=isBasic, readonly) BOOL basic;
@property (nonatomic, getter=isDigest, readonly) BOOL digest;

// Basic
@property (nonatomic, readonly, copy) NSString *base64Credentials;

// Digest
@property (nonatomic, readonly, copy) NSString *username;
@property (nonatomic, readonly, copy) NSString *realm;
@property (nonatomic, readonly, copy) NSString *nonce;
@property (nonatomic, readonly, copy) NSString *uri;
@property (nonatomic, readonly, copy) NSString *qop;
@property (nonatomic, readonly, copy) NSString *nc;
@property (nonatomic, readonly, copy) NSString *cnonce;
@property (nonatomic, readonly, copy) NSString *response;

@end
