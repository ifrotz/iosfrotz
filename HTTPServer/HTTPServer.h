#import <Foundation/Foundation.h>

@class AsyncSocket;


@interface HTTPServer : NSObject <NSNetServiceDelegate>
{
	// Underlying asynchronous TCP/IP socket
	AsyncSocket *asyncSocket;
	
	// Standard delegate
	id delegate;
	
	// HTTP server configuration
	NSURL *documentRoot;
	Class connectionClass;
	
	// NSNetService and related variables
	NSNetService *netService;
	NSString *domain;
	NSString *type;
	NSString *name;
	UInt16 port;
	NSDictionary *txtRecordDictionary;
	
	NSMutableArray *connections;
}

@property (nonatomic, assign) id delegate;

@property (nonatomic, copy) NSURL *documentRoot;

@property (nonatomic, strong) Class connectionClass;

@property (nonatomic, copy) NSString *domain;

@property (nonatomic, copy) NSString *type;

@property (nonatomic, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *publishedName;

@property (nonatomic) UInt16 port;

@property (nonatomic, copy) NSDictionary *TXTRecordDictionary;

- (BOOL)start:(NSError **)error;
@property (nonatomic, readonly, copy) NSArray *addresses;
@property (nonatomic, getter=isRunning, readonly) BOOL running;
@property (nonatomic, readonly) BOOL stop;

@property (nonatomic, readonly) uint numberOfHTTPConnections;

@end
