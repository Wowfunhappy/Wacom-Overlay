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
        
        // Handle tablet proximity events (pen entering/leaving tablet)
        if ([nsEvent isTabletProximityEvent]) {
            NSLog(@"Tablet proximity event detected");
            
            // Forward to TabletApplication for handling
            TabletApplication *app = (TabletApplication *)NSApp;
            if ([app respondsToSelector:@selector(handleProximityEvent:)]) {
                [app handleProximityEvent:nsEvent];
            }
        }
        
        // Handle tablet pointer events (drawing)
        if ([nsEvent isTabletPointerEvent]) {
            NSLog(@"Tablet pointer event - forwarding to draw view");
            
            // Forward to our draw view
            [appDelegate.drawView mouseEvent:nsEvent];
            
            // Prevent the event from propagating to other applications
            return NULL; // Return NULL to stop event propagation
        }
    }
    // Handle mouse events (for selecting and dragging strokes)
    else if (type == kCGEventLeftMouseDown || 
             type == kCGEventLeftMouseDragged || 
             type == kCGEventLeftMouseUp ||
             type == kCGEventMouseMoved) {
        
        // Get the location of the event
        CGPoint cgLocation = CGEventGetLocation(event);
        NSPoint screenPoint = NSMakePoint(cgLocation.x, cgLocation.y);
        
        // Get our draw view
        DrawView *drawView = appDelegate.drawView;
        
        // Convert to view coordinates
        NSPoint viewPoint = [drawView convertScreenPointToView:screenPoint];
        
        // Handle mouse events appropriately
        if (type == kCGEventLeftMouseDown) {
            // Forward the click to DrawView to check for strokes and handle selection
            [drawView setValue:[NSNumber numberWithInteger:-1] forKey:@"selectedStrokeIndex"];
            [drawView mouseEvent:nsEvent];
            
            // Check if a stroke was actually selected
            BOOL wasSelected = [[drawView valueForKey:@"isStrokeSelected"] boolValue];
            
            if (wasSelected) {
                // A stroke was selected, change cursor and capture the event
                [[NSCursor closedHandCursor] set];
                return NULL; // Return NULL to stop event propagation
            } else {
                // No stroke was found, use default cursor and pass through
                [[NSCursor arrowCursor] set];
            }
        }
        // For other mouse events, handle dragging if we have a selected stroke
        else if (type == kCGEventLeftMouseDragged) {
            // If we're already dragging a stroke, continue the drag operation
            if ([[drawView valueForKey:@"isDraggingStroke"] boolValue]) {
                [[NSCursor closedHandCursor] set];
                [drawView mouseEvent:nsEvent];
                return NULL; // Capture during drag
            }
        }
        // For mouse up, complete any drag operation
        else if (type == kCGEventLeftMouseUp) {
            if ([[drawView valueForKey:@"isDraggingStroke"] boolValue]) {
                [[NSCursor openHandCursor] set];
                [drawView mouseEvent:nsEvent];
                return NULL; // Capture to complete the drag
            }
        }
        // For mouse move, update cursor for hover feedback
        else if (type == kCGEventMouseMoved) {
            // For hover detection, use the stroke finding method
            // This will use the same sensitivity settings as in DrawView
            NSInteger strokeIndex = [drawView findStrokeAtPoint:viewPoint];
            if (strokeIndex >= 0) {
                [[NSCursor openHandCursor] set];
            } else {
                [[NSCursor arrowCursor] set];
            }
            // Always let move events through
        }
    }
    // Check if this is a keyboard event
    else if (type == kCGEventKeyDown) {
        NSLog(@"Key down event captured: %@", nsEvent);
        
        // First check for our special color toggle shortcut
        NSUInteger flags = [nsEvent modifierFlags];
        NSString *characters = [nsEvent charactersIgnoringModifiers];
        
        // In OS X 10.9, use the raw bit values
        BOOL isControlDown = (flags & (1 << 18)) != 0;   // NSControlKeyMask in 10.9
        BOOL isCommandDown = (flags & (1 << 20)) != 0;   // NSCommandKeyMask in 10.9
        BOOL isOptionDown = (flags & (1 << 19)) != 0;    // NSAlternateKeyMask in 10.9
        BOOL isShiftDown = (flags & (1 << 17)) != 0;     // NSShiftKeyMask in 10.9
        BOOL isC = ([characters isEqualToString:@"C"] || [characters isEqualToString:@"c"]);
        
        if (isControlDown && isCommandDown && isOptionDown && isShiftDown && isC) {
            NSLog(@"Special color toggle key combination detected");
            
            // Make sure the overlay window and drawing view are active,
            // even if we're on a different desktop/space
            [appDelegate.overlayWindow orderFront:nil];
            
            // Ensure the draw view receives the command
            DrawView *drawView = appDelegate.drawView;
            if (!drawView) {
                // Try to get the draw view if it's not directly available
                TabletApplication *app = (TabletApplication *)NSApp;
                OverlayWindow *window = [app overlayWindow];
                if (window) {
                    drawView = (DrawView *)[window contentView];
                }
            }
            
            if (drawView && [drawView respondsToSelector:@selector(toggleToNextColor)]) {
                NSLog(@"Executing color toggle command across desktops");
                [drawView toggleToNextColor];
                return NULL; // Consume the event
            }
        }
        
        // Check for standard editing shortcuts
        if (isCommandDown) {
            // Check for Cmd+Z (undo)
            if ([characters isEqualToString:@"z"] && !isShiftDown) {
                NSLog(@"Cmd+Z detected - forwarding to draw view");
                
                // Make sure the overlay window and drawing view are active,
                // even if we're on a different desktop/space
                [appDelegate.overlayWindow orderFront:nil];
                
                // Ensure the draw view receives the command
                DrawView *drawView = appDelegate.drawView;
                if (!drawView) {
                    // Try to get the draw view if it's not directly available
                    TabletApplication *app = (TabletApplication *)NSApp;
                    OverlayWindow *window = [app overlayWindow];
                    if (window) {
                        drawView = (DrawView *)[window contentView];
                    }
                }
                
                if (drawView && [drawView canUndo]) {
                    NSLog(@"Executing undo command across desktops");
                    [drawView undo];
                    return NULL; // Consume the event only if we handled it
                } else {
                    NSLog(@"Nothing to undo - passing event through");
                }
            }
            
            // Check for Cmd+Shift+Z (redo)
            if (isShiftDown && ([characters isEqualToString:@"Z"] || [characters isEqualToString:@"z"])) {
                NSLog(@"Cmd+Shift+Z detected - forwarding to draw view");
                
                // Make sure the overlay window and drawing view are active,
                // even if we're on a different desktop/space
                [appDelegate.overlayWindow orderFront:nil];
                
                // Ensure the draw view receives the command
                DrawView *drawView = appDelegate.drawView;
                if (!drawView) {
                    // Try to get the draw view if it's not directly available
                    TabletApplication *app = (TabletApplication *)NSApp;
                    OverlayWindow *window = [app overlayWindow];
                    if (window) {
                        drawView = (DrawView *)[window contentView];
                    }
                }
                
                if (drawView && [drawView canRedo]) {
                    NSLog(@"Executing redo command across desktops");
                    [drawView redo];
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

- (NSRect)totalScreensRect {
    NSRect totalRect = NSZeroRect;
    
    for (NSScreen *screen in [NSScreen screens]) {
        // Use frame, not visibleFrame to cover menu bars, docks, etc.
        NSRect screenRect = [screen frame];
        
        if (NSIsEmptyRect(totalRect)) {
            totalRect = screenRect;
        } else {
            totalRect = NSUnionRect(totalRect, screenRect);
        }
    }
    
    // If somehow there are no screens, return main screen rect
    if (NSIsEmptyRect(totalRect) && [NSScreen mainScreen]) {
        totalRect = [[NSScreen mainScreen] frame];
    }
    
    NSLog(@"Total screens rect: %@", NSStringFromRect(totalRect));
    return totalRect;
}

- (void)updateOverlayWindowFrame {
    // Get the union of all screen frames
    NSRect totalScreensRect = [self totalScreensRect];
    
    // Update the window frame
    [self.overlayWindow setFrame:totalScreensRect display:YES];
    
    NSLog(@"Updated overlay window frame to cover all screens: %@", NSStringFromRect(totalScreensRect));
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Create the overlay window that will cover all screens
    NSRect totalScreensRect = [self totalScreensRect];
    self.overlayWindow = [[OverlayWindow alloc] initWithContentRect:totalScreensRect
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
    
    // Connect overlay window with TabletApplication
    TabletApplication *app = (TabletApplication *)NSApp;
    [app setOverlayWindow:self.overlayWindow];
    
    // Register for screen configuration change notifications
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(screenParametersDidChange:)
                                                 name:NSApplicationDidChangeScreenParametersNotification
                                               object:nil];
    
    NSLog(@"Connected overlay window to TabletApplication for event interception");
    
    // Set up event tap to capture ALL tablet events and keyboard events system-wide
    // We need to tap into events at the lowest level to truly intercept them
    CGEventMask eventMask = CGEventMaskBit(kCGEventLeftMouseDown) | 
                            CGEventMaskBit(kCGEventLeftMouseUp) | 
                            CGEventMaskBit(kCGEventLeftMouseDragged) |
                            CGEventMaskBit(kCGEventRightMouseDown) |  // Add right mouse for completeness
                            CGEventMaskBit(kCGEventRightMouseUp) |
                            CGEventMaskBit(kCGEventRightMouseDragged) |
                            CGEventMaskBit(kCGEventOtherMouseDown) |  // Add other mouse buttons
                            CGEventMaskBit(kCGEventOtherMouseUp) |
                            CGEventMaskBit(kCGEventOtherMouseDragged) |
                            CGEventMaskBit(kCGEventKeyDown) |
                            CGEventMaskBit(kCGEventKeyUp);
    
    // Create the event tap at the highest level possible to capture everything
    eventTap = CGEventTapCreate(kCGHIDEventTap,      // HID level tap to get events from all processes
                                kCGHeadInsertEventTap, // Insert at beginning of list
                                kCGEventTapOptionDefault, // Default options
                                eventMask,    // Events to capture
                                eventTapCallback, // Callback function
                                self);  // User data passed to callback
    
    if (!eventTap) {
        NSLog(@"ERROR: Failed to create event tap! Make sure the app has accessibility permissions in System Preferences > Security & Privacy > Privacy > Accessibility");
        
        // Check if accessibility is enabled
        NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
        BOOL accessibilityEnabled = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
        
        NSLog(@"Accessibility enabled: %@", accessibilityEnabled ? @"YES" : @"NO");
        return;
    }
    
    // Create a run loop source for the event tap
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
    
    // Add the run loop source to the current run loop
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
    
    // Enable the event tap
    CGEventTapEnable(eventTap, true);
    
    NSLog(@"Event tap installed successfully");
    
    // Show the overlay window above all other windows
    [self.overlayWindow orderFront:nil];
    
    // Register for notifications
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillTerminate:)
                                                 name:NSApplicationWillTerminateNotification
                                               object:nil];
}

- (void)screenParametersDidChange:(NSNotification *)notification {
    NSLog(@"Screen parameters changed - updating overlay window frame");
    [self updateOverlayWindowFrame];
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