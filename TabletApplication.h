#import <Cocoa/Cocoa.h>
@class OverlayWindow;

@interface TabletApplication : NSApplication {
    OverlayWindow *overlayWindow;
}

- (void)handleProximityEvent:(NSEvent *)theEvent;
- (void)setOverlayWindow:(OverlayWindow *)window;

@end