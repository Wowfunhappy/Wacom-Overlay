#import <Cocoa/Cocoa.h>
@class OverlayWindow;

@interface TabletApplication : NSApplication {
    OverlayWindow *overlayWindow;
    id globalTabletEventMonitor;
    id globalTabletProximityMonitor;
    id globalKeyEventMonitor;
}

- (void)handleProximityEvent:(NSEvent *)theEvent;
- (void)handleKeyEvent:(NSEvent *)theEvent;
- (void)setOverlayWindow:(OverlayWindow *)window;
- (OverlayWindow *)overlayWindow;
- (void)setupGlobalEventMonitors;
- (void)tearDownGlobalEventMonitors;

@end