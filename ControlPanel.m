#import "ControlPanel.h"
#import "DrawView.h"

@implementation ControlPanel

- (NSTextField *)createLabelWithFrame:(NSRect)frame text:(NSString *)text {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    [label setStringValue:text];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    return label;
}

- (id)initWithDrawView:(DrawView *)aDrawView {
    NSRect frame = NSMakeRect(0, 0, 300, 230);
    self = [super initWithContentRect:frame
                            styleMask:1 | 2 // NSTitledWindowMask | NSClosableWindowMask
                              backing:NSBackingStoreBuffered
                                defer:NO];
    
    if (self) {
        drawView = [aDrawView retain];
        
        [self setTitle:@"Wacom Overlay Controls"];
        [self setReleasedWhenClosed:NO];
        
        NSView *contentView = [[NSView alloc] initWithFrame:frame];
        [self setContentView:contentView];
        
        // Current Color
        NSTextField *colorLabel = [self createLabelWithFrame:NSMakeRect(20, 195, 80, 17) text:@"Color:"];
        [contentView addSubview:colorLabel];
        
        colorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(100, 190, 44, 23)];
        [colorWell setColor:[drawView strokeColor] ?: [NSColor blackColor]];
        [colorWell setTarget:self];
        [colorWell setAction:@selector(colorChanged:)];
        [contentView addSubview:colorWell];
        
        // Line Width
        NSTextField *lineWidthLabel = [self createLabelWithFrame:NSMakeRect(20, 165, 80, 17) text:@"Line Width:"];
        [contentView addSubview:lineWidthLabel];
        
        lineWidthSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(100, 165, 170, 21)];
        [lineWidthSlider setMinValue:1];
        [lineWidthSlider setMaxValue:3.0];
        [lineWidthSlider setDoubleValue:[drawView lineWidth]];
        [lineWidthSlider setTarget:self];
        [lineWidthSlider setAction:@selector(lineWidthChanged:)];
        [contentView addSubview:lineWidthSlider];
        
        // Text Size
        NSTextField *textSizeLabel = [self createLabelWithFrame:NSMakeRect(20, 135, 80, 17) text:@"Text Size:"];
        [contentView addSubview:textSizeLabel];
        
        textSizeSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(100, 135, 170, 21)];
        [textSizeSlider setMinValue:24.0];
        [textSizeSlider setMaxValue:48.0];
        [textSizeSlider setDoubleValue:[drawView textSize]];
        [textSizeSlider setTarget:self];
        [textSizeSlider setAction:@selector(textSizeChanged:)];
        [contentView addSubview:textSizeSlider];
        
        // Preset Colors
        NSTextField *presetsLabel = [self createLabelWithFrame:NSMakeRect(20, 105, 260, 17) text:@"Preset Colors:"];
        [contentView addSubview:presetsLabel];
        [presetsLabel release];
        
        NSArray *presetColors = [drawView presetColors];
        NSArray *defaultColors = @[[NSColor redColor], [NSColor blueColor], [NSColor greenColor],
                                  [NSColor orangeColor], [NSColor purpleColor]];
        
        NSMutableArray *wells = [NSMutableArray array];
        for (int i = 0; i < 5; i++) {
            NSColorWell *well = [[NSColorWell alloc] initWithFrame:NSMakeRect(20 + i * 50, 75, 44, 23)];
            NSColor *color = (presetColors && i < [presetColors count]) ? presetColors[i] : defaultColors[i];
            [well setColor:color];
            [well setTarget:self];
            [well setAction:@selector(presetColorChanged:)];
            [well setTag:i];
            [contentView addSubview:well];
            [wells addObject:well];
            
            NSTextField *label = [self createLabelWithFrame:NSMakeRect(20 + i * 50, 55, 44, 17) 
                                                       text:[NSString stringWithFormat:@"%d", i + 1]];
            [label setAlignment:NSCenterTextAlignment];
            [contentView addSubview:label];
            [label release];
        }
        presetColorWells = [[NSArray alloc] initWithArray:wells];
        
        // Reset button
        NSButton *resetButton = [[NSButton alloc] initWithFrame:NSMakeRect(10, 15, 130, 25)];
        [resetButton setTitle:@"Reset to Defaults"];
        [resetButton setTarget:self];
        [resetButton setAction:@selector(resetToDefaultsClicked:)];
        [resetButton setButtonType:NSMomentaryPushInButton];
        [resetButton setBezelStyle:NSRoundedBezelStyle];
        [contentView addSubview:resetButton];
        [resetButton release];
        
        [self center];
        [contentView release];
    }
    
    return self;
}

- (void)colorChanged:(id)sender {
    NSColor *selectedColor = [colorWell color];
    [drawView setStrokeColor:selectedColor];
    
    NSArray *presets = [drawView presetColors];
    NSInteger bestMatchIndex = 0;
    CGFloat bestMatchDistance = CGFLOAT_MAX;
    
    for (NSInteger i = 0; i < [presets count]; i++) {
        NSColor *rgb1 = [selectedColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
        NSColor *rgb2 = [[presets objectAtIndex:i] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
        
        CGFloat dr = [rgb1 redComponent] - [rgb2 redComponent];
        CGFloat dg = [rgb1 greenComponent] - [rgb2 greenComponent];
        CGFloat db = [rgb1 blueComponent] - [rgb2 blueComponent];
        CGFloat distance = sqrt(dr*dr + dg*dg + db*db);
        
        if (distance < bestMatchDistance) {
            bestMatchDistance = distance;
            bestMatchIndex = i;
        }
    }
    
    if (bestMatchDistance < 0.1) {
        NSColorWell *presetWell = [presetColorWells objectAtIndex:bestMatchIndex];
        if (![[presetWell color] isEqual:selectedColor]) {
            [presetWell setColor:selectedColor];
            [drawView setPresetColorAtIndex:bestMatchIndex toColor:selectedColor];
        }
        drawView.currentColorIndex = bestMatchIndex;
    } else {
        NSInteger currentIndex = [drawView currentColorIndex];
        NSColorWell *currentPresetWell = [presetColorWells objectAtIndex:currentIndex];
        [currentPresetWell setColor:selectedColor];
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
    
    [drawView setPresetColorAtIndex:presetIndex toColor:[well color]];
    
    if ([drawView currentColorIndex] == presetIndex) {
        [colorWell setColor:[well color]];
    }
}

- (void)resetToDefaultsClicked:(id)sender {
    [drawView resetToDefaults];
    
    [colorWell setColor:[drawView strokeColor] ?: [NSColor redColor]];
    [lineWidthSlider setDoubleValue:[drawView lineWidth]];
    [textSizeSlider setDoubleValue:[drawView textSize]];
    
    NSArray *presetColors = [drawView presetColors];
    NSArray *defaultColors = @[[NSColor redColor], [NSColor blueColor], [NSColor greenColor],
                              [NSColor orangeColor], [NSColor purpleColor]];
    
    for (NSInteger i = 0; i < [presetColorWells count] && i < [presetColors count]; i++) {
        NSColorWell *well = [presetColorWells objectAtIndex:i];
        NSColor *color = presetColors[i] ?: defaultColors[i];
        [well setColor:color];
    }
}

- (void)dealloc {
    [drawView release];
    [presetColorWells release];
    [colorWell release];
    [lineWidthSlider release];
    [textSizeSlider release];
    [super dealloc];
}

@end