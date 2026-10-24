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

static FrotzWebView *sWebView;

+(FrotzWebView*)sharedWebView {
    if (!sWebView) {
        // Every presenter re-frames the shared view to its own view's frame before showing it.
        sWebView = [[FrotzWebView alloc] initWithFrame: CGRectZero];
        [sWebView setAutoresizingMask: UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth];
        sWebView.backgroundColor = [UIColor darkGrayColor];
    }
    return sWebView;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (@available(iOS 13.0,*)) {
        self.navigationController.navigationBar.scrollEdgeAppearance = self.navigationController.navigationBar.standardAppearance;
    }
}


+(void)releaseSharedWebView {
    sWebView = nil;
}

@end
