//
//  CompletionLabel.h
//  Frotz
//
//  Created by Craig Smith on 3/7/10.
//  Copyright 2010 Craig Smith. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "WordSelectionProtocol.h"


@interface CompletionLabel : UIView <WordSelection> {
    UILabel *m_label;
}
-(void)setOrigin:(CGPoint)origin;
-(CompletionLabel*)initWithFont:(UIFont*)font NS_DESIGNATED_INITIALIZER;
@property (nonatomic, copy) NSString *text;
-(void)setFont:(UIFont *)font;
-(void)autoSize;
@end
