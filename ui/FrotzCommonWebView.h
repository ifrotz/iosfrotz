/*
 *  FrotzCommonWebView.h
 *  Frotz
 *
 *  Created by Craig Smith on 3/16/10.
 *  Copyright 2010 Craig Smith. All rights reserved.
 *
 */

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import "iosfrotz.h"

typedef WKWebView FrotzWebView;

@interface FrotzCommonWebViewController : UIViewController

+(nonnull FrotzWebView*)sharedWebView;
+(void)releaseSharedWebView;
@end
