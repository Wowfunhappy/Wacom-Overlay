#import "DrawView.h"
#import "TabletEvents.h"

@implementation DrawView

@synthesize strokeColor;
@synthesize lineWidth;

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
        self.strokeColor = [NSColor redColor];
        self.lineWidth = 2.0;
        
        // Make the view transparent to allow click-through
        [self setWantsLayer:YES];
        
        // Ensure we can receive all events
        [[self window] setAcceptsMouseMovedEvents:YES];
        
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
    
    if (type == 1) { // NSLeftMouseDown
        [self mouseDown:event];
    }
    else if (type == 6) { // NSLeftMouseDragged
        [self mouseDragged:event];
    }
    else if (type == 2) { // NSLeftMouseUp
        [self mouseUp:event];
    }
}

- (NSPoint)convertScreenPointToView:(NSPoint)screenPoint {
    // Convert screen coordinates to window coordinates
    NSPoint windowPoint = [[self window] convertScreenToBase:screenPoint];
    
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
    
    // Start a new path
    currentPath = [[NSBezierPath bezierPath] retain];
    [currentPath setLineWidth:lineWidth];
    [currentPath setLineCapStyle:NSRoundLineCapStyle];
    [currentPath setLineJoinStyle:NSRoundLineJoinStyle];
    
    // Get the screen location
    NSPoint screenPoint = [NSEvent mouseLocation];
    
    // Convert to view coordinates
    NSPoint viewPoint = [self convertScreenPointToView:screenPoint];
    
    // Start the path
    [currentPath moveToPoint:viewPoint];
    lastPoint = viewPoint;
    
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
    
    // If we have a current path, add a line to it
    if (currentPath) {
        // Get the screen location
        NSPoint screenPoint = [NSEvent mouseLocation];
        
        // Convert to view coordinates
        NSPoint viewPoint = [self convertScreenPointToView:screenPoint];
        
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
        [segmentPath lineToPoint:viewPoint];
        
        // Add this segment to our collection
        [paths addObject:segmentPath];
        [pathColors addObject:[strokeColor copy]]; // Store current color with path
        [segmentPath release];
        
        // Update last point for next segment
        lastPoint = viewPoint;
        
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

// Check if there's something to undo
- (BOOL)canUndo {
    return ([paths count] > 0 && [strokeMarkers count] > 0);
}

// Check if there's something to redo
- (BOOL)canRedo {
    return ([undoPaths count] > 0 && [undoStrokeMarkers count] > 0);
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

// Clean up memory
- (void)dealloc {
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
    [super dealloc];
}

@end