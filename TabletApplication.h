#import <Cocoa/Cocoa.h>
@class OverlayWindow;

@interface TabletApplication : NSApplication {
    OverlayWindow *overlayWindow;
    id globalTabletEventMonitor;
    id globalTabletProximityMonitor;
    id globalKeyEventMonitor;
    NSCursor *customCursor;
    NSCursor *defaultCursor;
    BOOL isPenInProximity;
}

- (void)handleProximityEvent:(NSEvent *)theEvent;
- (void)handleKeyEvent:(NSEvent *)theEvent;
- (void)setOverlayWindow:(OverlayWindow *)window;
- (OverlayWindow *)overlayWindow;
- (void)setupGlobalEventMonitors;
- (void)tearDownGlobalEventMonitors;
- (void)setupCustomCursor;

@end