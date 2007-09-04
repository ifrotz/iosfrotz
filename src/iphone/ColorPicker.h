#import <UIKit/UIView-Hierarchy.h>
#import <UIKit/UIView-Rendering.h>
#import <UIKit/UIView-Geometry.h>
#import <UIKit/CDStructures.h>
#import <UIKit/UIImage.h>
#import <UIKit/UIImageView.h>
#import <CoreSurface/CoreSurface.h>

@class HSVPicker, HSVValuePicker, ColorTile;

@interface ColorPicker : UIView {
    HSVPicker *m_hsvPicker;
    HSVValuePicker *m_valuePicker;
    ColorTile *m_colorTile;
    UIView *m_background;
    UIView *m_tileBorder;
    UIImageView *m_hsvCursor;
    UIImageView *m_valueCursor;
    float m_hue;
    float m_saturation;
    float m_value;
    id m_delegate;
    CGRect m_rect;
    CGColorSpaceRef m_colorSpace;

    struct CGColor *m_color;
}
- (id)initWithFrame:(CGRect)frame;
- (void)dealloc;
- (CGColorSpaceRef)colorSpace;
- (void) setColor: (struct CGColor *)color;
- (struct CGColor *)color;
- (float*)hue;
- (float*)saturation;
- (float*)value;
- (HSVPicker *)hsvPicker;
- (HSVValuePicker *)valuePicker;
- (ColorTile *)colorTile;
- (id)delegate;
- (void)setDelegate: (id)delegate;
@end
