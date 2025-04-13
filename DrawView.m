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
    
    // Set the stroke color for all paths
    [strokeColor set];
    
    // Draw all saved paths
    NSEnumerator *pathEnumerator = [paths objectEnumerator];
    NSBezierPath *path;
    
    while ((path = [pathEnumerator nextObject])) {
        [path stroke];
    }
    
    // Draw current path if it exists
    if (currentPath) {
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
        
        // Use pressure if available to adjust line width
        if ([event pressure] > 0.0) {
            float pressureWidth = lineWidth * ([event pressure] * 2.0);
            [currentPath setLineWidth:MAX(0.5, pressureWidth)];
            
            NSLog(@"DrawView: Using pressure: %f, width: %f", [event pressure], pressureWidth);
        }
        
        // Add point to the path
        [currentPath lineToPoint:viewPoint];
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
    
    // Finish the current path and add it to our list of paths
    if (currentPath) {
        [paths addObject:currentPath];
        [currentPath release];
        currentPath = nil;
        [self setNeedsDisplay:YES];
        
        NSLog(@"DrawView: Finished path, total paths: %lu", (unsigned long)[paths count]);
    }
}

- (void)clear {
    [paths removeAllObjects];
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
    if (currentPath) {
        [currentPath release];
    }
    [strokeColor release];
    [super dealloc];
}

@end