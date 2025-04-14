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
        
        // Load colors from NSUserDefaults or use defaults if none are stored
        [self loadColorsFromUserDefaults];
        
        self.lineWidth = 2.0;
        mErasing = NO;
        hasLastErasePoint = NO;
        lastErasePoint = NSZeroPoint;
        
        // Initialize smoothing with maximum level
        pointBuffer = [[NSMutableArray alloc] init];
        self.smoothingLevel = 20;  // Maximum smoothing level for neatest handwriting
        self.enableSmoothing = YES;  // Always enabled
        
        // Initialize stroke selection and dragging variables
        selectedStrokeIndex = -1;
        isStrokeSelected = NO;
        isDraggingStroke = NO;
        dragStartPoint = NSZeroPoint;
        relatedStrokeIndices = [[NSMutableArray alloc] init];
        
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
        
        // Check if this path belongs to the selected stroke or related strokes
        if (isStrokeSelected) {
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
        }
        
        [color set];
        [path stroke];
    }
    
    // Draw current path if it exists
    if (currentPath) {
        [strokeColor set];
        [currentPath stroke];
    }
    
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
        
        // If we're in eraser mode, erase stroke at this point instead of drawing
        if (mErasing) {
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
    } else {
        // For regular mouse events, use the event's locationInWindow coordinates
        viewPoint = [self convertPoint:[event locationInWindow] fromView:nil];
        
        // Attempt to find a stroke at this point
        BOOL foundStroke = NO;
        
        // Only attempt to find a stroke if we have strokes to check
        if ([paths count] > 0 && [strokeMarkers count] > 0) {
            for (NSInteger markerIndex = [strokeMarkers count] - 1; markerIndex >= 0; markerIndex--) {
                // Get the range of paths for this stroke
                NSInteger startIndex = [[strokeMarkers objectAtIndex:markerIndex] integerValue];
                NSInteger endIndex;
                
                if (markerIndex < [strokeMarkers count] - 1) {
                    endIndex = [[strokeMarkers objectAtIndex:markerIndex + 1] integerValue] - 1;
                } else {
                    endIndex = [paths count] - 1;
                }
                
                // Check each path segment in the stroke
                for (NSInteger i = startIndex; i <= endIndex; i++) {
                    NSBezierPath *path = [paths objectAtIndex:i];
                    NSRect bounds = [path bounds];
                    
                    // Extend the bounds by a reasonable amount for selection
                    // Adjust this value to control selection sensitivity (smaller = more precise)
                    NSRect extendedBounds = NSInsetRect(bounds, -3, -3);
                    
                    if (NSPointInRect(viewPoint, extendedBounds)) {
                        // Set this as the selected stroke
                        selectedStrokeIndex = markerIndex;
                        isStrokeSelected = YES;
                        isDraggingStroke = YES;
                        dragStartPoint = viewPoint;
                        
                        // Find all related strokes (same color and intersecting)
                        [self findRelatedStrokes:markerIndex];
                        
                        foundStroke = YES;
                        break;
                    }
                }
                
                if (foundStroke) {
                    break;
                }
            }
        }
        
        // If no stroke was found at this point, clear any existing selection
        if (!foundStroke) {
            if (isStrokeSelected) {
                isStrokeSelected = NO;
                selectedStrokeIndex = -1;
                isDraggingStroke = NO;
                [relatedStrokeIndices removeAllObjects];
            }
        }
    }
    
    [self setNeedsDisplay:YES];
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
                if (distance > 10.0) {
                    [self eraseStrokeAtPoint:viewPoint];
                    lastErasePoint = viewPoint;
                }
            }
            return;
        }
        
        // If we have a current path, add a line to it
        if (currentPath) {
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
        }
    } else {
        // For regular mouse events, use the event's locationInWindow converted to view coordinates
        viewPoint = [self convertPoint:[event locationInWindow] fromView:nil];
        NSLog(@"DrawView: mouseDragged detected regular mouse event at point: %@", NSStringFromPoint(viewPoint));
        
        // Handle dragging a selected stroke
        if (isDraggingStroke && isStrokeSelected && selectedStrokeIndex >= 0) {
            // Calculate the movement offset
            CGFloat dx = viewPoint.x - dragStartPoint.x;
            CGFloat dy = viewPoint.y - dragStartPoint.y;
            
            // Apply the offset to the stroke
            [self moveSelectedStroke:NSMakePoint(dx, dy)];
            
            // Update the drag start point for the next mouse dragged event
            dragStartPoint = viewPoint;
            
            NSLog(@"DrawView: Dragged stroke by offset (%f, %f)", dx, dy);
        }
    }
    
    // Redraw
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
        
        // Clear the smoothing buffer at the end of a stroke
        [self clearSmoothingBuffer];
        
        // Release the current path as we now use individual segments
        if (currentPath) {
            [currentPath release];
            currentPath = nil;
            
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
    } else {
        NSPoint viewPoint = [self convertPoint:[event locationInWindow] fromView:nil];
        NSLog(@"DrawView: mouseUp detected regular mouse event at point: %@", NSStringFromPoint(viewPoint));
        
        // End any stroke dragging
        if (isDraggingStroke) {
            isDraggingStroke = NO;
            NSLog(@"DrawView: Finished dragging stroke");
        }
    }
    
    [self setNeedsDisplay:YES];
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

// Find the marker index of the stroke that contains the given point
- (NSInteger)findStrokeAtPoint:(NSPoint)point {
    NSLog(@"DrawView: Attempting to find stroke at point: %@", NSStringFromPoint(point));
    
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
            
            // Use a much larger detection threshold for now (debugging)
            CGFloat detectionThreshold = pathWidth * 10.0;
            
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
}

// Erase the entire stroke that contains the given point
- (void)eraseStrokeAtPoint:(NSPoint)point {
    NSLog(@"DrawView: Attempting to erase stroke at point: %@", NSStringFromPoint(point));
    
    // Find which stroke the point is in
    NSInteger markerIndex = [self findStrokeAtPoint:point];
    
    if (markerIndex >= 0) {
        NSInteger startIndex = [[strokeMarkers objectAtIndex:markerIndex] integerValue];
        NSInteger endIndex;
        
        // Determine the end index of this stroke
        if (markerIndex < [strokeMarkers count] - 1) {
            endIndex = [[strokeMarkers objectAtIndex:markerIndex + 1] integerValue] - 1;
        } else {
            endIndex = [paths count] - 1;
        }
        
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
    } else {
        NSLog(@"DrawView: No stroke found at point to erase");
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
    
    // Fallback to the extended bounds check which we already passed
    return YES;
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

// Override hit testing to allow click-through when not over a stroke
- (NSView *)hitTest:(NSPoint)point {
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
    
    // Save the updated colors to user defaults
    [self saveColorsToUserDefaults];
    
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
    [strokeColor release];
    [presetColors release];
    [pointBuffer release];
    [relatedStrokeIndices release];
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

// Removed debug visualization method

// Find all strokes that are related to the given stroke
// Related strokes are those with the same color and that intersect
- (void)findRelatedStrokes:(NSInteger)strokeIndex {
    // Clear any existing related strokes
    [relatedStrokeIndices removeAllObjects];
    
    // Add the selected stroke itself
    [relatedStrokeIndices addObject:[NSNumber numberWithInteger:strokeIndex]];
    
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
        return;
    }
    
    // Check all other strokes for color and intersection
    for (NSInteger i = 0; i < [strokeMarkers count]; i++) {
        // Skip the stroke itself
        if (i == strokeIndex) {
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
            [relatedStrokeIndices addObject:[NSNumber numberWithInteger:i]];
        }
    }
}

// Check if two strokes intersect
- (BOOL)doStrokesIntersect:(NSInteger)strokeIndex1 strokeIndex2:(NSInteger)strokeIndex2 {
    // Get bounds of first stroke
    NSInteger startIndex1 = [[strokeMarkers objectAtIndex:strokeIndex1] integerValue];
    NSInteger endIndex1;
    
    if (strokeIndex1 < [strokeMarkers count] - 1) {
        endIndex1 = [[strokeMarkers objectAtIndex:strokeIndex1 + 1] integerValue] - 1;
    } else {
        endIndex1 = [paths count] - 1;
    }
    
    // Get bounds of second stroke
    NSInteger startIndex2 = [[strokeMarkers objectAtIndex:strokeIndex2] integerValue];
    NSInteger endIndex2;
    
    if (strokeIndex2 < [strokeMarkers count] - 1) {
        endIndex2 = [[strokeMarkers objectAtIndex:strokeIndex2 + 1] integerValue] - 1;
    } else {
        endIndex2 = [paths count] - 1;
    }
    
    // Calculate overall bounds for each stroke
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
    
    // Add a small margin to the bounds for better intersection detection
    bounds1 = NSInsetRect(bounds1, -5, -5);
    bounds2 = NSInsetRect(bounds2, -5, -5);
    
    // Check if the bounds intersect
    return NSIntersectsRect(bounds1, bounds2);
}

#pragma mark - Color Persistence

- (void)loadColorsFromUserDefaults {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSData *colorData1 = [defaults objectForKey:@"PresetColor1"];
    NSData *colorData2 = [defaults objectForKey:@"PresetColor2"];
    NSData *colorData3 = [defaults objectForKey:@"PresetColor3"];
    NSInteger savedColorIndex = [defaults integerForKey:@"CurrentColorIndex"];
    
    // Default colors in case user defaults are not available
    NSColor *color1 = [NSColor redColor];
    NSColor *color2 = [NSColor blueColor];
    NSColor *color3 = [NSColor greenColor];
    
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
    
    // Initialize preset colors with loaded values
    presetColors = [[NSArray alloc] initWithObjects:color1, color2, color3, nil];
    
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
    if ([presetColors count] >= 3) {
        NSData *colorData1 = [NSArchiver archivedDataWithRootObject:[presetColors objectAtIndex:0]];
        NSData *colorData2 = [NSArchiver archivedDataWithRootObject:[presetColors objectAtIndex:1]];
        NSData *colorData3 = [NSArchiver archivedDataWithRootObject:[presetColors objectAtIndex:2]];
        
        // Save to user defaults
        [defaults setObject:colorData1 forKey:@"PresetColor1"];
        [defaults setObject:colorData2 forKey:@"PresetColor2"];
        [defaults setObject:colorData3 forKey:@"PresetColor3"];
        [defaults setInteger:currentColorIndex forKey:@"CurrentColorIndex"];
        
        // Synchronize to ensure the data is saved
        [defaults synchronize];
        
        NSLog(@"DrawView: Saved colors to user defaults");
    }
}

@end