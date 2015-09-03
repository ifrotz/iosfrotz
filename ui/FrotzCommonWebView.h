/*
 *  FrotzCommonWebView.h
 *  Frotz
 *
 *  Created by Craig Smith on 3/16/10.
 *  Copyright 2010 Craig Smith. All rights reserved.
 *
 */

#import <UIKit/UIKit.h>

@interface FrotzCommonWebViewController : UIViewController

+(nonnull UIWebView*)sharedWebView;
+(void)releaseSharedWebView;
@end
