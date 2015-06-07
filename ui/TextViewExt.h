/*
 *  TextViewExt.h
 *  Frotz
 *
 *  Created by Craig Smith on 8/6/08.
 *  Copyright 2008 Craig Smith. All rights reserved.
 *
 */

@interface UITextView (priv)
-(void)setContentToHTMLString:(NSString*)html;
#if !UseRichTextView
-(NSString*)contentAsHTMLString;
-(void)setSelectionToEnd;
-(CGRect)rectForSelection:(NSRange)range;
-(CGRect)visibleRect;
-(NSRange)selectedRange;
#endif
@end

@interface UITextField (priv)
-(BOOL)keyboardInput:(id)sender shouldInsertText:(NSString*)text isMarkedText:(BOOL)imt;
-(BOOL)keyboardInputShouldDelete:(id)sender;
@end

@interface UIAnimator
+(UIAnimator*)sharedAnimator;
-(void)removeAnimationsForTarget:(id)target;
@end

void removeAnim(UIView *view);