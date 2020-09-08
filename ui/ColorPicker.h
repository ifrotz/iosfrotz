
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
    CGFloat m_hue;
    CGFloat m_saturation;
    CGFloat m_value;
    id<ColorPickerDelegate> __weak m_delegate;
    CGColorSpaceRef m_colorSpace;

    UIColor *m_textColor, *m_bgColor;
    BOOL m_changeTextColor;
}
- (instancetype)init;
@property (nonatomic, readonly) CGColorSpaceRef colorSpace CF_RETURNS_NOT_RETAINED;
- (void)setTextColor:(UIColor*)textColor bgColor:(UIColor*)bgColor changeText:(BOOL)changeTextColor;
- (void)setColor: (UIColor *)color;
- (void)setColorOnly: (UIColor *)color; // doesn't update cursors or callback delegate
- (void)setColorValue: (UIColor*)color;
- (void)updateColorWithHue:(CGFloat)hue Saturation:(CGFloat)saturation Value:(CGFloat)value;
- (void)updateHSVCursors;
- (void)toggleMode;
@property (nonatomic, getter=isTextColorMode, readonly) BOOL textColorMode;
@property (nonatomic, readonly, copy) UIColor *textColor;
@property (nonatomic, readonly, copy) UIColor *bgColor;
@property (nonatomic, readonly) CGFloat hue;
@property (nonatomic, readonly) CGFloat saturation;
@property (nonatomic, readonly) CGFloat value;
@property (nonatomic, readonly, strong) HSVPicker *hsvPicker;
@property (nonatomic, readonly, strong) HSVValuePicker *valuePicker;
@property (nonatomic, readonly, strong) ColorTile *colorTile;
@property (nonatomic, weak) id<ColorPickerDelegate> delegate;
- (void)updateAccessibility;
@end

