#import "AppDelegate.h"
#import "OverlayWindow.h"
#import "TabletEvents.h"
#import "ControlPanel.h"
#import "DrawView.h"
#import "TabletApplication.h"

@implementation AppDelegate

@synthesize overlayWindow;
@synthesize controlPanel;
@synthesize drawView;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Create the overlay window that will receive tablet events
    self.overlayWindow = [[OverlayWindow alloc] initWithContentRect:[[NSScreen mainScreen] frame]
                                                          styleMask:0 // NSBorderlessWindowMask
                                                            backing:NSBackingStoreBuffered
                                                              defer:NO];
    
    // Set window to be transparent
    [self.overlayWindow setOpaque:NO];
    [self.overlayWindow setAlphaValue:1.0];
    [self.overlayWindow setBackgroundColor:[NSColor clearColor]];
    
    // CRITICAL: This makes mouse events pass through to applications below
    [self.overlayWindow setIgnoresMouseEvents:YES];
    
    // Get the draw view from the overlay window
    self.drawView = (DrawView *)[self.overlayWindow contentView];
    
    // Create and show the control panel
    self.controlPanel = [[ControlPanel alloc] initWithDrawView:self.drawView];
    [self.controlPanel makeKeyAndOrderFront:nil];
    
    // Show the overlay window
    [self.overlayWindow makeKeyAndOrderFront:nil];
    
    // Set up global event monitor to catch tablet events
    NSEventMask eventMask = NSLeftMouseDownMask | 
                            NSLeftMouseUpMask | 
                            NSLeftMouseDraggedMask;
    
    eventMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:eventMask 
                                                         handler:^(NSEvent *event) {
        // Only handle tablet events
        if ([event isTabletPointerEvent]) {
            NSLog(@"Global monitor captured tablet event: %ld", (long)[event type]);
            
            // Forward to our drawing view
            [self.drawView mouseEvent:event];
        }
    }];
    
    // Register for notifications
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillTerminate:)
                                                 name:NSApplicationWillTerminateNotification
                                               object:nil];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Clean up by removing notification observers
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // Remove event monitor
    [NSEvent removeMonitor:eventMonitor];
}

// Clean up memory
- (void)dealloc {
    if (eventMonitor) {
        [NSEvent removeMonitor:eventMonitor];
    }
    
    [overlayWindow release];
    [controlPanel release];
    [drawView release];
    [super dealloc];
}

@end