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
        
        // Important: we need to intercept events but allow mouse clicks through
        [self setIgnoresMouseEvents:NO];
        
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

// Override to selectively handle events - this is critical for separating tablet from mouse
- (void)sendEvent:(NSEvent *)event {
    // Handle tablet events specially
    if ([event isTabletPointerEvent]) {
        NSLog(@"OverlayWindow received tablet event - directly forwarding to view");
        
        // Directly send to our draw view for more reliable handling
        DrawView *drawView = (DrawView *)[self contentView];
        [drawView mouseEvent:event];
        return;
    } 
    else if ([event isTabletProximityEvent]) {
        NSLog(@"OverlayWindow received proximity event - passing to system");
        [super sendEvent:event];
        return;
    }
    
    // For all other events, check if they are mouse events
    if ([event isEventClassMouse]) {
        // Pass through mouse events to other applications
        NSLog(@"OverlayWindow ignoring mouse event: %ld", (long)[event type]);
        return; // Don't call super - this makes mouse events pass through
    }
    
    // Handle all non-mouse events normally
    [super sendEvent:event];
}

// Make window fully transparent to clicks
- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (BOOL)canBecomeMainWindow {
    return YES;
}

@end