//
//  AboutFrotz.h
//  Frotz
//
//  Created by Craig Smith on 8/29/08.
//  Copyright 2008 Craig Smith. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "FrotzCommonWebView.h"

NS_ASSUME_NONNULL_BEGIN

@interface AboutFrotz : FrotzCommonWebViewController
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
@end

NS_ASSUME_NONNULL_END
