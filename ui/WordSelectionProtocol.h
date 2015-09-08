/*
 *  WordSelectionProtocol.h
 *  Frotz
 *
 *  Created by Craig Smith on 3/8/10.
 *  Copyright 2010 Craig Smith. All rights reserved.
 *
 */

#import <UIKit/UIFont.h>
#import <UIKit/UILabel.h>

@protocol WordSelection <NSObject>
-(void)setFont:(UIFont*)font;
@end

@interface UILabelWA : UILabel <WordSelection> { }
@end
