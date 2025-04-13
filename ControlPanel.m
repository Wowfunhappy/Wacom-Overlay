#import "ControlPanel.h"
#import "DrawView.h"

@implementation ControlPanel

- (id)initWithDrawView:(DrawView *)aDrawView {
    NSRect frame = NSMakeRect(0, 0, 300, 150);
    self = [super initWithContentRect:frame
                            styleMask:1 | 2 // NSTitledWindowMask | NSClosableWindowMask
                              backing:NSBackingStoreBuffered
                                defer:NO];
    
    if (self) {
        drawView = [aDrawView retain];
        
        [self setTitle:@"Wacom Overlay Controls"];
        [self setReleasedWhenClosed:NO];
        
        // Create the content view
        NSView *contentView = [[NSView alloc] initWithFrame:frame];
        [self setContentView:contentView];
        
        // Create Clear button
        clearButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, 110, 120, 24)];
        [clearButton setTitle:@"Clear Drawing"];
        [clearButton setBezelStyle:NSRoundedBezelStyle];
        [clearButton setTarget:self];
        [clearButton setAction:@selector(clearButtonClicked:)];
        [contentView addSubview:clearButton];
        
        // Create Color label
        NSTextField *colorLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 80, 80, 17)];
        [colorLabel setStringValue:@"Color:"];
        [colorLabel setBezeled:NO];
        [colorLabel setDrawsBackground:NO];
        [colorLabel setEditable:NO];
        [colorLabel setSelectable:NO];
        [contentView addSubview:colorLabel];
        
        // Create Color well
        colorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(100, 75, 44, 23)];
        [colorWell setColor:[drawView strokeColor]];
        [colorWell setTarget:self];
        [colorWell setAction:@selector(colorChanged:)];
        [contentView addSubview:colorWell];
        
        // Create Line Width label
        NSTextField *lineWidthLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 50, 80, 17)];
        [lineWidthLabel setStringValue:@"Line Width:"];
        [lineWidthLabel setBezeled:NO];
        [lineWidthLabel setDrawsBackground:NO];
        [lineWidthLabel setEditable:NO];
        [lineWidthLabel setSelectable:NO];
        [contentView addSubview:lineWidthLabel];
        
        // Create Line Width slider
        lineWidthSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(100, 50, 180, 17)];
        [lineWidthSlider setMinValue:0.5];
        [lineWidthSlider setMaxValue:20.0];
        [lineWidthSlider setDoubleValue:[drawView lineWidth]];
        [lineWidthSlider setTarget:self];
        [lineWidthSlider setAction:@selector(lineWidthChanged:)];
        [contentView addSubview:lineWidthSlider];
        
        // Create Quit button
        quitButton = [[NSButton alloc] initWithFrame:NSMakeRect(180, 110, 100, 24)];
        [quitButton setTitle:@"Quit"];
        [quitButton setBezelStyle:NSRoundedBezelStyle];
        [quitButton setTarget:self];
        [quitButton setAction:@selector(quitButtonClicked:)];
        [contentView addSubview:quitButton];
        
        // Center window on screen
        [self center];
    }
    
    return self;
}

- (void)clearButtonClicked:(id)sender {
    [drawView clear];
}

- (void)colorChanged:(id)sender {
    NSColor *selectedColor = [colorWell color];
    [drawView setStrokeColor:selectedColor];
    
    // Update the currentColorIndex variable in DrawView if possible
    if ([drawView respondsToSelector:@selector(setCurrentColorIndex:)]) {
        // Try to find the closest matching color in the preset array
        NSArray *presets = [drawView valueForKey:@"presetColors"];
        if (presets) {
            NSInteger bestMatchIndex = 0;
            CGFloat bestMatchDistance = CGFLOAT_MAX;
            
            for (NSInteger i = 0; i < [presets count]; i++) {
                NSColor *presetColor = [presets objectAtIndex:i];
                
                // Convert both colors to RGB space for comparison
                NSColor *rgb1 = [selectedColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
                NSColor *rgb2 = [presetColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
                
                // Calculate a simple color distance
                CGFloat dr = [rgb1 redComponent] - [rgb2 redComponent];
                CGFloat dg = [rgb1 greenComponent] - [rgb2 greenComponent];
                CGFloat db = [rgb1 blueComponent] - [rgb2 blueComponent];
                CGFloat distance = sqrt(dr*dr + dg*dg + db*db);
                
                if (distance < bestMatchDistance) {
                    bestMatchDistance = distance;
                    bestMatchIndex = i;
                }
            }
            
            // If the color is close enough to a preset, update the index
            if (bestMatchDistance < 0.1) {
                [drawView setValue:[NSNumber numberWithInteger:bestMatchIndex] forKey:@"currentColorIndex"];
            }
        }
    }
}

- (void)lineWidthChanged:(id)sender {
    [drawView setLineWidth:[lineWidthSlider doubleValue]];
}

- (void)quitButtonClicked:(id)sender {
    [NSApp terminate:self];
}

// Clean up memory
- (void)dealloc {
    [drawView release];
    [super dealloc];
}

@end