#import "ControlPanel.h"
#import "DrawView.h"

@implementation ControlPanel

- (id)initWithDrawView:(DrawView *)aDrawView {
    NSRect frame = NSMakeRect(0, 0, 300, 250);  // Compact layout with left-aligned color wells
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
        
        // Clear button no longer needed as it's in the menu bar now
        
        // Create Current Color label
        NSTextField *colorLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 170, 80, 17)];
        [colorLabel setStringValue:@"Color:"];
        [colorLabel setBezeled:NO];
        [colorLabel setDrawsBackground:NO];
        [colorLabel setEditable:NO];
        [colorLabel setSelectable:NO];
        [contentView addSubview:colorLabel];
        
        // Create Color well
        colorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(100, 165, 44, 23)];
        [colorWell setColor:[drawView strokeColor]];
        [colorWell setTarget:self];
        [colorWell setAction:@selector(colorChanged:)];
        [contentView addSubview:colorWell];
        
        // Create Line Width label
        NSTextField *lineWidthLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 140, 80, 17)];
        [lineWidthLabel setStringValue:@"Line Width:"];
        [lineWidthLabel setBezeled:NO];
        [lineWidthLabel setDrawsBackground:NO];
        [lineWidthLabel setEditable:NO];
        [lineWidthLabel setSelectable:NO];
        [contentView addSubview:lineWidthLabel];
        
        // Create Line Width slider
        lineWidthSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(100, 140, 180, 17)];
        [lineWidthSlider setMinValue:1];
        [lineWidthSlider setMaxValue:3.0];
        [lineWidthSlider setDoubleValue:[drawView lineWidth]];
        [lineWidthSlider setTarget:self];
        [lineWidthSlider setAction:@selector(lineWidthChanged:)];
        [contentView addSubview:lineWidthSlider];
        
        // Create Text Size label
        NSTextField *textSizeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 110, 80, 17)];
        [textSizeLabel setStringValue:@"Text Size:"];
        [textSizeLabel setBezeled:NO];
        [textSizeLabel setDrawsBackground:NO];
        [textSizeLabel setEditable:NO];
        [textSizeLabel setSelectable:NO];
        [contentView addSubview:textSizeLabel];
        
        // Create Text Size slider
        textSizeSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(100, 110, 180, 17)];
        [textSizeSlider setMinValue:24.0];
        [textSizeSlider setMaxValue:48.0];
        [textSizeSlider setDoubleValue:[drawView textSize]];
        [textSizeSlider setTarget:self];
        [textSizeSlider setAction:@selector(textSizeChanged:)];
        [contentView addSubview:textSizeSlider];
        
        // Create Preset Colors label
        NSTextField *presetsLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 80, 260, 17)];
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
        preset1ColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(20, 50, 44, 23)];
        [preset1ColorWell setColor:[presetColors objectAtIndex:0]];
        [preset1ColorWell setTarget:self];
        [preset1ColorWell setAction:@selector(presetColorChanged:)];
        [preset1ColorWell setTag:0]; // Use tag to store the preset index
        [contentView addSubview:preset1ColorWell];
        
        preset2ColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(70, 50, 44, 23)];
        [preset2ColorWell setColor:[presetColors objectAtIndex:1]];
        [preset2ColorWell setTarget:self];
        [preset2ColorWell setAction:@selector(presetColorChanged:)];
        [preset2ColorWell setTag:1]; // Use tag to store the preset index
        [contentView addSubview:preset2ColorWell];
        
        preset3ColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(120, 50, 44, 23)];
        [preset3ColorWell setColor:[presetColors objectAtIndex:2]];
        [preset3ColorWell setTarget:self];
        [preset3ColorWell setAction:@selector(presetColorChanged:)];
        [preset3ColorWell setTag:2]; // Use tag to store the preset index
        [contentView addSubview:preset3ColorWell];
        
        preset4ColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(170, 50, 44, 23)];
        [preset4ColorWell setColor:[presetColors objectAtIndex:3]];
        [preset4ColorWell setTarget:self];
        [preset4ColorWell setAction:@selector(presetColorChanged:)];
        [preset4ColorWell setTag:3]; // Use tag to store the preset index
        [contentView addSubview:preset4ColorWell];
        
        preset5ColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(220, 50, 44, 23)];
        [preset5ColorWell setColor:[presetColors objectAtIndex:4]];
        [preset5ColorWell setTarget:self];
        [preset5ColorWell setAction:@selector(presetColorChanged:)];
        [preset5ColorWell setTag:4]; // Use tag to store the preset index
        [contentView addSubview:preset5ColorWell];
        
        // Store the color wells in an array for easier access
        presetColorWells = [[NSArray alloc] initWithObjects:
                            preset1ColorWell, preset2ColorWell, preset3ColorWell, preset4ColorWell, preset5ColorWell, nil];
        
        // Add preset labels
        NSTextField *preset1Label = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 30, 44, 17)];
        [preset1Label setStringValue:@"1"];
        [preset1Label setBezeled:NO];
        [preset1Label setDrawsBackground:NO];
        [preset1Label setEditable:NO];
        [preset1Label setSelectable:NO];
        [preset1Label setAlignment:NSCenterTextAlignment];
        [contentView addSubview:preset1Label];
        [preset1Label release];
        
        NSTextField *preset2Label = [[NSTextField alloc] initWithFrame:NSMakeRect(70, 30, 44, 17)];
        [preset2Label setStringValue:@"2"];
        [preset2Label setBezeled:NO];
        [preset2Label setDrawsBackground:NO];
        [preset2Label setEditable:NO];
        [preset2Label setSelectable:NO];
        [preset2Label setAlignment:NSCenterTextAlignment];
        [contentView addSubview:preset2Label];
        [preset2Label release];
        
        NSTextField *preset3Label = [[NSTextField alloc] initWithFrame:NSMakeRect(120, 30, 44, 17)];
        [preset3Label setStringValue:@"3"];
        [preset3Label setBezeled:NO];
        [preset3Label setDrawsBackground:NO];
        [preset3Label setEditable:NO];
        [preset3Label setSelectable:NO];
        [preset3Label setAlignment:NSCenterTextAlignment];
        [contentView addSubview:preset3Label];
        [preset3Label release];
        
        NSTextField *preset4Label = [[NSTextField alloc] initWithFrame:NSMakeRect(170, 30, 44, 17)];
        [preset4Label setStringValue:@"4"];
        [preset4Label setBezeled:NO];
        [preset4Label setDrawsBackground:NO];
        [preset4Label setEditable:NO];
        [preset4Label setSelectable:NO];
        [preset4Label setAlignment:NSCenterTextAlignment];
        [contentView addSubview:preset4Label];
        [preset4Label release];
        
        NSTextField *preset5Label = [[NSTextField alloc] initWithFrame:NSMakeRect(220, 30, 44, 17)];
        [preset5Label setStringValue:@"5"];
        [preset5Label setBezeled:NO];
        [preset5Label setDrawsBackground:NO];
        [preset5Label setEditable:NO];
        [preset5Label setSelectable:NO];
        [preset5Label setAlignment:NSCenterTextAlignment];
        [contentView addSubview:preset5Label];
        [preset5Label release];
        
        // Add Reset to Defaults button
        NSButton *resetButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, 10, 120, 25)];
        [resetButton setTitle:@"Reset to Defaults"];
        [resetButton setTarget:self];
        [resetButton setAction:@selector(resetToDefaultsClicked:)];
        [resetButton setButtonType:NSMomentaryPushInButton];
        [resetButton setBezelStyle:NSRoundedBezelStyle];
        [contentView addSubview:resetButton];
        [resetButton release];
        
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

- (void)textSizeChanged:(id)sender {
    [drawView setTextSize:[textSizeSlider doubleValue]];
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


- (void)resetToDefaultsClicked:(id)sender {
    // Reset DrawView to defaults
    [drawView resetToDefaults];
    
    // Update UI controls to reflect the reset values
    [colorWell setColor:[drawView strokeColor]];
    [lineWidthSlider setDoubleValue:[drawView lineWidth]];
    [textSizeSlider setDoubleValue:[drawView textSize]];
    
    // Update preset color wells
    NSArray *presetColors = [drawView presetColors];
    for (NSInteger i = 0; i < [presetColorWells count] && i < [presetColors count]; i++) {
        NSColorWell *well = [presetColorWells objectAtIndex:i];
        [well setColor:[presetColors objectAtIndex:i]];
    }
}

- (void)quitButtonClicked:(id)sender {
    [NSApp terminate:self];
}

// Clean up memory
- (void)dealloc {
    [drawView release];
    [presetColorWells release];
    [colorWell release];
    [lineWidthSlider release];
    [textSizeSlider release];
    [preset1ColorWell release];
    [preset2ColorWell release];
    [preset3ColorWell release];
    [super dealloc];
}

@end