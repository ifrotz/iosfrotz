#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import "ColorPicker.h"
#import "iphone_frotz.h"

@interface ColorPickerView : UIView 
{
    int m_width;
    int m_height;
//    CALayer *m_screenLayer;
//    CoreSurfaceBufferRef m_screenSurface;
}

- (id)initWithFrame:(CGRect)frame;
- (void)dealloc;
- (int)width;
- (int)height;
@end

@interface ColorTile: UIView {
    ColorPicker *m_colorPicker;
    UILabel *m_text;
    UIImage *m_flipFgImg, *m_flipBgImg;
    UIImageView *m_imgView;
}
- (id) initWithFrame:(CGRect)frame withColorPicker: colorPicker;
- (void) setFrame:(CGRect)frame;
- (void) setTextColor: (UIColor *)color;
- (void) setBGColor: (UIColor *)color;
- (UILabel*) textLabel;
@end

@interface HSVValuePicker : ColorPickerView {
    ColorPicker *m_colorPicker;
    int m_leftMargin;
    int m_barWidth;
    CGImageRef m_imageRef;
}
- (id) initWithFrame:(CGRect)frame withColorPicker: colorPicker;
- (void)drawRect:(CGRect)rect;
- (void)setLeftMargin: (int)margin;
- (void)setBarWidth : (int)width;
- (int)barWidth;
- (void)mousePositionToValue:(CGPoint)point;
- (void)touchesBegan:(NSSet*)touches withEvent:(UIEvent*)event;
- (void)touchesEnded:(NSSet*)touches withEvent:(UIEvent*)event;
- (void)touchesMoved:(NSSet*)touches withEvent:(UIEvent*)event;
- (void)touchesCancelled:(NSSet*)touches withEvent:(UIEvent*)event;
@end


@interface HSVPicker : ColorPickerView {
    ColorPicker *m_colorPicker;
    CGImageRef m_imageRef;
    unsigned int *m_hsvData;
}
- (id) initWithFrame:(CGRect)frame withColorPicker: colorPicker;
- (unsigned int *)hsvData;
- (void)dealloc;
- (void)drawRect:(CGRect)rect;
- (void)mousePositionToColor:(CGPoint)point;
- (void)touchesBegan:(NSSet*)touches withEvent:(UIEvent*)event;
- (void)touchesEnded:(NSSet*)touches withEvent:(UIEvent*)event;
- (void)touchesMoved:(NSSet*)touches withEvent:(UIEvent*)event;
- (void)touchesCancelled:(NSSet*)touches withEvent:(UIEvent*)event;
@end

@implementation ColorPickerView 
- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])!=nil) {
        m_width = frame.size.width;
	m_height = frame.size.height;
    }
    return self;
}

- (void)setFrame:(CGRect)frame {
    [super setFrame: frame];
    m_width = frame.size.width;
    m_height = frame.size.height;
}

- (void)dealloc {
//    [m_screenLayer release];
    [super dealloc];
}

- (int)width {
    return m_width;
}

- (int)height {
    return m_height;
}
@end


@implementation ColorTile

- (id) initWithFrame:(CGRect)frame withColorPicker: colorPicker {
    if ((self = [super initWithFrame: frame]) != nil) {
	m_colorPicker = colorPicker;
	self.autoresizesSubviews = YES;
	m_text = [[UILabel alloc] initWithFrame: CGRectMake(5, 5, frame.size.width-5, frame.size.height-10)];
	m_text.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
	m_text.lineBreakMode = UILineBreakModeWordWrap;
	m_text.backgroundColor = [UIColor clearColor];
	UIFont *font = [[m_colorPicker delegate] fontForColorDemo];
	if (font)
	    m_text.font = font;
	m_text.text = @"West of House\nThis is an open field west of a white house, with a boarded front door.\nThere is a small mailbox here.\n";
	m_text.numberOfLines = 0;
	[self addSubview: m_text];
	m_flipFgImg = [[UIImage imageNamed: @"colorflipfg.png"] retain];
	m_flipBgImg = [[UIImage imageNamed: @"colorflipbg.png"] retain];
	m_imgView = [[UIImageView alloc] initWithImage: m_flipFgImg];
	m_imgView.frame=CGRectMake(frame.size.width - m_flipFgImg.size.width - 1, frame.size.height - m_flipFgImg.size.height-1, m_flipFgImg.size.width, m_flipFgImg.size.height);
	m_imgView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleTopMargin;
	[self addSubview: m_imgView];
	[m_text sizeToFit];
   }
   return self;
}

-(void) touchesBegan:(NSSet*)touches withEvent:(UIEvent*)event
{
}

- (void) touchesEnded:(NSSet*)touches withEvent:(UIEvent*)event
{
    UITouch* touch = [touches anyObject];
    CGPoint pt =[touch locationInView: self];
    if (pt.y > self.bounds.origin.y + self.bounds.size.height*0.6
	&& pt.x > self.bounds.origin.x + self.bounds.size.width*0.8) {
	[m_colorPicker toggleMode];
	m_imgView.image = [m_colorPicker isTextColorMode] ? m_flipFgImg : m_flipBgImg;
    }
}

- (void)touchesCancelled:(NSSet*)touches withEvent:(UIEvent*)event {
}

- (UILabel*) textLabel {
    return m_text;
}

- (void) setFrame:(CGRect)frame {
    [super setFrame:frame];
    m_text.frame = CGRectMake(5, 5, frame.size.width-5, frame.size.height-10);
    UIFont *font = [[m_colorPicker delegate] fontForColorDemo];
    if (font)
	m_text.font = font;
}

- (void)setTextColor:(UIColor*)textColor {
    m_text.textColor = textColor;
}

- (void)setBGColor:(UIColor*)bgColor {
   self.backgroundColor = bgColor;
}

-(void)viewDidUnload {
    [m_text release];
    m_text = nil;
    [m_imgView release];
    m_imgView = nil;
    [m_flipFgImg release];
    [m_flipBgImg release];
    m_flipFgImg = nil;
    m_flipBgImg = nil;
}

-(void)dealloc {
    [m_text release];
    m_text = nil;
    [m_imgView release];
    m_imgView = nil;
    [m_flipFgImg release];
    [m_flipBgImg release];
    m_flipFgImg = nil;
    m_flipBgImg = nil;
    [super dealloc];
}

@end

void RGBtoHSV(float r, float g, float b, float *h, float *s, float *v)
{
    float min, max, delta;
    min = r;
    if (g < min)
        min = g;
    if (b < min)
        min = b;
    max = r;
    if (g > max)
        max = g;
    if (b > max)
        max = b;
    *v = max;				// v
    delta = max - min;
    if(max != 0.0f)
        *s = delta / max;		// s
    else { // r,g,b= 0			// s = 0, v is undefined
        *s = 0.0f;
        *h = 0.0f; // really -1,
        return;
    }
    if(r == max)
        *h = (g - b) / delta;		// between yellow & magenta
    else if(g == max)
        *h = 2.0f + (b - r) / delta;	// between cyan & yellow
    else
        *h = 4.0f + (r - g) / delta;	// between magenta & cyan
    *h /= 6.0f;				// 0 -> 1
    if(*h < 0.0f)
        *h += 1.0f;
}

void HSVtoRGB(float *r, float *g, float *b, float h, float s, float v)
{
    float f, p, q, t;
    if(s == 0) { // grey
	*r = *g = *b = v;
	return;
    }
    if (h < 0.0f)
	h = 0.0f;
    h *= 6.0f;
    int sector = ((int)h) % 6;
    f = h - (float)sector;			// factorial part of h
    p = v * (1 - s);
    q = v * (1 - s * f);
    t = v * (1 - s * (1-f));
    switch(sector) {
	case 0: default:
	    *r = v; *g = t; *b = p;
	    break;
	case 1:
	    *r = q; *g = v; *b = p;
	    break;
	case 2:
	    *r = p; *g = v; *b = t;
	    break;
	case 3:
	    *r = p; *g = q; *b = v;
	    break;
	case 4:
	    *r = t; *g = p; *b = v;
	    break;
	case 5:
	    *r = v; *g = p; *b = q;
	    break;
    }
}


@implementation HSVValuePicker

- (id) initWithFrame:(CGRect)frame withColorPicker: colorPicker {
    [super initWithFrame: frame];
    m_colorPicker = colorPicker;
    return self;
}

- (void)setLeftMargin: (int)margin {
    m_leftMargin = margin;
}

- (void)setBarWidth : (int)width {
    m_barWidth = width;
}

-(int)barWidth {
    return m_barWidth;
}

-(void)mousePositionToValue:(CGPoint)point {
    int y = (int)point.y;
	if (y < 0)
		y = 0;
	else if (y >= m_height)
		y = m_height;
    float value = 1.0f - (float)y / (float)m_height;
    
    float rgba[4] = {0.0, 0.0, 0.0, 1.0};
    UIColor *color;
    
    float hue, saturation;
    
    hue = [m_colorPicker hue];
    saturation = [m_colorPicker saturation];
    HSVtoRGB(&rgba[0], &rgba[1], &rgba[2], hue, saturation, value);

    color = [UIColor colorWithRed:rgba[0] green:rgba[1] blue:rgba[2] alpha:rgba[3]];
    [m_colorPicker setColorValue: color]; // hue and sat didn't change, so force them constant even if color is black or white
}

- (void)touchesBegan:(NSSet*)touches withEvent:(UIEvent*)event
{
    UITouch* touch = [touches anyObject];
    [self mousePositionToValue: [touch locationInView: self]];
}

- (void) touchesEnded:(NSSet*)touches withEvent:(UIEvent*)event
{
    UITouch* touch = [touches anyObject];
    [self mousePositionToValue: [touch locationInView: self]];
}

- (void)touchesCancelled:(NSSet*)touches withEvent:(UIEvent*)event {
}

- (void) touchesMoved:(NSSet*)touches withEvent:(UIEvent*)event
{
    UITouch* touch = [touches anyObject];
    [self mousePositionToValue: [touch locationInView: self]];
}


- (void)drawRect:(CGRect)rect {
    void *bitmapData = NULL;
    if (!m_imageRef) {
	int x, y, i = 0, j;
	float r, g, b;
	float h, s, v;

	CGContextRef    bmcontext = NULL;
	CGColorSpaceRef colorSpace;
	int             bitmapByteCount;
	int             bitmapBytesPerRow;

	int pixelsWide = m_width, pixelsHigh = m_height;
	bitmapBytesPerRow   = (pixelsWide * 4);
	bitmapByteCount     = (bitmapBytesPerRow * pixelsHigh);

	colorSpace = CGColorSpaceCreateDeviceRGB();
	if (colorSpace == NULL) {
	    NSLog(@"Error allocating color space\n");
	    return;
	}

	bitmapData = malloc(bitmapByteCount);

	if (bitmapData == NULL) {
	    NSLog(@"BitmapContext memory not allocated!");
	    CGColorSpaceRelease(colorSpace);
	    return;
	}
	unsigned int *c = (unsigned int*)bitmapData;
	unsigned int wColor;

	h = [m_colorPicker hue];
	s = [m_colorPicker saturation]; // use full sat on color picker
	for (y=0; y < m_height; y++)
	{
	    for (x=0; x < m_leftMargin; x++)
		c[i++] = 0xffffffffUL;
	    v = (float)y / (float)m_height;
	    HSVtoRGB(&r, &g, &b, h, s, v);
	    // iPhone is little endian, want alpha last in memoryt
	    wColor = 0xff000000UL | (((int)(b * 255.0f) & 0xff) << 16) | (((int)(g * 255.0f) & 0xff) << 8) | (((int)(r * 255.0f) & 0xff));
	    for (j=0; j < m_barWidth; j++, x++)
		c[i++] = wColor;
	    for (; x < m_width; x++)
		c[i++] = 0xffffffffUL;
	}

	// Create the bitmap context. We want pre-multiplied ARGB, 8-bits
	// per component. Regardless of what the source image format is
	// (CMYK, Grayscale, and so on) it will be converted over to the format
	// specified here by CGBitmapContextCreate.
	bmcontext = CGBitmapContextCreate (bitmapData,
					pixelsWide,
					pixelsHigh,
					8,      // bits per component
					bitmapBytesPerRow,
					colorSpace,
					kCGImageAlphaPremultipliedLast);
	if (bmcontext == NULL){
	    free (bitmapData);
	    NSLog(@"Context not created!");
	}
	
	m_imageRef = CGBitmapContextCreateImage(bmcontext);

	// When finished, release the context
	CGContextRelease(bmcontext);

	// Make sure and release colorspace before returning
	CGColorSpaceRelease( colorSpace );
	// Free image data memory for the context
    }

    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextDrawImage(context, CGRectMake(0,0,m_width,m_height), m_imageRef);
    CGImageRelease(m_imageRef);
    free (bitmapData);
    m_imageRef = NULL;
}
@end

@implementation HSVPicker

- (id) initWithFrame:(CGRect)frame withColorPicker: colorPicker {
    [super initWithFrame: frame];

    m_colorPicker = colorPicker;
    [self setFrame: frame];

    return self;
}

- (void)setFrame:(CGRect)frame {
    if (m_hsvData) {
	if (m_width == frame.size.width && m_height == frame.size.height) {
	    [super setFrame: frame];
	    return;
	}
	free(m_hsvData);
    }

    [super setFrame: frame]; // sets m_width/m_height

    int dataSize = sizeof(unsigned int) * m_width * m_height;
    m_hsvData = (unsigned int*)malloc(dataSize);

    unsigned int *c;
    int x, y, i = 0;
    float h, s, v;

    c = m_hsvData;

    float cx = m_width / 2.0f;
    float cy = m_height / 2.0f;
    float radius, theta, dx, dy;
    v = 1.0f;

    for (y=m_height-1; y >= 0; y--)
    {
	for (x=0; x < m_width; x++) {
	    dx = x - cx;
	    dy = y - cy;
	    radius = sqrt(dx*dx + dy*dy);
	    if (dx == 0) {
		if (y > cy)
		    theta = M_PI + M_PI/2.0f;
		else
		    theta = M_PI/2.0f;
	    }
	    else {
		theta = M_PI - atan(dy/dx);
		if (x > cx) {
		    if (y > cy)
			theta += M_PI;
		    else
			theta -= M_PI;
		}
	    }
	    s = radius / (float)cx;
	    if (s <= 1.0f) {
		h = theta  / (2.0f * M_PI);
		c[i] = 0xff000000UL|(((((int)(h * 255.0f)) << 16) | (((int)(s * 255.0f)) << 8) | ((int)(v * 255.0f))));
	    } else
		c[i] = 0x00ffffffUL;
	    i++;
	}
    }
}

- (unsigned int *)hsvData {
    return m_hsvData;
}

- (void)drawRect:(CGRect)rect {
    int x, y, i = 0;
    float r, g, b;
    float h, s, v;

    unsigned int wColor, hsv;

    v = 1.0; //[m_colorPicker value];

    CGContextRef    bmcontext = NULL;
    CGColorSpaceRef colorSpace;
    void *          bitmapData;
    int             bitmapByteCount;
    int             bitmapBytesPerRow;

    int pixelsWide = m_width, pixelsHigh = m_height;
    bitmapBytesPerRow   = (pixelsWide * 4);
    bitmapByteCount     = (bitmapBytesPerRow * pixelsHigh);

    colorSpace = CGColorSpaceCreateDeviceRGB();
    if (colorSpace == NULL)
    {
	NSLog(@"Error allocating color space\n");
	return;
    }

    bitmapData = malloc(bitmapByteCount);

    if (bitmapData == NULL)
    {
	NSLog(@"BitmapContext memory not allocated!");
	CGColorSpaceRelease(colorSpace);
	return;
    }
    unsigned int *c = (unsigned int*)bitmapData;

    for (y=0; y < m_height; y++)
    {
	for (x=0; x < m_width; x++) {
	    hsv = m_hsvData[i];
	    
	    if ((hsv & 0xff000000UL)) {
		h = (float)((hsv & 0x00ff0000UL) >> 16) / 255.0f;
		s = (float)((hsv & 0x0000ff00UL) >> 8) / 255.0f;
		HSVtoRGB(&r, &g, &b, h, s, v);
	    
		wColor = 0xff000000UL | (((int)(b * 255.0f)) << 16) | (((int)(g * 255.0f)) << 8) | ((int)(r * 255.0f));
		c[i] = wColor;
	    } else
		c[i] = 0xffffffffUL;
	    i++;
	}
    }
    
    bmcontext = CGBitmapContextCreate (bitmapData,
				    pixelsWide,
				    pixelsHigh,
				    8,      // bits per component
				    bitmapBytesPerRow,
				    colorSpace,
				    kCGImageAlphaPremultipliedLast);
    if (bmcontext == NULL)
    {
	free (bitmapData);
	NSLog(@"Context not created!");
    }

    // Make sure and release colorspace before returning
    CGColorSpaceRelease( colorSpace );
    
    m_imageRef = CGBitmapContextCreateImage(bmcontext);

    // When finished, release the context
    CGContextRelease(bmcontext);

    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextDrawImage(context, CGRectMake(0,0,m_width,m_height), m_imageRef);
    CGImageRelease(m_imageRef);
    m_imageRef = NULL;
    free (bitmapData);

}

-(void)mousePositionToColor:(CGPoint)point {
    unsigned int *c = [self hsvData];    
    float rgba[4] = {0.0, 0.0, 0.0, 1.0};
    unsigned int color;
    unsigned int x = (int)point.x;
    unsigned int y = (int)point.y;
    if (x >= m_width) x = m_width - 1;
    if (y >= m_height) y = m_height - 1;

    color = c[(m_height-1-y) * m_width + x];

    float hue = (float)((color & 0xff0000) >> 16) / 255.0f;
    float saturation = (float)((color & 0xff00) >> 8) / 255.0f;
    float value; // = (float)(color & 0xff) / 255.0f;
    float alpha = (float)((color & 0xff000000) >> 24) / 255.0f;
    
    if (alpha != 0.0f) {
	value = [m_colorPicker value];
	HSVtoRGB(&rgba[0], &rgba[1], &rgba[2], hue, saturation, value);

	UIColor *col = [UIColor colorWithRed: rgba[0] green:rgba[1] blue:rgba[2] alpha:rgba[3]];
	[m_colorPicker setColor: col];
    }
}
-(void)dealloc {
    if (m_hsvData)
	free(m_hsvData);
    m_hsvData = NULL;
    [super dealloc];
}

-(void) touchesBegan:(NSSet*)touches withEvent:(UIEvent*)event
{
    UITouch* touch = [touches anyObject];
    [self mousePositionToColor: [touch locationInView: self]];
}

- (void) touchesEnded:(NSSet*)touches withEvent:(UIEvent*)event
{
    UITouch* touch = [touches anyObject];
    [self mousePositionToColor: [touch locationInView: self]];
}

- (void)touchesCancelled:(NSSet*)touches withEvent:(UIEvent*)event {
}

- (void) touchesMoved:(NSSet*)touches withEvent:(UIEvent*)event
{
    UITouch* touch = [touches anyObject];
    [self mousePositionToColor: [touch locationInView: self]];
}
@end

@implementation ColorPicker
- (id)init {
    if ((self = [super init])!=nil) {
    	self.title = NSLocalizedString(@"Select Color", @"");
    }
    return self;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return gLargeScreenDevice ? YES : interfaceOrientation == UIInterfaceOrientationPortrait;
}


- (BOOL)shouldAutorotate {
    return YES;
}

-(void)viewDidLoad {
#ifdef NSFoundationVersionNumber_iOS_6_1
    if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1)
    {
        self.edgesForExtendedLayout=UIRectEdgeNone;
    }
#endif
}

- (void)loadView {
    CGRect frame = [[UIScreen mainScreen] applicationFrame];
    BOOL fullScreenLarge = (frame.size.width > 760);
    m_background = [[UIView alloc] initWithFrame: frame];
    self.view = m_background;

    UIColor *bgColor = [UIColor whiteColor];
    UIColor *borderColor = [UIColor blackColor];
    [m_background setBackgroundColor: bgColor];

//    [m_background setAutoresizesSubviews: YES];
    [m_background setAutoresizingMask: UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight];

    CGFloat colorTileHeight  = 64.0f;
    CGFloat leftMargin = 8.0f;
    CGFloat hsvBaseYOrigin = colorTileHeight + 64.0f;
    CGRect colorTileFrame = CGRectMake(leftMargin, 32.0f, frame.size.width-(leftMargin-1)*2, colorTileHeight);
    m_colorTile = [[ColorTile alloc] initWithFrame: colorTileFrame withColorPicker: self];
    m_tileBorder = [[UIView alloc] initWithFrame: CGRectInset(colorTileFrame, -1, -1)];
    [m_tileBorder setBackgroundColor: borderColor];
    [m_colorTile setAutoresizingMask: UIViewAutoresizingFlexibleWidth];
    [m_tileBorder setAutoresizingMask: UIViewAutoresizingFlexibleWidth];

    CGFloat radius = 128.0f;
    m_hsvPicker = [[HSVPicker alloc] initWithFrame: CGRectMake(leftMargin, hsvBaseYOrigin, radius*2, radius*2) withColorPicker: self];
    m_valuePicker = [[HSVValuePicker alloc] initWithFrame: CGRectMake(leftMargin+radius*2, hsvBaseYOrigin, 56.0f, radius*2) withColorPicker: self];
    [m_valuePicker setBarWidth: 32];

    [m_hsvPicker setAutoresizingMask: UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin];
    [m_valuePicker setAutoresizingMask: UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin];
    [m_valuePicker setLeftMargin: 16];

    UIImage *hsvCursorImage = [[UIImage alloc]
	initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"hsv-crosshair" ofType:@"png" inDirectory: @"/"]];
    m_hsvCursor = [[UIImageView alloc] initWithImage: hsvCursorImage];
    [hsvCursorImage release];
    UIImage *valCursorImage = [[UIImage alloc]
                               initWithContentsOfFile: [[NSBundle mainBundle] pathForResource:
                             (fullScreenLarge ? @"val-crosshair-ipad":@"val-crosshair") ofType:@"png" inDirectory: @"/"]];
    m_valueCursor = [[UIImageView alloc] initWithImage: valCursorImage];
    [valCursorImage release];
    
    CGRect cursFrame = [m_hsvCursor frame];
    cursFrame.origin = CGPointMake(radius - 16.0f, radius - 16.0f);
    [m_hsvCursor setFrame: cursFrame];

    cursFrame = [m_valueCursor frame];
    cursFrame.origin = CGPointMake(8, -16);
    [m_valueCursor setFrame: cursFrame];

    [self.view addSubview: m_tileBorder];
    [self.view addSubview: m_hsvPicker];
    [self.view addSubview: m_valuePicker];
    [self.view addSubview: m_colorTile];
    [m_hsvPicker addSubview: m_hsvCursor];
    [m_valuePicker addSubview: m_valueCursor];
    
    [self updateAccessibility];
}

- (void)viewWillLayoutSubviews {
    [self layoutViews];
}

-(void)layoutViews {
    CGRect frame = self.view.frame;
    BOOL fullScreenLarge = (frame.size.width >= 540.0 && frame.size.height >= 576.0);
    BOOL isPortrait = (UIApplication.sharedApplication.statusBarOrientation==UIInterfaceOrientationPortrait
                       || UIApplication.sharedApplication.statusBarOrientation==UIInterfaceOrientationPortraitUpsideDown);

    CGFloat colorTileHeight  = fullScreenLarge ? 128.0f : isPortrait ? 96.0f : 232.0f;
    CGFloat leftMargin = fullScreenLarge ? 32.0f : isPortrait ? 4.0f : 16.0f;
	CGFloat hsvBaseYOrigin = !isPortrait && !fullScreenLarge ? 24.0f : colorTileHeight + 48.0f;
	CGFloat rightMarin = 60;
	if (isPortrait && !fullScreenLarge && frame.size.height > 600) {
		leftMargin += 20;
		colorTileHeight += 60;
		hsvBaseYOrigin += 120;
		rightMarin += 20;
	}
    CGRect colorTileFrame = CGRectMake(leftMargin, 24.0f,
                                       isPortrait || fullScreenLarge ? frame.size.width-(leftMargin*2-1) : frame.size.width-328,
                                       colorTileHeight);
    if (!isPortrait && !fullScreenLarge)
        leftMargin += frame.size.width-312;
    [m_colorTile setFrame: colorTileFrame];
    [m_tileBorder setFrame: CGRectInset(colorTileFrame, -1, -1)];
    
    CGFloat radius = fullScreenLarge ? frame.size.width/3 : isPortrait ? 128.0f : 116.0f;
    if (fullScreenLarge) {
        [m_hsvPicker setFrame: CGRectMake(leftMargin, hsvBaseYOrigin, radius*2, radius*2)];
        [m_valuePicker setFrame: CGRectMake(frame.size.width - 80.0f - leftMargin, hsvBaseYOrigin, 96.0f, radius*2)];
        [m_valuePicker setBarWidth: 64];
    } else {
        [m_hsvPicker setFrame: CGRectMake(leftMargin, hsvBaseYOrigin, radius*2, radius*2)];
		[m_valuePicker setFrame: CGRectMake(frame.size.width - (isPortrait ? rightMarin : 60.0f), hsvBaseYOrigin, 56.0f, radius*2)];
        [m_valuePicker setBarWidth: 32];
    }
    
    CGRect cursFrame = [m_valueCursor frame];
    //    cursFrame.size.width = m_valueCursor.image.size.width * (fullScreenLarge ? 2 : 1);
    [m_valueCursor setFrame: cursFrame];
    
    [self updateHSVCursors];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self layoutViews];
}

-(void)viewDidUnload {
    [m_hsvPicker release];
    [m_valuePicker release];
    [m_colorTile release];
    [m_tileBorder release];
    [m_background release];
    [m_hsvCursor release];
    [m_valueCursor release];
    [m_textColor release];
    [m_bgColor release];
    m_textColor = nil;
    m_bgColor = nil;
}

- (void)dealloc {
    NSLog(@"colorpicker view dealloc");
    [m_hsvPicker release];
    [m_valuePicker release];
    [m_colorTile release];
    [m_tileBorder release];
    [m_background release];
    [m_hsvCursor release];
    [m_valueCursor release];
    [m_textColor release];
    [m_bgColor release];
    m_textColor = nil;
    m_bgColor = nil;
    [super dealloc];
}

- (void)updateAccessibility {
    if (m_colorTile && [m_colorTile respondsToSelector: @selector(setAccessibilityLabel:)]) {
	[[m_colorTile textLabel] setAccessibilityHint: NSLocalizedString(@"Sample text for color adjustment",nil)];
    }
}

- (CGColorSpaceRef)colorSpace {
    return m_colorSpace;
}

- (BOOL)isTextColorMode {
    return m_changeTextColor;
}

- (void)toggleMode {
    m_changeTextColor = !m_changeTextColor;
    if (m_changeTextColor) {
	self.title = @"Text Color";
    } else {
	self.title = @"Background Color";
    }
    [self updateHSVCursors];
}

- (void)setTextColor:(UIColor*)textColor bgColor:(UIColor*)bgColor changeText:(BOOL)changeTextColor {
    if (textColor && m_textColor != textColor) {
	if (m_textColor)
	    [m_textColor release];
	m_textColor = [textColor retain];
    }
    if (bgColor && m_bgColor != bgColor) {
	if (m_bgColor)
	    [m_bgColor release];
	m_bgColor = [bgColor retain];
    }
    m_changeTextColor = changeTextColor;

    (void)self.view; // force load of view
    if (textColor)
	[[self colorTile] setTextColor: textColor];
    if (bgColor)
	[[self colorTile] setBGColor: bgColor];

    if (!textColor || !bgColor)
	return;
    [self updateHSVCursors];
}

-(void) updateHSVCursors {
    UIColor *color = m_changeTextColor ? m_textColor : m_bgColor;
    const float *rgba = CGColorGetComponents([color CGColor]);
    float hue = 0, saturation = 0, value = 0;
    RGBtoHSV(rgba[0], rgba[1], rgba[2], &hue, &saturation, &value);
    [self updateColorWithHue:hue Saturation:saturation Value:value];
}

-(void) setColorOnly: (UIColor *)color {
    if (m_changeTextColor)
	[self setTextColor:color bgColor:nil changeText:m_changeTextColor];
    else
	[self setTextColor:nil bgColor:color changeText:m_changeTextColor];
}

-(void) setColor: (UIColor *)color {
    [self setColorOnly: color];
    const float *rgba = CGColorGetComponents([color CGColor]);
    float hue = 0, saturation = 0, value = 0;
    RGBtoHSV(rgba[0], rgba[1], rgba[2], &hue, &saturation, &value);
    [self updateColorWithHue:hue Saturation:saturation Value:value];
}

-(void)setColorValue: (UIColor*)color {
    [self setColorOnly: color];
    const float *rgba = CGColorGetComponents([color CGColor]);
    float hue = 0, saturation = 0, value = 0;
    RGBtoHSV(rgba[0], rgba[1], rgba[2], &hue, &saturation, &value);
    // keep only changed value
    hue = m_hue;
    saturation = m_saturation;
    [self updateColorWithHue:hue Saturation:saturation Value:value];
}

-(void)updateColorWithHue:(float)hue Saturation:(float)saturation Value:(float)value {
//  float oldValue = m_value;
    m_hue = hue == hue ? hue : 0; // NaN guard
    m_saturation = saturation;
    m_value = value;
    float radius = [m_hsvPicker width]/2.0;
    float valHeight = [m_valuePicker height];

    float hsvX = radius - 16.0f, hsvY = radius - 16.0f;
    float valX = [m_valuePicker barWidth] > 32 ? 0.0f : 8.0f, valY = -16.0f;
    
    hsvX += (m_saturation * radius) * cos(m_hue * 2.0f * M_PI);
    hsvY -= (m_saturation * radius) * sin(m_hue * 2.0f * M_PI);
    valY += (1.0f - m_value) * valHeight;
    
    CGRect cursFrame = [m_hsvCursor frame];
    cursFrame.origin = CGPointMake(hsvX, hsvY);
    [m_hsvCursor setFrame: cursFrame];
    cursFrame = [m_valueCursor frame];
    cursFrame.origin = CGPointMake(valX, valY);
    [m_valueCursor setFrame: cursFrame];

    [m_valuePicker setNeedsDisplay];
//    if (oldValue != m_value)
//	[m_hsvPicker setNeedsDisplay];
    if (m_delegate && [m_delegate respondsToSelector: @selector(colorPicker:selectedColor:)])
	[m_delegate colorPicker: self selectedColor: m_changeTextColor ? m_textColor : m_bgColor];
}

-(float)hue {
    return m_hue;
}
-(float)saturation {
    return m_saturation;
}
-(float)value {
    return m_value;
}
-(UIColor *) textColor {
    return m_textColor;
}
-(UIColor *) bgColor {
    return m_bgColor;
}

- (HSVPicker *)hsvPicker {
    return m_hsvPicker;
}
- (HSVValuePicker *)valuePicker {
    return m_valuePicker;
}
- (ColorTile *)colorTile {
    return m_colorTile;
}

- (id<ColorPickerDelegate>)delegate {
    return m_delegate;
}

- (void)setDelegate: (id<ColorPickerDelegate>)delegate {
    m_delegate = delegate;
}
@end
