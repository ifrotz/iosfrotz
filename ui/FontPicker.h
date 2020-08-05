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
@property (nonatomic, readonly) UIFont *font;
@property (nonatomic, readonly, copy) NSString *fontName;
@property (nonatomic, copy) NSString *fixedFont;
@property (nonatomic, readonly) NSInteger fontSize;
@end

@protocol FrotzFontPicker <NSObject>
@property (nonatomic, weak) id<FrotzFontDelegate> delegate;
@property (nonatomic, readonly, assign) BOOL fixedFontsOnly;
@end

typedef UIViewController<FrotzFontPicker> FrotzFontPickerController;

@interface FontPicker : NSObject {
}
+(UIViewController<FrotzFontPicker>*) frotzFontPickerWithTitle:(nullable NSString*)title includingFaces:(BOOL)includeFaces monospaceOnly:(BOOL)monospaceOnly;
+(FrotzFontPickerController*)frotzFontPicker;
@end

NS_ASSUME_NONNULL_END

