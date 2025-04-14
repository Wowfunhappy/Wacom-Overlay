#import <Cocoa/Cocoa.h>

@class OverlayWindow;
@class ControlPanel;
@class DrawView;

@interface AppDelegate : NSObject <NSApplicationDelegate> {
    id eventMonitor;
    CFMachPortRef eventTap;
    CFRunLoopSourceRef runLoopSource;
}

@property (nonatomic, retain) OverlayWindow *overlayWindow;
@property (nonatomic, retain) ControlPanel *controlPanel;
@property (nonatomic, retain) DrawView *drawView;
@property (nonatomic, assign) pid_t wacomDriverPID;

- (pid_t)findWacomDriverPID;

@end