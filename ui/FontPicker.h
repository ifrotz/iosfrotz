//
//  FontPicker.h
//  Frotz
//
//  Created by Craig Smith on 9/6/08.
//  Copyright 2008 Craig Smith. All rights reserved.
//

#import <UIKit/UIKit.h>

@protocol FrotzFontDelegate
-(void) setFont: (NSString*)font withSize:(NSInteger)size;
-(void) setFixedFont: (NSString*)font;
-(NSMutableString*) font;
-(NSMutableString*) fixedFont;
-(NSInteger) fontSize;
@end

@interface FrotzFontInfo : NSObject {
    NSString *family;
    NSString *fontName;
    UIFont *font;
}
-(instancetype)initWithFamily:(NSString*)aFamily fontName:(NSString*)aFont font:(UIFont*)aFont NS_DESIGNATED_INITIALIZER;

@property(nonatomic,strong) NSString *family;
@property(nonatomic,strong) NSString *fontName;
@property(nonatomic,strong) UIFont *font;
@end

@interface FontPicker : UITableViewController {
    NSMutableArray *m_fonts;
    NSMutableArray *m_fixedFonts;
    NSObject<FrotzFontDelegate> *m_delegate;
    BOOL m_fixedFontsOnly;
}
- (instancetype)init;
- (void)setDelegate:(NSObject<FrotzFontDelegate>*)delegate;
- (void)setFixedFontsOnly:(BOOL)fixed;
@end
