#import "DrawView.h"
#import "TabletEvents.h"
#import "TabletApplication.h"
#import "UndoCommand.h"

// Custom text field that properly handles ESC key
@interface EscapeHandlingTextField : NSTextField
@property (nonatomic, assign) DrawView *drawView;
@end

@implementation EscapeHandlingTextField

- (void)keyDown:(NSEvent *)event {
    if ([event keyCode] == 53) { // ESC key
        if (self.drawView) {
            [self.drawView cancelTextInput];
            return;
        }
    }
    [super keyDown:event];
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if ([event keyCode] == 53) { // ESC key
        if (self.drawView) {
            [self.drawView cancelTextInput];
            return YES;
        }
    }
    return [super performKeyEquivalent:event];
}

@end

@implementation DrawView

@synthesize lineWidth;
@synthesize strokeColor;
@synthesize erasing = mErasing;
@synthesize currentColorIndex;
@dynamic presetColors;

// Custom getter for strokeColor
- (NSColor *)strokeColor {
    return strokeColor;
}

// Custom setter for strokeColor to ensure cursor color updates
- (void)setStrokeColor:(NSColor *)color {
    if (strokeColor != color) {
        [strokeColor release];
        strokeColor = [color retain];
        
        // Only post notification if color is not nil (to avoid issues during initialization)
        if (color) {
            // Post a notification about the color change so the cursor can be updated
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:color forKey:@"color"];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"DrawViewColorChanged" 
                                                              object:self 
                                                            userInfo:userInfo];
        }
    }
}

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Initialize drawing properties
        paths = [[NSMutableArray alloc] init];
        pathColors = [[NSMutableArray alloc] init];
        strokeMarkers = [[NSMutableArray alloc] init];
        undoPaths = [[NSMutableArray alloc] init];
        undoPathColors = [[NSMutableArray alloc] init];
        undoStrokeMarkers = [[NSMutableArray alloc] init];
        
        // Initialize command-based undo/redo stacks
        undoStack = [[NSMutableArray alloc] init];
        redoStack = [[NSMutableArray alloc] init];
        
        // Load colors from NSUserDefaults or use defaults if none are stored
        [self loadColorsFromUserDefaults];
        
        self.lineWidth = 2.0;
        
        // Load text size from user defaults or use default
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        CGFloat savedTextSize = [defaults floatForKey:@"WacomOverlayTextSize"];
        if (savedTextSize > 0) {
            textSize = savedTextSize;
        } else {
            textSize = 24.0;  // Default text size
        }
        mErasing = NO;
        hasLastErasePoint = NO;
        lastErasePoint = NSZeroPoint;
        
        // Initialize stroke selection and dragging variables
        selectedStrokeIndex = -1;
        isStrokeSelected = NO;
        isDraggingStroke = NO;
        dragStartPoint = NSZeroPoint;
        relatedStrokeIndices = [[NSMutableArray alloc] init];
        
        // Initialize text field variables
        textFields = [[NSMutableArray alloc] init];
        textFieldColors = [[NSMutableArray alloc] init];
        undoTextFields = [[NSMutableArray alloc] init];
        undoTextFieldColors = [[NSMutableArray alloc] init];
        isTextInputMode = NO;
        isEditingText = NO;
        activeTextField = nil;
        selectedTextFieldIndex = -1;
        originalWindowLevel = NSScreenSaverWindowLevel;  // Initialize to default overlay window level
        
        // Make the view transparent to allow click-through
        [self setWantsLayer:YES];
        
        // Ensure we can receive all events
        [[self window] setAcceptsMouseMovedEvents:YES];
        
        // Register for proximity notifications
        [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(handleProximity:)
                                              name:kProximityNotification
                                              object:nil];
        
        // Initialize performance caching
        cachedStrokesLayer = NULL;
        cacheNeedsUpdate = YES;
        lastCachedStrokeCount = 0;
        
        NSLog(@"DrawView initialized with frame: %@", NSStringFromRect(frame));
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    // Clear the background (transparent)
    [[NSColor clearColor] set];
    NSRectFill(dirtyRect);
    
    // If we have stroke selection active, we need to handle it differently
    // because selection highlighting can't be cached
    if (isStrokeSelected) {
        // Draw all saved paths with their colors (traditional method for selection)
        for (NSUInteger i = 0; i < [paths count]; i++) {
            NSBezierPath *path = [paths objectAtIndex:i];
            NSColor *color = (i < [pathColors count]) ? [pathColors objectAtIndex:i] : strokeColor;
            
            // If related strokes array is empty, find them now
            if ([relatedStrokeIndices count] == 0 && selectedStrokeIndex >= 0) {
                [self findRelatedStrokes:selectedStrokeIndex];
            }
            
            // Check if this path belongs to any selected or related stroke
            BOOL isPathSelected = NO;
            
            for (NSNumber *relatedIndexNum in relatedStrokeIndices) {
                NSInteger relatedIndex = [relatedIndexNum integerValue];
                
                if (relatedIndex >= 0 && relatedIndex < [strokeMarkers count]) {
                    NSInteger startIndex = [[strokeMarkers objectAtIndex:relatedIndex] integerValue];
                    NSInteger endIndex;
                    
                    // Determine the end index of the related stroke
                    if (relatedIndex < [strokeMarkers count] - 1) {
                        endIndex = [[strokeMarkers objectAtIndex:relatedIndex + 1] integerValue] - 1;
                    } else {
                        endIndex = [paths count] - 1;
                    }
                    
                    // Check if this path belongs to the related stroke
                    if (i >= startIndex && i <= endIndex) {
                        isPathSelected = YES;
                        break;
                    }
                }
            }
            
            // If this path is part of any selected or related stroke, draw it with highlighting
            if (isPathSelected) {
                // Store the original line width
                CGFloat originalWidth = [path lineWidth];
                
                // Draw the selected path with a slightly wider stroke and lighter color
                NSBezierPath *highlightPath = [path copy];
                [highlightPath setLineWidth:originalWidth + 2.0];
                
                // Create a lighter version of the color
                NSColor *highlightColor = [color colorWithAlphaComponent:0.3];
                [highlightColor set];
                [highlightPath stroke];
                [highlightPath release];
                
                // Ensure we're using the original width for the actual stroke
                [path setLineWidth:originalWidth];
            }
            
            [color set];
            [path stroke];
        }
    } else {
        // Use high-performance cached rendering for normal drawing
        [self updateStrokeCache];
        [self drawCachedStrokes];
        
        // Draw any strokes that aren't cached yet (current active stroke)
        NSInteger cachedCount = lastCachedStrokeCount;
        for (NSUInteger i = cachedCount; i < [paths count]; i++) {
            NSBezierPath *path = [paths objectAtIndex:i];
            NSColor *color = (i < [pathColors count]) ? [pathColors objectAtIndex:i] : strokeColor;
            
            [color set];
            [path stroke];
        }
    }
    
    // Draw current path if it exists
    if (currentPath) {
        [strokeColor set];
        [currentPath stroke];
    }
    
    // Draw straight line preview if it exists
    if (straightLinePath) {
        [strokeColor set];
        [straightLinePath stroke];
    }
    
    // Text fields are now persistent NSTextField subviews, no need to draw them
    
    // Removed debug visualization code
}

// This special method handles events forwarded from the global event monitor
- (void)mouseEvent:(NSEvent *)event {
    // Handle event based on its type
    NSInteger type = [event type];
    
    NSLog(@"DrawView received forwarded event from monitor, type: %ld, isTablet: %d", 
          (long)type, [event isTabletPointerEvent] ? 1 : 0);
    
    switch (type) {
        case 1: // NSLeftMouseDown
            [self mouseDown:event];
            break;
            
        case 6: // NSLeftMouseDragged
            [self mouseDragged:event];
            break;
            
        case 2: // NSLeftMouseUp
            [self mouseUp:event];
            break;
            
        case 5: // NSMouseMoved
            [self mouseMoved:event];
            break;
            
        case 24: // NSTabletProximity
            // If we receive a proximity event, it should have already been handled by TabletApplication
            // but we can explicitly update our erasing status here if needed
            if ([event isTabletProximityEvent]) {
                // For OS X 10.9, we need to use the raw value 2 for eraser
                BOOL isEraser = ([event pointingDeviceType] == 2); // NSPointingDeviceTypeEraser is 2
                if (isEraser != mErasing) {
                    mErasing = isEraser;
                    NSLog(@"DrawView: Eraser state changed to %@", mErasing ? @"ON" : @"OFF");
                    
                    // Notify TabletApplication about erasing mode change
                    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:mErasing] 
                                                                         forKey:@"isErasing"];
                    [[NSNotificationCenter defaultCenter] postNotificationName:@"DrawViewErasingModeChanged" 
                                                                        object:self 
                                                                      userInfo:userInfo];
                }
            }
            break;
            
        default:
            NSLog(@"DrawView: Unhandled event type in mouseEvent: %ld", (long)type);
            break;
    }
}

- (NSPoint)convertScreenPointToView:(NSPoint)screenPoint {
    // Get our window
    NSWindow *window = [self window];
    if (!window) {
        // Try to get the overlay window from the application
        TabletApplication *app = (TabletApplication *)[NSApplication sharedApplication];
        if ([app respondsToSelector:@selector(overlayWindow)]) {
            window = (NSWindow *)[app performSelector:@selector(overlayWindow)];
        }
        
        if (!window) {
            return screenPoint;
        }
    }
    
    // For multi-screen setups, make sure the window is visible
    if (![window isVisible]) {
        [window orderFront:nil];
    }
    
    // Simple direct conversion method
    // 1. Convert screen point to window base coordinates
    NSPoint windowPoint = [window convertScreenToBase:screenPoint];
    
    // 2. Convert window coordinates to view coordinates
    NSPoint viewPoint = [self convertPoint:windowPoint fromView:nil];
    
    return viewPoint;
}

- (void)mouseDown:(NSEvent *)event {
    // Get the point from the event
    NSPoint viewPoint;
    
    if ([event isTabletPointerEvent]) {
        // For tablet events, use the screen location approach
        NSPoint screenPoint = [NSEvent mouseLocation];
        viewPoint = [self convertScreenPointToView:screenPoint];
        
        // If we're in eraser mode, erase stroke or text at this point instead of drawing
        if (mErasing) {
            // First try to erase text at this point
            NSInteger textIndex = [self findTextAnnotationAtPoint:viewPoint];
            if (textIndex >= 0) {
                [self eraseTextAtPoint:viewPoint];
            } else {
                // If no text found, try to erase stroke
                [self eraseStrokeAtPoint:viewPoint];
            }
            return;
        }
        
        // Store the starting point for potential straight line drawing
        straightLineStartPoint = viewPoint;
        
        // Clean up any existing straight line path
        if (straightLinePath) {
            [straightLinePath release];
            straightLinePath = nil;
        }
        
        // Check current modifier flags to detect shift key
        NSUInteger currentFlags = [NSEvent modifierFlags];
        BOOL shiftIsDown = (currentFlags & (1 << 17)) != 0; // NSShiftKeyMask in 10.9
        
        // Always update our shift key state at the start of a new stroke
        isShiftKeyDown = shiftIsDown;
        NSLog(@"DrawView: Shift key state at mouseDown: %@", isShiftKeyDown ? @"DOWN" : @"UP");
        
        // Check if shift key is already down when starting a new stroke
        if (shiftIsDown) {
            NSLog(@"DrawView: Starting in straight line mode (shift already down)");
            
            // Set the initial straight line width based on current pressure
            if ([event pressure] > 5.0) {
                // Capture the pressure-sensitive width at this moment
                straightLineWidth = lineWidth * ([event pressure] * 2.0);
                straightLineWidth = MAX(0.5, straightLineWidth);
            } else {
                // Just use the default line width
                straightLineWidth = lineWidth;
            }
            
            // Create a straight line path for preview
            straightLinePath = [[NSBezierPath bezierPath] retain];
            [straightLinePath setLineWidth:straightLineWidth]; // Use the captured width
            [straightLinePath setLineCapStyle:NSRoundLineCapStyle];
            [straightLinePath setLineJoinStyle:NSRoundLineJoinStyle];
            
            // Draw a straight line from the start point to itself initially
            [straightLinePath moveToPoint:viewPoint];
            [straightLinePath lineToPoint:viewPoint];
        } else {
            // Start a new path for normal drawing
            currentPath = [[NSBezierPath bezierPath] retain];
            [currentPath setLineWidth:lineWidth];
            [currentPath setLineCapStyle:NSRoundLineCapStyle];
            [currentPath setLineJoinStyle:NSRoundLineJoinStyle];
            
            // Start the path
            [currentPath moveToPoint:viewPoint];
        }
        
        lastPoint = viewPoint;
        
        // Add a marker for the start of a new stroke
        // We'll record the current path count at the beginning of a stroke
        [strokeMarkers addObject:[NSNumber numberWithInteger:[paths count]]];
    } else {
        // For regular mouse events, use the event's locationInWindow coordinates
        viewPoint = [self convertPoint:[event locationInWindow] fromView:nil];
        NSLog(@"DrawView: mouseDown detected regular mouse event at point: %@, isDraggingStroke=%d, selectedTextFieldIndex=%ld", NSStringFromPoint(viewPoint), isDraggingStroke, (long)selectedTextFieldIndex);
        
        // No longer handle text input mode via mouse clicks - only via keyboard shortcut
        
        // Check for text annotations first
        NSInteger textIndex = [self findTextAnnotationAtPoint:viewPoint];
        if (textIndex >= 0) {
            NSTextField *clickedTextField = [textFields objectAtIndex:textIndex];
            
            // Check if we're already editing this specific text field
            BOOL wasAlreadyEditingThisField = (isEditingText && activeTextField == clickedTextField);
            
            // Enter edit mode for the clicked text field (if not already editing it)
            if (!wasAlreadyEditingThisField) {
                [self startEditingExistingTextField:clickedTextField];
            }
            
            // Only prepare for dragging if we weren't already editing this field
            // If we were already editing, we want drag to select text, not move the field
            if (!wasAlreadyEditingThisField) {
                selectedTextFieldIndex = textIndex;
                selectedStrokeIndex = -1;
                isStrokeSelected = NO;
                isDraggingStroke = NO;  // Don't set to YES yet - wait for actual drag
                dragStartPoint = viewPoint;
                dragOriginalPosition = [clickedTextField frame].origin; // Store original position for undo
            } else {
                // Already editing - clear drag preparation so drag will select text
                selectedTextFieldIndex = -1;
                isDraggingStroke = NO;
            }
            
            [self setNeedsDisplay:YES];
            return;
        }
        
        // Attempt to find a stroke at this point using the more forgiving selection method
        NSInteger strokeIndex = [self findStrokeAtPointForSelection:viewPoint];
        
        if (strokeIndex >= 0) {
            // Exit text editing if we're editing
            if (isEditingText) {
                [self finishTextInput];
            }
            
            // Set this as the selected stroke
            selectedStrokeIndex = strokeIndex;
            selectedTextFieldIndex = -1;  // Clear text selection when selecting a stroke
            isStrokeSelected = YES;
            isDraggingStroke = YES;
            dragStartPoint = viewPoint;
            
            // Find all related strokes (same color and intersecting)
            [self findRelatedStrokes:strokeIndex];
        } else {
            // If no stroke was found at this point, clear any existing selection
            if (isStrokeSelected) {
                isStrokeSelected = NO;
                selectedStrokeIndex = -1;
                isDraggingStroke = NO;
                [relatedStrokeIndices removeAllObjects];
                
                // Invalidate cache when deselecting strokes to restore cached rendering
                [self invalidateStrokeCache];
            }
            
            // Also clear text selection and exit edit mode if clicking on empty space
            selectedTextFieldIndex = -1;
            if (isEditingText) {
                [self finishTextInput];
            }
        }
    }
    
    // Only redraw if something visual has changed
    if (isStrokeSelected || currentPath || straightLinePath) {
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseDragged:(NSEvent *)event {
    // Get the point from the event
    NSPoint viewPoint;
    
    if ([event isTabletPointerEvent]) {
        // For tablet events, use the screen location approach
        NSPoint screenPoint = [NSEvent mouseLocation];
        viewPoint = [self convertScreenPointToView:screenPoint];
        NSLog(@"DrawView: mouseDragged detected tablet event at point: %@", NSStringFromPoint(viewPoint));
        
        // If we're in eraser mode, handle eraser dragging
        if (mErasing) {
            if (!hasLastErasePoint) {
                lastErasePoint = viewPoint;
                hasLastErasePoint = YES;
            } else {
                // Calculate distance from last erase point
                CGFloat dx = viewPoint.x - lastErasePoint.x;
                CGFloat dy = viewPoint.y - lastErasePoint.y;
                CGFloat distance = sqrt(dx*dx + dy*dy);
                
                // Only process erase if we've moved enough distance (to avoid rapid erasures)
                // Reduced from 10.0 to 2.0 for more responsive erasing
                if (distance > 2.0) {
                    // First try to erase text at this point
                    NSInteger textIndex = [self findTextAnnotationAtPoint:viewPoint];
                    if (textIndex >= 0) {
                        [self eraseTextAtPoint:viewPoint];
                    } else {
                        // If no text found, try to erase stroke
                        [self eraseStrokeAtPoint:viewPoint];
                    }
                    lastErasePoint = viewPoint;
                }
            }
            return;
        }
        
        // Check current modifier flags to detect shift key
    NSUInteger currentFlags = [NSEvent modifierFlags];
    BOOL shiftIsDown = (currentFlags & (1 << 17)) != 0; // NSShiftKeyMask in 10.9
    
    // Check if shift key state changed
    if (isShiftKeyDown != shiftIsDown) {
        // If shift was just pressed, store current point as the straight line start
        if (shiftIsDown) {
            // Update the starting point to current position (not original pen down)
            straightLineStartPoint = viewPoint;
            
            // Store the current line width - we'll use this for the straight line
            if ([event pressure] > 0.0) {
                // Capture the pressure-sensitive width at this moment
                straightLineWidth = lineWidth * ([event pressure] * 2.0);
                straightLineWidth = MAX(0.5, straightLineWidth);
            } else {
                // Just use the default line width
                straightLineWidth = lineWidth;
            }
            
            NSLog(@"DrawView: Shift key pressed during drag, setting straight line start to: %@ with width: %f", 
                  NSStringFromPoint(straightLineStartPoint), straightLineWidth);
        } else {
            // Shift was just released - finalize the straight line if we have one
            if (straightLinePath) {
                NSLog(@"DrawView: Shift key released during drag, finalizing straight line");
                
                // Create a segment path for the straight line
                NSBezierPath *segmentPath = [[NSBezierPath bezierPath] retain];
                [segmentPath setLineCapStyle:NSRoundLineCapStyle];
                [segmentPath setLineJoinStyle:NSRoundLineJoinStyle];
                [segmentPath setLineWidth:straightLineWidth]; // Use the width from when shift was first pressed
                
                // Create the straight line segment
                [segmentPath moveToPoint:straightLineStartPoint];
                [segmentPath lineToPoint:viewPoint];
                
                // Add this segment to our collection
                [paths addObject:segmentPath];
                [pathColors addObject:[strokeColor copy]]; // Store current color with path
                [segmentPath release];
                
                // Add a marker for the straight line stroke if needed
                if ([strokeMarkers count] == 0 || 
                    [[strokeMarkers lastObject] integerValue] != [paths count] - 1) {
                    [strokeMarkers addObject:[NSNumber numberWithInteger:[paths count] - 1]];
                }
                
                // Clean up the preview path
                [straightLinePath release];
                straightLinePath = nil;
                
                // Continue normal drawing from this point
                if (currentPath) {
                    [currentPath release];
                }
                
                // Start a new path for continued drawing
                currentPath = [[NSBezierPath bezierPath] retain];
                [currentPath setLineWidth:lineWidth];
                [currentPath setLineCapStyle:NSRoundLineCapStyle];
                [currentPath setLineJoinStyle:NSRoundLineJoinStyle];
                [currentPath moveToPoint:viewPoint];
            }
        }
        
        // Update shift key state
        isShiftKeyDown = shiftIsDown;
        NSLog(@"DrawView: Shift key detected as %@ during mouseDragged", isShiftKeyDown ? @"DOWN" : @"UP");
    }
    
    // Check if shift key is down for straight line drawing
    if (shiftIsDown) {
            NSLog(@"DrawView: Shift key is down during drag, drawing straight line preview");
            
            // Release any existing straight line path and create a new one
            if (straightLinePath) {
                [straightLinePath release];
            }
            
            // Create a new path for the straight line
            straightLinePath = [[NSBezierPath bezierPath] retain];
            [straightLinePath setLineWidth:straightLineWidth]; // Use the stored width from when shift was pressed
            [straightLinePath setLineCapStyle:NSRoundLineCapStyle];
            [straightLinePath setLineJoinStyle:NSRoundLineJoinStyle];
            
            NSLog(@"DrawView: Using stored width for straight line: %f", straightLineWidth);
            
            // Draw a straight line from the start point to the current point
            [straightLinePath moveToPoint:straightLineStartPoint];
            [straightLinePath lineToPoint:viewPoint];
            
            // Save current point as last point (even though we're not adding segments)
            lastPoint = viewPoint;
            
            // Need full redraw to show the preview properly
            [self setNeedsDisplay:YES];
            
            return;
        }
        
        // Normal drawing mode - if we have a current path, add a line to it
        if (currentPath) {
            // Calculate distance between last point and current point
            CGFloat dx = viewPoint.x - lastPoint.x;
            CGFloat dy = viewPoint.y - lastPoint.y;
            CGFloat distance = sqrt(dx*dx + dy*dy);
            
            // Use pressure if available to adjust line width for this segment
            float segmentWidth = lineWidth;
            if ([event pressure] > 0.0) {
                segmentWidth = lineWidth * ([event pressure] * 2.0);
                segmentWidth = MAX(0.5, segmentWidth);
                
                NSLog(@"DrawView: Using pressure: %f, width: %f", [event pressure], segmentWidth);
            }
            
            // Balance performance and quality
            // Skip only extremely small movements
            if (distance < 0.1) {
                return; // Skip microscopic movements
            }
            
            // Adaptive interpolation based on distance for smooth curves
            NSInteger numSegments = 1;
            if (distance > 5.0) {
                // More aggressive interpolation for smoother curves
                // But still less than original (was /2.0, now /4.0)
                numSegments = MAX(1, (NSInteger)(distance / 4.0));
            }
            
            for (NSInteger i = 0; i < numSegments; i++) {
                // Calculate interpolated point
                CGFloat t = (i + 1.0) / numSegments;
                NSPoint interpolatedPoint = NSMakePoint(
                    lastPoint.x + (dx * t),
                    lastPoint.y + (dy * t)
                );
                
                // Create a segment path for this movement
                NSBezierPath *segmentPath = [[NSBezierPath bezierPath] retain];
                [segmentPath setLineCapStyle:NSRoundLineCapStyle];
                [segmentPath setLineJoinStyle:NSRoundLineJoinStyle];
                [segmentPath setLineWidth:segmentWidth];
                
                // Create segment from last point to interpolated point
                [segmentPath moveToPoint:(i == 0 ? lastPoint : NSMakePoint(lastPoint.x + (dx * i / numSegments), lastPoint.y + (dy * i / numSegments)))];
                [segmentPath lineToPoint:interpolatedPoint];
                
                // Add this segment to our collection
                [paths addObject:segmentPath];
                [pathColors addObject:[strokeColor copy]]; // Store current color with path
                [segmentPath release];
            }
            
            // Update last point for next segment
            lastPoint = viewPoint;
            
            NSLog(@"DrawView: Added %ld interpolated segments, distance: %f", (long)numSegments, distance);
            
            // Need full redraw during active drawing to ensure proper rendering
            [self setNeedsDisplay:YES];
        }
    } else {
        // For regular mouse events, use the event's locationInWindow converted to view coordinates
        viewPoint = [self convertPoint:[event locationInWindow] fromView:nil];
        NSLog(@"DrawView: mouseDragged detected regular mouse event at point: %@", NSStringFromPoint(viewPoint));
        
        // Check if we need to start dragging a text field
        // We can drag if we have a text field selected (selectedTextFieldIndex >= 0)
        // This happens on first click of a text field, even though we're also editing
        if (!isDraggingStroke && selectedTextFieldIndex >= 0) {
            // Start dragging the text field
            isDraggingStroke = YES;
            
            // Store the original position for undo if not already stored
            if (selectedTextFieldIndex >= 0 && selectedTextFieldIndex < [textFields count]) {
                NSTextField *textField = [textFields objectAtIndex:selectedTextFieldIndex];
                dragOriginalPosition = [textField frame].origin;
            }
            
            // Exit edit mode when we start dragging
            if (isEditingText) {
                [self finishTextInput];
            }
            
            NSLog(@"DrawView: Started dragging text field from position %@", NSStringFromPoint(dragOriginalPosition));
        }
        
        // Handle dragging a selected item
        if (isDraggingStroke) {
            // Calculate the movement offset
            CGFloat dx = viewPoint.x - dragStartPoint.x;
            CGFloat dy = viewPoint.y - dragStartPoint.y;
            
            // Check if we're dragging text or stroke
            if (selectedTextFieldIndex >= 0) {
                // Dragging text field
                [self moveSelectedText:NSMakePoint(dx, dy)];
                NSLog(@"DrawView: Dragged text field by offset (%f, %f)", dx, dy);
            } else if (isStrokeSelected && selectedStrokeIndex >= 0) {
                // Dragging stroke
                [self moveSelectedStroke:NSMakePoint(dx, dy)];
                NSLog(@"DrawView: Dragged stroke by offset (%f, %f)", dx, dy);
            }
            
            // Update the drag start point for the next mouse dragged event
            dragStartPoint = viewPoint;
        }
    }
    
    // Need full redraw during dragging to ensure visibility
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    if ([event isTabletPointerEvent]) {
        NSLog(@"DrawView: mouseUp detected tablet event");
        
        // If we're in eraser mode, reset tracking variables
        if (mErasing) {
            [self resetEraseTracking];
            return;
        }
        
        // Check current modifier flags to detect shift key
        NSUInteger currentFlags = [NSEvent modifierFlags];
        BOOL shiftIsDown = (currentFlags & (1 << 17)) != 0; // NSShiftKeyMask in 10.9
        
        // Update our shift key state
        if (isShiftKeyDown != shiftIsDown) {
            isShiftKeyDown = shiftIsDown;
            NSLog(@"DrawView: Shift key detected as %@ during mouseUp", isShiftKeyDown ? @"DOWN" : @"UP");
        }
        
        // Check if we have a straight line to commit (regardless of current shift state)
        if (straightLinePath) {
            NSLog(@"DrawView: Completing straight line drawing");
            
            // Get the current point
            NSPoint screenPoint = [NSEvent mouseLocation];
            NSPoint viewPoint = [self convertScreenPointToView:screenPoint];
            // Create a segment path for the straight line
            NSBezierPath *segmentPath = [[NSBezierPath bezierPath] retain];
            [segmentPath setLineCapStyle:NSRoundLineCapStyle];
            [segmentPath setLineJoinStyle:NSRoundLineJoinStyle];
            
            // Use the width from when shift was first pressed
            [segmentPath setLineWidth:straightLineWidth];
            
            // Create the straight line segment
            [segmentPath moveToPoint:straightLineStartPoint];
            [segmentPath lineToPoint:viewPoint];
            
            // Add this segment to our collection
            [paths addObject:segmentPath];
            [pathColors addObject:[strokeColor copy]]; // Store current color with path
            [segmentPath release];
            
            // Add a marker for the straight line stroke if we haven't added one yet
            if ([strokeMarkers count] == 0 || 
                [[strokeMarkers lastObject] integerValue] != [paths count] - 1) {
                [strokeMarkers addObject:[NSNumber numberWithInteger:[paths count] - 1]];
            }
            
            // Clean up the preview path
            [straightLinePath release];
            straightLinePath = nil;
            
            // Create add stroke command for undo
            NSMutableArray *strokePaths = [NSMutableArray array];
            NSMutableArray *strokeColors = [NSMutableArray array];
            
            // Get the last stroke's segments
            NSInteger markerIndex = [strokeMarkers count] - 1;
            NSInteger startIndex = [[strokeMarkers objectAtIndex:markerIndex] integerValue];
            NSInteger endIndex = [paths count] - 1;
            
            for (NSInteger i = startIndex; i <= endIndex; i++) {
                [strokePaths addObject:[paths objectAtIndex:i]];
                [strokeColors addObject:[pathColors objectAtIndex:i]];
            }
            
            AddStrokeCommand *command = [[AddStrokeCommand alloc] initWithDrawView:self 
                                                                             paths:strokePaths 
                                                                            colors:strokeColors 
                                                                       markerIndex:markerIndex];
            [undoStack addObject:command];
            [command release];
            
            // Clear the redo stack since we've added a new stroke
            [redoStack removeAllObjects];
            
            NSLog(@"DrawView: Completed straight line from %@ to %@", 
                  NSStringFromPoint(straightLineStartPoint), 
                  NSStringFromPoint(viewPoint));
        }
        else {
            
            // Release the current path as we now use individual segments
            if (currentPath) {
                [currentPath release];
                currentPath = nil;
                
                // Only create command if we've actually drawn something new
                if ([paths count] > 0 && [strokeMarkers count] > 0) {
                    // Create add stroke command for the completed stroke
                    NSMutableArray *strokePaths = [NSMutableArray array];
                    NSMutableArray *strokeColors = [NSMutableArray array];
                    
                    // Get the last stroke's segments
                    NSInteger markerIndex = [strokeMarkers count] - 1;
                    NSInteger startIndex = [[strokeMarkers objectAtIndex:markerIndex] integerValue];
                    NSInteger endIndex = [paths count] - 1;
                    
                    for (NSInteger i = startIndex; i <= endIndex; i++) {
                        [strokePaths addObject:[paths objectAtIndex:i]];
                        [strokeColors addObject:[pathColors objectAtIndex:i]];
                    }
                    
                    AddStrokeCommand *command = [[AddStrokeCommand alloc] initWithDrawView:self 
                                                                                     paths:strokePaths 
                                                                                    colors:strokeColors 
                                                                               markerIndex:markerIndex];
                    [undoStack addObject:command];
                    [command release];
                    
                    // Clear the redo stack since we've added new paths
                    [redoStack removeAllObjects];
                    
                    NSLog(@"DrawView: Added stroke to undo stack and cleared redo stack");
                }
                
                NSLog(@"DrawView: Finished stroke, total segments: %lu", (unsigned long)[paths count]);
            }
        }
    } else {
        NSPoint viewPoint = [self convertPoint:[event locationInWindow] fromView:nil];
        NSLog(@"DrawView: mouseUp detected regular mouse event at point: %@", NSStringFromPoint(viewPoint));
        
        // End any stroke dragging
        if (isDraggingStroke) {
            // Calculate total movement offset
            CGFloat totalDx = viewPoint.x - dragOriginalPosition.x;
            CGFloat totalDy = viewPoint.y - dragOriginalPosition.y;
            
            // Only create move command if there was actual movement
            if (fabs(totalDx) > 0.1 || fabs(totalDy) > 0.1) {
                if (selectedTextFieldIndex >= 0 && selectedTextFieldIndex < [textFields count]) {
                    // Create move text command
                    NSTextField *textField = [textFields objectAtIndex:selectedTextFieldIndex];
                    NSPoint oldPos = dragOriginalPosition;
                    NSPoint newPos = [textField frame].origin;
                    
                    MoveTextCommand *command = [[MoveTextCommand alloc] initWithDrawView:self 
                                                                               textField:textField 
                                                                            fromPosition:oldPos 
                                                                              toPosition:newPos];
                    [undoStack addObject:command];
                    [command release];
                    
                    // Clear redo stack
                    [redoStack removeAllObjects];
                    
                    NSLog(@"DrawView: Created move text command from %@ to %@", 
                          NSStringFromPoint(oldPos), NSStringFromPoint(newPos));
                } else if (isStrokeSelected && selectedStrokeIndex >= 0) {
                    // Create move stroke command
                    MoveStrokeCommand *command = [[MoveStrokeCommand alloc] initWithDrawView:self 
                                                                               strokeIndices:relatedStrokeIndices 
                                                                                      offset:NSMakePoint(totalDx, totalDy)];
                    [undoStack addObject:command];
                    [command release];
                    
                    // Clear redo stack
                    [redoStack removeAllObjects];
                    
                    NSLog(@"DrawView: Created move stroke command with offset (%f, %f)", totalDx, totalDy);
                }
            }
            
            isDraggingStroke = NO;
            selectedTextFieldIndex = -1;  // Clear text field selection
            
            // Also clear stroke selection state
            isStrokeSelected = NO;
            selectedStrokeIndex = -1;
            [relatedStrokeIndices removeAllObjects];
            
            // Invalidate cache since strokes may have been moved
            [self invalidateStrokeCache];
            
            // Note: Window should already be ignoring mouse events during normal operation
            // The event tap handles forwarding mouse events to us
            
            NSLog(@"DrawView: Finished dragging, cleared selection");
        }
        
        // Straight line path cleanup is now handled above
    }
    
    // When ending a stroke, invalidate cache so it gets rebuilt with the completed stroke
    [self invalidateStrokeCache];
    
    // Use full redraw on mouseUp to ensure cache is properly rendered
    [self setNeedsDisplay:YES];
}

- (void)mouseMoved:(NSEvent *)event {
    // Skip cursor updates if we're currently dragging something
    if (isDraggingStroke || isEditingText) {
        return;
    }
    
    // Get the current mouse position
    NSPoint screenPoint = [NSEvent mouseLocation];
    NSPoint viewPoint = [self convertScreenPointToView:screenPoint];
    
    // Check if pen is in proximity - pen cursor takes precedence
    if ([event isTabletPointerEvent] || mErasing) {
        // Let the system handle pen cursors
        return;
    }
    
    // Check if we're over a stroke that can be dragged
    NSInteger strokeIndex = [self findStrokeAtPointForSelection:viewPoint];
    
    // Also check if we're over a text annotation that can be dragged
    NSInteger textIndex = [self findTextAnnotationAtPoint:viewPoint];
    
    if (strokeIndex >= 0 || textIndex >= 0) {
        // Set hand cursor using a method that works even when not frontmost
        NSCursor *handCursor = [NSCursor openHandCursor];
        [handCursor set];
        
        // Use private API to force cursor update globally
        // This selector may exist to update cursor even when app isn't frontmost
        if ([NSCursor respondsToSelector:@selector(setHiddenUntilMouseMoves:)]) {
            [NSCursor setHiddenUntilMouseMoves:NO];
        }
    } else {
        // Reset to arrow cursor
        NSCursor *arrowCursor = [NSCursor arrowCursor];
        [arrowCursor set];
        
        // Use private API to force cursor update globally
        if ([NSCursor respondsToSelector:@selector(setHiddenUntilMouseMoves:)]) {
            [NSCursor setHiddenUntilMouseMoves:NO];
        }
    }
    
    // Update SetsCursorInBackground based on current conditions
    TabletApplication *app = (TabletApplication *)[NSApplication sharedApplication];
    if ([app respondsToSelector:@selector(updateSetsCursorInBackground)]) {
        [app updateSetsCursorInBackground];
    }
}

- (void)clear {
    // Save count for redo information
    NSInteger pathCount = [paths count];
    NSInteger textFieldCount = [textFields count];
    
    // Only save to undo stack if there are paths or text fields to save
    if (pathCount > 0 || textFieldCount > 0) {
        // Create clear all command
        ClearAllCommand *command = [[ClearAllCommand alloc] initWithDrawView:self];
        [command execute];
        
        // Add to undo stack
        [undoStack addObject:command];
        [command release];
        
        // Clear redo stack
        [redoStack removeAllObjects];
        [strokeMarkers removeAllObjects];
        
        // Remove all text field subviews
        for (NSTextField *textField in textFields) {
            [textField removeFromSuperview];
        }
        [textFields removeAllObjects];
        [textFieldColors removeAllObjects];
        
        NSLog(@"DrawView: Cleared drawing state - saved %ld paths for redo", (long)pathCount);
    }
    
    if (currentPath) {
        [currentPath release];
        currentPath = nil;
    }
    
    // Invalidate cache since we cleared everything
    [self invalidateStrokeCache];
    
    [self setNeedsDisplay:YES];
    
    NSLog(@"DrawView: Cleared all paths - stored %ld paths in undo stack", (long)pathCount);
}

// Make sure the view accepts first responder to get events
- (BOOL)acceptsFirstResponder {
    return YES;
}

// Handle key up events
- (void)keyUp:(NSEvent *)event {
    NSUInteger flags = [event modifierFlags];
    NSString *characters = [event charactersIgnoringModifiers];
    NSUInteger keyCode = [event keyCode];
    
    NSLog(@"DrawView: keyUp detected - keyCode: %lu, chars: '%@', flags: %lx", 
          (unsigned long)keyCode, characters, (unsigned long)flags);
    
    // Check if the shift key was released
    BOOL wasShiftKey = isShiftKeyDown && (flags & (1 << 17)) == 0; // NSShiftKeyMask in 10.9
    
    if (wasShiftKey) {
        NSLog(@"DrawView: Shift key released in keyUp");
        
        // If we have an active straight line preview, we need to finalize it
        if (straightLinePath) {
            NSLog(@"DrawView: Finalizing straight line on shift release");
            
            // We need the current mouse position
            NSPoint currentPoint = [NSEvent mouseLocation];
            NSPoint viewPoint = [self convertScreenPointToView:currentPoint];
            // Create a segment path for the straight line
            NSBezierPath *segmentPath = [[NSBezierPath bezierPath] retain];
            [segmentPath setLineCapStyle:NSRoundLineCapStyle];
            [segmentPath setLineJoinStyle:NSRoundLineJoinStyle];
            [segmentPath setLineWidth:straightLineWidth]; // Use the width from when shift was first pressed
            
            // Create the straight line segment
            [segmentPath moveToPoint:straightLineStartPoint];
            [segmentPath lineToPoint:viewPoint];
            
            // Add this segment to our collection
            [paths addObject:segmentPath];
            [pathColors addObject:[strokeColor copy]]; // Store current color with path
            [segmentPath release];
            
            // Add a marker for the straight line stroke if needed
            if ([strokeMarkers count] == 0 || 
                [[strokeMarkers lastObject] integerValue] != [paths count] - 1) {
                [strokeMarkers addObject:[NSNumber numberWithInteger:[paths count] - 1]];
            }
            
            // Clean up the preview path
            [straightLinePath release];
            straightLinePath = nil;
            
            // Continue normal drawing from this point
            if (currentPath) {
                [currentPath release];
            }
            
            // Start a new path for continued drawing
            currentPath = [[NSBezierPath bezierPath] retain];
            [currentPath setLineWidth:lineWidth];
            [currentPath setLineCapStyle:NSRoundLineCapStyle];
            [currentPath setLineJoinStyle:NSRoundLineJoinStyle];
            [currentPath moveToPoint:viewPoint];
            
            // Make sure the view redraws
            [self setNeedsDisplay:YES];
        }
        
        // Don't set isShiftKeyDown = NO here - let mouse events handle it
    }
    
    [super keyUp:event];
}

// Handle key down events for keyboard shortcuts
- (void)keyDown:(NSEvent *)event {
    NSUInteger flags = [event modifierFlags];
    NSString *characters = [event charactersIgnoringModifiers];
    NSUInteger keyCode = [event keyCode];
    
    NSLog(@"DrawView: keyDown detected - keyCode: %lu, chars: '%@', flags: %lx", 
          (unsigned long)keyCode, characters, (unsigned long)flags);
    
    // Get the CGEvent from the NSEvent to check the source
    CGEventRef cgEvent = [event CGEvent];
    pid_t eventSourcePID = CGEventGetIntegerValueField(cgEvent, kCGEventSourceUnixProcessID);
    
    // Get the AppDelegate to access the Wacom driver PID
    AppDelegate *appDelegate = (AppDelegate *)[[NSApplication sharedApplication] delegate];
    pid_t wacomDriverPID = [[appDelegate valueForKey:@"wacomDriverPID"] intValue];
    
    // Don't update isShiftKeyDown here - let mouse events handle it
    // This prevents keyboard events from interfering with shift state during drawing
    
    // Only process keyboard events from the Wacom driver
    if (wacomDriverPID != 0 && eventSourcePID == wacomDriverPID) {
        NSLog(@"DrawView: Keyboard event from Wacom tablet detected");
        
        // Check for keyboard shortcuts
        // In OS X 10.9, we need to use the raw values instead of the constants
        BOOL isCommandDown = (flags & (1 << 20)) != 0;   // NSCommandKeyMask in 10.9
        BOOL isD = ([characters isEqualToString:@"D"] || [characters isEqualToString:@"d"]);
        
        NSLog(@"DrawView: Key modifiers - Command: %d, Shift: %d, IsD: %d",
              isCommandDown, isShiftKeyDown, isD);
        
        if (isCommandDown && isD && !isShiftKeyDown) {
            NSLog(@"DrawView: Color toggle (Cmd+D) detected from Wacom, toggling color");
            [self toggleToNextColor];
        } else {
            // Otherwise, pass the event up the responder chain
            [super keyDown:event];
        }
    } else {
        NSLog(@"DrawView: Keyboard event not from Wacom tablet - passing through");
        [super keyDown:event];
    }
}

// Check if there's something to undo
- (BOOL)canUndo {
    return [undoStack count] > 0;
}

// Check if there's something to redo
- (BOOL)canRedo {
    return [redoStack count] > 0;
}

// Handle proximity notification from tablet
- (void)handleProximity:(NSNotification *)proxNotice {
    NSDictionary *proxDict = [proxNotice userInfo];
    UInt8 enterProximity;
    UInt8 pointerType;
    UInt16 pointerID;
    
    // Get entering proximity status
    [[proxDict objectForKey:kEnterProximity] getValue:&enterProximity];
    [[proxDict objectForKey:kPointerID] getValue:&pointerID];
    
    // Only interested in Enter Proximity for 1st concurrent device
    if (enterProximity != 0 && pointerID == 0) {
        // Get the pointer type
        [[proxDict objectForKey:kPointerType] getValue:&pointerType];
        
        // Check if it's the eraser end of the pen
        // Note: the value is 3 in Wacom.h but 2 in NSPointingDeviceType enum
        BOOL wasErasing = mErasing;
        if (pointerType == 3 || pointerType == 2) { // Try both values to be safe
            mErasing = YES;
            NSLog(@"DrawView: Eraser end detected - enabling eraser mode (type=%d)", pointerType);
        } else {
            mErasing = NO;
            NSLog(@"DrawView: Pen tip detected - disabling eraser mode (type=%d)", pointerType);
        }
        
        // Notify TabletApplication if erasing mode changed
        if (wasErasing != mErasing) {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:mErasing] 
                                                                 forKey:@"isErasing"];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"DrawViewErasingModeChanged" 
                                                                object:self 
                                                              userInfo:userInfo];
        }
    }
}

// Find the marker index of the stroke that contains the given point (for erasing - pixel perfect)
- (NSInteger)findStrokeAtPoint:(NSPoint)point {
    return [self findStrokeAtPoint:point forSelection:NO];
}

// Find the marker index of the stroke that contains the given point (for selection - more forgiving)
- (NSInteger)findStrokeAtPointForSelection:(NSPoint)point {
    return [self findStrokeAtPoint:point forSelection:YES];
}

// Internal method that handles both erasing and selection with different thresholds
- (NSInteger)findStrokeAtPoint:(NSPoint)point forSelection:(BOOL)isForSelection {
    NSLog(@"DrawView: Attempting to find stroke at point: %@ (forSelection: %d)", NSStringFromPoint(point), isForSelection);
    
    // Log information about the current state
    NSLog(@"DrawView: Current state - paths: %lu, strokeMarkers: %lu",
          (unsigned long)[paths count], (unsigned long)[strokeMarkers count]);
    
    // Safety check
    if ([paths count] == 0 || [strokeMarkers count] == 0) {
        NSLog(@"DrawView: No strokes to check");
        return -1;
    }
    
    // Find which stroke the point is in
    for (NSInteger markerIndex = [strokeMarkers count] - 1; markerIndex >= 0; markerIndex--) {
        NSInteger startIndex = [[strokeMarkers objectAtIndex:markerIndex] integerValue];
        NSInteger endIndex;
        
        // Determine the end index of this stroke
        if (markerIndex < [strokeMarkers count] - 1) {
            endIndex = [[strokeMarkers objectAtIndex:markerIndex + 1] integerValue] - 1;
        } else {
            endIndex = [paths count] - 1;
        }
        
        NSLog(@"DrawView: Checking stroke at marker index: %ld (segments %ld to %ld)",
              (long)markerIndex, (long)startIndex, (long)endIndex);
        
        // Check if the point is within any path in this stroke
        for (NSInteger i = startIndex; i <= endIndex; i++) {
            NSBezierPath *path = [paths objectAtIndex:i];
            CGFloat pathWidth = [path lineWidth];
            
            CGFloat detectionThreshold;
            if (isForSelection) {
                // For selection/dragging, be more forgiving - use 3x the stroke width
                // with a minimum of 5 pixels for easy selection
                detectionThreshold = MAX(5.0, pathWidth * 3.0);
            } else {
                // For erasing, use pixel-perfect detection
                // For very thin strokes, ensure a minimum threshold of 1 pixel
                detectionThreshold = MAX(1.0, pathWidth);
            }
            
            // Check if point is near this path segment
            if ([self point:point isNearPath:path withinDistance:detectionThreshold]) {
                NSLog(@"DrawView: Found stroke at marker index: %ld, path %ld, width %.2f, threshold %.2f",
                      (long)markerIndex, (long)i, pathWidth, detectionThreshold);
                return markerIndex;
            }
        }
    }
    
    NSLog(@"DrawView: No stroke found at point after checking all paths");
    return -1;
}

// Move the selected stroke by the given offset
- (void)moveSelectedStroke:(NSPoint)offset {
    if (!isStrokeSelected || selectedStrokeIndex < 0 || selectedStrokeIndex >= [strokeMarkers count]) {
        NSLog(@"DrawView: Cannot move stroke - no valid selection");
        return;
    }
    
    // If there are no related strokes found yet, find them now
    if ([relatedStrokeIndices count] == 0) {
        [self findRelatedStrokes:selectedStrokeIndex];
    }
    
    // Move all related strokes
    for (NSNumber *strokeIndexNum in relatedStrokeIndices) {
        NSInteger strokeIndex = [strokeIndexNum integerValue];
        
        // Skip invalid indices
        if (strokeIndex < 0 || strokeIndex >= [strokeMarkers count]) {
            continue;
        }
        
        NSInteger startIndex = [[strokeMarkers objectAtIndex:strokeIndex] integerValue];
        NSInteger endIndex;
        
        // Determine the end index of this stroke
        if (strokeIndex < [strokeMarkers count] - 1) {
            endIndex = [[strokeMarkers objectAtIndex:strokeIndex + 1] integerValue] - 1;
        } else {
            endIndex = [paths count] - 1;
        }
        
        // Move each path segment in the stroke
        for (NSInteger i = startIndex; i <= endIndex; i++) {
            NSBezierPath *path = [paths objectAtIndex:i];
            
            // Create a transform to move the path
            NSAffineTransform *transform = [NSAffineTransform transform];
            [transform translateXBy:offset.x yBy:offset.y];
            
            // Apply the transform to the path
            [path transformUsingAffineTransform:transform];
        }
    }
    
    // Note: Cache invalidation happens when dragging ends, not during each move
}

// Erase the entire stroke that contains the given point
- (void)eraseStrokeAtPoint:(NSPoint)point {
    NSLog(@"DrawView: Attempting to erase stroke at point: %@", NSStringFromPoint(point));
    
    // Find which stroke the point is in
    NSInteger markerIndex = [self findStrokeAtPoint:point];
    
    if (markerIndex >= 0) {
        NSLog(@"DrawView: Found stroke to erase at marker index: %ld", (long)markerIndex);
        
        // Create erase command and execute it
        EraseStrokeCommand *command = [[EraseStrokeCommand alloc] initWithDrawView:self strokeMarkerIndex:markerIndex];
        [command execute];
        
        // Add to undo stack
        [undoStack addObject:command];
        [command release];
        
        // Clear redo stack
        [redoStack removeAllObjects];
        
        NSLog(@"DrawView: Erased stroke using command pattern");
    } else {
        NSLog(@"DrawView: No stroke found at point to erase");
    }
}

// Erase text field at the given point
- (void)eraseTextAtPoint:(NSPoint)point {
    NSInteger textIndex = [self findTextFieldAtPoint:point];
    
    if (textIndex >= 0 && textIndex < [textFields count]) {
        // Create erase text command and execute it
        EraseTextCommand *command = [[EraseTextCommand alloc] initWithDrawView:self textFieldIndex:textIndex];
        [command execute];
        
        // Add to undo stack
        [undoStack addObject:command];
        [command release];
        
        // Clear redo stack
        [redoStack removeAllObjects];
        
        NSLog(@"DrawView: Erased text annotation using command pattern");
    }
}

// Helper method to check if a point is near a path
- (BOOL)point:(NSPoint)point isNearPath:(NSBezierPath *)path withinDistance:(CGFloat)distance {
    // Get the bounding box of the path first for a quick initial check
    NSRect bounds = [path bounds];
    NSRect extendedBounds = NSInsetRect(bounds, -distance, -distance);
    
    // Quick rejection based on extended bounding box 
    if (!NSPointInRect(point, extendedBounds)) {
        return NO;
    }
    
    // For a simple line segment, can check distance from the line
    if ([path elementCount] == 2) { // Simple line with moveToPoint and lineToPoint
        NSPoint points[2];
        [path elementAtIndex:0 associatedPoints:&points[0]]; // moveToPoint
        [path elementAtIndex:1 associatedPoints:&points[1]]; // lineToPoint
        
        return [self distanceFromPoint:point toLineWithPoints:points] <= distance;
    }
    
    // For more complex paths with multiple elements, check each segment
    if ([path elementCount] > 2) {
        NSPoint points[3]; // For storing points of the current segment
        NSBezierPathElement type;
        NSPoint movePoint = NSZeroPoint;
        BOOL haveMovePoint = NO;
        
        for (NSInteger i = 0; i < [path elementCount]; i++) {
            type = [path elementAtIndex:i associatedPoints:points];
            
            switch (type) {
                case NSMoveToBezierPathElement:
                    movePoint = points[0];
                    haveMovePoint = YES;
                    break;
                    
                case NSLineToBezierPathElement:
                    if (haveMovePoint) {
                        NSPoint linePoints[2] = {movePoint, points[0]};
                        if ([self distanceFromPoint:point toLineWithPoints:linePoints] <= distance) {
                            return YES;
                        }
                    }
                    movePoint = points[0];
                    break;
                    
                default:
                    // For curve elements, just use the bounding box check we did earlier
                    break;
            }
        }
    }
    
    // For complex paths, we couldn't find any segment within distance
    return NO;
}

// Calculate distance from point to line segment
- (CGFloat)distanceFromPoint:(NSPoint)point toLineWithPoints:(NSPoint[2])linePoints {
    NSPoint p1 = linePoints[0];
    NSPoint p2 = linePoints[1];
    
    // Vector from p1 to p2
    CGFloat vx = p2.x - p1.x;
    CGFloat vy = p2.y - p1.y;
    
    // Vector from p1 to point
    CGFloat wx = point.x - p1.x;
    CGFloat wy = point.y - p1.y;
    
    // Projection of point onto line
    CGFloat c1 = wx * vx + wy * vy; // Dot product
    
    if (c1 <= 0) {
        // Point is closest to p1
        return sqrt(wx * wx + wy * wy);
    }
    
    CGFloat c2 = vx * vx + vy * vy; // Length squared
    
    if (c2 <= c1) {
        // Point is closest to p2
        CGFloat dx = point.x - p2.x;
        CGFloat dy = point.y - p2.y;
        return sqrt(dx * dx + dy * dy);
    }
    
    // Point is closest to line itself
    CGFloat b = c1 / c2;
    CGFloat px = p1.x + b * vx;
    CGFloat py = p1.y + b * vy;
    CGFloat dx = point.x - px;
    CGFloat dy = point.y - py;
    
    return sqrt(dx * dx + dy * dy);
}

// Determine if a mouse event should be handled by us or passed through
- (BOOL)shouldAllowMouseEvent:(NSEvent *)event atPoint:(NSPoint)point {
    // Always handle tablet events
    if ([event isTabletPointerEvent]) {
        return YES;
    }
    
    // For mouse events, check if they're over a stroke
    return [self findStrokeAtPoint:point] >= 0;
}

// Undo the last complete stroke
- (void)undo {
    if ([undoStack count] > 0) {
        UndoCommand *command = [[undoStack lastObject] retain];
        [undoStack removeLastObject];
        
        // Perform the undo
        [command undo];
        
        // Add to redo stack
        [redoStack addObject:command];
        [command release];
        
        NSLog(@"DrawView: Undo performed - %@", [command description]);
    } else {
        NSLog(@"DrawView: Nothing to undo");
    }
}

// Redo the last undone stroke
- (void)redo {
    if ([redoStack count] > 0) {
        UndoCommand *command = [[redoStack lastObject] retain];
        [redoStack removeLastObject];
        
        // Perform the redo
        [command execute];
        
        // Add back to undo stack
        [undoStack addObject:command];
        [command release];
        
        NSLog(@"DrawView: Redo performed - %@", [command description]);
    } else {
        NSLog(@"DrawView: Nothing to redo");
    }
}

// Accept mouse down events regardless of key window status
- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    return YES;
}

- (BOOL)isOpaque {
    return NO;
}

// Override hit testing to allow click-through when not over a stroke
- (NSView *)hitTest:(NSPoint)point {
    // First check if we're editing text - if so, let normal hit testing work
    if (isEditingText && activeTextField) {
        // Check if the click is on the active text field
        NSPoint textFieldPoint = [activeTextField convertPoint:point fromView:nil];
        if ([activeTextField mouse:textFieldPoint inRect:[activeTextField bounds]]) {
            NSLog(@"DrawView: Hit test - click on active text field");
            return [activeTextField hitTest:point];
        }
    }
    
    // Also check if click is on any existing text field
    for (NSTextField *textField in textFields) {
        NSPoint textFieldPoint = [textField convertPoint:point fromView:nil];
        if ([textField mouse:textFieldPoint inRect:[textField bounds]]) {
            NSLog(@"DrawView: Hit test - click on text field");
            return [textField hitTest:point];
        }
    }
    
    // Convert incoming point from window coordinates to view coordinates
    NSPoint viewPoint = [self convertPoint:point fromView:nil];
    
    // Check if the point is over a stroke
    if ([self findStrokeAtPoint:viewPoint] >= 0) {
        // If we're over a stroke, return self to handle the event
        NSLog(@"DrawView: Hit test found stroke at point %@", NSStringFromPoint(viewPoint));
        return self;
    } else {
        // Otherwise, return nil to ignore the event (pass through)
        NSLog(@"DrawView: Hit test - no stroke at point %@, passing through", NSStringFromPoint(viewPoint));
        return nil;
    }
}

// Reset the eraser tracking variables
- (void)resetEraseTracking {
    hasLastErasePoint = NO;
    lastErasePoint = NSZeroPoint;
    NSLog(@"DrawView: Reset erase tracking");
}

// Calculate bounding rect for current stroke being drawn
- (NSRect)boundsForCurrentStroke {
    if (straightLinePath) {
        return NSInsetRect([straightLinePath bounds], -10, -10);
    }
    if (currentPath) {
        return NSInsetRect([currentPath bounds], -10, -10);
    }
    
    // For segment-based drawing, calculate bounds from recent segments
    if ([paths count] > 0 && [strokeMarkers count] > 0) {
        NSInteger lastMarker = [[strokeMarkers lastObject] integerValue];
        if ([paths count] > lastMarker) {
            // Get bounds of segments added since last stroke marker
            NSRect bounds = NSZeroRect;
            for (NSInteger i = lastMarker; i < [paths count]; i++) {
                NSBezierPath *path = [paths objectAtIndex:i];
                if (NSIsEmptyRect(bounds)) {
                    bounds = [path bounds];
                } else {
                    bounds = NSUnionRect(bounds, [path bounds]);
                }
            }
            return NSInsetRect(bounds, -10, -10);
        }
    }
    
    // If no current stroke, return a small rect around the last point
    return NSMakeRect(lastPoint.x - 20, lastPoint.y - 20, 40, 40);
}

- (NSArray *)presetColors {
    return presetColors;
}

- (void)setPresetColorAtIndex:(NSInteger)index toColor:(NSColor *)color {
    if (index < 0 || index >= [presetColors count]) {
        NSLog(@"DrawView: Invalid preset color index: %ld", (long)index);
        return;
    }
    
    // Create a mutable copy of the array
    NSMutableArray *mutablePresets = [presetColors mutableCopy];
    
    // Replace the color at the specified index
    [mutablePresets replaceObjectAtIndex:index withObject:color];
    
    // Release the old array and assign the new one
    [presetColors release];
    presetColors = [[NSArray alloc] initWithArray:mutablePresets];
    [mutablePresets release];
    
    // If the current color index is the one being changed, update the stroke color
    if (currentColorIndex == index) {
        // Update stroke color and trigger notification
        if (strokeColor != color) {
            [strokeColor release];
            strokeColor = [color retain];
            
            // Post a notification about the color change so the cursor can be updated
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:color forKey:@"color"];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"DrawViewColorChanged" 
                                                              object:self 
                                                            userInfo:userInfo];
            
            NSLog(@"DrawView: Posted color change notification with color: %@", color);
        }
        
        // Update the color well in the control panel
        NSArray *windows = [NSApp windows];
        for (NSWindow *window in windows) {
            if ([[window className] isEqualToString:@"ControlPanel"]) {
                NSColorWell *colorWell = [window valueForKey:@"colorWell"];
                if (colorWell) {
                    [colorWell setColor:color];
                }
                break;
            }
        }
    }
    
    // Save the updated colors to user defaults
    [self saveColorsToUserDefaults];
    
    NSLog(@"DrawView: Set preset color at index %ld to %@", (long)index, color);
}

- (void)toggleToNextColor {
    // Check if presetColors is empty or nil
    if (!presetColors || [presetColors count] == 0) {
        NSLog(@"DrawView: No preset colors available for toggling");
        return;
    }
    
    // Increment the color index
    currentColorIndex = (currentColorIndex + 1) % [presetColors count];
    
    // Set the new color
    NSColor *newColor = [presetColors objectAtIndex:currentColorIndex];
    
    // Release old color and retain new one
    if (strokeColor != newColor) {
        [strokeColor release];
        strokeColor = [newColor retain];
        
        // Post a notification about the color change so the cursor can be updated
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:newColor forKey:@"color"];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DrawViewColorChanged" 
                                                          object:self 
                                                        userInfo:userInfo];
        
        NSLog(@"DrawView: Posted color change notification with color: %@", newColor);
    }
    
    // Also update the color well in the control panel if there is one
    NSArray *windows = [NSApp windows];
    for (NSWindow *window in windows) {
        if ([[window className] isEqualToString:@"ControlPanel"]) {
            NSColorWell *colorWell = [window valueForKey:@"colorWell"];
            if (colorWell && self.strokeColor) {
                [colorWell setColor:self.strokeColor];
            }
            break;
        }
    }
    
    // Save the current color index to user defaults
    [[NSUserDefaults standardUserDefaults] setInteger:currentColorIndex forKey:@"CurrentColorIndex"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    NSLog(@"DrawView: Toggled to next color: %@", self.strokeColor);
}

// Clean up memory
- (void)dealloc {
    // Remove proximity notification observer
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:kProximityNotification
                                                  object:nil];
    
    [paths release];
    [pathColors release];
    [strokeMarkers release];
    [undoPaths release];
    [undoPathColors release];
    [undoStrokeMarkers release];
    if (currentPath) {
        [currentPath release];
    }
    if (straightLinePath) {
        [straightLinePath release];
    }
    [strokeColor release];
    [presetColors release];
    [relatedStrokeIndices release];
    
    // Clean up text fields
    for (NSTextField *textField in textFields) {
        [textField removeFromSuperview];
    }
    [textFields release];
    [textFieldColors release];
    [undoTextFields release];
    [undoTextFieldColors release];
    if (originalTextContent) {
        [originalTextContent release];
    }
    
    // Clean up cache
    if (cachedStrokesLayer) {
        CGLayerRelease(cachedStrokesLayer);
        cachedStrokesLayer = NULL;
    }
    
    [super dealloc];
}


// Removed debug visualization method

// Find all strokes that are related to the given stroke
// Related strokes are those with the same color and that intersect
- (void)findRelatedStrokes:(NSInteger)strokeIndex {
    // Clear any existing related strokes
    [relatedStrokeIndices removeAllObjects];
    
    // If invalid stroke index, just return
    if (strokeIndex < 0 || strokeIndex >= [strokeMarkers count]) {
        return;
    }
    
    // Get the color of the selected stroke
    NSInteger startIndexSelected = [[strokeMarkers objectAtIndex:strokeIndex] integerValue];
    NSColor *selectedColor = nil;
    
    if (startIndexSelected < [pathColors count]) {
        selectedColor = [pathColors objectAtIndex:startIndexSelected];
    }
    
    // If we can't determine the color, we can't find related strokes
    if (!selectedColor) {
        // At least add the selected stroke itself
        [relatedStrokeIndices addObject:[NSNumber numberWithInteger:strokeIndex]];
        return;
    }
    
    // Use a recursive approach to find all connected strokes
    NSMutableArray *processedStrokes = [NSMutableArray array];
    [self findConnectedStrokes:strokeIndex withColor:selectedColor processedStrokes:processedStrokes];
}

// Recursively find all connected strokes with the same color
- (void)findConnectedStrokes:(NSInteger)strokeIndex 
                   withColor:(NSColor *)selectedColor 
            processedStrokes:(NSMutableArray *)processedStrokes {
    
    // If we've already processed this stroke, skip it
    if ([processedStrokes containsObject:[NSNumber numberWithInteger:strokeIndex]]) {
        return;
    }
    
    // Add this stroke to our results and mark as processed
    [relatedStrokeIndices addObject:[NSNumber numberWithInteger:strokeIndex]];
    [processedStrokes addObject:[NSNumber numberWithInteger:strokeIndex]];
    
    // Find all directly connected strokes
    for (NSInteger i = 0; i < [strokeMarkers count]; i++) {
        // Skip if already processed
        if ([processedStrokes containsObject:[NSNumber numberWithInteger:i]]) {
            continue;
        }
        
        // Check if this stroke has the same color
        NSInteger startIndex = [[strokeMarkers objectAtIndex:i] integerValue];
        if (startIndex >= [pathColors count]) {
            continue;
        }
        
        NSColor *color = [pathColors objectAtIndex:startIndex];
        
        // If colors match, check for intersection
        if ([color isEqual:selectedColor] && [self doStrokesIntersect:strokeIndex strokeIndex2:i]) {
            // Recursively find connections from this stroke
            [self findConnectedStrokes:i withColor:selectedColor processedStrokes:processedStrokes];
        }
    }
}

// Check if two strokes intersect using rasterization for pixel-accurate detection
- (BOOL)doStrokesIntersect:(NSInteger)strokeIndex1 strokeIndex2:(NSInteger)strokeIndex2 {
    // Get path indices of first stroke
    NSInteger startIndex1 = [[strokeMarkers objectAtIndex:strokeIndex1] integerValue];
    NSInteger endIndex1;
    
    if (strokeIndex1 < [strokeMarkers count] - 1) {
        endIndex1 = [[strokeMarkers objectAtIndex:strokeIndex1 + 1] integerValue] - 1;
    } else {
        endIndex1 = [paths count] - 1;
    }
    
    // Get path indices of second stroke
    NSInteger startIndex2 = [[strokeMarkers objectAtIndex:strokeIndex2] integerValue];
    NSInteger endIndex2;
    
    if (strokeIndex2 < [strokeMarkers count] - 1) {
        endIndex2 = [[strokeMarkers objectAtIndex:strokeIndex2 + 1] integerValue] - 1;
    } else {
        endIndex2 = [paths count] - 1;
    }
    
    // Calculate combined bounds of both strokes
    NSRect bounds1 = NSZeroRect;
    BOOL first1 = YES;
    
    for (NSInteger i = startIndex1; i <= endIndex1; i++) {
        NSBezierPath *path = [paths objectAtIndex:i];
        if (first1) {
            bounds1 = [path bounds];
            first1 = NO;
        } else {
            bounds1 = NSUnionRect(bounds1, [path bounds]);
        }
    }
    
    NSRect bounds2 = NSZeroRect;
    BOOL first2 = YES;
    
    for (NSInteger i = startIndex2; i <= endIndex2; i++) {
        NSBezierPath *path = [paths objectAtIndex:i];
        if (first2) {
            bounds2 = [path bounds];
            first2 = NO;
        } else {
            bounds2 = NSUnionRect(bounds2, [path bounds]);
        }
    }
    
    // Add a small margin to the bounds
    bounds1 = NSInsetRect(bounds1, -1, -1);
    bounds2 = NSInsetRect(bounds2, -1, -1);
    
    // If the overall bounds don't even intersect, strokes definitely don't intersect
    if (!NSIntersectsRect(bounds1, bounds2)) {
        return NO;
    }
    
    // Calculate the union of both bounds to create our rasterization area
    NSRect unionBounds = NSUnionRect(bounds1, bounds2);
    
    // Make sure the bounds have a minimum size
    if (unionBounds.size.width < 2.0) unionBounds.size.width = 2.0;
    if (unionBounds.size.height < 2.0) unionBounds.size.height = 2.0;
    
    // Round up to integer size for our bitmap
    int width = (int)ceil(unionBounds.size.width);
    int height = (int)ceil(unionBounds.size.height);
    
    // Create a bitmap context for rasterization
    // We use 8 bits per component with a single 8-bit alpha channel
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
    
    // Create two separate bitmap contexts to render each stroke
    // Cast to CGBitmapInfo to avoid enum conversion warning
    CGContextRef bitmap1 = CGBitmapContextCreate(NULL, width, height, 8, width, colorSpace, (CGBitmapInfo)kCGImageAlphaOnly);
    CGContextRef bitmap2 = CGBitmapContextCreate(NULL, width, height, 8, width, colorSpace, (CGBitmapInfo)kCGImageAlphaOnly);
    
    if (!bitmap1 || !bitmap2) {
        NSLog(@"Failed to create bitmap contexts for intersection check");
        if (bitmap1) CGContextRelease(bitmap1);
        if (bitmap2) CGContextRelease(bitmap2);
        CGColorSpaceRelease(colorSpace);
        
        // If bitmap creation fails, just assume no intersection
        return NO;
    }
    
    // Prepare the contexts
    CGContextClearRect(bitmap1, CGRectMake(0, 0, width, height));
    CGContextClearRect(bitmap2, CGRectMake(0, 0, width, height));
    
    // Save the current graphics state
    CGContextSaveGState(bitmap1);
    CGContextSaveGState(bitmap2);
    
    // Set up coordinate system to match our bounds
    // First, flip the context because Core Graphics has origin at bottom-left
    CGContextTranslateCTM(bitmap1, 0, height);
    CGContextScaleCTM(bitmap1, 1.0, -1.0);
    CGContextTranslateCTM(bitmap2, 0, height);
    CGContextScaleCTM(bitmap2, 1.0, -1.0);
    
    // Then translate so that our bounds origin is at (0,0) in the context
    CGContextTranslateCTM(bitmap1, -unionBounds.origin.x, -unionBounds.origin.y);
    CGContextTranslateCTM(bitmap2, -unionBounds.origin.x, -unionBounds.origin.y);
    
    // Set up drawing parameters
    CGContextSetLineWidth(bitmap1, 1.0);  // Minimum line width for visibility
    CGContextSetLineWidth(bitmap2, 1.0);
    CGContextSetLineCap(bitmap1, kCGLineCapRound);
    CGContextSetLineCap(bitmap2, kCGLineCapRound);
    CGContextSetLineJoin(bitmap1, kCGLineJoinRound);
    CGContextSetLineJoin(bitmap2, kCGLineJoinRound);
    CGContextSetStrokeColorWithColor(bitmap1, CGColorGetConstantColor(kCGColorWhite));
    CGContextSetStrokeColorWithColor(bitmap2, CGColorGetConstantColor(kCGColorWhite));
    
    // Draw first stroke into bitmap1
    for (NSInteger i = startIndex1; i <= endIndex1; i++) {
        NSBezierPath *path = [paths objectAtIndex:i];
        CGPathRef cgPath = [self CGPathFromNSBezierPath:path];
        if (cgPath) {
            CGContextAddPath(bitmap1, cgPath);
            CGPathRelease(cgPath);
        }
    }
    CGContextStrokePath(bitmap1);
    
    // Draw second stroke into bitmap2
    for (NSInteger i = startIndex2; i <= endIndex2; i++) {
        NSBezierPath *path = [paths objectAtIndex:i];
        CGPathRef cgPath = [self CGPathFromNSBezierPath:path];
        if (cgPath) {
            CGContextAddPath(bitmap2, cgPath);
            CGPathRelease(cgPath);
        }
    }
    CGContextStrokePath(bitmap2);
    
    // Restore the graphics state
    CGContextRestoreGState(bitmap1);
    CGContextRestoreGState(bitmap2);
    
    // Get the bitmap data
    unsigned char *data1 = CGBitmapContextGetData(bitmap1);
    unsigned char *data2 = CGBitmapContextGetData(bitmap2);
    
    BOOL hasIntersection = NO;
    
    // Check for pixel overlap between the two bitmaps with a 1-pixel margin
    if (data1 && data2) {
        // Radius of 1 means check surrounding pixels
        int margin = 1;
        
        for (int y = margin; y < height - margin; y++) {
            for (int x = margin; x < width - margin; x++) {
                int index = y * width + x;
                
                // If the current pixel in bitmap1 has content
                if (data1[index] > 0) {
                    // Check this pixel and surrounding pixels in bitmap2 (within the margin)
                    BOOL foundNearby = NO;
                    
                    for (int dy = -margin; dy <= margin && !foundNearby; dy++) {
                        for (int dx = -margin; dx <= margin && !foundNearby; dx++) {
                            int nx = x + dx;
                            int ny = y + dy;
                            
                            // Make sure we're within bounds
                            if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
                                int neighborIndex = ny * width + nx;
                                
                                // If a nearby pixel in bitmap2 has content, consider it an intersection
                                if (data2[neighborIndex] > 0) {
                                    foundNearby = YES;
                                    hasIntersection = YES;
                                    break;
                                }
                            }
                        }
                    }
                    
                    if (foundNearby) {
                        break;
                    }
                }
            }
            if (hasIntersection) break;
        }
    }
    
    // Clean up
    CGContextRelease(bitmap1);
    CGContextRelease(bitmap2);
    CGColorSpaceRelease(colorSpace);
    
    return hasIntersection;
}

// Convert NSBezierPath to CGPathRef for use with Core Graphics
- (CGPathRef)CGPathFromNSBezierPath:(NSBezierPath *)path {
    CGMutablePathRef cgPath = CGPathCreateMutable();
    NSPoint points[3];
    BOOL didClosePath = NO;
    
    for (NSInteger i = 0; i < [path elementCount]; i++) {
        NSBezierPathElement element = [path elementAtIndex:i associatedPoints:points];
        
        switch(element) {
            case NSMoveToBezierPathElement:
                CGPathMoveToPoint(cgPath, NULL, points[0].x, points[0].y);
                break;
                
            case NSLineToBezierPathElement:
                CGPathAddLineToPoint(cgPath, NULL, points[0].x, points[0].y);
                break;
                
            case NSCurveToBezierPathElement:
                CGPathAddCurveToPoint(cgPath, NULL, 
                                     points[0].x, points[0].y,
                                     points[1].x, points[1].y,
                                     points[2].x, points[2].y);
                break;
                
            case NSClosePathBezierPathElement:
                CGPathCloseSubpath(cgPath);
                didClosePath = YES;
                break;
        }
    }
    
    // Use a different variable name to avoid shadowing the instance variable
    CGFloat pathLineWidth = [path lineWidth];
    if (pathLineWidth < 1.0) pathLineWidth = 1.0;
    
    // If the path has a line width, apply it as a stroke
    CGPathRef strokedPath = CGPathCreateCopyByStrokingPath(
        cgPath, NULL, pathLineWidth, kCGLineCapRound, kCGLineJoinRound, 0);
    
    CGPathRelease(cgPath);
    return strokedPath;
}

// This method has been removed as it's no longer needed with the rasterization approach

// These methods have been removed as they're no longer needed with the rasterization approach

#pragma mark - Color Persistence

- (void)loadColorsFromUserDefaults {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSData *colorData1 = [defaults objectForKey:@"PresetColor1"];
    NSData *colorData2 = [defaults objectForKey:@"PresetColor2"];
    NSData *colorData3 = [defaults objectForKey:@"PresetColor3"];
    NSData *colorData4 = [defaults objectForKey:@"PresetColor4"];
    NSData *colorData5 = [defaults objectForKey:@"PresetColor5"];
    NSInteger savedColorIndex = [defaults integerForKey:@"CurrentColorIndex"];
    
    // Default colors in case user defaults are not available
    NSColor *color1 = [NSColor redColor];
    NSColor *color2 = [NSColor blueColor];
    NSColor *color3 = [NSColor greenColor];
    NSColor *color4 = [NSColor orangeColor];
    NSColor *color5 = [NSColor purpleColor];
    
    // If we have stored colors, unarchive them
    if (colorData1) {
        NSColor *loadedColor = [NSUnarchiver unarchiveObjectWithData:colorData1];
        if (loadedColor) {
            color1 = loadedColor;
        }
    }
    
    if (colorData2) {
        NSColor *loadedColor = [NSUnarchiver unarchiveObjectWithData:colorData2];
        if (loadedColor) {
            color2 = loadedColor;
        }
    }
    
    if (colorData3) {
        NSColor *loadedColor = [NSUnarchiver unarchiveObjectWithData:colorData3];
        if (loadedColor) {
            color3 = loadedColor;
        }
    }
    
    if (colorData4) {
        NSColor *loadedColor = [NSUnarchiver unarchiveObjectWithData:colorData4];
        if (loadedColor) {
            color4 = loadedColor;
        }
    }
    
    if (colorData5) {
        NSColor *loadedColor = [NSUnarchiver unarchiveObjectWithData:colorData5];
        if (loadedColor) {
            color5 = loadedColor;
        }
    }
    
    // Initialize preset colors with loaded values
    presetColors = [[NSArray alloc] initWithObjects:color1, color2, color3, color4, color5, nil];
    
    // Set current color index (default to 0 if out of range)
    if (savedColorIndex >= 0 && savedColorIndex < [presetColors count]) {
        currentColorIndex = savedColorIndex;
    } else {
        currentColorIndex = 0;
    }
    
    // Set current stroke color
    self.strokeColor = [presetColors objectAtIndex:currentColorIndex];
    
    NSLog(@"DrawView: Loaded colors from user defaults");
}

- (void)saveColorsToUserDefaults {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // Archive the colors
    if ([presetColors count] >= 5) {
        NSData *colorData1 = [NSArchiver archivedDataWithRootObject:[presetColors objectAtIndex:0]];
        NSData *colorData2 = [NSArchiver archivedDataWithRootObject:[presetColors objectAtIndex:1]];
        NSData *colorData3 = [NSArchiver archivedDataWithRootObject:[presetColors objectAtIndex:2]];
        NSData *colorData4 = [NSArchiver archivedDataWithRootObject:[presetColors objectAtIndex:3]];
        NSData *colorData5 = [NSArchiver archivedDataWithRootObject:[presetColors objectAtIndex:4]];
        
        // Save to user defaults
        [defaults setObject:colorData1 forKey:@"PresetColor1"];
        [defaults setObject:colorData2 forKey:@"PresetColor2"];
        [defaults setObject:colorData3 forKey:@"PresetColor3"];
        [defaults setObject:colorData4 forKey:@"PresetColor4"];
        [defaults setObject:colorData5 forKey:@"PresetColor5"];
        [defaults setInteger:currentColorIndex forKey:@"CurrentColorIndex"];
        
        // Synchronize to ensure the data is saved
        [defaults synchronize];
        
        NSLog(@"DrawView: Saved colors to user defaults");
    }
}

#pragma mark - Text Annotation Methods

- (void)enterTextInputMode {
    // If already editing, finish the current text first
    if (isEditingText) {
        [self finishTextInput];
    }
    
    NSLog(@"Creating text input at cursor position");
    
    // Start text input immediately at current mouse position
    NSPoint mouseLocation = [NSEvent mouseLocation];
    NSPoint viewPoint = [self convertScreenPointToView:mouseLocation];
    [self startTextInputAtPoint:viewPoint];
}

- (void)exitTextInputMode {
    // This method is mainly for cleanup if text input needs to be cancelled
    if (isEditingText) {
        [self cancelTextInput];
    }
    NSLog(@"Exited text input mode");
    
    // Ensure window state is restored
    [[self window] setIgnoresMouseEvents:YES];
    [[self window] setLevel:originalWindowLevel];  // Always restore the window level
    
    // Restore normal cursor
    [[NSCursor arrowCursor] set];
}

- (void)startTextInputAtPoint:(NSPoint)point {
    // If already editing, finish the current text first
    if (isEditingText) {
        [self finishTextInput];
    }
    
    // Store the position for the text
    textInputPosition = point;
    isEditingText = YES;
    
    // Create a text field for input at the exact click point - start with minimal width
    // Height should be proportional to text size
    CGFloat textFieldHeight = self.textSize + 8; // Add some padding to the font size
    NSRect textFrame = NSMakeRect(point.x, point.y, 50, textFieldHeight);
    
    activeTextField = [[EscapeHandlingTextField alloc] initWithFrame:textFrame];
    [(EscapeHandlingTextField *)activeTextField setDrawView:self];
    [activeTextField setBackgroundColor:[NSColor clearColor]];
    [activeTextField setDrawsBackground:NO];
    [activeTextField setBordered:NO];
    [activeTextField setTextColor:strokeColor];
    [activeTextField setFont:[NSFont systemFontOfSize:self.textSize]];
    [activeTextField setEditable:YES];
    [activeTextField setSelectable:YES];
    [activeTextField setStringValue:@""];
    [activeTextField setDelegate:self];
    
    // Add to view
    [self addSubview:activeTextField];
    
    // Temporarily allow the window to accept events for text input
    [[self window] setIgnoresMouseEvents:NO];
    
    // Store the original window level
    originalWindowLevel = [[self window] level];
    
    // Temporarily lower window level to allow proper keyboard focus
    [[self window] setLevel:NSFloatingWindowLevel];
    
    // Activate the application to ensure it can receive keyboard events
    [NSApp activateIgnoringOtherApps:YES];
    
    // Make the window key and order front to accept keyboard input
    [[self window] makeKeyAndOrderFront:nil];
    
    
    // Use performSelector to delay setting first responder to avoid the exception
    [self performSelector:@selector(focusTextView) withObject:nil afterDelay:0.1];
    
    NSLog(@"Started text input at point: %@", NSStringFromPoint(point));
}

- (void)focusTextView {
    if (activeTextField) {
        // Set first responder (window should already be key)
        BOOL success = [[self window] makeFirstResponder:activeTextField];
        if (success) {
            NSLog(@"Text field focused successfully");
        } else {
            NSLog(@"Failed to focus text field - attempting to make window key first");
            [[self window] makeKeyWindow];
            success = [[self window] makeFirstResponder:activeTextField];
            if (success) {
                NSLog(@"Text field focused successfully on second attempt");
            } else {
                NSLog(@"Failed to focus text field even after making window key");
            }
        }
    }
}

- (void)finishTextInput {
    if (!isEditingText || !activeTextField) return;
    
    NSString *text = [[activeTextField stringValue] copy];
    
    // Check if this is an existing text field being edited
    BOOL isExistingTextField = [textFields containsObject:activeTextField];
    
    if ([text length] > 0) {
        // Remove focus from the text field
        [[self window] makeFirstResponder:nil];
        
        // Make the text field non-editable after editing
        [activeTextField setEditable:NO];
        [activeTextField setSelectable:NO];
        
        // Only add to arrays if it's a new text field
        if (!isExistingTextField) {
            // Create add text command
            AddTextCommand *command = [[AddTextCommand alloc] initWithDrawView:self 
                                                                      textField:activeTextField 
                                                                          color:strokeColor];
            [command execute];
            
            // Add to undo stack
            [undoStack addObject:command];
            [command release];
            
            // Clear redo stack
            [redoStack removeAllObjects];
            
            // Retain the text field since we're keeping it
            [activeTextField retain];
            
            NSLog(@"Added new text field: %@", text);
        } else {
            // Check if text actually changed
            if (originalTextContent && ![originalTextContent isEqualToString:text]) {
                // Create edit text command
                EditTextCommand *command = [[EditTextCommand alloc] initWithDrawView:self 
                                                                            textField:activeTextField 
                                                                              oldText:originalTextContent 
                                                                              newText:text];
                
                // Add to undo stack
                [undoStack addObject:command];
                [command release];
                
                // Clear redo stack
                [redoStack removeAllObjects];
            }
            NSLog(@"Updated existing text field: %@", text);
        }
    } else {
        // If empty, remove it
        if (isExistingTextField) {
            // Remove from arrays if it was existing
            NSInteger index = [textFields indexOfObject:activeTextField];
            if (index != NSNotFound) {
                [textFields removeObjectAtIndex:index];
                [textFieldColors removeObjectAtIndex:index];
            }
        }
        [activeTextField removeFromSuperview];
    }
    
    // Clean up active reference
    [activeTextField release];
    activeTextField = nil;
    [originalTextContent release];
    originalTextContent = nil;
    isEditingText = NO;
    
    // Completely exit text mode and restore normal operation
    [[self window] setIgnoresMouseEvents:YES];
    [[self window] setLevel:originalWindowLevel]; // Restore original window level
    [[NSCursor arrowCursor] set];
    
    NSLog(@"Text input completed, returned to normal mode");
    
    // Redraw
    [self setNeedsDisplay:YES];
    
    [text release];
}

- (void)finishTextInputAndCreateNewBelow {
    if (!isEditingText || !activeTextField) return;
    
    NSString *text = [[activeTextField stringValue] copy];
    NSPoint currentPosition = textInputPosition;
    
    // Check if this is an existing text field being edited
    BOOL isExistingTextField = [textFields containsObject:activeTextField];
    
    if ([text length] > 0) {
        // Remove focus from the text field
        [[self window] makeFirstResponder:nil];
        
        // Make the text field non-editable after editing
        [activeTextField setEditable:NO];
        [activeTextField setSelectable:NO];
        
        // Only add to arrays if it's a new text field
        if (!isExistingTextField) {
            // Create add text command
            AddTextCommand *command = [[AddTextCommand alloc] initWithDrawView:self 
                                                                      textField:activeTextField 
                                                                          color:strokeColor];
            [command execute];
            
            // Add to undo stack
            [undoStack addObject:command];
            [command release];
            
            // Clear redo stack
            [redoStack removeAllObjects];
            
            // Retain the text field since we're keeping it
            [activeTextField retain];
            
            NSLog(@"Added new text field: %@", text);
        } else {
            // Check if text actually changed
            if (originalTextContent && ![originalTextContent isEqualToString:text]) {
                // Create edit text command
                EditTextCommand *command = [[EditTextCommand alloc] initWithDrawView:self 
                                                                            textField:activeTextField 
                                                                              oldText:originalTextContent 
                                                                              newText:text];
                
                // Add to undo stack
                [undoStack addObject:command];
                [command release];
                
                // Clear redo stack
                [redoStack removeAllObjects];
            }
            NSLog(@"Updated existing text field: %@", text);
        }
    } else {
        // If empty, remove it
        if (isExistingTextField) {
            // Remove from arrays if it was existing
            NSInteger index = [textFields indexOfObject:activeTextField];
            if (index != NSNotFound) {
                [textFields removeObjectAtIndex:index];
                [textFieldColors removeObjectAtIndex:index];
            }
        }
        [activeTextField removeFromSuperview];
    }
    
    // Clean up current reference
    [activeTextField release];
    activeTextField = nil;
    [originalTextContent release];
    originalTextContent = nil;
    
    // Calculate position for new text area below current one
    // Use the current text size plus some line spacing
    CGFloat lineHeight = self.textSize + 4; // Add 4px line spacing
    NSPoint newPosition = NSMakePoint(currentPosition.x, currentPosition.y - lineHeight);
    
    // Create new text area below the current one
    [self startTextInputAtPoint:newPosition];
    
    // Redraw to show the completed text
    [self setNeedsDisplay:YES];
    
    [text release];
}

- (void)cancelTextInput {
    if (!isEditingText || !activeTextField) return;
    
    [activeTextField removeFromSuperview];
    [activeTextField release];
    activeTextField = nil;
    [originalTextContent release];
    originalTextContent = nil;
    isEditingText = NO;
    
    // Restore window to ignore mouse events and normal cursor
    [[self window] setIgnoresMouseEvents:YES];
    [[self window] setLevel:originalWindowLevel]; // Restore original window level
    [[NSCursor arrowCursor] set];
    
    NSLog(@"Cancelled text input");
}

- (void)startEditingExistingTextField:(NSTextField *)textField {
    // If already editing something else, finish it first
    if (isEditingText) {
        [self finishTextInput];
    }
    
    // Set the text field as active
    activeTextField = textField;
    [activeTextField retain];
    isEditingText = YES;
    
    // Store the original text for undo
    originalTextContent = [[textField stringValue] copy];
    
    // Store the position
    textInputPosition = [textField frame].origin;
     
    // Temporarily allow the window to accept events for text input
    [[self window] setIgnoresMouseEvents:NO];
    
    // Store the original window level
    originalWindowLevel = [[self window] level];
    
    // Temporarily lower window level to allow proper keyboard focus
    [[self window] setLevel:NSFloatingWindowLevel];
    
    // Make the text field editable
    [activeTextField setEditable:YES];
    [activeTextField setSelectable:YES];
    
    // Activate the application to ensure it can receive keyboard events
    [NSApp activateIgnoringOtherApps:YES];
    
    // Make the window key and order front to accept keyboard input
    [[self window] makeKeyAndOrderFront:nil];
    
    NSLog(@"Started editing existing text field: %@", [activeTextField stringValue]);
}

- (NSInteger)findTextAnnotationAtPoint:(NSPoint)point {
    // Now searches for text fields instead of annotations
    return [self findTextFieldAtPoint:point];
}

- (NSInteger)findTextFieldAtPoint:(NSPoint)point {
    for (NSInteger i = [textFields count] - 1; i >= 0; i--) {
        NSTextField *textField = [textFields objectAtIndex:i];
        NSRect bounds = [textField frame];
        
        if (NSPointInRect(point, bounds)) {
            return i;
        }
    }
    return -1;
}

- (NSRect)boundsForTextAnnotation:(NSDictionary *)annotation {
    NSString *text = [annotation objectForKey:@"text"];
    NSPoint position = [[annotation objectForKey:@"position"] pointValue];
    NSFont *font = [annotation objectForKey:@"font"];
    
    NSDictionary *attributes = @{NSFontAttributeName: font};
    NSSize stringSize = [text sizeWithAttributes:attributes];
    
    return NSMakeRect(position.x, position.y, stringSize.width, stringSize.height);
}

- (void)moveSelectedText:(NSPoint)offset {
    if (selectedTextFieldIndex < 0 || selectedTextFieldIndex >= [textFields count]) return;
    
    NSTextField *textField = [textFields objectAtIndex:selectedTextFieldIndex];
    NSRect currentFrame = [textField frame];
    NSRect newFrame = NSMakeRect(currentFrame.origin.x + offset.x, 
                                  currentFrame.origin.y + offset.y,
                                  currentFrame.size.width,
                                  currentFrame.size.height);
    
    [textField setFrame:newFrame];
    [self setNeedsDisplay:YES];
}

#pragma mark - NSTextFieldDelegate

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)selector {
    if (selector == @selector(insertNewline:)) {
        // Regular Enter pressed - finish text input
        [[control window] endEditingFor:control];
        [self finishTextInput];
        return YES; // Return YES to indicate we handled it
    } else if (selector == @selector(insertNewlineIgnoringFieldEditor:)) {
        // Alt+Enter pressed - finalize current text area and create new one below
        [self finishTextInputAndCreateNewBelow];
        return YES;
    }
    return NO;
}

- (void)controlTextDidChange:(NSNotification *)notification {
    NSTextField *textField = [notification object];
    if (textField == activeTextField) {
        // Auto-resize the text field width based on content
        NSString *currentText = [textField stringValue];
        NSFont *font = [textField font];
        
        NSDictionary *attributes = @{NSFontAttributeName: font};
        NSSize stringSize = [currentText sizeWithAttributes:attributes];
        
        // Add some padding and set reasonable min/max widths and height
        CGFloat newWidth = stringSize.width + 20; // 20px padding
        newWidth = MAX(newWidth, 50);  // Minimum 50px
        
        CGFloat newHeight = self.textSize + 8; // Height proportional to current text size + padding
        
        // Update the frame
        NSRect currentFrame = [textField frame];
        currentFrame.size.width = newWidth;
        currentFrame.size.height = newHeight;
        [textField setFrame:currentFrame];
    }
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    NSTextField *textField = [notification object];
    if (textField == activeTextField) {
        NSInteger whyEnd = [[[notification userInfo] objectForKey:@"NSTextMovement"] intValue];
        if (whyEnd == NSReturnTextMovement) {
            // Enter key pressed - already handled in control:textView:doCommandBySelector:
            // Do nothing here to avoid double processing
        } else if (whyEnd == NSCancelTextMovement) {
            // Escape key pressed - cancel text input
            [self cancelTextInput];
        }
    }
}

#pragma mark - Property Methods

- (CGFloat)textSize {
    return textSize;
}

- (void)setTextSize:(CGFloat)newTextSize {
    textSize = newTextSize;
    
    // Save to user defaults
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setFloat:textSize forKey:@"WacomOverlayTextSize"];
    [defaults synchronize];
}

- (void)resetToDefaults {
    // Reset to default colors
    NSColor *color1 = [NSColor redColor];
    NSColor *color2 = [NSColor blueColor];
    NSColor *color3 = [NSColor greenColor];
    NSColor *color4 = [NSColor orangeColor];
    NSColor *color5 = [NSColor purpleColor];
    
    [presetColors release];
    presetColors = [[NSArray alloc] initWithObjects:color1, color2, color3, color4, color5, nil];
    
    // Reset current color index
    currentColorIndex = 0;
    self.strokeColor = color1;
    
    // Reset line width
    self.lineWidth = 2.0;
    
    // Reset text size
    textSize = 24.0;
    
    // Clear user defaults
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:@"PresetColor1"];
    [defaults removeObjectForKey:@"PresetColor2"];
    [defaults removeObjectForKey:@"PresetColor3"];
    [defaults removeObjectForKey:@"PresetColor4"];
    [defaults removeObjectForKey:@"PresetColor5"];
    [defaults removeObjectForKey:@"CurrentColorIndex"];
    [defaults removeObjectForKey:@"WacomOverlayTextSize"];
    [defaults synchronize];
    
    // Refresh the view
    [self setNeedsDisplay:YES];
}

#pragma mark - Performance Caching Methods

- (void)invalidateStrokeCache {
    cacheNeedsUpdate = YES;
    NSLog(@"DrawView: Cache invalidated - will rebuild on next draw");
}

- (void)updateStrokeCache {
    // Determine how many strokes should be cached
    NSInteger targetCacheCount = [paths count];
    if (currentPath && [strokeMarkers count] > 0) {
        // If actively drawing, only cache completed strokes
        targetCacheCount = [[strokeMarkers lastObject] integerValue];
    }
    
    // Check if cache is still valid
    if (!cacheNeedsUpdate && lastCachedStrokeCount == targetCacheCount && cachedStrokesLayer) {
        return; // Cache is still valid
    }
    
    NSRect bounds = [self bounds];
    if (NSIsEmptyRect(bounds) || bounds.size.width <= 0 || bounds.size.height <= 0) {
        return; // Can't create cache with invalid bounds
    }
    
    // Clean up old cache
    if (cachedStrokesLayer) {
        CGLayerRelease(cachedStrokesLayer);
        cachedStrokesLayer = NULL;
    }
    
    // Get the current graphics context
    NSGraphicsContext *nsContext = [NSGraphicsContext currentContext];
    if (!nsContext) {
        // No context available - mark cache as needing update and return
        cacheNeedsUpdate = YES;
        return;
    }
    
    CGContextRef context = [nsContext graphicsPort];
    if (!context) {
        // No CG context available - mark cache as needing update and return
        cacheNeedsUpdate = YES;
        return;
    }
    
    // Create a new layer for caching completed strokes
    cachedStrokesLayer = CGLayerCreateWithContext(context, bounds.size, NULL);
    if (!cachedStrokesLayer) {
        // Failed to create layer - mark cache as needing update and return
        cacheNeedsUpdate = YES;
        return;
    }
    
    CGContextRef layerContext = CGLayerGetContext(cachedStrokesLayer);
    if (!layerContext) {
        CGLayerRelease(cachedStrokesLayer);
        cachedStrokesLayer = NULL;
        cacheNeedsUpdate = YES;
        return;
    }
    
    // Set up the layer context
    CGContextSetShouldAntialias(layerContext, true);
    CGContextSetLineCap(layerContext, kCGLineCapRound);
    CGContextSetLineJoin(layerContext, kCGLineJoinRound);
    
    // Create NSGraphicsContext for the layer
    NSGraphicsContext *layerNSContext = [NSGraphicsContext graphicsContextWithGraphicsPort:layerContext flipped:NO];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:layerNSContext];
    
    // Use the same calculation as in the validation check
    NSInteger strokesToDraw = targetCacheCount;
    
    // Draw all completed strokes to the cache layer
    for (NSUInteger i = 0; i < strokesToDraw; i++) {
        NSBezierPath *path = [paths objectAtIndex:i];
        NSColor *color = (i < [pathColors count]) ? [pathColors objectAtIndex:i] : strokeColor;
        
        [color set];
        [path stroke];
    }
    
    [NSGraphicsContext restoreGraphicsState];
    
    cacheNeedsUpdate = NO;
    lastCachedStrokeCount = strokesToDraw;
    NSLog(@"DrawView: Cache rebuilt with %ld strokes", (long)strokesToDraw);
}

- (void)drawCachedStrokes {
    if (!cachedStrokesLayer) {
        return;
    }
    
    // Get the current graphics context
    NSGraphicsContext *nsContext = [NSGraphicsContext currentContext];
    if (!nsContext) {
        return;
    }
    
    CGContextRef context = [nsContext graphicsPort];
    if (!context) {
        return;
    }
    
    // Draw the cached layer
    CGContextDrawLayerAtPoint(context, CGPointZero, cachedStrokesLayer);
}

@end