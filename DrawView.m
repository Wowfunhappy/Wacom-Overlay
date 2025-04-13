#import "DrawView.h"
#import "TabletEvents.h"
#import "TabletApplication.h"

@implementation DrawView

@synthesize strokeColor;
@synthesize lineWidth;
@synthesize erasing = mErasing;
@synthesize currentColorIndex;
@synthesize smoothingLevel;
@synthesize enableSmoothing;
@dynamic presetColors;

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
        
        // Initialize the preset colors
        presetColors = [[NSArray alloc] initWithObjects:
                        [NSColor redColor],
                        [NSColor blueColor],
                        [NSColor greenColor],
                        nil];
        currentColorIndex = 0;
        self.strokeColor = [presetColors objectAtIndex:currentColorIndex];
        
        self.lineWidth = 2.0;
        mErasing = NO;
        hasLastErasePoint = NO;
        lastErasePoint = NSZeroPoint;
        
        // Initialize smoothing with maximum level
        pointBuffer = [[NSMutableArray alloc] init];
        self.smoothingLevel = 20;  // Maximum smoothing level for neatest handwriting
        self.enableSmoothing = YES;  // Always enabled
        
        // Make the view transparent to allow click-through
        [self setWantsLayer:YES];
        
        // Ensure we can receive all events
        [[self window] setAcceptsMouseMovedEvents:YES];
        
        // Register for proximity notifications
        [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(handleProximity:)
                                              name:kProximityNotification
                                              object:nil];
        
        NSLog(@"DrawView initialized with frame: %@", NSStringFromRect(frame));
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    // Clear the background (transparent)
    [[NSColor clearColor] set];
    NSRectFill(dirtyRect);
    
    // Draw all saved paths with their colors
    for (NSUInteger i = 0; i < [paths count]; i++) {
        NSBezierPath *path = [paths objectAtIndex:i];
        NSColor *color = (i < [pathColors count]) ? [pathColors objectAtIndex:i] : strokeColor;
        
        [color set];
        [path stroke];
    }
    
    // Draw current path if it exists
    if (currentPath) {
        [strokeColor set];
        [currentPath stroke];
    }
}

// This special method handles events forwarded from the global event monitor
- (void)mouseEvent:(NSEvent *)event {
    // Handle event based on its type
    NSInteger type = [event type];
    
    NSLog(@"DrawView received forwarded event from monitor, type: %ld", (long)type);
    
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
            
        case 24: // NSTabletProximity
            // If we receive a proximity event, it should have already been handled by TabletApplication
            // but we can explicitly update our erasing status here if needed
            if ([event isTabletProximityEvent]) {
                // For OS X 10.9, we need to use the raw value 2 for eraser
                BOOL isEraser = ([event pointingDeviceType] == 2); // NSPointingDeviceTypeEraser is 2
                if (isEraser != mErasing) {
                    mErasing = isEraser;
                    NSLog(@"DrawView: Eraser state changed to %@", mErasing ? @"ON" : @"OFF");
                }
            }
            break;
            
        default:
            NSLog(@"DrawView: Unhandled event type in mouseEvent: %ld", (long)type);
            break;
    }
}

- (NSPoint)convertScreenPointToView:(NSPoint)screenPoint {
    // If the window is nil (which happens for global event monitoring when the app isn't active),
    // we need to account for that
    NSWindow *window = [self window];
    if (!window) {
        NSLog(@"DrawView: Warning - window is nil in convertScreenPointToView. Using overlay window.");
        
        // Try to get the overlay window from the application
        TabletApplication *app = (TabletApplication *)[NSApplication sharedApplication];
        if ([app respondsToSelector:@selector(overlayWindow)]) {
            window = (NSWindow *)[app performSelector:@selector(overlayWindow)];
        }
        
        // If we still don't have a window, just return the screen point
        if (!window) {
            NSLog(@"DrawView: Error - cannot find window for coordinate conversion");
            return screenPoint;
        }
    }
    
    // Convert screen coordinates to window coordinates
    NSPoint windowPoint = [window convertScreenToBase:screenPoint];
    
    // Convert window coordinates to view coordinates
    NSPoint viewPoint = [self convertPoint:windowPoint fromView:nil];
    
    return viewPoint;
}

- (void)mouseDown:(NSEvent *)event {
    // Check if this is a tablet event
    if ([event isTabletPointerEvent]) {
        NSLog(@"DrawView: mouseDown detected tablet event");
    } else {
        NSLog(@"DrawView: mouseDown detected regular mouse event, ignoring");
        return;
    }
    
    // Get the screen location
    NSPoint screenPoint = [NSEvent mouseLocation];
    
    // Convert to view coordinates
    NSPoint viewPoint = [self convertScreenPointToView:screenPoint];
    
    // If we're in eraser mode, erase stroke at this point instead of drawing
    if (mErasing) {
        NSLog(@"DrawView: Processing eraser action at point: %@", NSStringFromPoint(viewPoint));
        [self eraseStrokeAtPoint:viewPoint];
        return;
    }
    
    // Clear the smoothing buffer at the start of a new stroke
    [self clearSmoothingBuffer];
    
    // Apply smoothing to the starting point (adds it to buffer)
    NSPoint smoothedPoint = [self smoothPoint:viewPoint];
    
    // Start a new path
    currentPath = [[NSBezierPath bezierPath] retain];
    [currentPath setLineWidth:lineWidth];
    [currentPath setLineCapStyle:NSRoundLineCapStyle];
    [currentPath setLineJoinStyle:NSRoundLineJoinStyle];
    
    // Start the path
    [currentPath moveToPoint:smoothedPoint];
    lastPoint = smoothedPoint;
    
    // Add a marker for the start of a new stroke
    // We'll record the current path count at the beginning of a stroke
    [strokeMarkers addObject:[NSNumber numberWithInteger:[paths count]]];
    
    NSLog(@"DrawView: Starting new path at point: %@", NSStringFromPoint(viewPoint));
    
    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event {
    // Check if this is a tablet event
    if ([event isTabletPointerEvent]) {
        NSLog(@"DrawView: mouseDragged detected tablet event");
    } else {
        NSLog(@"DrawView: mouseDragged detected regular mouse event, ignoring");
        return;
    }
    
    // If we're in eraser mode, handle eraser dragging
    if (mErasing) {
        // Get the screen location
        NSPoint screenPoint = [NSEvent mouseLocation];
        
        // Convert to view coordinates
        NSPoint viewPoint = [self convertScreenPointToView:screenPoint];
        
        if (!hasLastErasePoint) {
            lastErasePoint = viewPoint;
            hasLastErasePoint = YES;
        } else {
            // Calculate distance from last erase point
            CGFloat dx = viewPoint.x - lastErasePoint.x;
            CGFloat dy = viewPoint.y - lastErasePoint.y;
            CGFloat distance = sqrt(dx*dx + dy*dy);
            
            // Only process erase if we've moved enough distance (to avoid rapid erasures)
            if (distance > 10.0) {
                [self eraseStrokeAtPoint:viewPoint];
                lastErasePoint = viewPoint;
            }
        }
        return;
    }
    
    // If we have a current path, add a line to it
    if (currentPath) {
        // Get the screen location
        NSPoint screenPoint = [NSEvent mouseLocation];
        
        // Convert to view coordinates
        NSPoint viewPoint = [self convertScreenPointToView:screenPoint];
        
        // Apply smoothing to the point
        NSPoint smoothedPoint = [self smoothPoint:viewPoint];
        
        // Create a segment path for this movement with pressure-sensitive width
        NSBezierPath *segmentPath = [[NSBezierPath bezierPath] retain];
        [segmentPath setLineCapStyle:NSRoundLineCapStyle];
        [segmentPath setLineJoinStyle:NSRoundLineJoinStyle];
        
        // Use pressure if available to adjust line width for this segment
        float segmentWidth = lineWidth;
        if ([event pressure] > 0.0) {
            segmentWidth = lineWidth * ([event pressure] * 2.0);
            segmentWidth = MAX(0.5, segmentWidth);
            
            NSLog(@"DrawView: Using pressure: %f, width: %f", [event pressure], segmentWidth);
        }
        [segmentPath setLineWidth:segmentWidth];
        
        // Create segment from last point to current point
        [segmentPath moveToPoint:lastPoint];
        [segmentPath lineToPoint:smoothedPoint];
        
        // Add this segment to our collection
        [paths addObject:segmentPath];
        [pathColors addObject:[strokeColor copy]]; // Store current color with path
        [segmentPath release];
        
        // Update last point for next segment
        lastPoint = smoothedPoint;
        
        NSLog(@"DrawView: Adding point to path: %@", NSStringFromPoint(viewPoint));
        
        // Redraw
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseUp:(NSEvent *)event {
    // Check if this is a tablet event
    if ([event isTabletPointerEvent]) {
        NSLog(@"DrawView: mouseUp detected tablet event");
    } else {
        NSLog(@"DrawView: mouseUp detected regular mouse event, ignoring");
        return;
    }
    
    // If we're in eraser mode, reset tracking variables
    if (mErasing) {
        [self resetEraseTracking];
        return;
    }
    
    // Clear the smoothing buffer at the end of a stroke
    [self clearSmoothingBuffer];
    
    // Release the current path as we now use individual segments
    if (currentPath) {
        [currentPath release];
        currentPath = nil;
        [self setNeedsDisplay:YES];
        
        // Only clear the redo stack if we've actually drawn something new
        if ([paths count] > 0) {
            // Clear the redo stack since we've added new paths
            [undoPaths removeAllObjects];
            [undoPathColors removeAllObjects];
            [undoStrokeMarkers removeAllObjects];
            
            NSLog(@"DrawView: Cleared redo stack due to new stroke");
        }
        
        NSLog(@"DrawView: Finished stroke, total segments: %lu", (unsigned long)[paths count]);
    }
}

- (void)clear {
    [paths removeAllObjects];
    [pathColors removeAllObjects];
    [strokeMarkers removeAllObjects];
    [undoPaths removeAllObjects];
    [undoPathColors removeAllObjects];
    [undoStrokeMarkers removeAllObjects];
    if (currentPath) {
        [currentPath release];
        currentPath = nil;
    }
    [self setNeedsDisplay:YES];
    
    NSLog(@"DrawView: Cleared all paths");
}

// Make sure the view accepts first responder to get events
- (BOOL)acceptsFirstResponder {
    return YES;
}

// Handle key down events for keyboard shortcuts
- (void)keyDown:(NSEvent *)event {
    NSUInteger flags = [event modifierFlags];
    NSString *characters = [event charactersIgnoringModifiers];
    NSUInteger keyCode = [event keyCode];
    
    NSLog(@"DrawView: keyDown detected - keyCode: %lu, chars: '%@', flags: %lx", 
          (unsigned long)keyCode, characters, (unsigned long)flags);
    
    // Check for the special key combination: control+cmd+option+shift+C
    // Note: We can't detect delete and return as simultaneous key presses in standard key events
    // In OS X 10.9, we need to use the raw values instead of the constants
    BOOL isControlDown = (flags & (1 << 18)) != 0;   // NSControlKeyMask in 10.9
    BOOL isCommandDown = (flags & (1 << 20)) != 0;   // NSCommandKeyMask in 10.9
    BOOL isOptionDown = (flags & (1 << 19)) != 0;    // NSAlternateKeyMask in 10.9
    BOOL isShiftDown = (flags & (1 << 17)) != 0;     // NSShiftKeyMask in 10.9
    BOOL isC = ([characters isEqualToString:@"C"] || [characters isEqualToString:@"c"]);
    
    NSLog(@"DrawView: Key modifiers - Control: %d, Command: %d, Option: %d, Shift: %d, IsC: %d",
          isControlDown, isCommandDown, isOptionDown, isShiftDown, isC);
    
    if (isControlDown && isCommandDown && isOptionDown && isShiftDown && isC) {
        NSLog(@"DrawView: Special key combination detected, toggling color");
        [self toggleToNextColor];
    } else {
        // Otherwise, pass the event up the responder chain
        [super keyDown:event];
    }
}

// Check if there's something to undo
- (BOOL)canUndo {
    return ([paths count] > 0 && [strokeMarkers count] > 0);
}

// Check if there's something to redo
- (BOOL)canRedo {
    return ([undoPaths count] > 0 && [undoStrokeMarkers count] > 0);
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
        if (pointerType == 3 || pointerType == 2) { // Try both values to be safe
            mErasing = YES;
            NSLog(@"DrawView: Eraser end detected - enabling eraser mode (type=%d)", pointerType);
        } else {
            mErasing = NO;
            NSLog(@"DrawView: Pen tip detected - disabling eraser mode (type=%d)", pointerType);
        }
    }
}

// Erase the entire stroke that contains the given point
- (void)eraseStrokeAtPoint:(NSPoint)point {
    NSLog(@"DrawView: Attempting to erase stroke at point: %@", NSStringFromPoint(point));
    
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
        
        // Check if the point is within any path in this stroke
        for (NSInteger i = startIndex; i <= endIndex; i++) {
            NSBezierPath *path = [paths objectAtIndex:i];
            CGFloat pathWidth = [path lineWidth];
            
            // Check if point is near this path segment
            // We'll use a simple distance check for each path segment
            if ([self point:point isNearPath:path withinDistance:pathWidth * 2.0]) {
                NSLog(@"DrawView: Found stroke to erase at marker index: %ld", (long)markerIndex);
                
                // Store the stroke info for undo
                NSInteger segmentCount = endIndex - startIndex + 1;
                [undoStrokeMarkers addObject:[NSNumber numberWithInteger:segmentCount]];
                
                // Move each path segment in the stroke to the undo stack (in reverse to maintain order)
                for (NSInteger j = endIndex; j >= startIndex; j--) {
                    // Get the path and color at this index
                    NSBezierPath *pathToUndo = [[paths objectAtIndex:j] retain];
                    NSColor *colorToUndo = [[pathColors objectAtIndex:j] retain];
                    
                    // Add to undo stacks
                    [undoPaths addObject:pathToUndo];
                    [undoPathColors addObject:colorToUndo];
                    
                    // Release our retained copies
                    [pathToUndo release];
                    [colorToUndo release];
                }
                
                // Remove the segments from the current paths
                NSRange removeRange = NSMakeRange(startIndex, segmentCount);
                [paths removeObjectsInRange:removeRange];
                [pathColors removeObjectsInRange:removeRange];
                
                // Update markers after this one (they all need to be shifted)
                for (NSInteger j = markerIndex + 1; j < [strokeMarkers count]; j++) {
                    NSInteger oldIndex = [[strokeMarkers objectAtIndex:j] integerValue];
                    [strokeMarkers replaceObjectAtIndex:j 
                                            withObject:[NSNumber numberWithInteger:oldIndex - segmentCount]];
                }
                
                // Remove the marker for this stroke
                [strokeMarkers removeObjectAtIndex:markerIndex];
                
                // Redraw
                [self setNeedsDisplay:YES];
                
                NSLog(@"DrawView: Erased stroke with %ld segments", (long)segmentCount);
                return;
            }
        }
    }
    
    NSLog(@"DrawView: No stroke found at point to erase");
}

// Helper method to check if a point is near a path
- (BOOL)point:(NSPoint)point isNearPath:(NSBezierPath *)path withinDistance:(CGFloat)distance {
    // For a simple line segment, we can check distance from the line
    if ([path elementCount] == 2) { // Simple line with moveToPoint and lineToPoint
        NSPoint points[2];
        [path elementAtIndex:0 associatedPoints:&points[0]]; // moveToPoint
        [path elementAtIndex:1 associatedPoints:&points[1]]; // lineToPoint
        
        return [self distanceFromPoint:point toLineWithPoints:points] <= distance;
    }
    
    // For more complex paths, we'll use a simpler check
    NSRect bounds = [path bounds];
    NSRect extendedBounds = NSInsetRect(bounds, -distance, -distance);
    return NSPointInRect(point, extendedBounds);
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

// Undo the last complete stroke
- (void)undo {
    // Check if there are any paths to undo
    if ([self canUndo]) {
        // Get the marker for the last stroke
        NSInteger markerIndex = [strokeMarkers count] - 1;
        NSInteger startIndex = [[strokeMarkers objectAtIndex:markerIndex] integerValue];
        NSInteger endIndex = [paths count] - 1;
        NSInteger segmentCount = endIndex - startIndex + 1;
        
        // Store the start index in the undo markers stack
        [undoStrokeMarkers addObject:[NSNumber numberWithInteger:segmentCount]];
        
        // Move each path segment in the stroke to the undo stack (in reverse to maintain order)
        for (NSInteger i = endIndex; i >= startIndex; i--) {
            // Get the path and color at this index
            NSBezierPath *pathToUndo = [[paths objectAtIndex:i] retain];
            NSColor *colorToUndo = [[pathColors objectAtIndex:i] retain];
            
            // Add to undo stacks
            [undoPaths addObject:pathToUndo];
            [undoPathColors addObject:colorToUndo];
            
            // Release our retained copies
            [pathToUndo release];
            [colorToUndo release];
        }
        
        // Remove the segments from the current paths
        NSRange removeRange = NSMakeRange(startIndex, segmentCount);
        [paths removeObjectsInRange:removeRange];
        [pathColors removeObjectsInRange:removeRange];
        
        // Remove the marker for this stroke
        [strokeMarkers removeObjectAtIndex:markerIndex];
        
        // Redraw
        [self setNeedsDisplay:YES];
        
        NSLog(@"DrawView: Undo performed, removed stroke with %ld segments", (long)segmentCount);
    } else {
        NSLog(@"DrawView: Nothing to undo");
    }
}

// Redo the last undone stroke
- (void)redo {
    NSLog(@"DrawView: Redo requested. undoPaths count: %lu, undoStrokeMarkers count: %lu", 
          (unsigned long)[undoPaths count], (unsigned long)[undoStrokeMarkers count]);
    
    // Check if there are any paths to redo
    if ([self canRedo]) {
        // Get the segment count for the stroke to redo
        NSInteger segmentCount = [[undoStrokeMarkers lastObject] integerValue];
        
        NSLog(@"DrawView: Attempting to redo stroke with %ld segments", (long)segmentCount);
        
        // Check if we have enough segments in the undo stack
        if ([undoPaths count] >= segmentCount) {
            // Add a marker for where this stroke starts in the paths array
            [strokeMarkers addObject:[NSNumber numberWithInteger:[paths count]]];
            
            // Move the paths and colors back (in reverse because we stored them in reverse)
            for (NSInteger i = 0; i < segmentCount; i++) {
                NSInteger undoIndex = [undoPaths count] - 1;
                
                // Get the path and color to redo
                NSBezierPath *pathToRedo = [[undoPaths objectAtIndex:undoIndex] retain];
                NSColor *colorToRedo = [[undoPathColors objectAtIndex:undoIndex] retain];
                
                // Add to active paths
                [paths addObject:pathToRedo];
                [pathColors addObject:colorToRedo];
                
                // Remove from undo stacks
                [undoPaths removeObjectAtIndex:undoIndex];
                [undoPathColors removeObjectAtIndex:undoIndex];
                
                // Release our retained copies
                [pathToRedo release];
                [colorToRedo release];
            }
            
            // Remove the marker for this stroke
            [undoStrokeMarkers removeLastObject];
            
            // Redraw
            [self setNeedsDisplay:YES];
            
            NSLog(@"DrawView: Redo performed, restored stroke with %ld segments", (long)segmentCount);
        } else {
            NSLog(@"DrawView: Error - undo stack count doesn't match marker. Need %ld but have %lu", 
                  (long)segmentCount, (unsigned long)[undoPaths count]);
        }
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

// Reset the eraser tracking variables
- (void)resetEraseTracking {
    hasLastErasePoint = NO;
    lastErasePoint = NSZeroPoint;
    NSLog(@"DrawView: Reset erase tracking");
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
        self.strokeColor = color;
        
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
    
    NSLog(@"DrawView: Set preset color at index %ld to %@", (long)index, color);
}

- (void)toggleToNextColor {
    // Increment the color index
    currentColorIndex = (currentColorIndex + 1) % [presetColors count];
    
    // Set the new color
    self.strokeColor = [presetColors objectAtIndex:currentColorIndex];
    
    // Also update the color well in the control panel if there is one
    NSArray *windows = [NSApp windows];
    for (NSWindow *window in windows) {
        if ([[window className] isEqualToString:@"ControlPanel"]) {
            NSColorWell *colorWell = [window valueForKey:@"colorWell"];
            if (colorWell) {
                [colorWell setColor:self.strokeColor];
            }
            break;
        }
    }
    
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
    [strokeColor release];
    [presetColors release];
    [pointBuffer release];
    [super dealloc];
}

- (NSPoint)smoothPoint:(NSPoint)point {
    // If smoothing is disabled, return the original point
    if (!self.enableSmoothing || self.smoothingLevel < 1) {
        return point;
    }
    
    // Add the new point to the buffer
    [pointBuffer addObject:[NSValue valueWithPoint:point]];
    
    // Determine how many points to use for smoothing
    NSInteger bufferSize = smoothingLevel;
    
    // Keep buffer from growing too large by removing oldest points
    while ([pointBuffer count] > bufferSize) {
        [pointBuffer removeObjectAtIndex:0];
    }
    
    // If we don't have enough points yet, just return the current one
    if ([pointBuffer count] < 2) {
        return point;
    }
    
    // Calculate a weighted average of the points
    NSPoint smoothedPoint = NSZeroPoint;
    CGFloat totalWeight = 0.0;
    
    // Use a basic weights array with more emphasis on recent points
    for (NSInteger i = 0; i < [pointBuffer count]; i++) {
        NSPoint pt = [[pointBuffer objectAtIndex:i] pointValue];
        CGFloat weight = (i + 1.0); // Linear weighting: newer points have higher weight
        
        smoothedPoint.x += pt.x * weight;
        smoothedPoint.y += pt.y * weight;
        totalWeight += weight;
    }
    
    // Normalize the smoothed point
    if (totalWeight > 0) {
        smoothedPoint.x /= totalWeight;
        smoothedPoint.y /= totalWeight;
    }
    
    return smoothedPoint;
}

- (void)clearSmoothingBuffer {
    [pointBuffer removeAllObjects];
}

@end