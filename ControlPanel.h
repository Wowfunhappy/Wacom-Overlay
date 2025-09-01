#import <Cocoa/Cocoa.h>
@class DrawView;

@interface ControlPanel : NSWindow {
    DrawView *drawView;
    NSColorWell *colorWell;
    NSSlider *lineWidthSlider;
    NSSlider *textSizeSlider;
    NSArray *presetColorWells;
}

- (id)initWithDrawView:(DrawView *)aDrawView;
- (void)colorChanged:(id)sender;
- (void)lineWidthChanged:(id)sender;
- (void)textSizeChanged:(id)sender;
- (void)presetColorChanged:(id)sender;
- (void)resetToDefaultsClicked:(id)sender;

@end