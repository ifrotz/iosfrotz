
#import "DisplayCell.h"

// table view cell content offsets
#define kCellLeftOffset      8.0
#define kCellTopOffset      12.0

#define kCellHeight	    25.0

// cell identifier for this custom cell
NSString *kDisplayCell_ID = @"DisplayCell_ID";

@implementation DisplayCell

@synthesize nameLabel;
@synthesize view;

- (id)initWithFrame:(CGRect)aRect reuseIdentifier:(NSString *)identifier
{
    if ((self = [super initWithFrame:aRect reuseIdentifier:identifier]))
    {
        // turn off selection use
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        
        nameLabel = [[UILabel alloc] initWithFrame:aRect];
        nameLabel.backgroundColor = [UIColor clearColor];
        nameLabel.opaque = NO;
        nameLabel.textColor = [UIColor blackColor];
        nameLabel.highlightedTextColor = [UIColor blackColor];
        nameLabel.font = [UIFont boldSystemFontOfSize:18];
        [self.contentView addSubview:nameLabel];
    }
    return self;
}

- (void)setView:(UIView *)inView
{
    if (view) {
        [view removeFromSuperview];
    }
    view = inView;
    if (inView) {
        [self.contentView addSubview:inView];
        [self.contentView bringSubviewToFront:inView];
    }
    [self layoutSubviews];
}

- (void)layoutSubviews
{	
    [super layoutSubviews];
    CGRect contentRect = [self.contentView bounds];
	
    // In this example we will never be editing, but this illustrates the appropriate pattern
    CGRect frame = CGRectMake(contentRect.origin.x + kCellLeftOffset, kCellTopOffset, contentRect.size.width, kCellHeight);
    nameLabel.frame = frame;
	
    if ([view isKindOfClass:[UIPageControl class]])
    {
        // special case UIPageControl since its width changes after its creation
        CGRect frame = self.view.frame;
        frame.size.width = kPageControlWidth;
        self.view.frame = frame;
    }
    
    CGRect uiFrame = CGRectMake(contentRect.size.width - self.view.bounds.size.width - kCellLeftOffset,
                                round((contentRect.size.height - self.view.bounds.size.height) / 2.0),
                                self.view.bounds.size.width, self.view.bounds.size.height);
    view.frame = uiFrame;
}


- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];
    
    // when the selected state changes, set the highlighted state of the lables accordingly
    nameLabel.highlighted = selected;
}

@end
