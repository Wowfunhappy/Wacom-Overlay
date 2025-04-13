#import <Cocoa/Cocoa.h>
@class DrawView;

@interface ControlPanel : NSWindow {
    DrawView *drawView;
    
    NSButton *clearButton;
    NSColorWell *colorWell;
    NSSlider *lineWidthSlider;
    NSButton *quitButton;
}

- (id)initWithDrawView:(DrawView *)aDrawView;
- (void)clearButtonClicked:(id)sender;
- (void)colorChanged:(id)sender;
- (void)lineWidthChanged:(id)sender;
- (void)quitButtonClicked:(id)sender;

@end