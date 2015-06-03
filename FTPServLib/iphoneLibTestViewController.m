//
//  iphoneLibTestViewController.m
//  iphoneLibTest
//
//  Created by Richard Dearlove on 23/10/2008.
//  Copyright DiddySoft 2008. All rights reserved.
//

#import "iphoneLibTestViewController.h"
#import "FtpServer.h"


#define FTP_PORT 20000

@implementation iphoneLibTestViewController

@synthesize theServer, baseDir;



/*
// Override initWithNibName:bundle: to load the view using a nib file then perform additional customization that is not appropriate for viewDidLoad.
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) {
        // Custom initialization
    }
    return self;
}
*/

/*
// Implement loadView to create a view hierarchy programmatically.
- (void)loadView {
}
*/
// ----------------------------------------------------------------------------------------------------------
-(void)didReceiveFileListChanged
// ----------------------------------------------------------------------------------------------------------
{
	NSLog(@"didReceiveFileListChanged");
}


// Cleaned up the code for viewDidLoad to keep the memory management a bit tidier.

// ----------------------------------------------------------------------------------------------------------
- (void)viewDidAppear:(BOOL) animated  {
// ----------------------------------------------------------------------------------------------------------

	[super viewDidAppear:animated];
	
///	NSString *localIPAddress = [ NetworkController localIPAddress ];
	NSString *localIPAddress = [ NetworkController localWifiIPAddress ];												// Changed by RD on 12/2/11 because the 4.3 simulator seems to pause a long time on [ NetworkController localIPAddress]
	NSString *alertTitle = [NSString stringWithFormat:@"%@ %@ %@", @"Connect to", localIPAddress, @"port 20000"];	
	
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:alertTitle 
													message:@"The FTP Server has been enabled, please use FTP client software to transfer any import/export data to or from this device.  Press the \"Stop FTP Server\" button once all data transfers have been completed."
												   delegate:self 
										  cancelButtonTitle:@"Stop FTP Server" 
										  otherButtonTitles:nil];
	[alert show];
	[alert release];
	

	

	NSArray *docFolders = NSSearchPathForDirectoriesInDomains (NSDocumentDirectory, NSUserDomainMask, YES ); 
	self.baseDir =  [docFolders lastObject];	

	
	FtpServer *aServer = [[ FtpServer alloc ] initWithPort:20000 withDir:baseDir notifyObject:self ];
	self.theServer = aServer;
	[aServer release];
}

// ----------------------------------------------------------------------------------------------------------
- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)buttonIndex {
// ----------------------------------------------------------------------------------------------------------
	if (buttonIndex == 0) {
		[alert dismissWithClickedButtonIndex:0 animated:YES];
		[self stopFtpServer];
	} 
}




// This is a method that will shut down the server cleanly, it calles the stopFtpServer method of FtpServer class.
// ----------------------------------------------------------------------------------------------------------
- (void)stopFtpServer {
// ----------------------------------------------------------------------------------------------------------
	NSLog(@"Stopping the FTP server");
	if(theServer)
	{
		[theServer stopFtpServer];
		[theServer release];
		theServer=nil;
	}
}

// ----------------------------------------------------------------------------------------------------------
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
// ----------------------------------------------------------------------------------------------------------
    // Return YES for supported orientations
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning]; // Releases the view if it doesn't have a superview
    // Release anything that's not essential, such as cached data
}


- (void)dealloc {
    [super dealloc];
}

@end
