/*
 
 This program is free software; you can redistribute it and/or
 modify it under the terms of the GNU General Public License
 as published by the Free Software Foundation; version 2
 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License
 along with this program; if not, write to the Free Software
 Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 
 */


#import "StoryBrowser.h"
#import "StoryWebBrowserController.h"
#import "StoryDetailsController.h"
#import "FrotzInfo.h"
#import "ui_utils.h"
#import "extractzfromz.h"
#import "iphone_frotz.h"

NSString *kSplashesDir = @"Splashes";

NSString *kMDFilename = @"metadata.plist";
NSString *kMDFrotzVersionKey = @"frotzVersion";
NSString *kMDFullTitlesKey = @"fullTitles";
NSString *kMDSplashesKey = @"splashes";
NSString *kMDTUIDKey = @"tuid";
NSString *kMDAuthorsKey = @"authors";
NSString *kMDThumbnailsKey = @"thumbnails";
NSString *kMDDescriptsKey = @"descripts";
NSString *kMDHiddenStoriesKey = @"hidden";

NSString *kSIFilename = @"storyinfo.plist";
NSString *kSIRecentStories = @"recentStories";
NSString *kSIStoryNotes = @"storyNotes";

static BOOL abortLaunchCondition = NO;

const long kMinimumRequiredSpaceFirstLaunch = 8; // MB
const long kMinimumRequiredSpace = 2;

@implementation StoryInfo
@synthesize path;

-(id)initWithPath:(NSString*)storyPath {
    if ((self = [super init]) != nil) {
    	self.path = storyPath;
    }
    return self;
}

-(BOOL)isEqual:(id)object {
    return [path isEqualToString: [object path]];
}

-(void)dealloc {
    //    NSLog(@"StoryInfo dealloc %@", path);
    [path release];
    [super dealloc];
}
@end


void removeOldPngSplash(const char *filename) {
    NSString *path = [[[NSString stringWithUTF8String: filename] stringByDeletingPathExtension] stringByAppendingPathExtension: @"png"];
    NSError *error = nil;
    NSFileManager *defaultManager = [NSFileManager defaultManager];
    if ([defaultManager fileExistsAtPath: path])
        [defaultManager removeItemAtPath: path error: &error];
}

@implementation StoryBrowser 

@synthesize popoverController = m_popoverController;
@synthesize popoverBarButton = m_popoverBarButton;

-(NSArray*)recentPaths {
    int count = [m_recents count];
    NSArray *array = [NSArray arrayWithObjects:
                      count > 0 ? [[m_recents objectAtIndex:0] path]: nil,
                      count > 1 ? [[m_recents objectAtIndex:1] path]: nil,
                      count > 2 ? [[m_recents objectAtIndex:2] path]: nil, nil];
    return array;
}

-(void)setRecentPaths:(NSArray*)paths {
    [m_recents removeAllObjects];
    for (NSString *path in paths) {
        [m_recents addObject: [[[StoryInfo alloc] initWithPath:path] autorelease]];
    }
}

-(BOOL)checkMinimumDiskSpace:(long long)minSpace freeSpace:(long long)freeSpace {
    if (freeSpace < minSpace) { // in MB
        UIAlertView *alert = [[UIAlertView alloc]  initWithTitle:
                              [NSString stringWithFormat: @"Frotz cannot launch because the device has only %lld MB of storage free.", freeSpace]
                                                         message: [NSString stringWithFormat:@"Frotz needs at least %lld MB to run so that game autosave and other features work correctly.\n\nFrotz will now terminate.", minSpace]
                                                        delegate:self cancelButtonTitle:@"OK" otherButtonTitles: nil];
        [alert show];
        [alert release];
        abortLaunchCondition = YES;
        return YES;
    }
    return NO;
}

- (id)init {
    
    if ((self = [super initWithStyle:UITableViewStylePlain]) != nil) {
        BOOL needMDDictUpdate = NO;
       	//self.title = NSLocalizedString(@"Frotz", @"");
        
        NSFileManager *defaultManager = [NSFileManager defaultManager];
        
        NSDictionary *fattributes = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:nil];
        NSNumber *fsfree = [fattributes objectForKey:NSFileSystemFreeSize];
        int64_t freeSpace = [fsfree longLongValue]/1024/1024;
        
        if ([self checkMinimumDiskSpace: kMinimumRequiredSpace freeSpace:freeSpace])
            return self;
        
        m_storyMainViewController = [[StoryMainViewController alloc] init];
        [m_storyMainViewController setStoryBrowser: self];
        m_webBrowserController = [[StoryWebBrowserController alloc] initWithBrowser: self];
        m_details = [[StoryDetailsController alloc] initWithNibName:gLargeScreenDevice ? @"StoryDetailsController-ipad":@"StoryDetailsController"
                                                             bundle:nil];
        [m_details setStoryBrowser:self];
        
        m_settings = [[FrotzSettingsController alloc] init];
        [m_settings setStoryDelegate: m_storyMainViewController];
        
        if (gUseSplitVC) {
            UINavigationController *nc = [m_details navigationController];
            if (!nc) {
                nc = [[UINavigationController alloc] initWithRootViewController: m_details];
                [nc.navigationBar setBarStyle: UIBarStyleBlackOpaque];
            }
        }
        
        m_storyNames = [[[NSMutableArray alloc] init] retain];
        m_unsupportedNames = [[[NSMutableArray alloc] init] retain];
        m_paths = [[[NSMutableArray alloc] init] retain];
        
        [self addPath: [m_storyMainViewController resourceGamePath]];
        [self addPath: [m_storyMainViewController storyGamePath]];
        
        m_defaultThumb = [[UIImage imageNamed: @"compass-small.png"] retain];
        
        
#ifdef NO_SANDBOX
        // This won't actually succeed anymore in post 2.0 because of sandboxing
        // I don't think jailbroken apps have to obey the sandbox, so if anyone compiles
        // from source for JB devices, add this #define to iphone_frotz.h
        NSString *topAppDir = [[[[NSBundle mainBundle] resourcePath] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
        
        NSArray *apps = [defaultManager directoryContentsAtPath: topAppDir];
        NSString *appDir;
        for (appDir in apps) {
            BOOL isDir = NO;
            NSString *magnetDir = [[[topAppDir stringByAppendingPathComponent: appDir]
                                    stringByAppendingPathComponent: @"Documents"] stringByAppendingPathComponent: @"FileMagnetStore"];
            if ([defaultManager fileExistsAtPath: magnetDir isDirectory:&isDir] && isDir)
                [self addPath: magnetDir];
            NSString *airSharingDir = [[[topAppDir stringByAppendingPathComponent: appDir]
                                        stringByAppendingPathComponent: @"Documents"] stringByAppendingPathComponent: @"Air Sharing"];
            if ([defaultManager fileExistsAtPath: airSharingDir isDirectory:&isDir] && isDir)
                [self addPath: airSharingDir];
            if ([defaultManager fileExistsAtPath: [[topAppDir stringByAppendingPathComponent: appDir] stringByAppendingPathComponent: @"MobileFinder.app"]]) {
                NSString *mfDir = [[topAppDir stringByAppendingPathComponent: appDir]  stringByAppendingPathComponent: @"Documents"];
                if ([defaultManager fileExistsAtPath: mfDir isDirectory:&isDir] && isDir)
                    [self addPath: mfDir];
            }
        }
#endif
        
        // create a custom navigation bar button and set it to always say "Back"
        UIBarButtonItem *temporaryBarButtonItem = [[UIBarButtonItem alloc] init];
        temporaryBarButtonItem.title = @"Story List";
        self.navigationItem.backBarButtonItem = temporaryBarButtonItem;
        [temporaryBarButtonItem release];
        
        UIBarButtonItem *browserButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Browse IFDB" style:UIBarButtonItemStylePlain target:self action:@selector(launchBrowser)];
        self.navigationItem.leftBarButtonItem = browserButtonItem;
        [browserButtonItem release];
        
        m_nowPlayingButtonView = [UIButton buttonWithType: UIButtonTypeCustom];
        UIImage *img = [UIImage imageNamed: @"nowplaying.png"];
        [m_nowPlayingButtonView setImage: img forState: UIControlStateNormal];
        [m_nowPlayingButtonView setFrame: CGRectMake(0,0,[img size].width, [img size].height)];
        [m_nowPlayingButtonView addTarget:self action:@selector(resumeStory) forControlEvents: UIControlEventTouchDown];
        m_nowPlayingButtonItem = [[UIBarButtonItem alloc] initWithCustomView: m_nowPlayingButtonView];
        [m_nowPlayingButtonItem setCustomView: m_nowPlayingButtonView];
        if ([m_nowPlayingButtonView respondsToSelector: @selector(setAccessibilityLabel:)])
            [m_nowPlayingButtonView setAccessibilityLabel: NSLocalizedString(@"Now playing",nil)];
        
        m_editButtonItem = [self editButtonItem];
        [m_editButtonItem setStyle: UIBarButtonItemStylePlain];
        
        NSArray *array = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, true);
        NSString *docPath = [array objectAtIndex: 0];
        NSString *metadataPath = [docPath stringByAppendingPathComponent: kMDFilename];
        NSString *siPath = [docPath stringByAppendingPathComponent: kSIFilename];
        NSString *splashPath = [docPath stringByAppendingPathComponent:	kSplashesDir];
        NSError *error;
        
        NSString *dfltMDPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: kMDFilename];
        if (![defaultManager fileExistsAtPath: metadataPath])
        {
            [defaultManager removeItemAtPath: metadataPath error: &error];
            [defaultManager copyItemAtPath:dfltMDPath toPath:metadataPath error:&error];
        }
        m_metaDict = [[NSMutableDictionary dictionaryWithContentsOfFile: metadataPath] retain];
        
        NSString *vers = m_metaDict ? [m_metaDict objectForKey: kMDFrotzVersionKey] : nil;
        
        if (!m_metaDict) {
            m_metaDict = [[NSMutableDictionary alloc] initWithCapacity: 4];
            NSMutableDictionary *titleDict = [[NSMutableDictionary alloc] initWithCapacity: 32];
            NSMutableDictionary *thumbDict = [[NSMutableDictionary alloc] initWithCapacity: 32];
            [m_metaDict setObject: @IPHONE_FROTZ_VERS forKey: kMDFrotzVersionKey];
            [m_metaDict setObject: titleDict forKey: kMDFullTitlesKey];
            [m_metaDict setObject: thumbDict forKey: kMDThumbnailsKey];
            [titleDict release];
            [thumbDict release];
            needMDDictUpdate = YES;
        }
        
        m_recents = [[NSMutableArray alloc] initWithCapacity:4];
        m_storyInfoDict = [[NSMutableDictionary dictionaryWithContentsOfFile: siPath] retain];
        if (!m_storyInfoDict)
            m_storyInfoDict = [[NSMutableDictionary alloc] initWithCapacity: 2];
        if (m_storyInfoDict)
            [self setRecentPaths: [m_storyInfoDict objectForKey: kSIRecentStories]];
        
        // the icons for these games weren't in the 1.0 release; add them to user's metadata dict
        NSArray *newItems = [NSArray arrayWithObjects: @"cutthroats", @"deadline", @"lurking", @"moonmist", @"plundered",
                             @"seastalker", @"sherlock", @"suspect", @"suspended", @"wishbringer", @"witness", @"photopia",
                             // updates in 1.5:
                             @"905", @"beyondzork", @"hitchhiker", @"dreamhold", @"heroes", @"minster", @"misdirection", @"tangle",
                             @"vespers", @"weather", @"zdungeon", nil];
        NSMutableDictionary *titleDict = [m_metaDict objectForKey: kMDFullTitlesKey];
        NSMutableDictionary *thumbDict = [m_metaDict objectForKey: kMDThumbnailsKey];
        NSMutableDictionary *oldSplashDict = [m_metaDict objectForKey: kMDSplashesKey];
        
        if (oldSplashDict) {
            if ([self checkMinimumDiskSpace: kMinimumRequiredSpaceFirstLaunch freeSpace:freeSpace])
                return self;
            
            NSEnumerator *splashEnum = [oldSplashDict keyEnumerator];
            id key;	     
            while ((key = [splashEnum nextObject])) {
                NSString *gameSplashPath = [splashPath stringByAppendingPathComponent:[key stringByAppendingPathExtension: @"png"]];
                NSData *imgData = [oldSplashDict objectForKey: key];
                [imgData writeToFile:gameSplashPath options:0 error:&error];
            }
            [m_metaDict removeObjectForKey: kMDSplashesKey];
            needMDDictUpdate = YES;
        }
        
        BOOL extractSplashes = NO;
        if (![defaultManager fileExistsAtPath: splashPath])
        {
            [defaultManager createDirectoryAtPath:kSplashesDir withIntermediateDirectories:NO attributes:nil error:&error];
            extractSplashes = YES;
        } else if (!vers || [vers compare: @"1.5"]==NSOrderedAscending)
            extractSplashes = YES;
        if (extractSplashes) {
            if ([self checkMinimumDiskSpace: kMinimumRequiredSpaceFirstLaunch freeSpace:freeSpace])
                return self;
            extractAllFilesFromZIPWithCallback([[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: @"splashes.zip"], splashPath, removeOldPngSplash);
        }
        
        NSMutableDictionary *dfltMetaData = nil;
        if (!vers || [vers compare: @"1.5"]==NSOrderedAscending) {
            
            if (titleDict && thumbDict) {
                NSString *item;
                for (item in newItems) {
                    if ([item isEqualToString: @"photopia"] || ![thumbDict objectForKey: item] || ![titleDict objectForKey: item]) {
                        needMDDictUpdate = YES;
                        if (!dfltMetaData)
                            dfltMetaData = [[NSDictionary alloc] initWithContentsOfFile: dfltMDPath];
                        if (dfltMetaData) {
                            NSObject *obj;
                            obj = [[dfltMetaData objectForKey: kMDFullTitlesKey] objectForKey: item];
                            if (obj)
                                [titleDict setObject: obj forKey: item];
                            obj = [[dfltMetaData objectForKey: kMDThumbnailsKey] objectForKey: item];
                            if (obj)
                                [thumbDict setObject: obj forKey: item];
                        }
                    }
                }
            }

            if (titleDict) {
                // fix misspelling in previous built-in metadata
                NSString *hhFix = @"Hitchhiker's Guide to the Galaxy";
                [titleDict setObject:hhFix forKey:@"hhgttg"];
                [titleDict setObject:hhFix forKey:@"hitchhiker"];
                [titleDict setObject:@"The Dreamhold" forKey:@"dreamhold"];
                [titleDict setObject:@"Bureaucracy" forKey:@"bureaucracy"];
                needMDDictUpdate = YES;
            }

            NSMutableDictionary *tuidDict = [m_metaDict objectForKey: kMDTUIDKey];
            NSMutableDictionary *authorDict = [m_metaDict objectForKey: kMDAuthorsKey];
            NSMutableDictionary *descriptDict = [m_metaDict objectForKey: kMDDescriptsKey];
            if (!dfltMetaData && (!tuidDict || !authorDict || !descriptDict))
                dfltMetaData = [[NSDictionary alloc] initWithContentsOfFile: dfltMDPath];
            if (!tuidDict)
                tuidDict = [[[NSMutableDictionary alloc] initWithDictionary: [dfltMetaData objectForKey: kMDTUIDKey] copyItems:YES] autorelease];
            if (!authorDict)
                authorDict = [[[NSMutableDictionary alloc] initWithDictionary: [dfltMetaData objectForKey: kMDAuthorsKey] copyItems:YES] autorelease];
            if (!descriptDict)
                descriptDict = [[[NSMutableDictionary alloc] initWithDictionary: [dfltMetaData objectForKey: kMDDescriptsKey] copyItems:YES] autorelease];
            
            NSString *bundledGamesListPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: @kBundledFileList];
            if (bundledGamesListPath && [defaultManager fileExistsAtPath: bundledGamesListPath]) {
                NSString *bundledList = [NSString stringWithContentsOfFile: bundledGamesListPath];
                NSInteger len = [bundledList length];
                NSRange r = NSMakeRange(0, len), r2;
                while ((r2 = [bundledList rangeOfString: @"\n" options:0 range:r]).length > 0) {
                    NSRange r3 = [bundledList rangeOfString: @"\t" options:0 range: NSMakeRange(r.location, r2.location-r.location)];
                    if (r3.length != 0) {
                        NSString *tuid = [bundledList substringWithRange: NSMakeRange(r.location, r3.location-r.location)];
                        r3 = [bundledList rangeOfString: @"\t" options:0 range:NSMakeRange(r3.location+1, r2.location-(r3.location+1))];
                        if (r3.length != 0) {
                            NSRange r4 = [bundledList rangeOfString: @"\t\t" options:0 range: NSMakeRange(r.location, r2.location-r.location)];
                            NSString *storyKey = [bundledList  substringWithRange: NSMakeRange(r3.location+1, r4.location-(r3.location+1))];
                            NSString *authors = r4.length ? [bundledList substringWithRange: NSMakeRange(r4.location+2, r2.location-(r4.location+2))]:@"";
                            if (storyKey) {
                                storyKey = [[[storyKey lastPathComponent] stringByDeletingPathExtension] lowercaseString];
                                if (tuid && authors) {
                                    [tuidDict setObject:tuid forKey:storyKey];
                                    [authorDict setObject: authors forKey:storyKey];
                                }
                            }
                            //NSLog(@"story=%@, tuid=%@, authors=%@", storyKey, tuid, authors);				
                        }
                    }
                    r.location = r2.location + 1;
                    r.length = len - r.location;
                }
            }
            [m_metaDict setObject: tuidDict forKey: kMDTUIDKey];
            [m_metaDict setObject: authorDict forKey:kMDAuthorsKey];
            [m_metaDict setObject: descriptDict forKey:kMDDescriptsKey];
            needMDDictUpdate = YES;
        }
        if (!vers || ![vers isEqualToString: @IPHONE_FROTZ_VERS]) {
            [m_metaDict setObject: @IPHONE_FROTZ_VERS forKey: kMDFrotzVersionKey];
            needMDDictUpdate = YES;
        }
        if (needMDDictUpdate) {
            [self saveMetaData];
            if (dfltMetaData)
                [dfltMetaData release];
        }
        [self refresh];
    }
    return self;
}

- (void)setLaunchPath:(NSString*)path {
    NSFileManager *defaultManager = [NSFileManager defaultManager];
    UIAlertView *alert = nil;
    if (m_launchPath) {
        [m_launchPath release];
        m_launchPath = nil;
    }
    if ([defaultManager fileExistsAtPath: path]) {
        NSError *error = nil;
        NSString *destPath = [m_storyMainViewController storyGamePath];
        destPath = [destPath stringByAppendingPathComponent:[path lastPathComponent]];
        [defaultManager removeItemAtPath:destPath error:&error];
        if ([defaultManager copyItemAtPath:path toPath:destPath error:&error]) {
            [defaultManager removeItemAtPath:path error:&error]; // remove Inbox copy so future invocations won't auto-number
            m_launchPath = [destPath retain];
        } else {
            NSLog(@"Frotz couldn't read launch URL path: %@", path);
            alert = [[UIAlertView alloc]  initWithTitle:@"Frotz cannot read external URL"
                                                message: [NSString stringWithFormat:@"Error %@: %@ : %@", error, path, destPath]
                                               delegate:self cancelButtonTitle:@"OK" otherButtonTitles: nil];
        }
    } else {
        NSLog(@"Frotz launch URL path %@ doesn't exist", path);
        alert = [[UIAlertView alloc]  initWithTitle:@"Frotz cannot find external URL"
                                            message: [NSString stringWithFormat:@".../%@", [path lastPathComponent]]
                                           delegate:self cancelButtonTitle:@"OK" otherButtonTitles: nil];
    }
    if (alert) {
        [alert show];
        [alert release];
    }
}

- (NSString*)launchPath {
    return m_launchPath;
}

-(UIView*)navTitleView {
    return m_navTitleView;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return gLargeScreenDevice ? YES : interfaceOrientation == UIInterfaceOrientationPortrait;
}

-(void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    if (gUseSplitVC && self.popoverBarButton)
        m_details.navigationItem.leftBarButtonItem = nil;
}

-(void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    if (gUseSplitVC && self.popoverBarButton &&  UIDeviceOrientationIsPortrait(toInterfaceOrientation))
        m_details.navigationItem.leftBarButtonItem = self.popoverBarButton;
}

- (BOOL)canEditStoryInfo {
    return [m_storyMainViewController canEditStoryInfo];
}

- (NSString*)fullTitleForStory:(NSString*)story {
    NSMutableDictionary *titleDict = [m_metaDict objectForKey: kMDFullTitlesKey];
    story = [story lowercaseString];
    NSString *title = [titleDict objectForKey: story];
    if (!title) {
        story = [story stringByDeletingPathExtension];
        title = [titleDict objectForKey: story];
    }
    if (!title) {
        story = [self mapInfocom83Filename: story];
        title = [titleDict objectForKey: story];
    }
    if (!title) {
        title = story;
        if ([title length] > 0) {
            if (islower([title characterAtIndex: 0]))
                title = [title capitalizedString];
            title = [title stringByReplacingOccurrencesOfString:@"_" withString:@" "];
            title = [title stringByReplacingPercentEscapesUsingEncoding: NSUTF8StringEncoding];
        }
    }
    return title;
}

- (NSString*)tuidForStory:(NSString*)story {
    NSMutableDictionary *tuidDict = [m_metaDict objectForKey: kMDTUIDKey];
    story = [story lowercaseString];
    NSString *tuid = [tuidDict objectForKey: story];
    if (!tuid) {
        story = [self mapInfocom83Filename: story];
        tuid = [tuidDict objectForKey: story];
    }
    return tuid;
}

- (NSString*)authorsForStory:(NSString*)story {
    NSMutableDictionary *authorDict = [m_metaDict objectForKey: kMDAuthorsKey];
    story = [story lowercaseString];
    NSString *authors = [authorDict objectForKey: story];
    if (!authors) {
        story = [self mapInfocom83Filename: story];
        authors = [authorDict objectForKey: story];
    }
    return authors;
}

- (NSString*)descriptForStory:(NSString*)story {
    NSMutableDictionary *descriptDict = [m_metaDict objectForKey: kMDDescriptsKey];
    story = [story lowercaseString];
    NSString *descript = [descriptDict objectForKey: story];
    if (!descript) {
        story = [self mapInfocom83Filename: story];
        descript = [descriptDict objectForKey: story];
    }
    return descript;
}

static int articlePrefix(NSString *str) {
    int len  = 0;
    if ([str hasPrefix: @"A "])
        len = 2;
    else if ([str hasPrefix: @"An "])
        len = 3;
    else if ([str hasPrefix: @"The "])
        len = 4;
    return len;
}

static NSInteger sortPathsByFilename(id a, id b, void *context) {
    StoryBrowser *sb = (StoryBrowser*)context;
    int art1 = 0, art2 = 0;
    NSString *str1 = [sb fullTitleForStory: [[[a path] lastPathComponent] stringByDeletingPathExtension]];
    NSString *str2 = [sb fullTitleForStory: [[[b path] lastPathComponent] stringByDeletingPathExtension]];
    art1 = articlePrefix(str1);
    art2 = articlePrefix(str2);
    if (art1)
        str1 = [str1 stringByReplacingCharactersInRange: NSMakeRange(0, art1) withString: @""];
    if (art2)
        str2 = [str2 stringByReplacingCharactersInRange: NSMakeRange(0, art2) withString: @""];
    return [str1 caseInsensitiveCompare: str2];
}

- (NSMutableArray*)storyNames {
    if (!m_numStories)
        [self refresh];
    return m_storyNames;
}

-(BOOL)storyIsInstalled:(NSString*)story {
    for (StoryInfo *si in m_storyNames)
        if ([[[si path] lastPathComponent] caseInsensitiveCompare: story] == NSOrderedSame)
            return YES;
    return NO;
}

- (NSString*)canonicalStoryName:(NSString*)story {
    story = [self mapInfocom83Filename: story];
    for (StoryInfo *si in m_storyNames)
        if ([[[[si path] lastPathComponent] stringByDeletingPathExtension] isEqualToString: story])
            return story;
    return nil;
}

- (NSMutableArray*)unsupportedStoryNames {
    return m_unsupportedNames;
}

-(void)refresh {
    
    NSString *path;
    
    m_numStories = 0;
    [m_storyNames removeAllObjects];
    [m_unsupportedNames removeAllObjects];
    
    if (abortLaunchCondition)
        return;
    int idx = 0;
    NSFileManager *defaultManager = [NSFileManager defaultManager];
    for (path in m_paths) {
        NSDirectoryEnumerator *enumerator  = [defaultManager enumeratorAtPath:  path];
        id curFile;
        while ((curFile = [enumerator nextObject])) {
            NSString *story = curFile;	    
            NSString *ext = [story pathExtension];
            if ([ext length] > 1) {
                char c = [[story pathExtension] characterAtIndex: 0];
                char c2 = [[story pathExtension] characterAtIndex: 1];
                if ((c=='z' || c=='Z') 
                    && (c2=='3' || c2=='4' || c2=='5' || c2=='8')
                    || [[ext lowercaseString] isEqualToString: @"zblorb"]
                    || [[ext lowercaseString] isEqualToString: @"zlb"]
                    || [[ext lowercaseString] isEqualToString: @"dat"]
                    
                    || [[ext lowercaseString] isEqualToString: @"blb"]
                    || [[ext lowercaseString] isEqualToString: @"gblorb"]
                    || [[ext lowercaseString] isEqualToString: @"ulx"]
                    ) {
                    if (idx==0) {
                        NSString *opath;
                        int j = 0;
                        if ([self isHidden: [story stringByDeletingPathExtension]])
                            continue;
                        for (opath in m_paths) {
                            if (j == 0) {
                                ++j;
                                continue;
                            }
                            if ([defaultManager fileExistsAtPath: [opath stringByAppendingPathComponent: curFile]])
                                break;
                            ++j;
                        }
                        if (j < [m_paths count])
                            continue;
                    }
                    StoryInfo *storyInfo = [[[StoryInfo alloc] initWithPath: [path stringByAppendingPathComponent: story]] autorelease];
                    [m_storyNames addObject: storyInfo];
                    m_numStories++;
                } else {
                    [m_unsupportedNames addObject: [path stringByAppendingPathComponent: story]];
                }
            }
        }
        ++idx;
    }
    [m_storyNames sortUsingFunction: sortPathsByFilename context: self];
}

-(void)reloadData {
    [self refresh];
    [[self tableView] reloadData];
}

-(void)launchBrowserWithURL:(NSString*)url
{
    [m_webBrowserController enterURL: url];
    [self launchBrowser];
}

-(void)launchBrowser {
    [[self navigationController] popToViewController:self animated:NO];
    
    if (gUseSplitVC && self.splitViewController) {
        if (m_popoverController)
            [m_popoverController dismissPopoverAnimated:YES];
        
        UINavigationController *nc = [m_webBrowserController navigationController];
        if (!nc) {
            nc = [[UINavigationController alloc] initWithRootViewController: m_webBrowserController];
            [nc.navigationBar setBarStyle: UIBarStyleBlackOpaque];   
        }
        if (nc) {
            if (!nc.topViewController.navigationItem.leftBarButtonItem) {
                UIBarButtonItem* backItem = [[UIBarButtonItem alloc] initWithTitle:@"Story List" style:UIBarButtonItemStyleBordered target:self action:@selector(didPressModalStoryListButton)];
                nc.topViewController.navigationItem.leftBarButtonItem = backItem;
                [backItem release];
            }
            [self.splitViewController presentModalViewController:nc animated:YES];
            return;
        }	
    }
    
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:0.8];
    [UIView setAnimationTransition: UIViewAnimationTransitionCurlUp forView:[[[self view] superview] superview] cache:NO];
    
    [self.navigationController pushViewController: m_webBrowserController animated: NO];
    
    [UIView commitAnimations];
}

- (void)saveRecents {
    [m_storyInfoDict setObject: [self recentPaths] forKey: kSIRecentStories];
    [self saveStoryInfoDict];
}

- (NSString*)getNotesForStory:(NSString*)story {
    NSMutableDictionary *notesDict = [m_storyInfoDict objectForKey: kSIStoryNotes];
    if (notesDict)
        return [notesDict objectForKey: story];
    return nil;
}

- (void)saveNotes:(NSString*)notesText forStory:(NSString*)story {
    NSMutableDictionary *notesDict = [m_storyInfoDict objectForKey: kSIStoryNotes];
    if (!notesDict) {
        notesDict = [[[NSMutableDictionary alloc] initWithCapacity: 4] autorelease];
        [m_storyInfoDict setObject:notesDict forKey:kSIStoryNotes];
    }
    if (notesText && [notesText length] > 0 || [notesDict objectForKey:story]) {
        [notesDict setObject:notesText forKey:story];
        [self saveStoryInfoDict];
    }
}


- (void)saveStoryInfoDict {
    NSArray *array = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, true);
    NSString *docPath = [array objectAtIndex: 0];
    NSString *siPath = [docPath stringByAppendingPathComponent: kSIFilename];
    NSString *error;
    
    NSData *plistData = [NSPropertyListSerialization dataFromPropertyList:m_storyInfoDict
                                                                   format:NSPropertyListBinaryFormat_v1_0
                                                         errorDescription:&error];
    if(plistData)
        [plistData writeToFile:siPath atomically:YES];
    else
    {
        NSLog(@"savesi: err %@", error);
        [error release];
    }
}

- (void)saveMetaData {
    if (!m_metaDict) // || m_lowMemory)
        return;
    NSArray *array = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, true);
    NSString *docPath = [array objectAtIndex: 0];
    NSString *metadataPath = [docPath stringByAppendingPathComponent: kMDFilename];
    NSData *plistData;
    NSString *error;
    
    plistData = [NSPropertyListSerialization dataFromPropertyList:m_metaDict
                                                           format:NSPropertyListBinaryFormat_v1_0
                                                 errorDescription:&error];
    if(plistData)
        [plistData writeToFile:metadataPath atomically:YES];
    else
    {
        NSLog(@"savemeta: err %@", error);
        [error release];
    }
}

- (void)addTitle: (NSString*)fullName forStory:(NSString*)story {
    NSMutableDictionary *titleDict = [m_metaDict objectForKey: kMDFullTitlesKey];
    [titleDict setObject: fullName forKey: [story lowercaseString]];
}

- (void)addAuthors: (NSString*)authors forStory:(NSString*)story {
    NSMutableDictionary *authorDict = [m_metaDict objectForKey: kMDAuthorsKey];
    [authorDict setObject: authors forKey: [story lowercaseString]];
}

- (void)addTUID: (NSString*)tuid forStory:(NSString*)story {
    NSMutableDictionary *tuidDict = [m_metaDict objectForKey: kMDTUIDKey];
    [tuidDict setObject: tuid forKey: [story lowercaseString]];
}

- (void)addDescript: (NSString*)descript forStory:(NSString*)story {
    NSMutableDictionary *descriptDict = [m_metaDict objectForKey: kMDDescriptsKey];
    [descriptDict setObject: descript forKey: [story lowercaseString]];
}

- (void)hideStory: (NSString*)story withState:(BOOL)hide {
    NSMutableDictionary *hiddenDict = [m_metaDict objectForKey: kMDHiddenStoriesKey];
    if (!hiddenDict) {
        if (!hide)
            return;
        hiddenDict = [[[NSMutableDictionary alloc] initWithCapacity: 10] autorelease];
        [m_metaDict setObject: hiddenDict forKey: kMDHiddenStoriesKey];
    }
    if (hide)
        [hiddenDict setValue:[NSNumber numberWithBool: YES] forKey: [story lowercaseString]];
    else
        [hiddenDict removeObjectForKey: [story lowercaseString]];
}

- (void)unHideAll {
    [m_metaDict removeObjectForKey: kMDHiddenStoriesKey];
    [self saveMetaData];
}

- (BOOL)isHidden: (NSString*)story {
    NSMutableDictionary *hiddenDict = [m_metaDict objectForKey: kMDHiddenStoriesKey];
    if (!hiddenDict)
        return NO;
    id obj = [hiddenDict objectForKey: [story lowercaseString]];
    if (obj && [obj boolValue])
        return YES;
    return NO;
}

-(void)addThumbData: (NSData*)imageData forStory:(NSString*)story {
    if (!m_metaDict)
        return;
    NSMutableDictionary *thumbDict = [m_metaDict objectForKey: kMDThumbnailsKey];
    [thumbDict setObject: imageData forKey: [story lowercaseString]];
}

- (NSString*)mapInfocom83Filename:(NSString*)story {
    static NSDictionary *map = nil;
    if (!map)
        map = [[NSDictionary dictionaryWithObjectsAndKeys: // map alternate/shortened filenames and common misspellings
                @"beyondzork", @"beyondzo", @"borderzone", @"borderzo", @"bureaucracy", @"bureaucr", @"bureaucracy", @"bureau", @"cutthroats", @"cutthroa", @"enchanter", @"enchante",
                @"hitchhiker", @"hitchhik", @"hitchhiker", @"hgg", @"hitchhiker", @"hhgg", @"hitchhiker", @"h2g2", @"hitchhiker", @"hhgttg",
                @"hollywood", @"hollywoo", @"leather", @"phobos", @"nordandbert", @"nordandb", @"planetfall", @"planetfa", @"plundered", @"plundere",
                @"seastalker", @"seastalk", @"sorcerer", @"sorceror", @"spellbreaker", @"spellbr",@"spellbreaker", @"spellbre", @"starcross", @"starcros",
                @"stationfall", @"stationf", @"suspended", @"suspend", @"suspended", @"suspende", @"wishbringer", @"wishbrin",
                nil] retain];
    NSString *longStory;
    longStory = [map objectForKey: story];
    if (longStory)
        return longStory;
    NSRange r = [story rangeOfString: @"-"];
    if (r.length > 0 && r.location > 4 && r.location < [story length]-1 && isdigit([story characterAtIndex: r.location+1])) {
        story = [story substringToIndex: r.location];
        longStory = [map objectForKey: story];
        if (!longStory)
            longStory = story;
        NSMutableDictionary *titleDict = [m_metaDict objectForKey: kMDFullTitlesKey];
        NSString *title = [titleDict objectForKey: longStory];
        if (title)
            return longStory;
    }
    return story;
}

-(NSString*)splashPathForStory:(NSString*)story {
    NSArray *array = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, true);
    NSString *docPath = [array objectAtIndex: 0];
    NSString *splashPath = [docPath stringByAppendingPathComponent: kSplashesDir];
    NSString *basefile = [self mapInfocom83Filename: [story lowercaseString]];    
    NSString *gameSplashPath = [splashPath stringByAppendingPathComponent:basefile];
    NSString *gameSplashPathPNG = [gameSplashPath stringByAppendingPathExtension: @"png"];
    NSFileManager *fileMgr = [NSFileManager defaultManager];
    if ([fileMgr fileExistsAtPath: gameSplashPathPNG])
        return gameSplashPathPNG;
    NSString *gameSplashPathJPG = [gameSplashPath stringByAppendingPathExtension: @"jpg"];
    return gameSplashPathJPG;
}

-(void)addSplashData: (NSData*)imageData forStory:(NSString*)story {
    NSString *gameSplashPath = [self splashPathForStory: story];
    NSError *error = NULL;
    [imageData writeToFile:gameSplashPath options:0 error:&error];
}

-(void)removeSplashDataForStory: (NSString*)story {
    static NSArray *infocomArr;
    if (!infocomArr)
        infocomArr = [[NSArray arrayWithObjects:
                       @"amfv", @"arthur", @"ballyhoo", @"beyondzork", @"borderzone", @"cutthroats", @"deadline", @"enchanter", @"hitchhiker",
                       @"hollywood", @"leather", @"lurking", @"moonmist", @"nordandbert", @"planetfall", @"plundered", @"seastalker",
                       @"sherlock", @"sorceror", @"starcross", @"suspect", @"suspended", @"wishbringer", @"witness",
                       @"zork1", @"zork2", @"zork3", @"zorkzero", nil] retain];
    
    if ([infocomArr indexOfObject: [self mapInfocom83Filename:story]] != NSNotFound)
        return;
    NSString *gameSplashPath = [self splashPathForStory: story];
    NSError *error = NULL;
    NSFileManager *fileMgr = [NSFileManager defaultManager];
    [fileMgr removeItemAtPath: gameSplashPath error: &error];
}

- (NSData*)splashDataForStory: (NSString*)story {
#if 0
    NSMutableDictionary *splashDict = [m_metaDict objectForKey: kMDSplashesKey];
    NSString *key = [self mapInfocom83Filename: [story lowercaseString]];    
    return [splashDict objectForKey: key];
#endif
    NSString *gameSplashPath = [self splashPathForStory: story];
    NSData *imgData = [NSData dataWithContentsOfFile: gameSplashPath];
    return imgData;
}

-(void)viewDidUnload {
    return;
    NSLog(@"sb viewdidunload!");
    [m_tableView release];
    m_tableView = nil;
    [m_background release];
    m_background = nil;
}

- (void)loadView {
    [super loadView];
    UITableView *realView = [super tableView];
    CGRect frame = [realView frame];
    m_background = [[UIView alloc] initWithFrame: frame];
    [m_background setAutoresizingMask: UIViewAutoresizingFlexibleWidth];
    [m_background setAutoresizesSubviews: YES];
    [m_background setBackgroundColor: [UIColor blackColor]];
    if (!abortLaunchCondition)
        [m_background addSubview: realView];
    [self setView: m_background];
    [realView setFrame: [realView bounds]];
    m_tableView = realView;
    [m_tableView retain];
    if ([m_tableView respondsToSelector: @selector(setAccessibilityLabel:)])
        [m_tableView setAccessibilityLabel: @"Select a story"];
    
    if (!m_frotzInfoController)
        m_frotzInfoController = [[FrotzInfo alloc] initWithSettingsController:m_settings navController:self.navigationController navItem:self.navigationItem];
}

- (StoryDetailsController*)detailsController {
    return m_details;
}

-(void)updateAccessibility {
    [m_frotzInfoController updateAccessibility];
    [m_settings updateAccessibility];
}

-(UITableView*)tableView {
    return m_tableView;
}

-(void)autoRestoreAndShowMainStoryController {
    if ([m_storyMainViewController currentStory] && [[m_storyMainViewController currentStory] length] > 0) {
        StoryInfo *si = [[StoryInfo alloc] initWithPath: [m_storyMainViewController currentStory]];
        [self setStoryDetails: si];
        [si release];
        [self showMainStoryController];
        
        [m_storyMainViewController autoRestoreSession];
    }
}

- (void)viewDidLoad {
    if (!gUseSplitVC)
        self.navigationItem.titleView = [m_frotzInfoController view];
    [self updateNavButton];
    
    if (m_postLaunch || m_launchPath)
        ;
    else if ([m_storyMainViewController willAutoRestoreSession:/*isFirstLaunch*/ YES]) {
        if (gUseSplitVC) // delay push of story controller so views have time to be sized correctly
            [self performSelector: @selector(autoRestoreAndShowMainStoryController) withObject:nil afterDelay:0.001];
        else
            [self autoRestoreAndShowMainStoryController];
    } else
        self.view.userInteractionEnabled = YES;
    m_postLaunch = YES;
}

- (void)updateNavButton {
    //    NSLog(@"updatenav: %@ %d", self.navigationController.navigationBar, [self.navigationController.navigationBar barStyle]);
    
    [self.navigationController.navigationBar setBarStyle: UIBarStyleBlackOpaque];
    
    if (!gUseSplitVC && [[m_storyMainViewController currentStory] length] > 0)
        self.navigationItem.rightBarButtonItem = m_nowPlayingButtonItem;
    else
        self.navigationItem.rightBarButtonItem = m_editButtonItem;
}

- (UIBarButtonItem*)nowPlayingNavItem {
    if (self.navigationItem.rightBarButtonItem == m_nowPlayingButtonItem)
        return m_nowPlayingButtonItem;
    return nil;
}

-(void)viewWillAppear:(BOOL)animated {
    [self reloadData];
    [self updateNavButton];
    [m_tableView scrollToNearestSelectedRowAtScrollPosition: UITableViewScrollPositionMiddle animated:YES];
}

-(void)viewDidAppear:(BOOL)animated {
    self.view.userInteractionEnabled = YES;
}

-(void)viewWillDisappear:(BOOL)animated {
    [self setEditing: NO animated: YES];
}

-(void)viewDidDisappear:(BOOL)animated {
}

- (StoryMainViewController*)storyMainViewController {
    return m_storyMainViewController;
}

- (FrotzInfo*)frotzInfoController {
    return m_frotzInfoController;
}

- (FrotzSettingsController*)settings {
    return m_settings;
}

- (void) dealloc {
    if (m_launchPath)
        [m_launchPath release];
    [m_tableView release];
    [m_storyNames release];
    [m_unsupportedNames release];
    [m_recents release];
    NSString *path;
    for (path in m_paths)
        [path release];
    [m_paths release];
    
    [m_editButtonItem release];
    [m_nowPlayingButtonItem release];
    [m_nowPlayingButtonView release];
    [m_metaDict release];
    [m_storyInfoDict release];
    [m_defaultThumb release];
    [super dealloc];
}

- (void)addPath: (NSString *)path {
    [m_paths addObject: path];
}

-(void)showMainStoryController {
    if (gUseSplitVC && self.splitViewController) {
        UINavigationController *nc = [m_storyMainViewController navigationController];
        if (nc) {
            if (!nc.topViewController.navigationItem.leftBarButtonItem) {
                UIBarButtonItem* backItem = [[UIBarButtonItem alloc] initWithTitle:@"Story List" style:UIBarButtonItemStyleBordered target:self action:@selector(didPressModalStoryListButton)];
                nc.topViewController.navigationItem.leftBarButtonItem = backItem;
                [backItem release];
            }
            [self.splitViewController presentModalViewController:nc animated:YES];
            return;
        }
    }
    [[self navigationController] pushViewController:m_storyMainViewController animated:YES];
}

-(void)hidePopover {
    m_details.navigationItem.leftBarButtonItem = self.popoverBarButton;
    if (self.popoverController) {
        [self.popoverController dismissPopoverAnimated: NO];
    }
}

- (void)didPressModalStoryListButton {
    if (gUseSplitVC && self.splitViewController) {
        if (self.splitViewController.modalViewController) {
            [self.splitViewController dismissModalViewControllerAnimated: YES];
            if (UIDeviceOrientationIsLandscape([self interfaceOrientation]))
                self.popoverBarButton = nil;
            [self hidePopover];
            NSString *storyPath = [[m_details storyInfo] path];
            m_details.willResume = storyPath && [storyPath length] > 0
            && ([[m_storyMainViewController currentStory] isEqualToString: storyPath]
                || [m_storyMainViewController autoSaveExistsForStory: storyPath]);
            [m_details refresh];
            
            // There's a bug where if the split VC view was unloaded due to a memory warning, sometimes its first VC
            // (StoryList) takes over the whole screen.  Dunno what to do to prevent it, but rotating the device fixes it.
        }
    }
}

-(void)launchStory:(NSString*)storyPath {
    NSString *currStory = [[m_storyMainViewController currentStory] lastPathComponent];
    NSString *autosaveMsg = nil;
    [[self navigationController] popToViewController:self animated:NO];
    
    if ([storyPath length] > 0 &&
        [currStory isEqualToString: [storyPath lastPathComponent]])
        [self resumeStory];
    else {
        if ([currStory length] > 0 && [m_storyMainViewController possibleUnsavedProgress]) {
#if 0
            if (islower([storyName characterAtIndex: 0]))
                storyName = [storyName capitalizedString];
            storyName = [storyName stringByReplacingOccurrencesOfString:@"_" withString:@" "];
            NSString *message = [NSString stringWithFormat:
                                 @"Abandon Story\n\nYou are currently playing \"%@\".\nDo you want to quit the current story\nand start a new one?",
                                 storyName];
            UIActionSheet *dialog = [[UIActionSheet alloc] initWithTitle:message delegate:self cancelButtonTitle:@"Keep Current Story" destructiveButtonTitle: @"Start New Story" otherButtonTitles:nil];
            [dialog showInView: [self view]];
            [dialog release];
        } else {
#else	
            autosaveMsg = [self fullTitleForStory: [NSString stringWithFormat: @"Autosaving story \"%@\".\n", [self fullTitleForStory: [currStory stringByDeletingPathExtension]]]];
            [m_storyMainViewController suspendStory];
        } {
#endif
            [m_storyMainViewController abandonStory:NO];
            [m_storyMainViewController setCurrentStory: storyPath];
            
            if ([m_storyMainViewController currentStory]) {
                if ([m_storyMainViewController willAutoRestoreSession: NO]) {
                    
                    autosaveMsg = [NSString stringWithFormat: @"%@Restoring story \"%@\".\n(If you wish to start over, use the 'restart' command.)",
                                   (autosaveMsg ? autosaveMsg : @""),
                                   [self fullTitleForStory: [[storyPath lastPathComponent] stringByDeletingPathExtension]]];
                    [m_storyMainViewController setLaunchMessage: autosaveMsg clear:YES];
                    //self.view.userInteractionEnabled = NO;
                    [self autoRestoreAndShowMainStoryController];
                    
                } else if ([m_storyMainViewController currentStory]) { // (check again in case of error detected in willAutoRestoreSession)
                    
                    autosaveMsg = [NSString stringWithFormat: @"%@Beginning story \"%@\"...\n",
                                   (autosaveMsg ? autosaveMsg : @""),
                                   [self fullTitleForStory: [[[m_storyMainViewController currentStory] lastPathComponent] stringByDeletingPathExtension]]];
                    [m_storyMainViewController setLaunchMessage: autosaveMsg clear:YES];
                    [self showMainStoryController];
                    [m_storyMainViewController launchStory];
                    
                }
            }
        }
    }
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (abortLaunchCondition)
        exit(1);
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == 0) {
        [m_storyMainViewController abandonStory: YES];
        NSIndexPath *indexPath = [[self tableView] indexPathForSelectedRow];
        NSString *story = [self storyForIndexPath: indexPath];
        if (story)
            [self launchStory: story];
    }
    [self updateNavButton];
}

-(void)resumeStory {
    if ([[m_storyMainViewController currentStory] length] > 0) {
        [[self navigationController] popToViewController:self animated:NO];
        [self showMainStoryController];
    }
}

- (NSString*)resourceGamePath {
    return [m_storyMainViewController resourceGamePath];
}

- (NSString*)currentStory {
    return [m_storyMainViewController currentStory];
}

- (NSInteger) tableView:(UITableView*)tableView numberOfRowsInSection: (NSInteger)section {
    int nRecents = [m_recents count];
    if (section == 0 && (m_isDeleting || nRecents > 0))
        return nRecents;
    if (section > 1)
        return 0;
    return m_numStories;
}

- (NSString*)tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0 && (m_isDeleting || [m_recents count] > 0)) {
        return @"Recently Played";
    } else if (section <= 1) {
        if (m_numStories > 0)
            return @"Story List";
        else
            return @"No Story Files Found.";
    } else
        return @"Hidden Story Files";
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView  {
    if (abortLaunchCondition)
        return 0;
    return m_isDeleting ? 2 :  1 + ([m_recents count] > 0);
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger row = indexPath.row;
    if (indexPath.section == 0 && [m_recents count] > 0)
        return NO;
    if (row < [m_storyNames count]) {
        NSString *delStory = [[m_storyNames objectAtIndex: row] path];
        if ([[m_storyMainViewController currentStory] isEqualToString: delStory])
            return NO;
        NSFileManager *fileMgr = [NSFileManager defaultManager];
        if ([delStory hasPrefix: [m_storyMainViewController resourceGamePath]]
            || [fileMgr isDeletableFileAtPath: delStory])
            return YES;
    }
    return NO;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSInteger row = indexPath.row;
        if (row < [m_storyNames count]) {
            StoryInfo *storyInfo = [m_storyNames objectAtIndex: row];
            NSString *delStory = [storyInfo path];
            NSFileManager *fileMgr = [NSFileManager defaultManager];
            NSError *error;
            BOOL doDelete = NO;
            if ([delStory hasPrefix: [m_storyMainViewController resourceGamePath]]) {
                doDelete = YES;
                [self hideStory: [[delStory lastPathComponent] stringByDeletingPathExtension] withState:YES];
                [self saveMetaData];
            } else if ([fileMgr removeItemAtPath: delStory error: &error]) {
                doDelete = YES;
                [self removeSplashDataForStory: [[delStory lastPathComponent] stringByDeletingPathExtension]];
            }
            if (doDelete) {
                NSMutableArray *indexPaths = [NSMutableArray arrayWithObject: indexPath];
                int recentIndex = [m_recents indexOfObject: storyInfo];
                if ([m_recents count] > 0)
                    m_isDeleting = YES;
                if (recentIndex != NSNotFound && recentIndex >= 0 && recentIndex < [m_recents count]) {
                    NSUInteger indexes[] = { 0, recentIndex };
                    [m_recents removeObjectAtIndex: recentIndex];
                    [indexPaths addObject: [NSIndexPath indexPathWithIndexes: indexes length:2]];
                    [self saveRecents];
                }
                if (gUseSplitVC) {
                    if ([[m_details storyInfo] isEqual: storyInfo])
                        [m_details clear];
                }
                [m_storyNames removeObjectAtIndex: row];
                m_numStories--;
                [self.tableView deleteRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationFade];
                m_isDeleting = NO;
                [tableView reloadData];
            }
        }
    }
}

-(void)addRecentStoryInfo:(StoryInfo*)storyInfo {
    int idx;
    if (!storyInfo || !storyInfo.path || [storyInfo.path length]==0)
        return;
    if (m_recents) {
        [storyInfo retain];
        if ((idx = [self recentRowFromStoryInfo: storyInfo]) != NSNotFound)
            [m_recents removeObjectAtIndex: idx];
        [m_recents insertObject: storyInfo atIndex: 0];
        if ([m_recents count] > 3)
            [m_recents removeLastObject];
        [self saveRecents];
        [storyInfo release];
    }
}

-(void)addRecentStory:(NSString*)storyPath {
    if (storyPath && [storyPath length] > 0) {
        StoryInfo *si = [[StoryInfo alloc] initWithPath:storyPath];
        [self addRecentStoryInfo: si];
        [si release];
    }
}

- (void)storyInfoChanged {
    NSString *newTitle = m_details.storyTitle;
    NSString *newAuthors = m_details.author;
    NSString *newTUID = m_details.tuid;
    NSString *storyPath = [[m_details storyInfo] path];
    BOOL update = NO;
    if (storyPath) {
        NSString *storyName = [[[storyPath lastPathComponent] stringByDeletingPathExtension] lowercaseString];
        
        if (newTitle && ![newTitle isEqual: [self fullTitleForStory: storyName]]) {
            NSMutableDictionary *titleDict = [m_metaDict objectForKey: kMDFullTitlesKey];
            if (titleDict) {
                [titleDict setObject: newTitle forKey: storyName];
                update = YES;
            }
        }
        if (newAuthors && ![newAuthors isEqual: [self authorsForStory: storyName]]) {
            NSMutableDictionary *authorDict = [m_metaDict objectForKey: kMDAuthorsKey];
            if (authorDict) {
                [authorDict setObject: newAuthors forKey: storyName];
                update = YES;
            }
        }
        if (newTUID && ![newTUID isEqual: [self tuidForStory: storyName]]) {
            NSMutableDictionary *tuidDict = [m_metaDict objectForKey: kMDTUIDKey];
            if (tuidDict) {
                [tuidDict setObject: newTUID forKey: storyName];
                update = YES;
            }
        }
        if (update)
            [self saveMetaData];
    }
}

-(void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    StoryInfo *storyInfo = [self storyInfoForIndexPath: indexPath];
    [self showStoryDetails: storyInfo];
}

-(void)setStoryDetails:(StoryInfo*)storyInfo {
    if (storyInfo) {
        NSString *storyPath = [storyInfo path];
        NSString *storyName = [[storyPath lastPathComponent] stringByDeletingPathExtension];
        m_details.storyInfo = storyInfo;
        m_details.artwork = nil;
        m_details.willResume = storyPath && [storyPath length] > 0
        && ([[m_storyMainViewController currentStory] isEqualToString: storyPath]
            || [m_storyMainViewController autoSaveExistsForStory: storyPath]);
        NSString *storySplashPath = [self splashPathForStory: storyName];
        NSString *ext = [storyPath pathExtension];
        BOOL isBlorb = ([ext isEqualToString:@"zblorb"] || [ext isEqualToString: @"gblorb"]);
        if (storySplashPath && [[NSFileManager defaultManager] fileExistsAtPath:storySplashPath])
            m_details.artwork = scaledUIImage([UIImage imageWithContentsOfFile: storySplashPath],0,0);
        else {
            if (isBlorb) {
                NSData *data = imageDataFromBlorb(storyPath);
                if (data) {
                    UIImage *image = scaledUIImage([UIImage imageWithData: data], 0, 0);
                    m_details.artwork = image;
                    [data release];
                }
            }
        }
        NSString *titleBlorb = nil, *authorBlorb = nil, *descriptBlorb = nil, *tuidBlorb = nil;
        if (isBlorb)
            metaDataFromBlorb(storyPath, &titleBlorb, &authorBlorb, &descriptBlorb, &tuidBlorb);

        m_details.storyTitle = titleBlorb ? titleBlorb : [self fullTitleForStory: storyName];
        m_details.author = authorBlorb ? authorBlorb : [self authorsForStory: storyName];
        m_details.tuid = tuidBlorb ? tuidBlorb : [self tuidForStory: storyName];
        m_details.descriptionHTML = descriptBlorb ? descriptBlorb : [self descriptForStory: storyName];
    }
}

-(void)refreshDetails {
    if (m_details) {
        StoryInfo *si = m_details.storyInfo;
        if (si)
            [self setStoryDetails: si];
    }
}

-(void)showStoryDetails:(StoryInfo*)storyInfo {
    if (storyInfo) {
        [storyInfo retain];
        [self setStoryDetails: storyInfo];
        if (gLargeScreenDevice && self.splitViewController) {
            [m_details refresh];
        }
        else
            [[self navigationController] pushViewController:m_details animated:YES];
        [storyInfo release];
    }
}

-(void)launchStoryInfo:(StoryInfo*)storyInfo {
    if (storyInfo) {
        [storyInfo retain];
        [self addRecentStoryInfo: storyInfo];
        [self launchStory: [storyInfo path]];
        [storyInfo release];
    }
}

#define DebugDetailsDeselect (0 && FROTZ_BETA)

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    static int lastRow = -1;
    BOOL secondTap = NO;
    if (self.popoverController)
        [self.popoverController dismissPopoverAnimated: YES];
    
    if (gUseSplitVC && indexPath.row == lastRow) {
        if (DebugDetailsDeselect) {
            [m_details clear];
            lastRow = -1;
        }
        secondTap = YES;
    } else
        lastRow = indexPath.row;
    
    StoryInfo *storyInfo = [self storyInfoForIndexPath: indexPath];
    if (storyInfo && lastRow != -1) {
        if (gUseSplitVC && (!secondTap || (self.popoverController!=nil)))
            [self showStoryDetails: storyInfo];
        else {
            [[self tableView] deselectRowAtIndexPath:indexPath animated:NO];
            [self launchStoryInfo: storyInfo];
        }
    }
    
    if (gUseSplitVC) {
    	[m_details setEditing:NO animated: YES];
        [m_details updateSelectionInstructions: NO];
    }
}

-(NSData*)thumbDataForStory:(NSString*)story {
    NSString *key = [self mapInfocom83Filename: [story lowercaseString]];
    NSMutableDictionary *thumbDict = [m_metaDict objectForKey: kMDThumbnailsKey];
    NSData *imageData = [thumbDict objectForKey: key];
    return imageData;
}

-(int)indexRowFromStoryInfo:(StoryInfo*)storyInfo {
    int row = [m_storyNames indexOfObject: storyInfo];
    if (row == NSNotFound) {
        int i = 0;
        NSString *story = [[storyInfo path] lastPathComponent];
        for (StoryInfo  *rsi in m_storyNames) {
            if ([[[rsi path] lastPathComponent] isEqualToString: story]) {
                row = i; break;
            }
            ++i;
        }
    }
    return row;
}

-(int)recentRowFromStoryInfo:(StoryInfo*)storyInfo {
    int row = [m_recents indexOfObject: storyInfo];
    if (row == NSNotFound) {
        int i = 0;
        NSString *story = [[storyInfo path] lastPathComponent];
        for (StoryInfo  *rsi in m_recents) {
            if ([[[rsi path] lastPathComponent] isEqualToString: story]) {
                row = i; break;
            }
            ++i;
        }
    }
    return row;
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"storyCell"];
    if (cell == nil) {
        cell = [[[UITableViewCell alloc] initWithFrame:CGRectZero reuseIdentifier:@"storyCell"] autorelease];
    }
    cell.image = nil;
    cell.text = @"";
    NSInteger row = indexPath.row;
    
    if (indexPath.section == 0 && row < [m_recents count])
        row = [self indexRowFromStoryInfo: [m_recents objectAtIndex: row]];
    
    if (gUseSplitVC)
        cell.accessoryType = UITableViewCellAccessoryNone;
    else if (row >= 0 && row < [m_storyNames count])
        cell.accessoryType = [tableView isEditing] ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDetailDisclosureButton;
    else
        cell.accessoryType = [tableView isEditing] ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    
    if (indexPath.section > 1) {
        return cell;
    }
    if (row >= 0 && row < m_numStories) {
        NSString *storyName = [[[[m_storyNames objectAtIndex: row] path] lastPathComponent] stringByDeletingPathExtension];
        NSString *title = [self fullTitleForStory: storyName];
        UIImage *image;
        cell.textLabel.text = title;
        cell.textLabel.frame = CGRectMake(10, 10, 0, 0);
        cell.imageView.image = nil;
        NSData *imageData = [self thumbDataForStory: storyName];
        if (imageData)
            image = [UIImage imageWithData: imageData];
        else
            image = m_defaultThumb;
        cell.imageView.image = image;
        cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
        
        CGFloat imgIndentWidth = 0;
        CGSize imgSize = image.size;
        // Use indentation support to tweak alignment so text lines up.
        // It's not worth it making a custom view to do this.
        if (imgSize.height > imgSize.width)
            imgIndentWidth = 40.0 - (int)(imgSize.width * 40.0/imgSize.height) + 2;
        if (imgIndentWidth < 0)
            imgIndentWidth = 0;
        cell.indentationWidth = imgIndentWidth + 1;
        cell.indentationLevel = 1;
        
        int titleLen = [title length];
        CGFloat fontsize = 20;
        CGFloat fudge = gUseSplitVC ? 2 : 0;
        if (gLargeScreenDevice && !gUseSplitVC)
            fontsize = 22;
        else if (titleLen > 34)
            fontsize = 12;
        else if (titleLen > 28)
            fontsize = 14;
        else if (titleLen > 24)
            fontsize = 15;
        else if (titleLen > 23)
            fontsize = 17;
        else if (titleLen > 22)
            fontsize = 18;
        cell.font = [UIFont boldSystemFontOfSize: fontsize+fudge];
    }
    return cell;
}

- (BOOL) tableView:(id)tableView showDisclosureForRow:(int)row {
    return (row >= 0 && row < [m_storyNames count]);
}
- (BOOL) table:(id)tableView disclosureClickableForRow:(int)row {
    return (row > 0 && row < [m_storyNames count]);
}

- (StoryInfo *)storyInfoForIndexPath:(NSIndexPath*)indexPath {
    int row = indexPath.row;
    if (indexPath.section == 0 && [m_recents count] > 0)
        return [m_recents objectAtIndex: row];
    if (indexPath == nil || indexPath.section > 1 || indexPath.row == -1 || row >= [m_storyNames count])
        return nil;
	
    return [m_storyNames objectAtIndex: row];
}

- (NSString *)storyForIndexPath:(NSIndexPath*)indexPath {
    return [[self storyInfoForIndexPath: indexPath] path];
}

- (BOOL)lowMemory {
    return m_lowMemory;
}

- (void)didReceiveMemoryWarning {
    //    NSMutableDictionary *thumbDict = [m_metaDict objectForKey: kMDThumbnailsKey];
    //    [thumbDict removeAllObjects];
    //    [m_tableView reloadData];
    [super didReceiveMemoryWarning];
#if 0
    if (!m_lowMemory) {
        UIAlertView *memWarning = [[UIAlertView alloc] initWithTitle:@"Low memory" message:@"Frotz is disabling display of thumbnails and splash images to conserve memory." delegate:self cancelButtonTitle:@"Okay" otherButtonTitles:nil];
        [memWarning show];
        [memWarning release];
    }
#endif
    m_lowMemory = YES;
}

- (void)splitViewController:(UISplitViewController*)svc popoverController:(UIPopoverController*)pc willPresentViewController:(UIViewController *)aViewController {
    [m_details updateSelectionInstructions: YES];    
}

- (void)splitViewController:(UISplitViewController*)splitViewController willHideViewController:(UIViewController *)aViewController 
          withBarButtonItem:(UIBarButtonItem*)barButtonItem forPopoverController:(UIPopoverController*)pc {
    barButtonItem.title = @"Select Story";
    
    self.popoverController = pc;
    [pc setDelegate: self];
    self.popoverBarButton = barButtonItem;
    m_details.navigationItem.leftBarButtonItem = barButtonItem;
}

- (void)splitViewController:(UISplitViewController*)splitViewController willShowViewController:(UIViewController *)aViewController 
  invalidatingBarButtonItem:(UIBarButtonItem *)button {
    m_details.navigationItem.leftBarButtonItem = nil;
    self.popoverController = nil;
    self.popoverBarButton = nil;
}

- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController {
    [m_details updateSelectionInstructions: NO];
}

@end

