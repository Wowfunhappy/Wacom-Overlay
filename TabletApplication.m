#import "TabletApplication.h"
#import "TabletEvents.h"
#import "OverlayWindow.h"
#import "DrawView.h"
#import "AppDelegate.h"

@implementation TabletApplication

- (void)setOverlayWindow:(OverlayWindow *)window {
    overlayWindow = window; // No retain - window is owned by AppDelegate
    
    // Setup global event monitors once we have a window
    if (overlayWindow != nil) {
        [self setupGlobalEventMonitors];
    }
}

- (OverlayWindow *)overlayWindow {
    return overlayWindow;
}

- (void)setupGlobalEventMonitors {
    NSLog(@"TabletApplication: Setting up global event monitors");
    
    // Setup a global monitor for tablet proximity events
    // NSEventMaskTabletProximity would be 1 << 24 on newer macOS versions
    NSEventMask proximityMask = 1 << 24;
    globalTabletProximityMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:proximityMask
                                                 handler:^(NSEvent *event) {
        NSLog(@"TabletApplication: Global proximity monitor caught event");
        [self handleProximityEvent:event];
    }];
    
    // Setup a global monitor for tablet pointer events (for erasing)
    // Use legacy constants for OS X 10.9
    NSEventMask mouseEventMask = (1 << 1) |  // NSLeftMouseDown
                                 (1 << 6) |  // NSLeftMouseDragged 
                                 (1 << 2);   // NSLeftMouseUp
    
    globalTabletEventMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:mouseEventMask
                                                 handler:^(NSEvent *event) {
        // Only handle tablet events, not regular mouse events
        if ([event isTabletPointerEvent]) {
            NSLog(@"TabletApplication: Global event monitor caught tablet event");
            
            // Get draw view from our overlay window
            if (overlayWindow != nil) {
                DrawView *drawView = (DrawView *)[overlayWindow contentView];
                
                // Forward events to draw view, which will handle the erasing based on the erasing state
                // We need to forward both regular and eraser events to maintain proper state
                [drawView mouseEvent:event];
            }
        }
    }];
    
    // Setup a global monitor for keyboard events
    // NSEventMaskKeyDown would be 1 << 10 on newer macOS versions
    NSEventMask keyEventMask = 1 << 10;  // NSKeyDown
    
    globalKeyEventMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:keyEventMask
                                                handler:^(NSEvent *event) {
        NSLog(@"TabletApplication: Global key monitor caught event: keyCode=%lu, chars=%@", 
             (unsigned long)[event keyCode], [event charactersIgnoringModifiers]);
        [self handleKeyEvent:event];
    }];
}

- (void)tearDownGlobalEventMonitors {
    if (globalTabletEventMonitor != nil) {
        [NSEvent removeMonitor:globalTabletEventMonitor];
        globalTabletEventMonitor = nil;
    }
    
    if (globalTabletProximityMonitor != nil) {
        [NSEvent removeMonitor:globalTabletProximityMonitor];
        globalTabletProximityMonitor = nil;
    }
    
    if (globalKeyEventMonitor != nil) {
        [NSEvent removeMonitor:globalKeyEventMonitor];
        globalKeyEventMonitor = nil;
    }
}

- (void)sendEvent:(NSEvent *)theEvent {
    // Check if this is a tablet event
    if ([theEvent isTabletPointerEvent]) {
        NSLog(@"TabletApplication: Intercepting tablet event: %@", [theEvent description]);
        
        // Get draw view from our overlay window
        if (overlayWindow != nil) {
            DrawView *drawView = (DrawView *)[overlayWindow contentView];
            
            // Forward the event to the draw view
            [drawView mouseEvent:theEvent];
            
            // Don't call super for tablet events - this prevents them from reaching other applications
            return;
        }
    } 
    else if ([theEvent isTabletProximityEvent]) {
        // Handle proximity events
        [self handleProximityEvent:theEvent];
    }
    else if ([theEvent type] == NSKeyDown) {
        // Handle our special key combinations only if they come from the Wacom tablet
        
        // Get the CGEvent from the NSEvent to check the source
        CGEventRef cgEvent = [theEvent CGEvent];
        pid_t eventSourcePID = CGEventGetIntegerValueField(cgEvent, kCGEventSourceUnixProcessID);
        
        // Get the AppDelegate to access the Wacom driver PID
        AppDelegate *appDelegate = (AppDelegate *)[[NSApplication sharedApplication] delegate];
        pid_t wacomDriverPID = [[appDelegate valueForKey:@"wacomDriverPID"] intValue];
        
        // Only process keyboard events from the Wacom driver
        if (wacomDriverPID != 0 && eventSourcePID == wacomDriverPID) {
            NSLog(@"TabletApplication: Keyboard event from Wacom driver detected");
            
            NSUInteger flags = [theEvent modifierFlags];
            NSString *characters = [theEvent charactersIgnoringModifiers];
            
            // In OS X 10.9, we need to use the raw values instead of the constants
            BOOL isControlDown = (flags & (1 << 18)) != 0;   // NSControlKeyMask in 10.9
            BOOL isCommandDown = (flags & (1 << 20)) != 0;   // NSCommandKeyMask in 10.9
            BOOL isOptionDown = (flags & (1 << 19)) != 0;    // NSAlternateKeyMask in 10.9
            BOOL isShiftDown = (flags & (1 << 17)) != 0;     // NSShiftKeyMask in 10.9
            BOOL isC = ([characters isEqualToString:@"C"] || [characters isEqualToString:@"c"]);
            BOOL isZ = ([characters isEqualToString:@"Z"] || [characters isEqualToString:@"z"]);
            
            NSLog(@"TabletApplication: Key event in sendEvent - Control: %d, Command: %d, Option: %d, Shift: %d, IsC: %d, IsZ: %d, chars: %@",
                  isControlDown, isCommandDown, isOptionDown, isShiftDown, isC, isZ, characters);
            
            // Make sure the overlay window is frontmost
            if (overlayWindow != nil) {
                [overlayWindow orderFront:nil];
                DrawView *drawView = (DrawView *)[overlayWindow contentView];
                
                // Handle color toggle
                if (isControlDown && isCommandDown && isOptionDown && isShiftDown && isC) {
                    NSLog(@"TabletApplication: Special color toggle detected in sendEvent");
                    if ([drawView respondsToSelector:@selector(toggleToNextColor)]) {
                        [drawView toggleToNextColor];
                        return; // Don't forward the event
                    }
                }
                
                // Handle undo shortcut
                if (isCommandDown && !isShiftDown && isZ) {
                    NSLog(@"TabletApplication: Undo command detected in sendEvent");
                    if ([drawView respondsToSelector:@selector(canUndo)] && 
                        [drawView respondsToSelector:@selector(undo)]) {
                        if ([drawView canUndo]) {
                            [drawView undo];
                        } else {
                            NSLog(@"TabletApplication: Nothing to undo - but still intercepting event");
                        }
                        return; // Always intercept the event
                    }
                }
                
                // Handle redo shortcut
                if (isCommandDown && isShiftDown && isZ) {
                    NSLog(@"TabletApplication: Redo command detected in sendEvent");
                    if ([drawView respondsToSelector:@selector(canRedo)] && 
                        [drawView respondsToSelector:@selector(redo)]) {
                        if ([drawView canRedo]) {
                            [drawView redo];
                        } else {
                            NSLog(@"TabletApplication: Nothing to redo - but still intercepting event");
                        }
                        return; // Always intercept the event
                    }
                }
            }
        } else {
            NSLog(@"TabletApplication: Keyboard event not from Wacom tablet - passing through");
        }
    }
    
    // Pass all other events (including mouse events) to the standard event system
    [super sendEvent:theEvent];
}

- (void)handleKeyEvent:(NSEvent *)theEvent {
    NSLog(@"TabletApplication: Handling key event");
    
    // Get the CGEvent from the NSEvent to check the source
    CGEventRef cgEvent = [theEvent CGEvent];
    pid_t eventSourcePID = CGEventGetIntegerValueField(cgEvent, kCGEventSourceUnixProcessID);
    
    // Get the AppDelegate to access the Wacom driver PID
    AppDelegate *appDelegate = (AppDelegate *)[[NSApplication sharedApplication] delegate];
    pid_t wacomDriverPID = [[appDelegate valueForKey:@"wacomDriverPID"] intValue];
    
    // Only process keyboard events from the Wacom driver
    if (wacomDriverPID != 0 && eventSourcePID == wacomDriverPID) {
        NSLog(@"TabletApplication: Global keyboard event from Wacom driver detected");
        
        // Check for the special key combination: Ctrl+Cmd+Option+Shift+C
        NSUInteger flags = [theEvent modifierFlags];
        NSString *characters = [theEvent charactersIgnoringModifiers];
        
        // In OS X 10.9, we need to use the raw values instead of the constants
        BOOL isControlDown = (flags & (1 << 18)) != 0;   // NSControlKeyMask in 10.9
        BOOL isCommandDown = (flags & (1 << 20)) != 0;   // NSCommandKeyMask in 10.9
        BOOL isOptionDown = (flags & (1 << 19)) != 0;    // NSAlternateKeyMask in 10.9
        BOOL isShiftDown = (flags & (1 << 17)) != 0;     // NSShiftKeyMask in 10.9
        BOOL isC = ([characters isEqualToString:@"C"] || [characters isEqualToString:@"c"]);
        BOOL isZ = ([characters isEqualToString:@"Z"] || [characters isEqualToString:@"z"]);
        
        NSLog(@"TabletApplication: Key modifiers - Control: %d, Command: %d, Option: %d, Shift: %d, IsC: %d, IsZ: %d, chars: %@",
              isControlDown, isCommandDown, isOptionDown, isShiftDown, isC, isZ, characters);
        
        // First ensure the overlay window is frontmost no matter which space we're on
        if (overlayWindow != nil && [overlayWindow respondsToSelector:@selector(orderFront:)]) {
            [overlayWindow orderFront:nil];
        }
        
        // Handle all relevant keyboard commands
        if (overlayWindow != nil) {
            DrawView *drawView = (DrawView *)[overlayWindow contentView];
            
            // Handle the color toggle shortcut
            if (isControlDown && isCommandDown && isOptionDown && isShiftDown && isC) {
                NSLog(@"TabletApplication: Special color toggle combination detected from Wacom");
                if ([drawView respondsToSelector:@selector(toggleToNextColor)]) {
                    [drawView toggleToNextColor];
                }
            }
            
            // Handle undo command
            if (isCommandDown && !isShiftDown && isZ) {
                NSLog(@"TabletApplication: Undo command detected from Wacom");
                if ([drawView respondsToSelector:@selector(canUndo)] && 
                    [drawView respondsToSelector:@selector(undo)]) {
                    if ([drawView canUndo]) {
                        [drawView undo];
                    } else {
                        NSLog(@"TabletApplication: Nothing to undo - but still intercepting event");
                    }
                }
            }
            
            // Handle redo command
            if (isCommandDown && isShiftDown && isZ) {
                NSLog(@"TabletApplication: Redo command detected from Wacom");
                if ([drawView respondsToSelector:@selector(canRedo)] && 
                    [drawView respondsToSelector:@selector(redo)]) {
                    if ([drawView canRedo]) {
                        [drawView redo];
                    } else {
                        NSLog(@"TabletApplication: Nothing to redo - but still intercepting event");
                    }
                }
            }
        }
    } else {
        NSLog(@"TabletApplication: Global keyboard event not from Wacom tablet - ignoring");
    }
}

- (void)handleProximityEvent:(NSEvent *)theEvent {
    NSLog(@"TabletApplication: Handling proximity event");
    
    NSUInteger vendorID = [theEvent vendorID];
    NSUInteger tabletID = [theEvent tabletID];
    NSUInteger pointingDeviceID = [theEvent pointingDeviceID];
    NSUInteger deviceID = [theEvent deviceID];
    NSUInteger systemTabletID = [theEvent systemTabletID];
    NSUInteger vendorPointingDeviceType = [theEvent vendorPointingDeviceType];
    NSUInteger pointingDeviceSerialNumber = [theEvent pointingDeviceSerialNumber];
    NSUInteger capabilityMask = [theEvent capabilityMask];
    NSPointingDeviceType pointingDeviceType = [theEvent pointingDeviceType];
    BOOL enteringProximity = [theEvent isEnteringProximity];
    
    NSLog(@"Tablet details - deviceID: %lu, entering: %d, type: %lu", 
         (unsigned long)deviceID, enteringProximity, (unsigned long)pointingDeviceType);
    
    // Set up the keys for the dictionary
    NSArray *keys = [NSArray arrayWithObjects:
                     kVendorID,
                     kTabletID,
                     kPointerID,
                     kDeviceID,
                     kSystemTabletID,
                     kVendorPointerType,
                     kPointerSerialNumber,
                     kCapabilityMask,
                     kPointerType,
                     kEnterProximity,
                     nil];
    
    // Setup the data aligned with the keys to create the Dictionary
    NSArray *values = [NSArray arrayWithObjects:
                       [NSValue valueWithBytes:&vendorID objCType:@encode(UInt16)],
                       [NSValue valueWithBytes:&tabletID objCType:@encode(UInt16)],
                       [NSValue valueWithBytes:&pointingDeviceID objCType:@encode(UInt16)],
                       [NSValue valueWithBytes:&deviceID objCType:@encode(UInt16)],
                       [NSValue valueWithBytes:&systemTabletID objCType:@encode(UInt16)],
                       [NSValue valueWithBytes:&vendorPointingDeviceType objCType:@encode(UInt16)],
                       [NSValue valueWithBytes:&pointingDeviceSerialNumber objCType:@encode(UInt32)],
                       [NSValue valueWithBytes:&capabilityMask objCType:@encode(UInt32)],
                       [NSValue valueWithBytes:&pointingDeviceType objCType:@encode(UInt8)],
                       [NSValue valueWithBytes:&enteringProximity objCType:@encode(UInt8)],
                       nil];
    
    // Create the dictionary and post notification
    NSDictionary *proximityDict = [NSDictionary dictionaryWithObjects:values forKeys:keys];
    [[NSNotificationCenter defaultCenter] postNotificationName:kProximityNotification object:self userInfo:proximityDict];
}

- (void)dealloc {
    // Clean up our global event monitors
    [self tearDownGlobalEventMonitors];
    
    // Don't release overlayWindow - we don't own it
    [super dealloc];
}

@end