// Cleanup.h
// 
// Cleanup of UIKit headers
#include <UIKit/UITextView.h>
#include <UIKit/UIView.h>

@interface UITextView (CleanWarnings)
-(UIView*) webView;
@end

@interface UIView (CleanWarnings)
- (void) moveToEndOfDocument:(id)inVIew;
- (void) insertText: (id)ourText;
@end

