//
//  StoryDetailsController.h
//
//  Created by Craig Smith on 9/11/10.
//  Copyright 2010 Craig Smith. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#import "StoryBrowser.h"

@class StoryDetailsController;

@interface FrotzImageView : UIImageView  <UIAlertViewDelegate>
{
    StoryDetailsController *m_detailsController;
    NSTimer *m_tapTimer;
    CGRect m_savedBounds;
}
-(void)displayMenu;
-(BOOL)isMagnified;
-(void)magnifyImage:(BOOL)toggle;
-(void)doPaste;
@property (nonatomic,assign) StoryDetailsController *detailsController;
@end

@interface StoryDetailsController : UIViewController <UIScrollViewDelegate, UITextFieldDelegate, UIActionSheetDelegate> {

    IBOutlet UITextField *m_titleField;
    IBOutlet UITextField *m_authorField;
    IBOutlet UITextField *m_TUIDField;
    IBOutlet FrotzImageView *m_artworkView;
    IBOutlet UIView *m_flipper;
    IBOutlet UIWebView *m_descriptionWebView;
    IBOutlet UIButton *m_infoButton;
    IBOutlet UIButton *m_ifdbButton;
    IBOutlet UIButton *m_playButton;
    IBOutlet UILabel *m_artworkLabel;
    IBOutlet UIView *m_portraitCover;
    IBOutlet UILabel *m_portraitCoverLabel;
    IBOutlet UIView *m_contentView;
    IBOutlet UIButton *m_restartButton;

    BOOL m_willResume;

    NSString *m_title, *m_author, *m_tuid, *m_descriptionHTML;
    StoryInfo *m_storyInfo;
    UIImage *m_artwork;

    StoryBrowser *m_browser;
    FrotzInfo *m_frotzInfoController;
    
    CGSize m_artSizeLandscape, m_artSizePortrait;
}

-(IBAction) toggleArtDescript;
-(void)clear;
-(void)refresh;
-(void)updateSelectionInstructions:(BOOL)hasPopover;
-(BOOL)keyboardIsActive;
-(void)dimArtwork:(BOOL)dim;
-(IBAction)playButtonPressed;
-(IBAction)IFDBButtonPressed;
-(IBAction)dismissKeyboard;
-(IBAction)showRestartMenu;

@property(nonatomic,assign) StoryBrowser* storyBrowser;
@property(nonatomic,retain) NSString* storyTitle;
@property(nonatomic,retain) NSString* author;
@property(nonatomic,retain) NSString* descriptionHTML;
@property(nonatomic,retain) StoryInfo* storyInfo;
@property(nonatomic,retain,setter=setTUID:) NSString* tuid;
@property(nonatomic,retain) UIImage* artwork;
@property(nonatomic,retain) UIView* contentView;
@property(nonatomic,retain) UIWebView* descriptionWebView;
@property(nonatomic,retain) UIView* flipper;
@property(nonatomic,retain) UIView* infoButton;
@property(nonatomic,assign) BOOL willResume;

@end
