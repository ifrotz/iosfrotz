#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import "ColorPicker.h"
#import <UIKit/UIWindow.h>
#import <CoreSurface/CoreSurface.h>
#import <LayerKit/LKLayer.h>
#import <GraphicsServices/GraphicsServices.h>

// Patch to libarmfp, thanks to rickbdotcom
double __floatunsidf (unsigned int i) 
{ 
  double r = (double)(int)i; 
  if ((int)i < 0) 
    r += 0x1p32f; 
  return r; 
} 

float __floatunsisf(unsigned int n) {
    return __floatunsidf(n);
}

@interface ScreenLayerView : UIView 
{
    int m_width;
    int m_height;
    LKLayer *m_screenLayer;
    CoreSurfaceBufferRef m_screenSurface;
}

- (id)initWithFrame:(CGRect)frame;
- (void)dealloc;
- (void)updateScreen;
@end

@interface ColorTile: UIView {
    ColorPicker *m_colorPicker;
}
- (id) initWithFrame:(CGRect)frame withColorPicker: colorPicker;
- (void) setColor: (struct CGColor *)color;
@end

@interface HSVValuePicker : ScreenLayerView {
    ColorPicker *m_colorPicker;
    int m_leftMargin;
    int m_barWidth;
}
- (id) initWithFrame:(CGRect)frame withColorPicker: colorPicker;
- (void)drawRect:(CGRect)rect;
- (void)setLeftMargin: (int)margin;
- (void)setBarWidth : (int)width;
- (void)mousePositionToValue:(GSEvent *)event;
- (void)mouseDown:(GSEvent *)event;
- (void)mouseDragged:(GSEvent *)event;
@end

//static    unsigned int hsvData [512 * 512];
unsigned int *hsvData;

@interface HSVPicker : ScreenLayerView {
    ColorPicker *m_colorPicker;
}
- (id) initWithFrame:(CGRect)frame withColorPicker: colorPicker;
- (void)dealloc;
- (void)drawRect:(CGRect)rect;
- (void)mousePositionToColor:(GSEvent *)event;
- (void)mouseDown:(GSEvent *)event;
- (void)mouseDragged:(GSEvent *)event;
@end

@implementation ScreenLayerView 
- (id)initWithFrame:(CGRect)frame {
    if ((self == [super initWithFrame:frame])!=nil) {
        m_width = frame.size.width;
	m_height = frame.size.height;
	int i;
	CFMutableDictionaryRef dict;
	int pitch = m_width*4, allocSize = 4 * m_width * m_height;
	char *pixelFormat = "ARGB";
	unsigned short *screen;

	dict = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
	    &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFDictionarySetValue(dict, kCoreSurfaceBufferGlobal, kCFBooleanTrue);
	CFDictionarySetValue(dict, kCoreSurfaceBufferMemoryRegion,
	    CFSTR("PurpleGFXMem"));
	CFDictionarySetValue(dict, kCoreSurfaceBufferPitch,
	    CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &pitch));
	CFDictionarySetValue(dict, kCoreSurfaceBufferWidth,
	    CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &m_width));
	CFDictionarySetValue(dict, kCoreSurfaceBufferHeight,
	    CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &m_height));
	CFDictionarySetValue(dict, kCoreSurfaceBufferPixelFormat,
	    CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, pixelFormat));
	CFDictionarySetValue(dict, kCoreSurfaceBufferAllocSize,
	    CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &allocSize));

	m_screenSurface = CoreSurfaceBufferCreate(dict);
	CoreSurfaceBufferLock(m_screenSurface, 3);
	
	m_screenLayer = [[LKLayer layer] retain];
	[m_screenLayer setFrame: CGRectMake(0.0f, 0.0f, (float)m_width, (float)m_height)];

	[m_screenLayer setContents: m_screenSurface];
	[m_screenLayer setOpaque: YES];
	[[self _layer] addSublayer: m_screenLayer];

	CoreSurfaceBufferUnlock(m_screenSurface);

    }
    return self;
}

- (void)dealloc {
    [m_screenLayer release];
    [super dealloc];
}

- (void)updateScreen {
    [self setNeedsDisplay];
}

@end


@implementation ColorTile

- (id) initWithFrame:(CGRect)frame withColorPicker: colorPicker {
    [super initWithFrame: frame];
    m_colorPicker = colorPicker;
    return self;
}

-(void) setColor: (struct CGColor *)color {
    [self setBackgroundColor: color];
    [self setNeedsDisplay];
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
    int i;
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

-(void)mousePositionToValue:(GSEvent *)event {
    CGRect rect = GSEventGetLocationInWindow(event);
    id superview = self;
    while ([superview superview]) {
	superview = [superview superview];
    }
    rect = [superview convertRect: rect toView: self];
    CGPoint point = rect.origin;
    unsigned int y = (unsigned int)point.y;
    if (y >= m_height)
	y = m_height;
    float value = 1.0f - (float)y / (float)m_height;
    
    float rgba[4] = {0.0, 0.0, 0.0, 1.0};
    struct CGColor *color;
    CGColorSpaceRef colorSpace = [m_colorPicker colorSpace];
    
    float hue, saturation;
    
    hue = *[m_colorPicker hue];
    saturation = *[m_colorPicker saturation];
    HSVtoRGB(&rgba[0], &rgba[1], &rgba[2], hue, saturation, value);

    color = CGColorCreate(colorSpace, rgba);
    [m_colorPicker setColor: color];
}

-(void)mouseDown:(GSEvent *)event {
    [self mousePositionToValue: event];
}

-(void)mouseDragged:(GSEvent *)event {
    [self mousePositionToValue: event];
}

- (void)drawRect:(CGRect)rect {
    unsigned int *c;
    int x, y, i = 0, j;
    float r, g, b;
    float h, s, v;
    c = CoreSurfaceBufferGetBaseAddress(m_screenSurface);
    unsigned int wColor;

    h = *[m_colorPicker hue];
    s = *[m_colorPicker saturation];
    for (y=0; y < m_height; y++)
    {
	for (x=0; x < m_leftMargin; x++)
	    c[i++] = 0xffffffUL;
	v = 1.0f - (float)y / (float)m_height;
	HSVtoRGB(&r, &g, &b, h, s, v);
	wColor = (0xff<<24) | (((int)(r * 255.0f) & 0xff) << 16) | (((int)(g * 255.0f) & 0xff) << 8) | ((int)(b * 255.0f) & 0xff);
	for (j=0; j < m_barWidth; j++, x++)
	    c[i++] = wColor;
	for (; x < m_width; x++)
	    c[i++] = 0xffffffUL;
    }
    
}
@end

@implementation HSVPicker

- (id) initWithFrame:(CGRect)frame withColorPicker: colorPicker {
    [super initWithFrame: frame];
    int dataSize = sizeof(unsigned int) * m_width * m_height;
    hsvData = (unsigned int*)malloc(dataSize);
//    hsvData += dataSize;
//    memset(hsvData, 0x00ffffffUL, dataSize);

    m_colorPicker = colorPicker;

    unsigned int *c;
    int x, y, i = 0;
    float r, g, b;
    float h, s, v;

    c = hsvData;

    float cx = m_width / 2.0f;
    float cy = m_height / 2.0f;
    float radius, theta, dx, dy;
    v = 1.0f;

    for (y=0; y < m_height; y++)
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
		c[i] = 0xff000000UL | (((int)(h * 255.0f)) << 16) | (((int)(s * 255.0f)) << 8) | ((int)(v * 255.0f));
	    } else
		c[i] = 0x00ffffffUL;
	    i++;
	}
    }

    return self;
}

- (void)drawRect:(CGRect)rect {
    unsigned int *c;
    int x, y, i = 0;
    float r, g, b;
    float h, s, v;

    CoreSurfaceBufferLock(m_screenSurface, 3);

    c = CoreSurfaceBufferGetBaseAddress(m_screenSurface);
    unsigned int wColor, hsv;

    float cx = m_width / 2.0f;
    float cy = m_height / 2.0f;
    float radius, theta, dx, dy;
    v = *[m_colorPicker value];

    for (y=0; y < m_height; y++)
    {
	for (x=0; x < m_width; x++) {
	    hsv = hsvData[i];
	    
	    if ((hsv & 0xff000000UL)) {
		h = (float)((hsv & 0xff0000) >> 16) / 255.0f;
		s = (float)((hsv & 0x00ff00) >> 8) / 255.0f;
		HSVtoRGB(&r, &g, &b, h, s, v);
	    
		wColor = 0xff000000UL | (((int)(r * 255.0f)) << 16) | (((int)(g * 255.0f)) << 8) | ((int)(b * 255.0f));
		c[i] = wColor;
	    } else
		c[i] = 0x00ffffffUL;
	    i++;
	}
    }
    CoreSurfaceBufferUnlock(m_screenSurface);
}

-(void)mousePositionToColor:(GSEvent *)event {
    unsigned int *c = CoreSurfaceBufferGetBaseAddress(m_screenSurface);
    CGRect rect = GSEventGetLocationInWindow(event);
    id superview = self;
    while ([superview superview]) {
	superview = [superview superview];
    }
    rect = [superview convertRect: rect toView: self];
    CGPoint point = rect.origin;
    float rgba[4] = {0.0, 0.0, 0.0, 1.0};
    unsigned int color;
    CGColorSpaceRef colorSpace = [m_colorPicker colorSpace];
    unsigned int x = (int)point.x;
    unsigned int y = (int)point.y;
    if (x >= m_width) x = m_width - 1;
    if (y >= m_height) y = m_height - 1;

    color = c[y * m_width + x];
    rgba[0] = (float)((color & 0xff0000) >> 16) / 255.0f;
    rgba[1] = (float)((color & 0xff00) >> 8) / 255.0f;
    rgba[2] = (float)(color & 0xff) / 255.0f;
    rgba[3] = (float)((color & 0xff000000) >> 24) / 255.0f;
    
    if (rgba[3] != 0.0f) {
	float hue, saturation, value;
	RGBtoHSV(rgba[0], rgba[1], rgba[2], &hue, &saturation, &value);
	HSVValuePicker *valuePicker = [m_colorPicker valuePicker];
	value = *[m_colorPicker value];
	HSVtoRGB(&rgba[0], &rgba[1], &rgba[2], hue, saturation, value);

	struct CGColor *col = CGColorCreate(colorSpace, rgba);
	[m_colorPicker setColor: col];
    }
}
-(void)dealloc {
    if (hsvData)
	free(hsvData);
    [super dealloc];
}
-(void)mouseDown:(GSEvent *)event {
    [self mousePositionToColor: event];
}

-(void)mouseDragged:(GSEvent *)event {
    [self mousePositionToColor: event];
}
@end


@implementation ColorPicker
- (id)initWithFrame:(CGRect)frame {
    if ((self == [super initWithFrame:frame])!=nil) {
	m_rect = frame;
	m_background = [[UIView alloc] initWithFrame: frame];
    
	float whiteRGB[4] = {1.0f, 1.0f, 1.0f, 1.0f};
	float blackRGB[4] = {0.0f, 0.0f, 0.0f, 1.0f};
	m_colorSpace = CGColorSpaceCreateDeviceRGB();
	struct CGColor *bgColor = CGColorCreate(m_colorSpace, whiteRGB);
	struct CGColor *borderColor = CGColorCreate(m_colorSpace, blackRGB);
	[m_background setBackgroundColor: bgColor];

	m_colorTile = [[ColorTile alloc] initWithFrame: CGRectMake(8.0f, 36.0f, 306.0f, 64.0f) withColorPicker: self];
	m_tileBorder = [[UIView alloc] initWithFrame: CGRectMake(7.0f, 35.0f, 308.0f, 66.0f)];
	[m_tileBorder setBackgroundColor: borderColor];
      
	m_hsvPicker = [[HSVPicker alloc] initWithFrame: CGRectMake(8.0f, 128.0f, 256.0f, 256.0f) withColorPicker: self];
	m_valuePicker = [[HSVValuePicker alloc] initWithFrame: CGRectMake(264.0f, 128.0f, 56.0f, 256.0f) withColorPicker: self];
	[m_valuePicker setLeftMargin: 16];
	[m_valuePicker setBarWidth: 32];

	UIImage *hsvCursorImage = [[UIImage alloc]
	    initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"hsv-crosshair" ofType:@"png" inDirectory: @"/"]];
	m_hsvCursor = [[UIImageView alloc] initWithImage: hsvCursorImage];
      	UIImage *valCursorImage = [[UIImage alloc]
	    initWithContentsOfFile: [[NSBundle mainBundle] pathForResource:@"val-crosshair" ofType:@"png" inDirectory: @"/"]];
	m_valueCursor = [[UIImageView alloc] initWithImage: valCursorImage];
	[m_hsvCursor setOrigin: CGPointMake(128.0f + 8.0f - 16.0f,  128.f + 128.0f - 16.0f)];
	[m_valueCursor setOrigin: CGPointMake(280.0f - 8.0f, 128.0f - 16.0f)];

	[self addSubview: m_background];
	[self addSubview: m_tileBorder];
	[self addSubview: m_hsvPicker];
	[self addSubview: m_valuePicker];
	[self addSubview: m_colorTile];
	[self addSubview: m_hsvCursor];
	[self addSubview: m_valueCursor];
	[self setNeedsDisplay];
    }
    return self;
}

- (void)dealloc {
    [m_hsvPicker release];
    [m_valuePicker release];
    [m_colorTile release];
    [m_tileBorder release];
    [m_background release];
    [m_hsvCursor release];
    [m_valueCursor release];
    if (m_color)
	CGColorRelease(m_color);
    CGColorSpaceRelease(m_colorSpace);
    [super dealloc];
}

- (CGColorSpaceRef)colorSpace {
    return m_colorSpace;
}
-(void) setColor: (struct CGColor *)color {
    if (m_color)
	CGColorRelease(m_color);
    m_color = CGColorCreateCopy(color);
    [[self colorTile] setColor: m_color];
    
    const float *rgba = CGColorGetComponents(color);
    float oldValue = m_value;
    RGBtoHSV(rgba[0], rgba[1], rgba[2], &m_hue, &m_saturation, &m_value);
    
    float hsvX = 128.0f + 8.0f - 16.0f, hsvY = 128.f + 128.0f - 16.0f;
    float valX = 280.0f - 8.0f, valY = 128.0f - 16.0f;
    
    hsvX += (m_saturation * 128.0f) * cos(m_hue * 2.0f * M_PI);
    hsvY -= (m_saturation * 128.0f) * sin(m_hue * 2.0f * M_PI);
    valY += (1.0f - m_value) * 256.0f;
    
    [m_hsvCursor setOrigin: CGPointMake(hsvX, hsvY)];
    [m_valueCursor setOrigin: CGPointMake(valX, valY)];

    [m_valuePicker setNeedsDisplay];
    if (oldValue != m_value)
	[m_hsvPicker setNeedsDisplay];
    if (m_delegate && [m_delegate respondsToSelector: @selector(colorPicker:selectedColor:)])
	[m_delegate colorPicker: self selectedColor: color];
}

-(float*)hue {
    return &m_hue;
}
-(float*)saturation {
    return &m_saturation;
}
-(float*)value {
    return &m_value;
}
-(struct CGColor *) color {
    return m_color;
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
- (id)delegate {
    return m_delegate;
}
- (void)setDelegate: (id)delegate {
    m_delegate = delegate;
}
@end
