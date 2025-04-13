#import <Cocoa/Cocoa.h>
@class DrawView;

@interface ControlPanel : NSWindow {
    DrawView *drawView;
    
    NSButton *clearButton;
    NSColorWell *colorWell;
    NSSlider *lineWidthSlider;
    NSButton *quitButton;
    
    NSColorWell *preset1ColorWell;
    NSColorWell *preset2ColorWell;
    NSColorWell *preset3ColorWell;
    NSArray *presetColorWells;
}

- (id)initWithDrawView:(DrawView *)aDrawView;
- (void)clearButtonClicked:(id)sender;
- (void)colorChanged:(id)sender;
- (void)lineWidthChanged:(id)sender;
- (void)quitButtonClicked:(id)sender;
- (void)presetColorChanged:(id)sender;

@end