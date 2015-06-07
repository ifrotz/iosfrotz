//
//  This class was created by Nonnus,
//  who graciously decided to share it with the CocoaHTTPServer community.
//

#import "FrotzHTTPConnection.h"
#import "HTTPServer.h"
#import "HTTPResponse.h"
#import "AsyncSocket.h"
#import "FileTransferInfo.h"
#import "StoryBrowser.h"
#import "ui_utils.h"

@implementation FrotzHTTPConnection


static NSInteger indexOfBytes(NSData *data, NSInteger offset, const char *searchBytes, NSInteger searchLength, BOOL *partialMatchAtEnd) {
    
    const char *bytes = [data bytes];
    NSInteger dataLen = [data length];
    
    *partialMatchAtEnd = NO;
    const char *cur = bytes + offset, *bytesEnd = bytes + dataLen;
    const char *searchEnd = searchBytes + searchLength;
    while (cur < bytesEnd) {
        const char *b = cur, *s = searchBytes;
        while (s < searchEnd && b < bytesEnd && *b == *s)
            ++b, ++s;
        if (s > searchBytes) {
            if (s == searchEnd)
                return cur - bytes;
            if (b == bytesEnd) {
                *partialMatchAtEnd = YES;
                return cur - bytes;
            }
        }
        ++cur;
    }
    return -1;
}



/**
 * Returns whether or not the requested resource is browseable.
 **/
- (BOOL)isBrowseable:(NSString *)path
{
	// Override me to provide custom configuration...
	// You can configure it for the entire server, or based on the current request
	
	return YES;
}


/**
 * This method creates a html browseable page.
 * Customize to fit your needs
 **/
- (NSString *)createBrowseableIndex:(NSString *)path
{
    BOOL isRoot = NO, isRemove = NO;
    
    if ([path hasPrefix: @"/remove="]) {
        isRemove = YES;
        path = [path substringFromIndex: 8];
    }
    NSString *rootPath = [[server documentRoot] path];
    NSMutableString *outdata = [NSMutableString new];
    NSString *fullPath;
    if ([path isEqualToString: @"/Games/"] || [path hasPrefix: @"/Saves/"] && [path hasSuffix: @".d/"]) {
        [outdata appendFormat: @"<html><head>\n<meta HTTP-EQUIV=\"REFRESH\" content=\"0; url=/\"></head>\n<body></body></html>\n"];
        return [outdata autorelease];
    } if ([path isEqualToString:@"/"]) {
        isRoot = YES;
        fullPath = rootPath;
    } else {
        fullPath = [NSString stringWithFormat: @"%@%@", rootPath, path];
    }
    NSFileManager *defaultManager = [NSFileManager defaultManager];
    StoryBrowser *sb = (StoryBrowser*)[server delegate];
    if (isRemove) {
        BOOL isDir = NO;
        NSError *error = nil;
        NSString *gameName = [path lastPathComponent];
        if (![defaultManager fileExistsAtPath: fullPath isDirectory: &isDir]) {
            fullPath = [fullPath stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];            
            gameName = [fullPath lastPathComponent];
        }
        if ([defaultManager fileExistsAtPath: fullPath isDirectory: &isDir] && !isDir) {
            [defaultManager removeItemAtPath: fullPath error: &error];
            [sb removeSplashDataForStory: [gameName stringByDeletingPathExtension]];
        } else {
            NSString *resourceGamePath = [sb resourceGamePath];
            if (resourceGamePath) {
                NSString *filePath = [resourceGamePath stringByAppendingPathComponent: gameName];
                if ([defaultManager fileExistsAtPath:filePath isDirectory: &isDir] && !isDir) {
                    [sb hideStory: [gameName stringByDeletingPathExtension] withState:YES];
                    [sb saveMetaData];
                }
            }
        }
        [sb refresh];
        [outdata appendFormat: @"<html><head>\n<meta HTTP-EQUIV=\"REFRESH\" content=\"0; url=/\"></head>\n<body></body></html>\n"];
        return [outdata autorelease];
    }
    if (![defaultManager fileExistsAtPath: fullPath]) {
        int origFullLength = [fullPath length], origLength = [path length], truncated = 0;
        do {
            fullPath = [fullPath stringByDeletingLastPathComponent];
            if ([defaultManager fileExistsAtPath: fullPath])
                break;
        } while ([fullPath length] > 1);
        truncated = origFullLength - [fullPath length];
        if (truncated > origLength)
            truncated = origLength - 1;
        path = [path substringToIndex: origLength - truncated];
        [outdata appendFormat: @"<html><head>\n<meta HTTP-EQUIV=\"REFRESH\" content=\"0; url=%@%s\"></head>\n<body></body></html>\n",
         path, [path length] <= 1 ? "/":""];
        return [outdata autorelease];
    }
    if (![path hasSuffix: @"/"])
        path = [path stringByAppendingString: @"/"];
    
    
    [outdata appendString:@"<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\"\n<html><head>"];
    [outdata appendFormat:@"<title>&gt; Frotz</title>"];
    [outdata appendString:@"<style>\nhtml {background-color:#eeeeee}\n body { background-color:#FFFFFF; font-family:Tahoma,Arial,Helvetica,sans-serif; "
     "font-size:18x; margin-left:10%; margin-right:10%; border:2px groove #006600; padding:15px; }\n"
     " hr { margin-top: 0px; margin-bottom: 0px; padding: 0px;}\n span.submitbut { float:right;}\n</style>\n"];
    [outdata appendString: @"\n\
     <script type='text/javascript'>\n\
     \n\
     function showFull(id) {\n\
     var e = document.getElementById(id);\n\
     var spans = e.getElementsByTagName('span');\n\
     for (var i = 0; i < spans.length; i++) {\n\
     if (spans[i].id == \"showentry\") {\n\
     spans[i].style.display = 'inline';\n\
     }\n\
     }\n\
     e = document.getElementById(id + '-links');\n\
     spans = e.getElementsByTagName('span');\n\
     for (var i = 0; i < spans.length; i++) {\n\
     if (spans[i].id == \"showlink\")\n\
     spans[i].style.display = 'none';\n\
     if (spans[i].id == \"hidelink\")\n\
     spans[i].style.display = 'inline';\n\
     }\n\
     }\n\
     \n\
     \n\
     function hideFull(id) {\n\
     var e = document.getElementById(id);\n\
     var spans = e.getElementsByTagName('span');\n\
     for (var i = 0; i < spans.length; i++) {\n\
     if (spans[i].id == \"showentry\") {\n\
     spans[i].style.display = 'none';\n\
     }\n\
     }\n\
     e = document.getElementById(id + '-links');\n\
     spans = e.getElementsByTagName('span');\n\
     for (var i = 0; i < spans.length; i++) {\n\
     if (spans[i].id == \"showlink\")\n\
     spans[i].style.display = 'inline';\n\
     if (spans[i].id == \"hidelink\")\n\
     spans[i].style.display = 'none';\n\
     }\n\
     }\n\
     \n\
     function checkFull(id) {\n\
     var e = document.getElementById(id);\n\
     var spans = e.getElementsByTagName('span');\n\
     var found = 0;\n\
     for (var i = 0; i < spans.length; i++) {\n\
     if (spans[i].id == \"showentry\") {\n\
     spans[i].style.display = 'none';\n\
     found = 1;\n\
     }\n\
     }\n\
     if (found == 0) {\n\
     e = document.getElementById(id + '-links');\n\
     spans = e.getElementsByTagName('span');\n\
     for (var i = 0; i < spans.length; i++) {\n\
     if ((spans[i].id == \"showlink\") )\n\
     spans[i].style.display = 'none';\n\
     }\n\
     }\n\
     }\n\
     function confirmRemove(id, link) {\n\
     if (confirm(\"Are you sure you want to remove this item?\")) {\n\
     document.getElementById(id).href=link;\n\
     } else { \n\
     document.getElementById(id).href='';\n\
     }\n\
     }\n\
     </script>\n"];
    
    
    
    [outdata appendString:@"</head>\n<body>\n"];
    [outdata appendString:@"<h1>&gt; Frotz</h1>\n"];
    
    [outdata appendString:@"<div align=\"left\"><small><p><i>This page allows you to transfer story files and saved games between Frotz and your computer.<br/>\n"];
    
    if (isRoot) {
        fullPath = [fullPath stringByAppendingPathComponent: @"Games"];
    } 
    NSArray *array = nil;
    
    if (isRoot) {
        [outdata appendString: @"Click on a story file to download it, or the Remove link to delete the story from Frotz.<br/>"
         "Click the <large><b>+</b></large> symbol to the left of each story to access its saved games.</i></p>\n"
         "<p><i>To upload a story file, use the form at the bottom of the page.</i></p></small></div>\n"];
        
        array = [sb storyNames];
        
        [outdata appendString: @"<div><table align=\"center\" border=\"0\" cellspacing=\"4\" cellpadding=\"0\">\n"];
        NSString *currentStory = [[[[sb currentStory] lastPathComponent] stringByDeletingPathExtension] lowercaseString];
        BOOL foundSaves = NO;
        for (StoryInfo* storyInfo in array)
        {
            BOOL isDir = NO;
            NSString *storyPath = [storyInfo path];
            NSString *fname = [storyPath lastPathComponent];
            [defaultManager fileExistsAtPath: storyPath isDirectory: &isDir];
            if (!isDir) {
                NSString *story = [[fname stringByDeletingPathExtension] lowercaseString];
                NSString *storyId = [story stringByReplacingOccurrencesOfString:@"'" withString:@""];
                NSString *title = [sb fullTitleForStory: story];
                NSString *saveDir =  [fname stringByAppendingString: @".d"];
                NSString *savePath = [[rootPath stringByAppendingPathComponent:@"Saves"] stringByAppendingPathComponent: saveDir];
                NSArray *saveFiles = [defaultManager directoryContentsAtPath: savePath];
                if (islower([title characterAtIndex: 0]))
                    title = [title capitalizedString];
                [outdata appendFormat: @"<tr class='entry' id=\"entry-%@-links\">\n", storyId];
                BOOL showSaves = !currentStory || [currentStory length] == 0 ? !foundSaves && [saveFiles count] > 0 : [story isEqualToString: currentStory];
                [outdata appendFormat: @"<td><a name=\"%@\"></a><span id='showlink' %@><a style='text-decoration:none; color:#000000;' "
                 "href='javascript:void(0);' onclick='javascript:showFull(\"entry-%@\");'>"
                 "<large><b>+</b><large>&nbsp;</a> </span>\n"
                 "<span id='hidelink' %@><a style='text-decoration:none; color:#000000;' "
                 "href='javascript:void(0);' onclick='javascript:hideFull(\"entry-%@\");'><large><b>-</b>&nbsp;</large></a> </span></td>",
                 story, showSaves ? @"style='display:none';" : @"",
                 storyId, showSaves ? @"" : @"style='display:none';", storyId];
                
                if ([sb thumbDataForStory: story]) {
                    NSString *splashPath = [sb splashPathForStory: story];
                    [outdata appendFormat: @"<td height=\"40px\"><a href=\"%@/Splashes/%@\"><img height=\"40\" src=\"icon=%@\"/></a></td>\n",
                     [defaultManager fileExistsAtPath: splashPath] ? @"":@"#",
                     [splashPath lastPathComponent], [fname stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
                }
                else 
                    [outdata appendFormat: @"<td height=\"40px\"> </td>\n"];
                [outdata appendFormat: @"<td>&nbsp;&nbsp;</td><td>%@&nbsp;&nbsp;</td><td><a href=\"/Games/%@\">%32@</a></td>", title, fname, fname];
                [outdata appendFormat: @"<td><small>&nbsp;&nbsp;&nbsp;<a id=\"remove-%@\" href=\"/remove=/Games/%@\""
                 " onclick=\"confirmRemove('remove-%@','/remove=/Games/%@\');\">(Remove)</a></small></td></tr>\n", fname, fname, fname, fname];
                [outdata appendFormat: @"<tr height=\"2px\" id=\"entry-%@\"><td colspan=\"6\">\n<div class='entry-body'>"   //<style>#showentry {%@}</style>"
                 "<span id=\"showentry\">\n", storyId];
                NSMutableString *saveFileList =  [NSMutableString stringWithString: @"<small>&nbsp;&nbsp;&nbsp;<i>No Saved Games</i>&nbsp;&nbsp;"];
                NSMutableString *scriptFileList = nil;
                int saveCount = 0, textCount = 0;
                if ([saveFiles count]) {
                    for (NSString *saveFile in saveFiles) {
                        if ([saveFile hasSuffix: @".sav"] || [saveFile hasSuffix: @".qut"]) {
                            if (++saveCount == 1)
                                [saveFileList setString: @"<small>&nbsp;&nbsp;&nbsp;<b><i>Saved Games:</i></b>&nbsp;&nbsp;"];
                            [saveFileList appendFormat: @"<a href=\"/Saves/%@/%@\">%@</a>&nbsp;&nbsp;", saveDir, saveFile, [saveFile stringByDeletingPathExtension]];
                        } else if ([saveFile hasSuffix: @".txt"]) {
                            if (++textCount == 1)
                                scriptFileList = [NSMutableString stringWithString:@"<small>&nbsp;&nbsp;&nbsp;<b><i>Transcripts:</i></b>&nbsp;&nbsp;"];
                            [scriptFileList appendFormat: @"<a href=\"/Saves/%@/%@\">%@</a>&nbsp;&nbsp;", saveDir, saveFile, [saveFile stringByDeletingPathExtension]];

                        }
                    }
                    foundSaves = YES;
                }
                [outdata appendString:saveFileList];
                if (saveCount)
                    [outdata appendString: @"</small><br/>\n"];
                if (scriptFileList) {
                    [outdata appendString:scriptFileList];
                    [outdata appendString:@"</small><br/>"];
                }
                if ([self supportsMethod:@"POST" atPath:path])
                {
                    [outdata appendFormat:@"<form action=\"/Saves/%@/\" method=\"post\" enctype=\"multipart/form-data\" name=\"%@\" id=\"%@\">", saveDir, story, story];
                    [outdata appendString:@"<label>&nbsp;&nbsp;&nbsp;<small>Upload Saved Game (.sav,.qut) or Splash Image (.png,.jpg):</small>&nbsp;<input type=\"file\" name=\"file\" id=\"file\" /></label>"];
                    [outdata appendString:@"<span class=\"submitbut\">&nbsp<input type=\"submit\" align=\"right\" name=\"button\" id=\"button\" value=\"Submit\" />&nbsp;</span>"];
                    [outdata appendString:@"</form>\n"];
                }		    
                
                [outdata appendFormat: @"</small></span><script type='text/javascript'>%@(\"entry-%@\");</script>\n"
                 "</div></td></tr>\n",  showSaves ? @"void" : @"checkFull", storyId];
                
                [outdata appendString: @"<tr height=\"1\"><td colspan=\"6\"><hr/></td></tr>\n"];
            }		
        }
        NSMutableArray *unsupportedNames = [sb unsupportedStoryNames];
        if (unsupportedNames && [unsupportedNames count] > 0) {
            [outdata appendString: @"<td colspan=\"6\"><b><span style='color:red;'>The following items have file extensions not currently supported by Frotz</span></b></td>\n"];
            int ucount = 0;
            [outdata appendFormat: @"<tr>\n"];
            for (NSString* path in unsupportedNames) {
                NSString *fname = [path lastPathComponent];
                if (ucount % 3 == 2)
                    [outdata appendFormat: @"</tr><tr>\n"];	    
                [outdata appendFormat: @"<td height=\"40px\"> </td>\n"];
                [outdata appendFormat: @"<td><a href=\"/Games/%@\">%@</a></td>", fname, fname];
                [outdata appendFormat: @"<td><small>&nbsp;&nbsp;&nbsp;<a id=\"remove-%@\" href=\"/remove=/Games/%@\""
                 " onclick=\"confirmRemove('remove-%@','/remove=/Games/%@\');\">(Remove)</a></small></td>\n", fname, fname, fname, fname];
                ++ucount;
            }
            [outdata appendFormat: @"</tr>\n"];
            [outdata appendString: @"<tr height=\"1\"><td colspan=\"6\"><hr/></td></tr>\n"];
            [outdata appendString: @"\n"];
        }
        if ([self supportsMethod:@"POST" atPath:path]) {
            [outdata appendString:@"<tr><td colspan=\"6\">"];
            [outdata appendString:@"<br/><small><p align=\"center\"><i>To add a story file to Frotz, choose the file, type in the story's title, and click Submit.<br/>"
             "Frotz can play stories in the Z-machine format, with file extensions <b>.z3</b>, <b>.z4</b>, <b>.z5</b>, <b>.z8</b>, and <b>.zblorb</b>.<br/>\n"
             "Original Infocom files with extension <b>.dat</b> are also supported.</i></p></small>\n"];
            [outdata appendString:@"<form action=\"/Games/\" method=\"post\" enctype=\"multipart/form-data\" name=\"form1\" id=\"form1\">"];
            [outdata appendString:@"<label>Upload Story File:&nbsp;<input type=\"file\" name=\"file\" id=\"file\" /></label>"];
            [outdata appendString:@"&nbsp;&nbsp;&nbsp;<label>Story title <input type=\"text\" name=\"title\" id=\"title\"/></label>"];
            [outdata appendString:@"&nbsp;&nbsp;<span class=\"submitbut\"><input type=\"submit\" align=\"right\" name=\"button\" id=\"button\" value=\"Submit\" />&nbsp;</span>"];
            [outdata appendString:@"</form>\n"];
            [outdata appendString:@"</td></tr>\n"];
        }
        [outdata appendString: @"</table></div><br/>\n"];
    } else {
        [outdata appendString: @"</div>\n"];
        array = [defaultManager directoryContentsAtPath:fullPath];
        [outdata appendFormat:@"<a href=\"..\">[Parent folder]</a><br />\n"];
        if ([array count] > 0) {
            [outdata appendString: @"<table>\n"];
            if (!isRoot)
                [outdata appendString: @"<tr><td>Name</td> <td align=\"right\">Size</td> <td>Date</td><td> </td></tr>\n"];
        } else
            [outdata appendString: @"<p>It is pitch black.  You are likely to be eaten by a grue.</p>\n"];
        
        for (NSString *fname in array)
        {
            BOOL isDir = NO;
            if (isHiddenFile(fname))
                continue;
            NSDictionary *fileDict = [defaultManager fileAttributesAtPath:[fullPath stringByAppendingPathComponent:fname] traverseLink:NO];
            NSString *modDate = [fileDict[NSFileModificationDate] description];
            if ([fileDict[NSFileType] isEqualToString: @"NSFileTypeDirectory"]) {
                isDir = YES;
                fname = [fname stringByAppendingString:@"/"];
            }
            [outdata appendFormat: @"<tr><td><a href=\"%@%@\">%32@</a></td> <td align=\"right\">%d</td> <td>%@</td><td>  ", path, fname, fname,
             [fileDict[NSFileSize] intValue], [modDate substringToIndex: [modDate length]-5]];
            if (!isDir)
                [outdata appendFormat: @"<td><small><a href=\"/remove=%@%@\">(Remove)</a></small></td></tr>\n", path, fname];
            else
                [outdata appendString: @"<td></td></tr>\n"];		
        }
        if ([array count] > 0)
            [outdata appendString:@"</table><br/>"];
    }
    [outdata appendString:@"</body></html>\n"];
    
    //NSLog(@"outData: %@", outdata);
    return [outdata autorelease];
}

/**
 * Returns whether or not the server will accept POSTs.
 * That is, whether the server will accept uploaded data for the given URI.
 **/
- (BOOL)supportsMethod:(NSString *)method atPath:(NSString *)relativePath
{
	if ([@"POST" isEqualToString:method])
	{
		return YES;
	}
	
	return [super supportsMethod:method atPath:relativePath];
}

/**
 * Called from the superclass after receiving all HTTP headers, but before reading any of the request body
 * so we use it to initialize our stuff
 **/
- (void)prepareForBodyWithSize:(UInt64)contentLength
{
    dataStartIndex = 0;
    if (multipartData == nil ) multipartData = [[NSMutableArray alloc] init];   //jlz
    postHeaderOK = FALSE;
}

/**
 * This method is called to get a response for a request.
 * You may return any object that adopts the HTTPResponse protocol.
 * The HTTPServer comes with two such classes: HTTPFileResponse and HTTPDataResponse.
 * HTTPFileResponse is a wrapper for an NSFileHandle object, and is the preferred way to send a file response.
 * HTTPDataResopnse is a wrapper for an NSData object, and may be used to send a custom response.
 **/
- (NSObject<HTTPResponse> *)httpResponseForMethod:(NSString *)method URI:(NSString *)path
{
	NSLog(@"httpResponseForURI: method:%@ path:%@ self: %@", method, path, self);
	
	NSData *requestData = [(NSData *)CFHTTPMessageCopySerializedMessage(request) autorelease];
	
	NSString *requestStr = [[[NSString alloc] initWithData:requestData encoding:NSASCIIStringEncoding] autorelease];
	NSLog(@"\n=== Request ====================\n%@\n================================", requestStr);
	NSFileManager *defaultManager = [NSFileManager defaultManager];
	if (requestContentLength > 0)  // Process POST data
	{
		NSLog(@"processing post data: %llu", requestContentLength);
		
		if ([multipartData count] < 2) return nil;
		
		NSString* postInfo = [[NSString alloc] initWithBytes:[multipartData[1] bytes]
													  length:[multipartData[1] length]
													encoding:NSUTF8StringEncoding];
		
		NSArray* postInfoComponents = [postInfo componentsSeparatedByString:@"; filename="];
		postInfoComponents = [[postInfoComponents lastObject] componentsSeparatedByString:@"\""];
		postInfoComponents = [postInfoComponents[1] componentsSeparatedByString:@"\\"];
		NSString* fn = [postInfoComponents lastObject];
 		if (fn) {
			NSLog(@"NewFileUploaded %@", fn);
			[[NSNotificationCenter defaultCenter] postNotificationName:@"NewFileUploaded" object:nil];
		}
		
		for (int n = 1; n < [multipartData count] - 1; n++)
			NSLog(@"%@", [[[NSString alloc] initWithBytes:[multipartData[n] bytes] length:[multipartData[n] length] encoding:NSUTF8StringEncoding] autorelease]);
		
		[postInfo release];
		[multipartData release];
        
		multipartData = nil ;
		requestContentLength = 0;
		NSError *ferror = nil;
		if ([fn hasSuffix: @".png"] || [fn hasSuffix:@".jpg"] || [fn hasSuffix: @".PNG"] || [fn hasSuffix:@".JPG"]) {
		    NSString *ext = [[fn pathExtension] lowercaseString];
		    NSString *rootPath = [[server documentRoot] path];
		    NSString *oldPath = [NSString stringWithFormat:@"%@%@%@", rootPath, [path stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding], fn];
            NSString *story = [[[[path lastPathComponent] stringByDeletingPathExtension] stringByDeletingPathExtension ]stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
		    StoryBrowser *sb = (StoryBrowser*)[server delegate];
		    story = [sb canonicalStoryName:story];
		    if (story) {
                NSString *newPath = [NSString stringWithFormat:@"%@/Splashes/%@.%@", rootPath, story, ext];
                [defaultManager removeItemAtPath: newPath error:&ferror];
                if ([ext isEqualToString: @"jpg"])
                    [defaultManager removeItemAtPath: [newPath stringByReplacingOccurrencesOfString:@".jpg" withString:@".png"] error:&ferror];
                if ([defaultManager moveItemAtPath:oldPath toPath: newPath error:&ferror]) {
                    NSData *data = [NSData dataWithContentsOfFile: newPath];
                    if (data) {
                        UIImage *image = [UIImage imageWithData: data];
                        if (image) {
                            UIImage *thumb = scaledUIImage(image, 40, 32);
                            if (thumb) {
                                [sb addThumbData: UIImagePNGRepresentation(thumb) forStory:story];
                                [sb saveMetaData];
                            }
                        }
                    }
                } else
                    [defaultManager removeItemAtPath: oldPath error:&ferror];
		    }
		}
		
		if ([path hasPrefix: @"/Games/"]) {
		    return [[[HTTPDataResponse alloc] initWithData:
                     [@"<html><head>\n<meta HTTP-EQUIV=\"REFRESH\" content=\"0; url=/\"></head>\n<body></body></html>\n"
                      dataUsingEncoding: NSUTF8StringEncoding]] autorelease];
		}
	}
	
	NSString *filePath = [self filePathForURI:path];
	BOOL isDir = NO;
	if ([defaultManager fileExistsAtPath:filePath isDirectory: &isDir] && !isDir) {
	    HTTPFileResponse *fileResponse = [[[HTTPFileResponse alloc] initWithFilePath:filePath] autorelease];
	    if ([filePath hasSuffix: @".sav"])
            [fileResponse setFileName: [[[filePath lastPathComponent] stringByDeletingPathExtension] stringByAppendingPathExtension: @"sav"]];
	    else if ([filePath hasSuffix: @".qut"])
            [fileResponse setFileName: [[[filePath lastPathComponent] stringByDeletingPathExtension] stringByAppendingPathExtension: @"qut"]];
	    return fileResponse;
    }
	else {
	    if ([path hasPrefix: @"/Games/"]) {
            NSString *gameName = [path lastPathComponent];
            NSString *resourceGamePath = [[server delegate] resourceGamePath];
            if (resourceGamePath) {
                filePath = [resourceGamePath stringByAppendingPathComponent: gameName];
                if ([defaultManager fileExistsAtPath:filePath isDirectory: &isDir] && !isDir)
                {
                    return [[[HTTPFileResponse alloc] initWithFilePath:filePath] autorelease];
                }
            }
	    }
	    if ([path hasPrefix: @"/icon="]) {
            path = [path substringFromIndex: 6];
            NSString *story = [[[path stringByDeletingPathExtension] lowercaseString] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            NSData *imgData = [[server delegate] thumbDataForStory: story];
            if (imgData)
                return [[[HTTPDataResponse alloc] initWithData:imgData] autorelease];
            return nil;
	    }
	    if ([self isBrowseable:path])
	    {
		    //NSLog(@"folder: %@", folder);
		    NSData *browseData = [[self createBrowseableIndex:path] dataUsingEncoding:NSUTF8StringEncoding];
		    return [[[HTTPDataResponse alloc] initWithData:browseData] autorelease];
	    }
	}
	
	return nil;
}


/**
 * This method is called to handle data read from a POST.
 * The given data is part of the POST body.
 **/
- (void)processDataChunk:(NSData *)postDataChunk
{
    // Override me to do something useful with a POST.
    // If the post is small, such as a simple form, you may want to simply append the data to the request.
    // If the post is big, such as a file upload, you may want to store the file to disk.
    // 
    // Remember: In order to support LARGE POST uploads, the data is read in chunks.
    // This prevents a 50 MB upload from being stored in RAM.
    // The size of the chunks are limited by the POST_CHUNKSIZE definition.
    // Therefore, this method may be called multiple times for the same POST request.
    
    //NSLog(@"processPostDataChunk");
    BOOL partialMatch = NO;
    NSLog(@"process dataChunk: %@", self);
    if (!postHeaderOK)
    {		
        const char* crlfString = "\r\n";
        
        int postDataLen = [postDataChunk length];
        int crlfLen = strlen(crlfString);
        int i = 0;
        while ((i = indexOfBytes(postDataChunk, i, crlfString, crlfLen, &partialMatch)) >= 0) {
            NSRange newDataRange = {dataStartIndex, i - dataStartIndex};
            dataStartIndex = i + crlfLen;
            i += crlfLen - 1;
            NSData *newData = [postDataChunk subdataWithRange:newDataRange];
            
            if ([newData length])
                [multipartData addObject:newData];
            else {
                postHeaderOK = TRUE;
                partSeparator =      [[[NSString alloc] initWithBytes:[multipartData[0] bytes] length:[multipartData[0] length] encoding:NSUTF8StringEncoding] autorelease];
                partSeparator = [[@"\r\n" stringByAppendingString: partSeparator] retain];
                NSString* postInfo = [[NSString alloc] initWithBytes:[multipartData[1] bytes] length:[multipartData[1] length] encoding:NSUTF8StringEncoding];
                int partSepLen = [partSeparator length];
                NSArray* postInfoComponents = [postInfo componentsSeparatedByString:@"; filename="];
                postInfoComponents = [[postInfoComponents lastObject] componentsSeparatedByString:@"\""];
                postInfoComponents = [postInfoComponents[1] componentsSeparatedByString:@"\\"];
                
                NSURL *uri = CFBridgingRelease(CFHTTPMessageCopyRequestURL(request));
                int partEndOffset = indexOfBytes(postDataChunk, dataStartIndex, [partSeparator UTF8String], partSepLen, &partialMatch);
                if (partEndOffset >= 0) {
                    postDataLen = partEndOffset;
                }
                NSLog(@"process data write file docpath=%@ fn=%@ self=%@", [uri relativeString], [postInfoComponents lastObject], self);
                NSString *destPath = [[[server documentRoot] path] stringByAppendingPathComponent: [[uri relativeString] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
                BOOL isDir = NO;
                if (![[NSFileManager defaultManager] fileExistsAtPath: destPath isDirectory: &isDir] && [destPath hasSuffix: @".d"])
                    [[NSFileManager defaultManager] createDirectoryAtPath: destPath attributes:nil];
                filename = [[destPath stringByAppendingPathComponent:[postInfoComponents lastObject]] retain];
                NSRange fileDataRange = {dataStartIndex, postDataLen - dataStartIndex};
                
                [[NSFileManager defaultManager] createFileAtPath:filename contents:[postDataChunk subdataWithRange:fileDataRange] attributes:nil];
                fileHandle = [[NSFileHandle fileHandleForUpdatingAtPath:filename] retain];
                
                
                if (partEndOffset >= 0) {
                    if (partialMatch) {
                        leftOverMatch = [[postDataChunk
                                          subdataWithRange: NSMakeRange(partEndOffset, [postDataChunk length] - partEndOffset)] retain];
                    } else {
                        [self handlePostMultipartData: [postDataChunk 
                                                        subdataWithRange: NSMakeRange(partEndOffset + partSepLen, [postDataChunk length] - partEndOffset - partSepLen)]];
                        [fileHandle closeFile];
                        fileHandle = nil;
                    }
                }
                if (fileHandle)
                    [fileHandle seekToEndOfFile];
                
                [postInfo release];
                [[server delegate] refresh];
                break;
            }
        }
    } else {
        if (leftOverMatch) {
            NSMutableData *newChunk = [NSMutableData dataWithData: leftOverMatch];
            [newChunk appendData: postDataChunk];
            postDataChunk = newChunk;
            [leftOverMatch release];
            leftOverMatch = nil;
        }
        if (partSeparator) {
            int partSepLen = [partSeparator length];
            partialMatch = NO;
            int partEndOffset = indexOfBytes(postDataChunk, 0, [partSeparator UTF8String], partSepLen, &partialMatch);
            if (partEndOffset >= 0) {
                if (fileHandle && partEndOffset > 0)
                    [fileHandle writeData: [postDataChunk subdataWithRange: NSMakeRange(0, partEndOffset)]];
                if (partialMatch) {
                    leftOverMatch = [[postDataChunk
                                      subdataWithRange: NSMakeRange(partEndOffset, [postDataChunk length] - partEndOffset)] retain];
                } else {
                    [self handlePostMultipartData: [postDataChunk
                                                    subdataWithRange: NSMakeRange(partEndOffset + partSepLen, [postDataChunk length] - partEndOffset - partSepLen)]];
                    [fileHandle closeFile];
                    fileHandle = nil;
                }
                return;
            }
        }
        if (fileHandle)	
            [fileHandle writeData:postDataChunk];
    }
}

- (void)handlePostControl: (NSString*)control value:(NSString*)value {
    if ([control isEqualToString: @"title"]) {
        if (filename) {
            if (value && [value length] > 0 && [value rangeOfString: @"/"].length == 0) {
                NSString *story = [filename storyKey];
                [[server delegate] addTitle: value forStory: story];
            }
        }
    }
}

- (void)handlePostMultipartData:(NSData *)data {
    NSString *str = [[[NSString alloc] initWithBytes: [data bytes] length: [data length] encoding:NSUTF8StringEncoding] autorelease];
    NSArray* partComponents = [str componentsSeparatedByString:partSeparator];
    for (NSString *part in partComponents) {
        NSArray* partHeaderComponents = [part componentsSeparatedByString:@"form-data; name="];
        if ([partHeaderComponents count] > 1) {
            partHeaderComponents = [[partHeaderComponents lastObject] componentsSeparatedByString:@"\""];
            NSString *control = partHeaderComponents[1];
            partHeaderComponents = [[partHeaderComponents lastObject] componentsSeparatedByString:@"\r\n"];
            NSString *value = [partHeaderComponents lastObject];
            [self handlePostControl: control value: value];
        }
    }
}

- (void)doneWithBody {
    if (fileHandle) {
        if (leftOverMatch)
            [fileHandle writeData:leftOverMatch];
        [fileHandle closeFile];
    }
    if (leftOverMatch)
        [leftOverMatch release];
    if (partSeparator)
        [partSeparator release];
    if (filename)
        [filename release];
    fileHandle = nil;
    partSeparator = nil;
    filename = nil;
    leftOverMatch = nil;
}

-(void)dealloc {
    [self doneWithBody];
    if (multipartData)
        [multipartData release];
    [super dealloc];
}


@end