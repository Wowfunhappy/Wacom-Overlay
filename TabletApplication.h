#import <Cocoa/Cocoa.h>

// External CoreGraphics Services declarations for cursor background control
void *CGSDefaultConnectionForThread(void);
OSStatus CGSSetConnectionProperty(void *connection, void *ownerConnection, CFStringRef key, CFTypeRef value);

@class OverlayWindow;

@interface TabletApplication : NSApplication {
    OverlayWindow *overlayWindow;
    id globalTabletEventMonitor;
    id globalTabletProximityMonitor;
    id globalKeyEventMonitor;
    NSCursor *customCursor;
    NSCursor *defaultCursor;
    BOOL isPenInProximity;
    NSTimer *cursorCheckTimer;
    NSColor *currentCursorColor;
}

- (void)handleProximityEvent:(NSEvent *)theEvent;
- (void)handleKeyEvent:(NSEvent *)theEvent;
- (void)setOverlayWindow:(OverlayWindow *)window;
- (OverlayWindow *)overlayWindow;
- (void)setupGlobalEventMonitors;
- (void)tearDownGlobalEventMonitors;
- (void)setupCustomCursor;
- (void)enforceCursor:(NSTimer *)timer;
- (void)updateCursorWithColor:(NSColor *)color;
- (NSCursor *)createCursorWithColor:(NSColor *)color;
- (void)registerForColorNotifications;
- (void)updateSetsCursorInBackground;

@end