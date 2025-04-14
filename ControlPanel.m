#import "ControlPanel.h"
#import "DrawView.h"

@implementation ControlPanel

- (id)initWithDrawView:(DrawView *)aDrawView {
    NSRect frame = NSMakeRect(0, 0, 300, 220);  // Original height without smoothing controls
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
        clearButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, 180, 120, 24)];
        [clearButton setTitle:@"Clear Drawing"];
        [clearButton setBezelStyle:NSRoundedBezelStyle];
        [clearButton setTarget:self];
        [clearButton setAction:@selector(clearButtonClicked:)];
        [contentView addSubview:clearButton];
        
        // Create Current Color label
        NSTextField *colorLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 150, 80, 17)];
        [colorLabel setStringValue:@"Color:"];
        [colorLabel setBezeled:NO];
        [colorLabel setDrawsBackground:NO];
        [colorLabel setEditable:NO];
        [colorLabel setSelectable:NO];
        [contentView addSubview:colorLabel];
        
        // Create Color well
        colorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(100, 145, 44, 23)];
        [colorWell setColor:[drawView strokeColor]];
        [colorWell setTarget:self];
        [colorWell setAction:@selector(colorChanged:)];
        [contentView addSubview:colorWell];
        
        // Create Line Width label
        NSTextField *lineWidthLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 120, 80, 17)];
        [lineWidthLabel setStringValue:@"Line Width:"];
        [lineWidthLabel setBezeled:NO];
        [lineWidthLabel setDrawsBackground:NO];
        [lineWidthLabel setEditable:NO];
        [lineWidthLabel setSelectable:NO];
        [contentView addSubview:lineWidthLabel];
        
        // Create Line Width slider
        lineWidthSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(100, 120, 180, 17)];
        [lineWidthSlider setMinValue:0.5];
        [lineWidthSlider setMaxValue:20.0];
        [lineWidthSlider setDoubleValue:[drawView lineWidth]];
        [lineWidthSlider setTarget:self];
        [lineWidthSlider setAction:@selector(lineWidthChanged:)];
        [contentView addSubview:lineWidthSlider];
        
        // Create Preset Colors label
        NSTextField *presetsLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 90, 260, 17)];
        [presetsLabel setStringValue:@"Preset Colors:"];
        [presetsLabel setBezeled:NO];
        [presetsLabel setDrawsBackground:NO];
        [presetsLabel setEditable:NO];
        [presetsLabel setSelectable:NO];
        [contentView addSubview:presetsLabel];
        [presetsLabel release];
        
        // Get preset colors from the DrawView
        NSArray *presetColors = [drawView presetColors];
        
        // Create color wells for each preset
        preset1ColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(60, 60, 44, 23)];
        [preset1ColorWell setColor:[presetColors objectAtIndex:0]];
        [preset1ColorWell setTarget:self];
        [preset1ColorWell setAction:@selector(presetColorChanged:)];
        [preset1ColorWell setTag:0]; // Use tag to store the preset index
        [contentView addSubview:preset1ColorWell];
        
        preset2ColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(130, 60, 44, 23)];
        [preset2ColorWell setColor:[presetColors objectAtIndex:1]];
        [preset2ColorWell setTarget:self];
        [preset2ColorWell setAction:@selector(presetColorChanged:)];
        [preset2ColorWell setTag:1]; // Use tag to store the preset index
        [contentView addSubview:preset2ColorWell];
        
        preset3ColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(200, 60, 44, 23)];
        [preset3ColorWell setColor:[presetColors objectAtIndex:2]];
        [preset3ColorWell setTarget:self];
        [preset3ColorWell setAction:@selector(presetColorChanged:)];
        [preset3ColorWell setTag:2]; // Use tag to store the preset index
        [contentView addSubview:preset3ColorWell];
        
        // Store the color wells in an array for easier access
        presetColorWells = [[NSArray alloc] initWithObjects:
                            preset1ColorWell, preset2ColorWell, preset3ColorWell, nil];
        
        // Add preset labels
        NSTextField *preset1Label = [[NSTextField alloc] initWithFrame:NSMakeRect(60, 40, 44, 17)];
        [preset1Label setStringValue:@"1"];
        [preset1Label setBezeled:NO];
        [preset1Label setDrawsBackground:NO];
        [preset1Label setEditable:NO];
        [preset1Label setSelectable:NO];
        [preset1Label setAlignment:NSCenterTextAlignment];
        [contentView addSubview:preset1Label];
        [preset1Label release];
        
        NSTextField *preset2Label = [[NSTextField alloc] initWithFrame:NSMakeRect(130, 40, 44, 17)];
        [preset2Label setStringValue:@"2"];
        [preset2Label setBezeled:NO];
        [preset2Label setDrawsBackground:NO];
        [preset2Label setEditable:NO];
        [preset2Label setSelectable:NO];
        [preset2Label setAlignment:NSCenterTextAlignment];
        [contentView addSubview:preset2Label];
        [preset2Label release];
        
        NSTextField *preset3Label = [[NSTextField alloc] initWithFrame:NSMakeRect(200, 40, 44, 17)];
        [preset3Label setStringValue:@"3"];
        [preset3Label setBezeled:NO];
        [preset3Label setDrawsBackground:NO];
        [preset3Label setEditable:NO];
        [preset3Label setSelectable:NO];
        [preset3Label setAlignment:NSCenterTextAlignment];
        [contentView addSubview:preset3Label];
        [preset3Label release];
        
        // Create Quit button
        quitButton = [[NSButton alloc] initWithFrame:NSMakeRect(180, 180, 100, 24)];
        [quitButton setTitle:@"Quit"];
        [quitButton setBezelStyle:NSRoundedBezelStyle];
        [quitButton setTarget:self];
        [quitButton setAction:@selector(quitButtonClicked:)];
        [contentView addSubview:quitButton];
        
        // Center window on screen
        [self center];
        
        // Release the content view since it's retained by the window
        [contentView release];
    }
    
    return self;
}

- (void)clearButtonClicked:(id)sender {
    [drawView clear];
}

- (void)colorChanged:(id)sender {
    NSColor *selectedColor = [colorWell color];
    [drawView setStrokeColor:selectedColor];
    
    // Get the current preset colors
    NSArray *presets = [drawView presetColors];
    
    // Try to find a close match among the preset colors
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
    
    // If the color is close enough to a preset, select that preset
    if (bestMatchDistance < 0.1) {
        // Update the color well for the current preset
        NSColorWell *presetWell = [presetColorWells objectAtIndex:bestMatchIndex];
        if (![[presetWell color] isEqual:selectedColor]) {
            [presetWell setColor:selectedColor];
            // Update the preset in the DrawView
            [drawView setPresetColorAtIndex:bestMatchIndex toColor:selectedColor];
        }
        
        // Update the current color index
        drawView.currentColorIndex = bestMatchIndex;
    } else {
        // If it's not close to any preset, update the current preset's color
        NSInteger currentIndex = [drawView currentColorIndex];
        NSColorWell *currentPresetWell = [presetColorWells objectAtIndex:currentIndex];
        [currentPresetWell setColor:selectedColor];
        
        // Update the preset in the DrawView
        [drawView setPresetColorAtIndex:currentIndex toColor:selectedColor];
    }
}

- (void)lineWidthChanged:(id)sender {
    [drawView setLineWidth:[lineWidthSlider doubleValue]];
}

- (void)presetColorChanged:(id)sender {
    NSColorWell *well = (NSColorWell *)sender;
    NSInteger presetIndex = [well tag];
    
    NSLog(@"ControlPanel: Preset color %ld changed to %@", (long)presetIndex, [well color]);
    
    // Update the preset color in the DrawView
    [drawView setPresetColorAtIndex:presetIndex toColor:[well color]];
    
    // If this is the current color, update the main color well too
    if ([drawView currentColorIndex] == presetIndex) {
        [colorWell setColor:[well color]];
    }
}


- (void)quitButtonClicked:(id)sender {
    [NSApp terminate:self];
}

// Clean up memory
- (void)dealloc {
    [drawView release];
    [presetColorWells release];
    [clearButton release];
    [colorWell release];
    [lineWidthSlider release];
    [quitButton release];
    [preset1ColorWell release];
    [preset2ColorWell release];
    [preset3ColorWell release];
    [super dealloc];
}

@end