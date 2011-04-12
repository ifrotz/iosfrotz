
#import <UIKit/UIKit.h>

@class HSVPicker, HSVValuePicker, ColorTile, ColorPicker;

@protocol ColorPickerDelegate <NSObject>
-(void)colorPicker:(ColorPicker*)picker selectedColor:(UIColor*)color;
-(UIFont*)fontForColorDemo;
@end

@interface ColorPicker : UIViewController {
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
    id<ColorPickerDelegate> m_delegate;
    CGColorSpaceRef m_colorSpace;

    UIColor *m_textColor, *m_bgColor;
    BOOL m_changeTextColor;
}
- (id)init;
- (void)dealloc;
- (CGColorSpaceRef)colorSpace;
- (void)setTextColor:(UIColor*)textColor bgColor:(UIColor*)bgColor changeText:(BOOL)changeTextColor;
- (void)setColor: (UIColor *)color;
- (void)setColorOnly: (UIColor *)color; // doesn't update cursors or callback delegate
- (void)setColorValue: (UIColor*)color;
- (void)updateColorWithHue:(float)hue Saturation:(float)saturation Value:(float)value;
- (void)updateHSVCursors;
- (void)toggleMode;
- (BOOL)isTextColorMode;
- (UIColor *)textColor;
- (UIColor *)bgColor;
- (float)hue;
- (float)saturation;
- (float)value;
- (HSVPicker *)hsvPicker;
- (HSVValuePicker *)valuePicker;
- (ColorTile *)colorTile;
- (id<ColorPickerDelegate>)delegate;
- (void)setDelegate: (id<ColorPickerDelegate>)delegate;
- (void)updateAccessibility;
@end

