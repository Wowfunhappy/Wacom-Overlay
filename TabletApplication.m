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
        [self registerForColorNotifications];
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
    // Get the AppDelegate to check if F14 is held down
    AppDelegate *appDelegate = (AppDelegate *)[[NSApplication sharedApplication] delegate];
    BOOL isNormalModeActive = [appDelegate isNormalModeKeyDown];
    
    if (enteringProximity) {
        // Pen is entering proximity - set custom cursor only if not in passthrough mode
        if (!isPenInProximity && customCursor && !isNormalModeActive) {
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
    
    // Get current stroke color from DrawView if possible
    NSColor *initialColor = nil;
    if (overlayWindow != nil) {
        DrawView *drawView = (DrawView *)[overlayWindow contentView];
        if ([drawView respondsToSelector:@selector(strokeColor)]) {
            initialColor = [drawView strokeColor];
        }
    }
    
    // Use the DrawView's color or fallback to red if not available
    if (initialColor != nil) {
        currentCursorColor = [initialColor retain];
        NSLog(@"Using DrawView's current color for cursor: %@", initialColor);
    } else {
        currentCursorColor = [[NSColor redColor] retain];
        NSLog(@"DrawView color not available, using red as default cursor color");
    }
    
    // Create the initial custom cursor
    customCursor = [self createCursorWithColor:currentCursorColor];
    
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
    // Check if F14 is held down (passthrough mode)
    AppDelegate *appDelegate = (AppDelegate *)[[NSApplication sharedApplication] delegate];
    BOOL isNormalModeActive = [appDelegate isNormalModeKeyDown];
    
    // If pen is in proximity and NOT in passthrough mode, ensure custom cursor is active
    if (isPenInProximity && customCursor && !isNormalModeActive) {
        // Forcibly set the cursor back to our custom one
        [customCursor set];
        
        // Every few seconds, reapply the CGS connection property
        static int counter = 0;
        if (++counter % 10 == 0) { // Every ~1 seconds (20 * 0.1s = 2s)
            void *connection = CGSDefaultConnectionForThread();
            if (connection) {
                CFStringRef propertyString = CFSTR("SetsCursorInBackground");
                CFBooleanRef boolVal = kCFBooleanTrue;
                CGSSetConnectionProperty(connection, connection, propertyString, boolVal);
            }
        }
    }
    // If we've entered passthrough mode while pen is in proximity, restore default cursor
    else if (isPenInProximity && isNormalModeActive && defaultCursor) {
        [defaultCursor set];
    }
}

- (NSCursor *)createCursorWithColor:(NSColor *)color {
    // Load the menuIcon image for our custom cursor
    NSString *menuIconPath = [[NSBundle mainBundle] pathForResource:@"menuIcon" ofType:@"png"];
    if (!menuIconPath) {
        NSLog(@"Failed to find menuIcon.png for custom cursor");
        return [[NSCursor arrowCursor] retain];
    }
    
    NSImage *menuImage = [[[NSImage alloc] initWithContentsOfFile:menuIconPath] autorelease];
    if (!menuImage) {
        NSLog(@"Failed to load menuIcon.png for custom cursor");
        return [[NSCursor arrowCursor] retain];
    }
    
    // Create a copy of the image that we can modify with our color
    NSSize imageSize = [menuImage size];
    NSImage *coloredImage = [[NSImage alloc] initWithSize:imageSize];
    
    [coloredImage lockFocus];
    
    // Draw original image as template
    [menuImage drawAtPoint:NSZeroPoint fromRect:NSZeroRect operation:NSCompositeCopy fraction:1.0];
    
    // Apply color
    [color set];
    NSRectFillUsingOperation(NSMakeRect(0, 0, imageSize.width, imageSize.height), NSCompositeSourceAtop);
    
    [coloredImage unlockFocus];
    
    // Create a cursor with the colored image
    NSCursor *cursor = [[NSCursor alloc] initWithImage:coloredImage 
                                              hotSpot:NSMakePoint(0, imageSize.height - 1)];
    
    [coloredImage release];
    
    NSLog(@"Created custom cursor with color: %@", color);
    return cursor;
}

- (void)updateCursorWithColor:(NSColor *)color {
    if (color == nil) {
        return;
    }
    
    // Store the new color
    [currentCursorColor release];
    currentCursorColor = [color retain];
    
    // Create a new cursor with the color
    NSCursor *newCursor = [self createCursorWithColor:color];
    
    // Replace the old cursor
    [customCursor release];
    customCursor = newCursor;
    
    // If pen is in proximity, update the cursor immediately
    if (isPenInProximity) {
        [customCursor set];
    }
    
    NSLog(@"Updated cursor with new color: %@", color);
}

- (void)registerForColorNotifications {
    // Register for color change notifications from DrawView
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleColorChanged:)
                                                 name:@"DrawViewColorChanged"
                                               object:nil];
    
    NSLog(@"Registered for color change notifications");
}

- (void)handleColorChanged:(NSNotification *)notification {
    // Extract the color from the notification
    NSColor *newColor = [[notification userInfo] objectForKey:@"color"];
    if (newColor) {
        [self updateCursorWithColor:newColor];
    }
}

- (void)dealloc {
    // Unregister for notifications
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // Invalidate and release the timer
    if (cursorCheckTimer != nil) {
        [cursorCheckTimer invalidate];
        cursorCheckTimer = nil;
    }
    
    // Clean up our global event monitors
    [self tearDownGlobalEventMonitors];
    
    // Release our cursors and color
    [customCursor release];
    [defaultCursor release];
    [currentCursorColor release];
    
    // Don't release overlayWindow - we don't own it
    [super dealloc];
}

@end