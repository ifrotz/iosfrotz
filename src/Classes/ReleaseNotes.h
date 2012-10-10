//
//  ReleaseNotes.h
//  Frotz
//
//  Created by Craig Smith on 8/29/08.
//  Copyright 2008 Craig Smith. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "FrotzCommonWebView.h"


@interface ReleaseNotes : FrotzCommonWebViewController {
    NSObject *m_controller;
    NSURLRequest *m_request;
    NSMutableData *m_data;
    NSString *m_relNotesPath;
}
- (id)init;
- (void)updateReleaseNotes:(BOOL)force;
- (void)updateReleaseNotesAuto;
- (void)showReleaseNotes;
@end
