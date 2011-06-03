/*
 *  FrotzCommonWebView.m
 *  Frotz
 *
 *  Created by Craig Smith on 3/16/10.
 *  Copyright 2010 Craig Smith. All rights reserved.
 *
 */

#include "FrotzCommonWebView.h"

@implementation FrotzCommonWebViewController

static UIWebView *sWebView;

+(UIWebView*)sharedWebView {
    if (!sWebView) {
	sWebView = [[UIWebView alloc] initWithFrame: CGRectZero];
	[sWebView setAutoresizingMask: UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth];
	sWebView.backgroundColor = [UIColor darkGrayColor];
    }
    return sWebView;
}

+(void)releaseSharedWebView {
    if (sWebView)
	[sWebView release];
    sWebView = nil;
}

@end
