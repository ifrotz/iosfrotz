/*
 iosFtpServer
 Copyright (C) 2008  Richard Dearlove ( monsta )
 
 This library is free software; you can redistribute it and/or
 modify it under the terms of the GNU Lesser General Public
 License as published by the Free Software Foundation; either
 version 2.1 of the License, or (at your option) any later version.
 
 This library is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 Lesser General Public License for more details.
 
 You should have received a copy of the GNU Lesser General Public
 License along with this library; if not, write to the Free Software
 Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */


// 11/02/08 changes to made to allow stopping of the server.  Also added a bit of code to show users IP address.
// Cleaned up the code to make the retains and releases a bit more obvious... mostly programming style preferences.  
// Added a stop Ftp server method to be called from where ever it was start.  See iphoneLibTestViewController.m to see how I was calling it.
// Most users wouldn't want the server to continue to run once the transfers are done.


#import "FtpServer.h"

@implementation FtpServer

@synthesize listenSocket, connectedSockets, server, notificationObject, portNumber, delegate, commands, baseDir, connections;

@synthesize clientEncoding;
@synthesize changeRoot;

// ----------------------------------------------------------------------------------------------------------
- (id)initWithPort:(unsigned)serverPort withDir:(NSString*)aDirectory notifyObject:(id)sender
// ----------------------------------------------------------------------------------------------------------
{
    if( (self = [super init] )) {
		
		
		self.notificationObject = sender;
		
		// Load up commands
		NSString *plistPath = [[ NSBundle mainBundle ] pathForResource:@"ftp_commands" ofType:@"plist"];
		if ( ! [ [ NSFileManager defaultManager ] fileExistsAtPath:plistPath ] )
			{
				NSLog(@"ftp_commands.plist missing");
			}
		commands = [ [ NSDictionary alloc ] initWithContentsOfFile:plistPath];
				
		
		// Create a socket
        self.portNumber = serverPort ? serverPort:21;
		
		
		// Set directory - have to do this because on iphone, some directories arent what they report back as, so need real path it resolves to, CHECKME - might be an easier way
		NSFileManager	*fileManager  = [ NSFileManager defaultManager ];
		NSString		*expandedPath = [ aDirectory stringByStandardizingPath ];

		// CHANGE TO NEW DIRECTORY & GET SYSTEM FILE PATH ( no .. etc )
		if ([ fileManager changeCurrentDirectoryPath:expandedPath ]) 	// try changing to directory		
		{

			self.baseDir = [[ fileManager currentDirectoryPath ] stringByStandardizingPath];
		}
		else
		{
			self.baseDir =  aDirectory;													// shouldnt get to this line really
		}
		
		self.changeRoot = false;		// true if you want them to be sandboxed/chrooted into the basedir	

		// the default client encoding is UTF8
		self.clientEncoding = NSUTF8StringEncoding;
    }
    return self;
}

-(void)startFtpServer {
    NSError *error = nil;

    // Clear out connections list
    NSMutableArray *myConnections = [[NSMutableArray alloc] init];
    self.connections = myConnections;
    [myConnections release];
    
    AsyncSocket *myListenSocket = [[AsyncSocket alloc] initWithDelegate:self];
    self.listenSocket = myListenSocket;
    [myListenSocket release];
    
    NSLog(@"Listening on %u", portNumber);
    [listenSocket acceptOnPort:self.portNumber error:&error];					// start listening on this port.
    
    NSMutableArray *myConnectedSockets = [[NSMutableArray alloc] initWithCapacity:1];
    self.connectedSockets = myConnectedSockets;
    [myConnectedSockets release];

}
// ----------------------------------------------------------------------------------------------------------
-(void)stopFtpServer
// ----------------------------------------------------------------------------------------------------------
{
	if(listenSocket)
        [listenSocket disconnect];
    if (connectedSockets)
        [connectedSockets removeAllObjects];
	if (connections)
        [connections removeAllObjects];
    self.listenSocket = nil;
    self.connectedSockets = nil;
    self.connections = nil;	
}

- (BOOL)isRunning {
    return (listenSocket != 0);
}

#pragma mark ASYNCSOCKET DELEGATES
// ----------------------------------------------------------------------------------------------------------
- (void)onSocket:(AsyncSocket *)sock didAcceptNewSocket:(AsyncSocket *)newSocket
// ----------------------------------------------------------------------------------------------------------
{
	
	FtpConnection *newConnection = [[[ FtpConnection alloc ] initWithAsyncSocket:newSocket forServer:self] autorelease];			// Create an ftp connection



	
	[ connections addObject:newConnection ];			// Add this to our list of connections
	
	NSLog(@"FS:didAcceptNewSocket  port:%i", [sock localPort]);
	
	if ([sock localPort] == portNumber )
	{
		NSLog(@"Connection on Server Port");
		
	}
	else
	{
		// must be a data comms port
		// spawn a data comms port
		// look for the connection with the same port
		// and attach it
		NSLog(@"--ERROR %i, %i", [sock localPort],portNumber);
		
	}
}

// ----------------------------------------------------------------------------------------------------------
- (void)onSocket:(AsyncSocket *)sock didConnectToHost:(NSString *)host port:(UInt16)port
// ----------------------------------------------------------------------------------------------------------
{
	NSLog(@"FtpServer:didConnectToHost  port:%i", [sock localPort]);
}

#pragma mark NOTIFICATIONS
// ----------------------------------------------------------------------------------------------------------
-(void)didReceiveFileListChanged
// ----------------------------------------------------------------------------------------------------------
{
	if ([notificationObject respondsToSelector:@selector(didReceiveFileListChanged)]) 
		[notificationObject didReceiveFileListChanged ]; 
}
#pragma mark CONNECTIONS
// ----------------------------------------------------------------------------------------------------------
- (void)closeConnection:(id)theConnection
// ----------------------------------------------------------------------------------------------------------
{
	// Search through connections for this one - and delete
	// this should release it - and delloc
	
	[connections removeObject:theConnection ];
	
	
}

// ----------------------------------------------------------------------------------------------------------
-(NSString*)createList:(NSString*)directoryPath shortForm:(BOOL)shortForm
// ----------------------------------------------------------------------------------------------------------
{ 
	return createList(directoryPath, shortForm);
	
	
}

// ----------------------------------------------------------------------------------------------------------
- (void)dealloc
// ----------------------------------------------------------------------------------------------------------
{   
	
	
	if(listenSocket)
	{
		[listenSocket disconnect];
		[listenSocket release];
	}
	
	[connectedSockets release];
	[notificationObject release];
	[connections release];
	[commands release];
	[baseDir release];
	[super dealloc];
	
}


@end
