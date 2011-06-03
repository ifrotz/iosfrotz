/*
 *  WordSelectionProtocol.h
 *  Frotz
 *
 *  Created by Craig Smith on 3/8/10.
 *  Copyright 2010 Craig Smith. All rights reserved.
 *
 */


@protocol WordSelection
-(void)setFont:(UIFont*)font;
@end

@interface UILabelWA : UILabel <WordSelection> { }
@end
