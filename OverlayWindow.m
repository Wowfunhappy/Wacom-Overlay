#import "OverlayWindow.h"
#import "DrawView.h"
#import "TabletEvents.h"

@implementation OverlayWindow

- (id)initWithContentRect:(NSRect)contentRect 
                styleMask:(NSUInteger)aStyle 
                  backing:(NSBackingStoreType)bufferingType 
                    defer:(BOOL)flag {
    
    self = [super initWithContentRect:contentRect 
                            styleMask:0 // NSBorderlessWindowMask
                              backing:NSBackingStoreBuffered 
                                defer:NO];
    
    if (self) {
        // Set window properties for an overlay that won't interfere with mouse
        [self setAcceptsMouseMovedEvents:YES];
        
        // Set a high level so we're above other windows
        [self setLevel:NSFloatingWindowLevel];
        
        // Important: We want the window to ignore ALL mouse events
        // We'll use a global event monitor to catch tablet events instead
        [self setIgnoresMouseEvents:YES];
        
        [self setOpaque:NO];
        [self setHasShadow:NO];
        [self setBackgroundColor:[NSColor clearColor]];
        
        // Set the content view to our custom draw view
        DrawView *drawView = [[DrawView alloc] initWithFrame:contentRect];
        [self setContentView:drawView];
        [drawView release];
        
        // Log for debugging
        NSLog(@"OverlayWindow initialized with frame: %@", NSStringFromRect(contentRect));
    }
    
    return self;
}

// We don't need to override sendEvent: anymore since we're using a global event monitor
// and setIgnoresMouseEvents:YES makes the window completely transparent to events

// Make window fully transparent to clicks
- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (BOOL)canBecomeMainWindow {
    return YES;
}

@end