//
//  FontPicker.h
//  Frotz
//
//  Created by Craig Smith on 9/6/08.
//  Copyright 2008 Craig Smith. All rights reserved.
//

#import <UIKit/UIKit.h>

@protocol FrotzFontDelegate
-(void) setFont: (NSString*)font withSize:(int)size;
-(void) setFixedFont: (NSString*)font;
-(NSMutableString*) font;
-(NSMutableString*) fixedFont;
-(int) fontSize;
@end

@interface FrotzFontInfo : NSObject {
    NSString *family;
    NSString *fontName;
    UIFont *font;
}
-(instancetype)initWithFamily:(NSString*)aFamily fontName:(NSString*)aFont font:(UIFont*)aFont NS_DESIGNATED_INITIALIZER;

@property(nonatomic,retain) NSString *family;
@property(nonatomic,retain) NSString *fontName;
@property(nonatomic,retain) UIFont *font;
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
