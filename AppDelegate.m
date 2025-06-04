#import "AppDelegate.h"
#import "OverlayWindow.h"
#import "TabletEvents.h"
#import "ControlPanel.h"
#import "DrawView.h"
#import "TabletApplication.h"
#import <Carbon/Carbon.h>
#include <stdio.h>

@implementation AppDelegate

@synthesize overlayWindow;
@synthesize controlPanel;
@synthesize drawView;
@synthesize wacomDriverPID;
@synthesize statusItem;
@synthesize lastUndoKeyTime;
@synthesize isUndoKeyDown;
@synthesize isNormalModeKeyDown;
@synthesize undoHoldTimer;

// Find the Wacom Tablet Driver PID
- (pid_t)findWacomDriverPID {
    pid_t wacomPID = 0;
    FILE *fp = popen("ps -ax | grep '/Library/Application\\ Support/Tablet/WacomTabletDriver.app/' | grep -v grep", "r");
    if (fp) {
        char path[1024];
        if (fgets(path, sizeof(path), fp)) {
            wacomPID = atoi(path);
        }
        pclose(fp);
    }
    NSLog(@"Found Wacom Tablet Driver with PID: %d", (int)wacomPID);
    return wacomPID;
}

// Define a global to track which events are handled by event tap
static BOOL g_handledByEventTap = NO;

// Event tap callback function
static CGEventRef eventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *userInfo) {
    AppDelegate *appDelegate = (AppDelegate *)userInfo;
    
    // Reset handled flag for each new event
    g_handledByEventTap = NO;
    
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
            // Note: With our TabletEvents.m changes, isTabletPointerEvent will
            // already return false when F14 is pressed, so this condition won't be true in normal mode
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
        
        // Get our draw view
        DrawView *drawView = appDelegate.drawView;
        
        // Handle mouse events appropriately
        if (type == kCGEventLeftMouseDown) {
            // Forward the click to DrawView to check for strokes and handle selection
            [drawView mouseEvent:nsEvent];
            
            // Check if a stroke or text was actually selected
            BOOL wasStrokeSelected = [[drawView valueForKey:@"isStrokeSelected"] boolValue];
            BOOL isDragging = [[drawView valueForKey:@"isDraggingStroke"] boolValue];
            
            if (wasStrokeSelected || isDragging) {
                // A stroke or text was selected, capture the event
                return NULL; // Return NULL to stop event propagation
            }
        }
        // For other mouse events, handle dragging if we have a selected stroke
        else if (type == kCGEventLeftMouseDragged) {
            // If we're already dragging a stroke, continue the drag operation
            if ([[drawView valueForKey:@"isDraggingStroke"] boolValue]) {
                [drawView mouseEvent:nsEvent];
                return NULL; // Capture during drag
            }
        }
        // For mouse up, complete any drag operation
        else if (type == kCGEventLeftMouseUp) {
            if ([[drawView valueForKey:@"isDraggingStroke"] boolValue]) {
                [drawView mouseEvent:nsEvent];
                return NULL; // Capture to complete the drag
            }
        }
        // For mouse move events, let them through without any special handling
        else if (type == kCGEventMouseMoved) {
            // No cursor changing for hover feedback
        }
    }
    // Check if this is a keyboard event
    else if (type == kCGEventKeyDown) {
        NSLog(@"Key down event captured in event tap: %@", nsEvent);
        
        // Get the source process ID of the event
        pid_t eventSourcePID = CGEventGetIntegerValueField(event, kCGEventSourceUnixProcessID);
        NSLog(@"EVENT TAP: Event source PID: %d, Wacom PID: %d", (int)eventSourcePID, (int)appDelegate.wacomDriverPID);
        
        // Only handle keyboard events from the Wacom driver
        if (appDelegate.wacomDriverPID != 0 && eventSourcePID == appDelegate.wacomDriverPID) {
            NSLog(@"EVENT TAP: Blocking ALL keyboard events from Wacom tablet");
            
            // First process the event by our app
            NSUInteger flags = [nsEvent modifierFlags];
            NSString *characters = [nsEvent charactersIgnoringModifiers];
            
            // In OS X 10.9, use the raw bit values
            BOOL isCommandDown = (flags & (1 << 20)) != 0;   // NSCommandKeyMask in 10.9
            BOOL isShiftDown = (flags & (1 << 17)) != 0;     // NSShiftKeyMask in 10.9
            BOOL isControlDown = (flags & (1 << 18)) != 0;   // NSControlKeyMask in 10.9
            BOOL isOptionDown = (flags & (1 << 19)) != 0;    // NSAlternateKeyMask in 10.9
            BOOL isC = ([characters isEqualToString:@"C"] || [characters isEqualToString:@"c"]);
            BOOL isZ = ([characters isEqualToString:@"Z"] || [characters isEqualToString:@"z"]);
            BOOL isD = ([characters isEqualToString:@"D"] || [characters isEqualToString:@"d"]);
            BOOL isT = ([characters isEqualToString:@"T"] || [characters isEqualToString:@"t"]);
            
            // Track whether we handled this event
            BOOL eventHandled = NO;
            
            // Make sure the overlay window and drawing view are active
            [appDelegate.overlayWindow orderFront:nil];
            
            // Get the draw view
            DrawView *drawView = appDelegate.drawView;
            if (!drawView) {
                // Try to get the draw view if it's not directly available
                TabletApplication *app = (TabletApplication *)NSApp;
                OverlayWindow *window = [app overlayWindow];
                if (window) {
                    drawView = (DrawView *)[window contentView];
                }
            }
            
            if (drawView) {
                // Handle special toggle with Ctrl+Cmd+Opt+Shift+C
                if (isControlDown && isCommandDown && isOptionDown && isShiftDown && isC) {
                    NSLog(@"EVENT TAP: Special color toggle detected");
                    if ([drawView respondsToSelector:@selector(toggleToNextColor)]) {
                        [drawView toggleToNextColor];
                    }
                    eventHandled = YES;
                }
                // Handle F14 to temporarily act as a normal mouse while pressed
                else if ([nsEvent keyCode] == 107) { // F14 key code
                    NSLog(@"EVENT TAP: F14 detected - temporarily disabling tablet interception");
                    // Set the flag to indicate normal mode is active
                    appDelegate.isNormalModeKeyDown = YES;
                    
                    // If pen is in proximity, immediately restore default cursor
                    TabletApplication *app = (TabletApplication *)NSApp;
                    id proximityValue = [app valueForKey:@"isPenInProximity"];
                    BOOL isPenInProximity = [proximityValue boolValue];
                    if (isPenInProximity) {
                        // Get default cursor and set it
                        NSCursor *defaultCursor = [app valueForKey:@"defaultCursor"];
                        if (defaultCursor) {
                            [defaultCursor set];
                        }
                    }
                    
                    eventHandled = YES;
                } 
                // Handle undo (Cmd+Z)
                else if (isCommandDown && !isShiftDown && isZ) {
                    // Get the current time
                    NSDate *now = [NSDate date];
                    
                    // Mark that the undo key is down
                    appDelegate.isUndoKeyDown = YES;
                    
                    // Cancel any existing timer
                    if (appDelegate.undoHoldTimer) {
                        [appDelegate.undoHoldTimer invalidate];
                        appDelegate.undoHoldTimer = nil;
                    }
                    
                    // Create a new timer that will trigger after holding the key for 0.5 seconds
                    appDelegate.undoHoldTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                                      target:appDelegate
                                                                    selector:@selector(undoKeyHoldTimerFired:)
                                                                    userInfo:nil
                                                                     repeats:NO];
                    
                    // Store the current time
                    appDelegate.lastUndoKeyTime = [now retain];
                    
                    NSLog(@"EVENT TAP: Cmd+Z - undo detected, starting hold timer");
                    
                    // Perform a normal undo for the initial key press
                    if ([drawView respondsToSelector:@selector(canUndo)] && 
                        [drawView respondsToSelector:@selector(undo)]) {
                        if ([drawView canUndo]) {
                            [drawView undo];
                        }
                    }
                    eventHandled = YES;
                }
                // Handle redo (Cmd+Shift+Z)
                else if (isCommandDown && isShiftDown && isZ) {
                    NSLog(@"EVENT TAP: Cmd+Shift+Z - redo detected");
                    if ([drawView respondsToSelector:@selector(canRedo)] && 
                        [drawView respondsToSelector:@selector(redo)]) {
                        if ([drawView canRedo]) {
                            [drawView redo];
                        }
                    }
                    eventHandled = YES;
                }
                // Handle color toggle (Cmd+D)
                else if (isCommandDown && isD && !isShiftDown) {
                    NSLog(@"EVENT TAP: Cmd+D - color toggle detected");
                    if ([drawView respondsToSelector:@selector(toggleToNextColor)]) {
                        [drawView toggleToNextColor];
                    }
                    eventHandled = YES;
                }
                // Handle text input mode toggle (Cmd+Option+Shift+T)
                else if (isCommandDown && isOptionDown && isShiftDown && isT) {
                    NSLog(@"EVENT TAP: Cmd+Option+Shift+T - text input mode toggle detected");
                    if ([drawView respondsToSelector:@selector(enterTextInputMode)]) {
                        [drawView enterTextInputMode];
                    }
                    eventHandled = YES;
                }
            }
            
            // Only block the event if we actually handled it
            if (eventHandled) {
                NSLog(@"EVENT TAP: Blocking handled keyboard event from Wacom tablet");
                return NULL;
            } else {
                NSLog(@"EVENT TAP: Passing through unhandled keyboard event from Wacom tablet");
                return event;
            }
        } else {
            NSLog(@"EVENT TAP: Keyboard event not from Wacom tablet - checking for text input shortcut");
            
            // Check for text input mode toggle from regular keyboard (Cmd+Option+Shift+T)
            NSUInteger flags = [nsEvent modifierFlags];
            NSString *characters = [nsEvent charactersIgnoringModifiers];
            
            BOOL isCommandDown = (flags & (1 << 20)) != 0;   // NSCommandKeyMask in 10.9
            BOOL isShiftDown = (flags & (1 << 17)) != 0;     // NSShiftKeyMask in 10.9
            BOOL isOptionDown = (flags & (1 << 19)) != 0;    // NSAlternateKeyMask in 10.9
            BOOL isT = ([characters isEqualToString:@"T"] || [characters isEqualToString:@"t"]);
            
            if (isCommandDown && isOptionDown && isShiftDown && isT) {
                NSLog(@"EVENT TAP: Cmd+Option+Shift+T from regular keyboard - text input mode toggle detected");
                
                // Get the draw view
                DrawView *drawView = appDelegate.drawView;
                if (!drawView) {
                    TabletApplication *app = (TabletApplication *)NSApp;
                    OverlayWindow *window = [app overlayWindow];
                    if (window) {
                        drawView = (DrawView *)[window contentView];
                    }
                }
                
                if (drawView && [drawView respondsToSelector:@selector(enterTextInputMode)]) {
                    [drawView enterTextInputMode];
                }
                
                // Block this shortcut from being processed by other apps
                return NULL;
            }
        }
    }
    // Handle key up events
    else if (type == kCGEventKeyUp) {
        // Get the source process ID of the event
        pid_t eventSourcePID = CGEventGetIntegerValueField(event, kCGEventSourceUnixProcessID);
        
        // Only handle keyboard events from the Wacom driver
        if (appDelegate.wacomDriverPID != 0 && eventSourcePID == appDelegate.wacomDriverPID) {
            // Get event details
            NSUInteger flags = [nsEvent modifierFlags];
            NSString *characters = [nsEvent charactersIgnoringModifiers];
            
            // In OS X 10.9, use the raw bit values
            BOOL isShiftDown = (flags & (1 << 17)) != 0;     // NSShiftKeyMask in 10.9
            BOOL isZ = ([characters isEqualToString:@"Z"] || [characters isEqualToString:@"z"]);
            BOOL isT = ([characters isEqualToString:@"T"] || [characters isEqualToString:@"t"]);
            
            // Track whether we handled this event
            BOOL eventHandled = NO;
            
            // Handle F14 key up (normal mode toggle off) - we need to check actual key codes
            // Since F14 key release might not match the same character representation
            NSUInteger keyCode = [nsEvent keyCode];
            if (keyCode == 107) { // F14 key code
                NSLog(@"EVENT TAP: F14 key up detected - re-enabling tablet interception");
                appDelegate.isNormalModeKeyDown = NO;
                
                // If pen is in proximity, restore custom cursor
                TabletApplication *app = (TabletApplication *)NSApp;
                id proximityValue = [app valueForKey:@"isPenInProximity"];
                BOOL isPenInProximity = [proximityValue boolValue];
                if (isPenInProximity) {
                    // Get custom cursor and set it
                    NSCursor *customCursor = [app valueForKey:@"customCursor"];
                    if (customCursor) {
                        [customCursor set];
                    }
                }
                
                eventHandled = YES;
            }
            // Check if this is the undo key releasing
            else if (isZ && !isShiftDown) {
                NSLog(@"EVENT TAP: Cmd+Z key up detected");
                
                // Mark undo key as no longer down
                appDelegate.isUndoKeyDown = NO;
                
                // Cancel the hold timer if it exists
                if (appDelegate.undoHoldTimer) {
                    [appDelegate.undoHoldTimer invalidate];
                    appDelegate.undoHoldTimer = nil;
                }
                
                // Release the stored time
                [appDelegate.lastUndoKeyTime release];
                appDelegate.lastUndoKeyTime = nil;
                
                eventHandled = YES;
            }
            
            // Only block the event if we actually handled it
            if (eventHandled) {
                NSLog(@"EVENT TAP: Blocking handled key up event from Wacom tablet");
                return NULL;
            } else {
                NSLog(@"EVENT TAP: Passing through unhandled key up event from Wacom tablet");
                return event;
            }
        }
    }
    
    // Let all other events through
    return event;
}

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

- (void)setupStatusBarMenu {
    // Create the status bar item
    self.statusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength] retain];
    
    // Set the image for the status item
    NSString *menuIconPath = [[NSBundle mainBundle] pathForResource:@"menuIcon" ofType:@"png"];
    NSImage *statusImage = nil;
    
    if (menuIconPath) {
        statusImage = [[[NSImage alloc] initWithContentsOfFile:menuIconPath] autorelease];
    }
    
    if (statusImage) {
        // First, create a proper template image that works with menu bar
        NSImage *templateImage = [[[NSImage alloc] initWithSize:NSMakeSize(18, 18)] autorelease];
        
        [templateImage lockFocus];
        
        // Create a mask-friendly version (black and transparent only)
        [[NSColor blackColor] set];
        
        // Draw the original image as black silhouette
        [statusImage drawAtPoint:NSZeroPoint fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
        
        [templateImage unlockFocus];
        
        // Mark as template image (macOS will automatically invert when selected)
        [templateImage setTemplate:YES];
        
        // Set as the status item image
        [statusItem setImage:templateImage];
        
        // Still enable highlight mode just to be sure
        [statusItem setHighlightMode:YES];
    } else {
        // Fallback to text if image not found
        [statusItem setTitle:@"✏️"];
    }
    
    // Create the menu
    NSMenu *menu = [[[NSMenu alloc] init] autorelease];
    
    // 1. Clear Drawing
    NSMenuItem *clearItem = [[[NSMenuItem alloc] initWithTitle:@"Clear Drawing" 
                                                      action:@selector(clearDrawing:) 
                                               keyEquivalent:@""] autorelease];
    [clearItem setTarget:self];
    [menu addItem:clearItem];
    
    // 2. Change Color submenu
    NSMenuItem *colorItem = [[[NSMenuItem alloc] initWithTitle:@"Change Color" 
                                                      action:nil 
                                               keyEquivalent:@""] autorelease];
    colorMenu = [[NSMenu alloc] init]; // Store in our global variable
    [colorItem setSubmenu:colorMenu];
    [menu addItem:colorItem];
    
    // Will populate color menu dynamically when shown
    [colorMenu setDelegate:(id<NSMenuDelegate>)self];
    
    // 3. Open Controls...
    NSMenuItem *controlsItem = [[[NSMenuItem alloc] initWithTitle:@"Open Controls..." 
                                                         action:@selector(openControls:) 
                                                  keyEquivalent:@""] autorelease];
    [controlsItem setTarget:self];
    [menu addItem:controlsItem];
    
    // Add separator
    [menu addItem:[NSMenuItem separatorItem]];
    
    // 4. Quit
    NSMenuItem *quitItem = [[[NSMenuItem alloc] initWithTitle:@"Quit" 
                                                    action:@selector(terminate:) 
                                             keyEquivalent:@"q"] autorelease];
    [quitItem setTarget:NSApp];
    [menu addItem:quitItem];
    
    // Set the menu
    [statusItem setMenu:menu];
}

// Open Controls window
- (void)openControls:(id)sender {
    if (self.controlPanel) {
        [NSApp activateIgnoringOtherApps:YES];
        [self.controlPanel orderFrontRegardless];
        [self.controlPanel makeKeyAndOrderFront:nil];
    }
}

// Clear Drawing action
- (void)clearDrawing:(id)sender {
    if (self.drawView) {
        [self.drawView clear];
    }
}

// For storing menu references
NSMenu *colorMenu = nil;

// Menu delegate method to update color menu
- (void)menuNeedsUpdate:(NSMenu *)menu {
    // Check if this is our color submenu
    if (colorMenu == menu) {
        // Clear existing items
        [menu removeAllItems];
        
        // Get the current color index and preset colors
        NSInteger currentIndex = [self.drawView currentColorIndex];
        NSArray *presetColors = [self.drawView presetColors];
        
        // Add menu items for all colors
        for (NSInteger i = 0; i < [presetColors count]; i++) {
            NSColor *color = [presetColors objectAtIndex:i];
            
            // Create menu item with no title, just showing the color swatch
            NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:@"" 
                                                          action:@selector(changeToColor:) 
                                                   keyEquivalent:@""] autorelease];
            [item setTag:i]; // Store color index in tag
            [item setTarget:self];
            
            // Create color swatch
            NSImage *swatchImage = [[[NSImage alloc] initWithSize:NSMakeSize(16, 16)] autorelease];
            [swatchImage lockFocus];
            [color set];
            NSRectFill(NSMakeRect(0, 0, 16, 16));
            [[NSColor blackColor] set];
            NSFrameRect(NSMakeRect(0, 0, 16, 16));
            [swatchImage unlockFocus];
            
            [item setImage:swatchImage];
            
            // Add a check mark to the current color
            if (i == currentIndex) {
                [item setState:NSOnState];
            }
            
            [menu addItem:item];
        }
    }
}

// Change to selected color
- (void)changeToColor:(id)sender {
    NSInteger colorIndex = [sender tag];
    
    // Only change if it's a different color than the current one
    if (colorIndex != [self.drawView currentColorIndex]) {
        // Set the current color index
        [self.drawView setCurrentColorIndex:colorIndex];
        
        // Update the stroke color
        NSArray *presetColors = [self.drawView presetColors];
        if (colorIndex < [presetColors count]) {
            NSColor *newColor = [presetColors objectAtIndex:colorIndex];
            
            // Instead of using setStrokeColor accessor, we'll modify the property directly
            // and post the notification ourselves to ensure it's triggered
            DrawView *dv = self.drawView;
            if ([dv strokeColor] != newColor) {
                [[dv strokeColor] release];
                [dv setValue:[newColor retain] forKey:@"strokeColor"];
                
                // Post a color change notification for the cursor
                NSDictionary *userInfo = [NSDictionary dictionaryWithObject:newColor forKey:@"color"];
                [[NSNotificationCenter defaultCenter] postNotificationName:@"DrawViewColorChanged"
                                                                  object:dv
                                                                userInfo:userInfo];
                
                NSLog(@"AppDelegate: Posted color change notification for menu bar color change with color: %@", newColor);
            }
            
            // Update color well in control panel if it's open
            if (self.controlPanel) {
                NSColorWell *colorWell = [self.controlPanel valueForKey:@"colorWell"];
                if (colorWell) {
                    [colorWell setColor:newColor];
                }
            }
        }
    }
}

// This method is called after the undo key has been held down for a moment
- (void)undoKeyHoldTimerFired:(NSTimer *)timer {
    NSLog(@"EVENT TAP: Undo key hold timer fired - clearing drawing");
    
    // Only clear if the undo key is still down
    if (self.isUndoKeyDown) {
        if ([self.drawView respondsToSelector:@selector(clear)]) {
            [self.drawView clear];
        }
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Initialize key state trackers
    self.isUndoKeyDown = NO;
    self.isNormalModeKeyDown = NO;
    self.lastUndoKeyTime = nil;
    
    // Find the Wacom driver PID
    wacomDriverPID = [self findWacomDriverPID];
    if (wacomDriverPID == 0) {
        NSLog(@"Warning: Wacom Tablet Driver not found. Keyboard shortcuts will pass through.");
    } else {
        NSLog(@"Wacom Tablet Driver found with PID: %d", (int)wacomDriverPID);
    }
    
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
    
    // Create the control panel but don't show it by default
    self.controlPanel = [[ControlPanel alloc] initWithDrawView:self.drawView];
    
    // Show the overlay window
    [self.overlayWindow makeKeyAndOrderFront:nil];
    
    // Connect overlay window with TabletApplication
    TabletApplication *app = (TabletApplication *)NSApp;
    [app setOverlayWindow:self.overlayWindow];
    
    // Setup status bar menu
    [self setupStatusBarMenu];
    
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
                            CGEventMaskBit(kCGEventKeyUp);   // Make sure we capture key up events too
    
    // Create the event tap at the session level
    // Previously: kCGHIDEventTap, but this might not block events properly
    // Switch to kCGSessionEventTap to ensure events are fully intercepted 
    eventTap = CGEventTapCreate(kCGSessionEventTap,   // Session level tap to intercept before dispatch to apps
                                kCGHeadInsertEventTap, // Insert at beginning of list
                                0,                     // Default options, NOT kCGEventTapOptionDefault
                                eventMask,             // Events to capture
                                eventTapCallback,      // Callback function
                                self);                 // User data passed to callback
    
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
    
    // Clean up timers
    if (self.undoHoldTimer) {
        [self.undoHoldTimer invalidate];
        self.undoHoldTimer = nil;
    }
    
    // Release the stored time
    [self.lastUndoKeyTime release];
    self.lastUndoKeyTime = nil;
    
    // No need to clean up key tracking dictionary as we're not using it anymore
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
    
    if (undoHoldTimer) {
        [undoHoldTimer invalidate];
    }
    
    [undoHoldTimer release];
    [lastUndoKeyTime release];
    [overlayWindow release];
    [controlPanel release];
    [drawView release];
    [statusItem release];
    [colorMenu release];
    [super dealloc];
}

@end
