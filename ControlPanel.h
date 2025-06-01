#import <Cocoa/Cocoa.h>
@class DrawView;

@interface ControlPanel : NSWindow {
    DrawView *drawView;
    
    NSColorWell *colorWell;
    NSSlider *lineWidthSlider;
    NSSlider *textSizeSlider;
    
    NSColorWell *preset1ColorWell;
    NSColorWell *preset2ColorWell;
    NSColorWell *preset3ColorWell;
    NSColorWell *preset4ColorWell;
    NSColorWell *preset5ColorWell;
    NSArray *presetColorWells;
}

- (id)initWithDrawView:(DrawView *)aDrawView;
- (void)clearButtonClicked:(id)sender;
- (void)colorChanged:(id)sender;
- (void)lineWidthChanged:(id)sender;
- (void)textSizeChanged:(id)sender;
- (void)quitButtonClicked:(id)sender;
- (void)presetColorChanged:(id)sender;
- (void)resetToDefaultsClicked:(id)sender;

@end