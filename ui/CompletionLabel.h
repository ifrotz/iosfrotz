//
//  CompletionLabel.h
//  Frotz
//
//  Created by Craig Smith on 3/7/10.
//  Copyright 2010 Craig Smith. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "WordSelectionProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface CompletionLabel : UIView <WordSelection> {
    UILabel *m_label;
}
-(void)setOrigin:(CGPoint)origin;
-(instancetype)initWithFont:(UIFont*)font NS_DESIGNATED_INITIALIZER;
-(nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
-(instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;
@property (nullable, nonatomic, copy) NSString *text;
-(void)setFont:(UIFont *)font;
-(void)autoSize;
@end

NS_ASSUME_NONNULL_END