#import <Cocoa/Cocoa.h>
@class OverlayWindow;

@interface TabletApplication : NSApplication {
    OverlayWindow *overlayWindow;
    id globalTabletEventMonitor;
    id globalTabletProximityMonitor;
}

- (void)handleProximityEvent:(NSEvent *)theEvent;
- (void)setOverlayWindow:(OverlayWindow *)window;
- (OverlayWindow *)overlayWindow;
- (void)setupGlobalEventMonitors;
- (void)tearDownGlobalEventMonitors;

@end