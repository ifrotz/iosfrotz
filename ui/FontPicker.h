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
-(void) setFont: (nullable NSString*)font withSize:(NSInteger)size;
@property (nonatomic, readonly, copy) NSString *font;
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

@interface FontPicker : UITableViewController {
    NSMutableArray *m_fonts;
    NSMutableArray *m_fixedFonts;
    id<FrotzFontDelegate> __weak m_delegate;
    BOOL m_fixedFontsOnly;
}
@property (nonatomic, weak) id<FrotzFontDelegate> delegate;
@property (nonatomic, assign) BOOL fixedFontsOnly;

- (instancetype)init;
@end

NS_ASSUME_NONNULL_END

