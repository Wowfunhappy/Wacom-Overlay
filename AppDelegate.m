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
    
    // Convert to NSEvent to check event type
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
    // Check if this is a keyboard event
    else if (type == kCGEventKeyDown) {
        NSLog(@"Key down event captured: %@", nsEvent);
        
        // Check if Command key is pressed
        NSUInteger flags = [nsEvent modifierFlags];
        if (flags & NSCommandKeyMask) {
            NSString *characters = [nsEvent characters];
            
            // Check for Cmd+Z (undo)
            if ([characters isEqualToString:@"z"] && !(flags & NSShiftKeyMask)) {
                NSLog(@"Cmd+Z detected - forwarding to draw view");
                if ([appDelegate.drawView canUndo]) {
                    [appDelegate.drawView undo];
                    return NULL; // Consume the event only if we handled it
                } else {
                    NSLog(@"Nothing to undo - passing event through");
                }
            }
            
            // Check for Cmd+Shift+Z (redo)
            if ((flags & NSShiftKeyMask) && ([characters isEqualToString:@"Z"] || [characters isEqualToString:@"z"])) {
                NSLog(@"Cmd+Shift+Z detected - forwarding to draw view");
                if ([appDelegate.drawView canRedo]) {
                    [appDelegate.drawView redo];
                    return NULL; // Consume the event only if we handled it
                } else {
                    NSLog(@"Nothing to redo - passing event through");
                }
            }
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
    
    // Set up event tap to capture ALL tablet events and keyboard events system-wide
    // We need to tap into events at the lowest level to truly intercept them
    CGEventMask eventMask = CGEventMaskBit(kCGEventLeftMouseDown) | 
                            CGEventMaskBit(kCGEventLeftMouseUp) | 
                            CGEventMaskBit(kCGEventLeftMouseDragged) |
                            CGEventMaskBit(kCGEventKeyDown) |
                            CGEventMaskBit(kCGEventKeyUp);
    
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