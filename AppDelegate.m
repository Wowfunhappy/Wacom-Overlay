#import "AppDelegate.h"
#import "OverlayWindow.h"
#import "TabletEvents.h"
#import "ControlPanel.h"
#import "DrawView.h"
#import "TabletApplication.h"
#import <Carbon/Carbon.h>
#include <stdio.h>

@implementation AppDelegate

@synthesize overlayWindow, controlPanel, drawView, wacomDriverPID;
@synthesize statusItem, lastUndoKeyTime, isUndoKeyDown, isNormalModeKeyDown, undoHoldTimer;

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
    return wacomPID;
}

#pragma mark - Event Handling Helpers

- (BOOL)parseModifierFlags:(NSUInteger)flags cmd:(BOOL *)cmd shift:(BOOL *)shift option:(BOOL *)option {
    if (cmd) *cmd = (flags & (1 << 20)) != 0;
    if (shift) *shift = (flags & (1 << 17)) != 0;  
    if (option) *option = (flags & (1 << 19)) != 0;
    return YES;
}

- (DrawView *)getDrawView {
    if (drawView) return drawView;
    TabletApplication *app = (TabletApplication *)NSApp;
    OverlayWindow *window = [app overlayWindow];
    return window ? (DrawView *)[window contentView] : nil;
}

- (BOOL)handleTabletEvent:(NSEvent *)nsEvent type:(CGEventType)type {
    if ([nsEvent isTabletProximityEvent]) {
        TabletApplication *app = (TabletApplication *)NSApp;
        if ([app respondsToSelector:@selector(handleProximityEvent:)]) {
            [app handleProximityEvent:nsEvent];
        }
        return YES;
    }
    
    if ([nsEvent isTabletPointerEvent]) {
        [[self getDrawView] mouseEvent:nsEvent];
        return YES;
    }
    
    return NO;
}

- (BOOL)handleMouseEvent:(NSEvent *)nsEvent type:(CGEventType)type {
    DrawView *view = [self getDrawView];
    
    switch (type) {
        case kCGEventLeftMouseDown:
            // Forward the click to DrawView to check for strokes and handle selection
            [view mouseEvent:nsEvent];
            
            // Check if a stroke or text was actually selected
            BOOL wasStrokeSelected = [[view valueForKey:@"isStrokeSelected"] boolValue];
            BOOL isDragging = [[view valueForKey:@"isDraggingStroke"] boolValue];
            
            if (wasStrokeSelected || isDragging) {
                // A stroke or text was selected, capture the event
                return YES; // Block event propagation
            }
            return NO;
            
        case kCGEventLeftMouseDragged: {
            BOOL isDragging = [[view valueForKey:@"isDraggingStroke"] boolValue];
            BOOL isEditingText = [[view valueForKey:@"isEditingText"] boolValue];
            NSInteger selectedTextField = [[view valueForKey:@"selectedTextFieldIndex"] integerValue];
            
            // Forward drag events if we're dragging or have a text field selected
            if (isDragging || (!isDragging && selectedTextField >= 0)) {
                [view mouseEvent:nsEvent];
                return YES; // Capture during drag
            }
            
            // If we're editing text and no text field is selected for dragging,
            // let the drag through for text selection
            if (isEditingText && selectedTextField < 0) {
                return NO; // Let it through for text selection
            }
            return NO;
        }
            
        case kCGEventLeftMouseUp:
            if ([[view valueForKey:@"isDraggingStroke"] boolValue]) {
                [view mouseEvent:nsEvent];
                // Let the event through after processing - prevents mouse from getting "stuck"
                return NO;
            }
            return NO;
            
        default:
            return NO;
    }
}

- (BOOL)handleKeyboardEvent:(NSEvent *)nsEvent type:(CGEventType)type isFromWacom:(BOOL)isFromWacom {
    if (!isFromWacom && type == kCGEventKeyDown) {
        BOOL cmd, shift, option;
        [self parseModifierFlags:[nsEvent modifierFlags] cmd:&cmd shift:&shift option:&option];
        NSString *chars = [[nsEvent charactersIgnoringModifiers] lowercaseString];
        
        if (cmd && option && shift && [chars isEqualToString:@"t"]) {
            [[self getDrawView] enterTextInputMode];
            return YES;
        }
        return NO;
    }
    
    if (!isFromWacom) return NO;
    
    NSUInteger keyCode = [nsEvent keyCode];
    BOOL cmd, shift, option;
    [self parseModifierFlags:[nsEvent modifierFlags] cmd:&cmd shift:&shift option:&option];
    NSString *chars = [[nsEvent charactersIgnoringModifiers] lowercaseString];
    
    if (type == kCGEventKeyDown) {
        if (keyCode == 107) { // F14
            self.isNormalModeKeyDown = YES;
            [self updateCursorForNormalMode:YES];
            return YES;
        }
        
        if (cmd && !shift && [chars isEqualToString:@"z"]) {
            [self handleUndoKeyDown];
            return YES;
        }
        
        if (cmd && shift && [chars isEqualToString:@"z"]) {
            DrawView *view = [self getDrawView];
            if ([view canRedo]) [view redo];
            return YES;
        }
        
        if (cmd && !shift && [chars isEqualToString:@"d"]) {
            [[self getDrawView] toggleToNextColor];
            return YES;
        }
        
        if (cmd && option && shift && [chars isEqualToString:@"t"]) {
            [[self getDrawView] enterTextInputMode];
            return YES;
        }
    } else if (type == kCGEventKeyUp) {
        if (keyCode == 107) { // F14
            self.isNormalModeKeyDown = NO;
            [self updateCursorForNormalMode:NO];
            return YES;
        }
        
        if ([chars isEqualToString:@"z"] && !shift) {
            [self handleUndoKeyUp];
            return YES;
        }
    }
    
    return NO;
}

- (void)handleUndoKeyDown {
    self.isUndoKeyDown = YES;
    [self.undoHoldTimer invalidate];
    self.undoHoldTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                          target:self
                                                        selector:@selector(undoKeyHoldTimerFired:)
                                                        userInfo:nil
                                                         repeats:NO];
    self.lastUndoKeyTime = [[NSDate date] retain];
    
    DrawView *view = [self getDrawView];
    if ([view canUndo]) [view undo];
}

- (void)handleUndoKeyUp {
    self.isUndoKeyDown = NO;
    [self.undoHoldTimer invalidate];
    self.undoHoldTimer = nil;
    [self.lastUndoKeyTime release];
    self.lastUndoKeyTime = nil;
}

- (void)updateCursorForNormalMode:(BOOL)normalMode {
    TabletApplication *app = (TabletApplication *)NSApp;
    BOOL isPenInProximity = [[app valueForKey:@"isPenInProximity"] boolValue];
    if (!isPenInProximity) return;
    
    NSCursor *cursor = normalMode ? [app valueForKey:@"defaultCursor"] : [app valueForKey:@"customCursor"];
    if (cursor) [cursor set];
}

- (void)undoKeyHoldTimerFired:(NSTimer *)timer {
    if (self.isUndoKeyDown) {
        [[self getDrawView] clear];
    }
}

#pragma mark - Event Tap Callback

static CGEventRef eventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *userInfo) {
    AppDelegate *appDelegate = (AppDelegate *)userInfo;
    
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        CGEventTapEnable(appDelegate->eventTap, true);
        return event;
    }
    
    NSEvent *nsEvent = [NSEvent eventWithCGEvent:event];
    
    // Check if this is a tablet event
    if ([nsEvent isTabletPointerEvent] || [nsEvent isTabletProximityEvent]) {
        if ([appDelegate handleTabletEvent:nsEvent type:type]) {
            return NULL;
        }
    }
    // Handle mouse events (for selecting and dragging strokes) - ONLY if not a tablet event
    else if (type == kCGEventLeftMouseDown || 
             type == kCGEventLeftMouseDragged || 
             type == kCGEventLeftMouseUp ||
             type == kCGEventMouseMoved) {
        if ([appDelegate handleMouseEvent:nsEvent type:type]) {
            return NULL;
        }
    }
    
    if (type == kCGEventKeyDown || type == kCGEventKeyUp) {
        pid_t eventPID = CGEventGetIntegerValueField(event, kCGEventSourceUnixProcessID);
        BOOL isFromWacom = (appDelegate.wacomDriverPID != 0 && eventPID == appDelegate.wacomDriverPID);
        
        if ([appDelegate handleKeyboardEvent:nsEvent type:type isFromWacom:isFromWacom]) {
            return NULL;
        }
    }
    
    return event;
}

#pragma mark - UI Setup

- (NSRect)totalScreensRect {
    NSRect totalRect = NSZeroRect;
    for (NSScreen *screen in [NSScreen screens]) {
        totalRect = NSIsEmptyRect(totalRect) ? [screen frame] : NSUnionRect(totalRect, [screen frame]);
    }
    return NSIsEmptyRect(totalRect) ? [[NSScreen mainScreen] frame] : totalRect;
}

- (void)updateOverlayWindowFrame {
    [self.overlayWindow setFrame:[self totalScreensRect] display:YES];
}

- (void)setupStatusBarMenu {
    self.statusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength] retain];
    
    NSString *menuIconPath = [[NSBundle mainBundle] pathForResource:@"menuIcon" ofType:@"png"];
    NSImage *statusImage = menuIconPath ? [[[NSImage alloc] initWithContentsOfFile:menuIconPath] autorelease] : nil;
    
    if (statusImage) {
        NSImage *templateImage = [[[NSImage alloc] initWithSize:NSMakeSize(18, 18)] autorelease];
        [templateImage lockFocus];
        [[NSColor blackColor] set];
        [statusImage drawAtPoint:NSZeroPoint fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
        [templateImage unlockFocus];
        [templateImage setTemplate:YES];
        [statusItem setImage:templateImage];
        [statusItem setHighlightMode:YES];
    } else {
        [statusItem setTitle:@"✏️"];
    }
    
    NSMenu *menu = [[[NSMenu alloc] init] autorelease];
    
    [menu addItemWithTitle:@"Clear Drawing" action:@selector(clearDrawing:) keyEquivalent:@""].target = self;
    
    NSMenuItem *colorItem = [[[NSMenuItem alloc] initWithTitle:@"Change Color" action:nil keyEquivalent:@""] autorelease];
    colorMenu = [[NSMenu alloc] init];
    [colorItem setSubmenu:colorMenu];
    [colorMenu setDelegate:(id<NSMenuDelegate>)self];
    [menu addItem:colorItem];
    
    [menu addItemWithTitle:@"Open Controls..." action:@selector(openControls:) keyEquivalent:@""].target = self;
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Keyboard Shortcuts..." action:@selector(showKeyboardShortcuts:) keyEquivalent:@""].target = self;
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"].target = NSApp;
    
    [statusItem setMenu:menu];
}

#pragma mark - Menu Actions

- (void)openControls:(id)sender {
    if (self.controlPanel) {
        [NSApp activateIgnoringOtherApps:YES];
        [self.controlPanel orderFrontRegardless];
        [self.controlPanel makeKeyAndOrderFront:nil];
    }
}

- (void)showKeyboardShortcuts:(id)sender {
    NSString *shortcutsPath = [[NSBundle mainBundle] pathForResource:@"KeyboardShortcuts" ofType:@"txt"];
    NSString *shortcuts = shortcutsPath ? [NSString stringWithContentsOfFile:shortcutsPath encoding:NSUTF8StringEncoding error:nil] : nil;
    
    if (!shortcuts) {
        shortcuts = @"Drawing & Navigation:\n"
                   @"• Shift + Drag: Draw straight lines\n"
                   @"• F14 (hold): Temporarily use pen as normal mouse\n"
                   @"• Click on stroke: Select and drag to move\n\n"
                   @"Editing:\n"
                   @"• ⌘Z: Undo last stroke\n"
                   @"• ⌘Z (hold): Clear all drawing\n"
                   @"• ⇧⌘Z: Redo\n\n"
                   @"Colors:\n"
                   @"• ⌘D: Toggle to next color\n\n"
                   @"Text:\n"
                   @"• ⌥⇧⌘T: Enter text input mode\n"
                   @"• Alt+Enter: Create new text area below (in text mode)\n\n"
                   @"Note: Most shortcuts work from the Wacom tablet buttons.";
    }
    
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:@"Keyboard Shortcuts"];
    [alert setInformativeText:shortcuts];
    [alert addButtonWithTitle:@"OK"];
    [alert setAlertStyle:NSInformationalAlertStyle];
    [alert runModal];
}

- (void)clearDrawing:(id)sender {
    [self.drawView clear];
}

NSMenu *colorMenu = nil;

- (void)menuNeedsUpdate:(NSMenu *)menu {
    if (colorMenu != menu) return;
    
    [menu removeAllItems];
    
    NSInteger currentIndex = [self.drawView currentColorIndex];
    NSArray *presetColors = [self.drawView presetColors];
    
    for (NSInteger i = 0; i < [presetColors count]; i++) {
        NSColor *color = [presetColors objectAtIndex:i];
        NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:@"" action:@selector(changeToColor:) keyEquivalent:@""] autorelease];
        [item setTag:i];
        [item setTarget:self];
        
        NSImage *swatchImage = [[[NSImage alloc] initWithSize:NSMakeSize(16, 16)] autorelease];
        [swatchImage lockFocus];
        [color set];
        NSRectFill(NSMakeRect(0, 0, 16, 16));
        [[NSColor blackColor] set];
        NSFrameRect(NSMakeRect(0, 0, 16, 16));
        [swatchImage unlockFocus];
        
        [item setImage:swatchImage];
        if (i == currentIndex) [item setState:NSOnState];
        [menu addItem:item];
    }
}

- (void)changeToColor:(id)sender {
    NSInteger colorIndex = [sender tag];
    if (colorIndex == [self.drawView currentColorIndex]) return;
    
    [self.drawView setCurrentColorIndex:colorIndex];
    NSArray *presetColors = [self.drawView presetColors];
    if (colorIndex < [presetColors count]) {
        NSColor *newColor = [presetColors objectAtIndex:colorIndex];
        
        [[self.drawView strokeColor] release];
        [self.drawView setValue:[newColor retain] forKey:@"strokeColor"];
        
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:newColor forKey:@"color"];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DrawViewColorChanged" object:self.drawView userInfo:userInfo];
        
        if (self.controlPanel) {
            NSColorWell *colorWell = [self.controlPanel valueForKey:@"colorWell"];
            if (colorWell) [colorWell setColor:newColor];
        }
    }
}

#pragma mark - Application Lifecycle

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    self.isUndoKeyDown = NO;
    self.isNormalModeKeyDown = NO;
    self.lastUndoKeyTime = nil;
    
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @NO};
    if (!AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options)) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:@"Accessibility Permission Required"];
        [alert setInformativeText:@"Wacom Overlay needs accessibility permissions to capture tablet input.\n\nGrant permission in System Preferences > Security & Privacy > Privacy > Accessibility"];
        [alert addButtonWithTitle:@"Open System Preferences"];
        [alert addButtonWithTitle:@"Quit"];
        [alert setAlertStyle:NSWarningAlertStyle];
        
        if ([alert runModal] == NSAlertFirstButtonReturn) {
            [[NSWorkspace sharedWorkspace] openFile:@"/System/Library/PreferencePanes/Security.prefPane"];
        }
        [NSApp terminate:nil];
        return;
    }
    
    wacomDriverPID = [self findWacomDriverPID];
    
    NSRect totalScreensRect = [self totalScreensRect];
    self.overlayWindow = [[OverlayWindow alloc] initWithContentRect:totalScreensRect styleMask:0 backing:NSBackingStoreBuffered defer:NO];
    [self.overlayWindow setOpaque:NO];
    [self.overlayWindow setAlphaValue:1.0];
    [self.overlayWindow setBackgroundColor:[NSColor clearColor]];
    [self.overlayWindow setIgnoresMouseEvents:YES];
    
    self.drawView = (DrawView *)[self.overlayWindow contentView];
    self.controlPanel = [[ControlPanel alloc] initWithDrawView:self.drawView];
    
    [self.overlayWindow makeKeyAndOrderFront:nil];
    
    TabletApplication *app = (TabletApplication *)NSApp;
    [app setOverlayWindow:self.overlayWindow];
    
    [self setupStatusBarMenu];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(screenParametersDidChange:) 
                                                 name:NSApplicationDidChangeScreenParametersNotification object:nil];
    
    CGEventMask eventMask = CGEventMaskBit(kCGEventLeftMouseDown) | CGEventMaskBit(kCGEventLeftMouseUp) | 
                           CGEventMaskBit(kCGEventLeftMouseDragged) | CGEventMaskBit(kCGEventRightMouseDown) |
                           CGEventMaskBit(kCGEventRightMouseUp) | CGEventMaskBit(kCGEventRightMouseDragged) |
                           CGEventMaskBit(kCGEventOtherMouseDown) | CGEventMaskBit(kCGEventOtherMouseUp) |
                           CGEventMaskBit(kCGEventOtherMouseDragged) | CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp);
    
    eventTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, 0, eventMask, eventTapCallback, self);
    
    if (!eventTap) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:@"Failed to Initialize"];
        [alert setInformativeText:@"Could not create event tap. Please restart the application."];
        [alert addButtonWithTitle:@"Quit"];
        [alert setAlertStyle:NSCriticalAlertStyle];
        [alert runModal];
        [NSApp terminate:nil];
        return;
    }
    
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
    CGEventTapEnable(eventTap, true);
    
    [self.overlayWindow orderFront:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminate:) 
                                                 name:NSApplicationWillTerminateNotification object:nil];
}

- (void)screenParametersDidChange:(NSNotification *)notification {
    [self updateOverlayWindowFrame];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
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
    
    if (eventMonitor) [NSEvent removeMonitor:eventMonitor];
    if (self.undoHoldTimer) [self.undoHoldTimer invalidate];
    
    [self.lastUndoKeyTime release];
    self.lastUndoKeyTime = nil;
}

- (void)dealloc {
    if (eventTap) {
        CGEventTapEnable(eventTap, false);
        CFMachPortInvalidate(eventTap);
        CFRelease(eventTap);
    }
    
    if (runLoopSource) {
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
        CFRelease(runLoopSource);
    }
    
    if (eventMonitor) [NSEvent removeMonitor:eventMonitor];
    if (undoHoldTimer) [undoHoldTimer invalidate];
    
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