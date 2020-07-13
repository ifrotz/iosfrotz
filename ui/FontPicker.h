//
//  FontPicker.h
//  Frotz
//
//  Created by Craig Smith on 9/6/08.
//  Copyright 2008 Craig Smith. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FrotzFontDelegate <NSObject>
-(void) setFont: (nullable NSString*)fontName withSize:(NSInteger)size;
-(void) setFont: (nullable UIFont*)font;
@property (nonatomic, readonly, copy) NSString *fontName;
@property (nonatomic, copy) NSString *fixedFont;
@property (nonatomic, readonly) NSInteger fontSize;
@end

@interface FrotzFontInfo : NSObject {
    NSString *family;
    NSString *fontName;
    UIFont *font;
}
-(instancetype)initWithFamily:(NSString*)aFamily fontName:(NSString*)aFont font:(UIFont*)aFont NS_DESIGNATED_INITIALIZER;
-(instancetype)init NS_UNAVAILABLE;

@property(nonatomic,strong) NSString *family;
@property(nonatomic,strong) NSString *fontName;
@property(nonatomic,strong) UIFont *font;
@end

@protocol FrotzFontPicker <NSObject>
@property (nonatomic, weak) id<FrotzFontDelegate> delegate;
@property (nonatomic, assign) BOOL fixedFontsOnly;
@end

typedef UIViewController<FrotzFontPicker> FrotzFontPickerController;
@interface FontPicker : NSObject {
}
+(FrotzFontPickerController*)frotzFontPicker;
@end


NS_ASSUME_NONNULL_END

