//
//  FrotzView.h
//  Frotz
//
//  Created by Craig Smith on 2/9/10.
//  Copyright 2010 Craig Smith. All rights reserved.
//

#define UseRichTextView 1

#if UseRichTextView

#import "RichTextView.h"
#import "StoryMainViewController.h"

@interface FrotzView : RichTextView
#else
@interface FrotzView : UITextView
#endif
{
    BOOL m_magnified;
    CGFloat m_origFontSize;
}
-(BOOL)handleMagnifyTouchWithPhase:(UITouchPhase)phase atPoint:(CGPoint) pt;
@end

@interface SavedTouch : NSObject {
    UITouchPhase phase;
    CGPoint pt;
}
@property(nonatomic,assign) UITouchPhase phase;
@property(nonatomic,assign) CGPoint pt;
-(id)initWithPhase:(UITouchPhase)phase point:(CGPoint)pt;
@end

