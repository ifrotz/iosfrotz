//
//  CompletionLabel.m
//  Frotz
//
//  Created by Craig Smith on 3/7/10.
//  Copyright 2010 Craig Smith. All rights reserved.
//

#import "CompletionLabel.h"


@implementation CompletionLabel


-(CompletionLabel*)initWithFont:(UIFont*)font {
    if ((self = [super init])) {
        [self setBackgroundColor: [UIColor colorWithWhite:1.0 alpha:0.0]];
        m_label = [[UILabel alloc] init];
        [m_label setFont: font];
        [self setText: @""];
        [m_label setTextColor: [UIColor blueColor]];
        [m_label setShadowColor: [UIColor darkGrayColor]];
        [m_label setBackgroundColor: [UIColor whiteColor]];
        [self addSubview: m_label];
    }
    return self;
}

- (void) drawRect:(CGRect)rect {
    [super drawRect: rect];

    CGRect frame = [m_label frame];
    CGContextRef context = UIGraphicsGetCurrentContext();
    [[UIColor redColor] set];
    CGContextBeginPath(context);
    CGFloat spacer = [@"xx" sizeWithFont: [m_label font]].width;

    CGContextSetLineWidth(context, 1);
    for (int i =0; i < 2; ++i) {
	CGFloat shadowOff = i ? 0.0 : 3.0;
	if (i) {
	    CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, 1.0);
	    CGContextSetRGBStrokeColor(context, 0.8, 0.8, 1.0, 1.0);
	    CGContextMoveToPoint(context, frame.size.width + spacer, 0);
	    CGContextAddLineToPoint(context, 0, 0);
	    CGContextAddLineToPoint(context, 0, frame.size.height+1);
	    CGContextAddLineToPoint(context, frame.size.width+spacer, frame.size.height+1);
	    CGContextClosePath(context);
	    CGContextDrawPath(context, kCGPathFillStroke);
	} else {
	    CGContextSetRGBFillColor(context, 0.1, 0.1, 0.15, 0.05);
	    CGContextSetRGBStrokeColor(context, 0.1, 0.1, 0.15, 0.0);
	}
	CGContextBeginPath(context);
	CGContextMoveToPoint(context, frame.size.width+spacer-1 + shadowOff, frame.size.height/2 + shadowOff);
	CGContextAddArc(context, frame.size.width+spacer-1 + shadowOff, (frame.size.height+1)/2.0 + shadowOff, (frame.size.height+1)/2.0, M_PI_2,  M_PI+M_PI_2, true);
	CGContextDrawPath(context, kCGPathFillStroke);
	CGContextBeginPath(context);
	if (i)
	    CGContextAddRect(context, CGRectMake(frame.size.width, 1, spacer, frame.size.height));
	else 
	    CGContextAddRect(context, CGRectMake(shadowOff, 1 + shadowOff, frame.size.width + spacer - 1, frame.size.height));
	CGContextFillPath(context);
    }

    CGContextBeginPath(context);
    CGContextSetLineCap(context, kCGLineCapRound);
    CGContextSetLineWidth(context, 2);
    CGContextSetRGBStrokeColor(context, 0.5, 0.5, 0.5, 1.0);

    CGFloat xWidth = (frame.size.height+1)/4.0;
    if (frame.size.height <= 12)
	xWidth = 3;
    CGFloat x = frame.size.width + 2 + xWidth + (xWidth > 3), y = frame.size.height/2 - xWidth/2 + 1;
    CGContextMoveToPoint(context, x, y);
    CGContextAddLineToPoint(context, x+xWidth, y+xWidth);
    CGContextDrawPath(context, kCGPathStroke);
    CGContextMoveToPoint(context, x+xWidth, y);
    CGContextAddLineToPoint(context, x, y+xWidth);
    CGContextDrawPath(context, kCGPathStroke);
}

-(void)setOrigin:(CGPoint)origin {
    CGRect frame = [self frame];
    frame.origin = origin;
    [self setFrame: frame];
}

-(NSString*)text {
    return [m_label text];
}

-(void)setFont:(UIFont *)font {
    [m_label setFont: font];
    [self autoSize];
}

-(void)autoSize {
    NSString *text = [self text];
    if (text) {
        UIFont *font = [m_label font];
        CGSize textSize = [text sizeWithFont: font];
        CGSize spacer = [@"xx" sizeWithFont: font];
        CGRect labelFrame = CGRectMake(3, 1, textSize.width, textSize.height-1);
        CGRect frame = [self frame];
        frame.size = CGSizeMake(textSize.width+spacer.width+12, textSize.height+6);
        [self setFrame: frame];
        [self setNeedsDisplay];
        [m_label setFrame: labelFrame];
    } else {
        [self setFrame: CGRectZero];
        [m_label setFrame: CGRectZero];
    }
}

-(void)setText:(NSString*)text {
    [m_label setText: text];
    [self autoSize];
}

-(void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event	{
    [m_label setText: nil];
    [self removeFromSuperview];
}

-(void)touchEnded:(NSSet *)touches withEvent:(UIEvent *)event{
    [m_label setText: nil];
    [self removeFromSuperview];
}

-(void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [m_label setText: nil];
    [self removeFromSuperview];
}



@end
