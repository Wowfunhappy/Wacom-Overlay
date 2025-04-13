#import <Cocoa/Cocoa.h>

@class OverlayWindow;
@class ControlPanel;
@class DrawView;

@interface AppDelegate : NSObject <NSApplicationDelegate> {
    id eventMonitor;
}

@property (nonatomic, retain) OverlayWindow *overlayWindow;
@property (nonatomic, retain) ControlPanel *controlPanel;
@property (nonatomic, retain) DrawView *drawView;

@end