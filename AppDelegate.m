#import "AppDelegate.h"
#import "OverlayWindow.h"
#import "TabletEvents.h"
#import "ControlPanel.h"
#import "DrawView.h"
#import "TabletApplication.h"
#import <Carbon/Carbon.h>

// Event tap callback function
static CGEventRef eventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *userInfo) {
    AppDelegate *appDelegate = (AppDelegate *)userInfo;
    
    // Check if this is a tablet event
    // There's no direct way to check for tablet events through CGEvent API in 10.9
    // So we'll convert to NSEvent and check
    NSEvent *nsEvent = [NSEvent eventWithCGEvent:event];
    
    // Check if this is a tablet event
    if ([nsEvent isTabletPointerEvent] || [nsEvent isTabletProximityEvent]) {
        NSLog(@"CG Event tap captured tablet event: %lld", (long long)type);
        
        if ([nsEvent isTabletPointerEvent]) {
            NSLog(@"Tablet pointer event - forwarding to draw view");
            
            // Forward to our draw view
            [appDelegate.drawView mouseEvent:nsEvent];
            
            // Prevent the event from propagating to other applications
            return NULL; // Return NULL to stop event propagation
        }
    }
    
    // Let all other events through
    return event;
}

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
    
    // Make sure window is always above other windows and gets tablet events
    [self.overlayWindow setLevel:NSScreenSaverWindowLevel];
    
    // Get the draw view from the overlay window
    self.drawView = (DrawView *)[self.overlayWindow contentView];
    
    // Create and show the control panel
    self.controlPanel = [[ControlPanel alloc] initWithDrawView:self.drawView];
    [self.controlPanel makeKeyAndOrderFront:nil];
    
    // Show the overlay window
    [self.overlayWindow makeKeyAndOrderFront:nil];
    
    // Connect overlay window with TabletApplication
    TabletApplication *app = (TabletApplication *)NSApp;
    [app setOverlayWindow:self.overlayWindow];
    
    NSLog(@"Connected overlay window to TabletApplication for event interception");
    
    // Set up event tap to capture ALL tablet events system-wide
    // We need to tap into events at the lowest level to truly intercept them
    CGEventMask eventMask = CGEventMaskBit(kCGEventLeftMouseDown) | 
                            CGEventMaskBit(kCGEventLeftMouseUp) | 
                            CGEventMaskBit(kCGEventLeftMouseDragged);
    
    // Create the event tap
    eventTap = CGEventTapCreate(kCGSessionEventTap,  // Tap at session level (lowest level)
                                kCGHeadInsertEventTap, // Insert at beginning of list
                                kCGEventTapOptionDefault, // Default options
                                eventMask,    // Events to capture
                                eventTapCallback, // Callback function
                                self);  // User data passed to callback
    
    if (!eventTap) {
        NSLog(@"ERROR: Failed to create event tap!");
        return;
    }
    
    // Create a run loop source for the event tap
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
    
    // Add the run loop source to the current run loop
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
    
    // Enable the event tap
    CGEventTapEnable(eventTap, true);
    
    NSLog(@"Event tap installed successfully");
    
    // Register for notifications
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillTerminate:)
                                                 name:NSApplicationWillTerminateNotification
                                               object:nil];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Clean up by removing notification observers
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // Cleanup event tap
    if (eventTap) {
        CGEventTapEnable(eventTap, false);
        CFMachPortInvalidate(eventTap);
        CFRelease(eventTap);
        eventTap = NULL;
    }
    
    if (runLoopSource) {
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
        CFRelease(runLoopSource);
        runLoopSource = NULL;
    }
    
    // Remove event monitor if it exists
    if (eventMonitor) {
        [NSEvent removeMonitor:eventMonitor];
    }
}

// Clean up memory
- (void)dealloc {
    // Additional cleanup
    if (eventTap) {
        CGEventTapEnable(eventTap, false);
        CFMachPortInvalidate(eventTap);
        CFRelease(eventTap);
    }
    
    if (runLoopSource) {
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
        CFRelease(runLoopSource);
    }
    
    if (eventMonitor) {
        [NSEvent removeMonitor:eventMonitor];
    }
    
    [overlayWindow release];
    [controlPanel release];
    [drawView release];
    [super dealloc];
}

@end