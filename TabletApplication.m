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
        [self setupCustomCursor];
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
        // Note: isTabletPointerEvent will return false when F14 is pressed due to our override
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
    
    // DISABLED: Global key event monitor - could be causing double event handling
    // Now relying only on the event tap in AppDelegate to intercept all keyboard shortcuts
    globalKeyEventMonitor = nil;
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
    // Note: isTabletPointerEvent will return false when F14 is pressed due to our override
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
        // Get the CGEvent to check source
        CGEventRef cgEvent = [theEvent CGEvent];
        
        // Check if this is from the Wacom tablet
        pid_t eventSourcePID = CGEventGetIntegerValueField(cgEvent, kCGEventSourceUnixProcessID);
        
        // Get the AppDelegate to access the Wacom driver PID
        AppDelegate *appDelegate = (AppDelegate *)[[NSApplication sharedApplication] delegate];
        pid_t wacomDriverPID = [[appDelegate valueForKey:@"wacomDriverPID"] intValue];
        
        // Only handle keyboard events from the Wacom driver
        if (wacomDriverPID != 0 && eventSourcePID == wacomDriverPID) {
            NSLog(@"TabletApplication: BLOCKING keyboard event from Wacom in sendEvent");
            
            // NEVER call super.sendEvent for Wacom keyboard events
            // This ensures they are never passed to the responder chain
            return;
        } else {
            NSLog(@"TabletApplication: Non-Wacom keyboard event in sendEvent");
        }
    }
    
    // Pass all other events (including mouse events) to the standard event system
    [super sendEvent:theEvent];
}

- (void)handleKeyEvent:(NSEvent *)theEvent {
    // This method is now disabled since we're no longer using the global key monitor
    // All keyboard handling occurs in the AppDelegate's event tap
    NSLog(@"TabletApplication: handleKeyEvent called but global monitor is disabled");
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
    
    // Change the cursor when pen enters or leaves proximity
    if (enteringProximity) {
        // Pen is entering proximity - set custom cursor
        if (!isPenInProximity && customCursor) {
            NSLog(@"Setting custom cursor - pen entering proximity");
            [customCursor set];
            isPenInProximity = YES;
            
            // Start timer to periodically enforce custom cursor
            if (cursorCheckTimer == nil) {
                cursorCheckTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 // 100ms interval
                                                                target:self
                                                              selector:@selector(enforceCursor:)
                                                              userInfo:nil
                                                               repeats:YES];
                NSLog(@"Started cursor check timer to enforce custom cursor");
            }
        }
    } else {
        // Pen is leaving proximity - restore default cursor
        if (isPenInProximity && defaultCursor) {
            NSLog(@"Restoring default cursor - pen leaving proximity");
            [defaultCursor set];
            isPenInProximity = NO;
            
            // Stop the cursor check timer
            if (cursorCheckTimer != nil) {
                [cursorCheckTimer invalidate];
                cursorCheckTimer = nil;
                NSLog(@"Stopped cursor check timer");
            }
        }
    }
    
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

- (void)setupCustomCursor {
    // Initialize pen proximity flag
    isPenInProximity = NO;
    
    // Store the default cursor for later use
    defaultCursor = [[NSCursor arrowCursor] retain];
    
    // Load the menuIcon image for our custom cursor
    NSString *menuIconPath = [[NSBundle mainBundle] pathForResource:@"menuIcon" ofType:@"png"];
    if (menuIconPath) {
        NSImage *menuImage = [[[NSImage alloc] initWithContentsOfFile:menuIconPath] autorelease];
        
        if (menuImage) {
            // Create a cursor with the hotspot at the bottom left (tip of the pencil)
            // Get the image size to properly set the bottom left position
            NSSize imageSize = [menuImage size];
            // NSCursor coordinates have (0,0) at the bottom left, going up to (width,height)
            // Since our image is showing the hotspot is currently at top left,
            // we need to flip it and set it at y = height - offset
            customCursor = [[NSCursor alloc] initWithImage:menuImage hotSpot:NSMakePoint(0, imageSize.height - 1)];
            NSLog(@"Custom pen cursor created successfully with hotspot at bottom left");
        } else {
            NSLog(@"Failed to load menuIcon.png for custom cursor");
            customCursor = [defaultCursor retain];
        }
    } else {
        NSLog(@"Failed to find menuIcon.png for custom cursor");
        customCursor = [defaultCursor retain];
    }
    
    // Enable setting cursor in background when app is not focused
    // This uses an undocumented system call to allow cursor setting when not in foreground
    void *connection = CGSDefaultConnectionForThread();
    if (connection) {
        CFStringRef propertyString = CFSTR("SetsCursorInBackground");
        CFBooleanRef boolVal = kCFBooleanTrue;
        CGSSetConnectionProperty(connection, connection, propertyString, boolVal);
        NSLog(@"Enabled SetsCursorInBackground for custom cursor visibility when app loses focus");
    } else {
        NSLog(@"Warning: Could not get CGS connection for setting cursor in background");
    }
}

- (void)enforceCursor:(NSTimer *)timer {
    // If pen is in proximity, ensure custom cursor is active
    if (isPenInProximity && customCursor) {
        // Forcibly set the cursor back to our custom one
        [customCursor set];
        
        // Every few seconds, reapply the CGS connection property
        static int counter = 0;
        if (++counter % 20 == 0) { // Every ~2 seconds (20 * 0.1s = 2s)
            void *connection = CGSDefaultConnectionForThread();
            if (connection) {
                CFStringRef propertyString = CFSTR("SetsCursorInBackground");
                CFBooleanRef boolVal = kCFBooleanTrue;
                CGSSetConnectionProperty(connection, connection, propertyString, boolVal);
            }
        }
    }
}

- (void)dealloc {
    // Invalidate and release the timer
    if (cursorCheckTimer != nil) {
        [cursorCheckTimer invalidate];
        cursorCheckTimer = nil;
    }
    
    // Clean up our global event monitors
    [self tearDownGlobalEventMonitors];
    
    // Release our cursors
    [customCursor release];
    [defaultCursor release];
    
    // Don't release overlayWindow - we don't own it
    [super dealloc];
}

@end