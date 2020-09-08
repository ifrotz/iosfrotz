//
//  ReleaseNotes.h
//  Frotz
//
//  Created by Craig Smith on 8/29/08.
//  Copyright 2008 Craig Smith. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "FrotzCommonWebView.h"

NS_ASSUME_NONNULL_BEGIN

@interface ReleaseNotes : FrotzCommonWebViewController {
    NSObject *m_controller;
    NSURLRequest *m_request;
    NSURLConnection *m_connection;
    NSMutableData *m_data;
    NSString *m_relNotesPath;
    UIButton *m_rateButton;
}
- (instancetype)init NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)aDecoder NS_UNAVAILABLE;
- (void)updateReleaseNotes:(BOOL)force;
- (void)updateReleaseNotesAuto;
- (void)showReleaseNotes;
- (void)loadView;
- (void)rateFrotz;
@end

NS_ASSUME_NONNULL_END
