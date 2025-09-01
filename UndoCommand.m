#import "UndoCommand.h"
#import "DrawView.h"

// Base implementation
@implementation UndoCommand
@synthesize drawView;

- (id)initWithDrawView:(DrawView *)view {
    self = [super init];
    if (self) {
        drawView = view;
    }
    return self;
}

- (void)execute {
    // Subclasses implement
}

- (void)undo {
    // Subclasses implement
}

- (NSString *)description {
    return @"UndoCommand";
}

- (void)dealloc {
    [super dealloc];
}
@end

// Add Stroke Command
@implementation AddStrokeCommand

- (id)initWithDrawView:(DrawView *)view paths:(NSArray *)paths colors:(NSArray *)colors markerIndex:(NSInteger)marker {
    self = [super initWithDrawView:view];
    if (self) {
        // Make deep copies of the paths so they won't be affected by future transformations
        strokePaths = [[NSMutableArray alloc] initWithCapacity:[paths count]];
        for (NSBezierPath *path in paths) {
            NSBezierPath *pathCopy = [path copy];
            [strokePaths addObject:pathCopy];
            [pathCopy release];
        }
        
        // Colors can be shallow copied as they're immutable
        strokeColors = [[NSMutableArray alloc] initWithArray:colors];
        markerIndex = marker;
        segmentCount = [paths count];
    }
    return self;
}

- (void)execute {
    // Re-add the stroke to the drawing
    NSMutableArray *paths = [drawView valueForKey:@"paths"];
    NSMutableArray *pathColors = [drawView valueForKey:@"pathColors"];
    NSMutableArray *strokeMarkers = [drawView valueForKey:@"strokeMarkers"];
    
    // Add marker
    [strokeMarkers addObject:[NSNumber numberWithInteger:[paths count]]];
    
    // Add copies of all segments to avoid them being modified by future operations
    for (NSInteger i = 0; i < [strokePaths count]; i++) {
        NSBezierPath *pathCopy = [[strokePaths objectAtIndex:i] copy];
        [paths addObject:pathCopy];
        [pathCopy release];
        [pathColors addObject:[strokeColors objectAtIndex:i]];
    }
    
    [drawView invalidateStrokeCache];
    [drawView setNeedsDisplay:YES];
}

- (void)undo {
    // Remove the stroke from the drawing
    NSMutableArray *paths = [drawView valueForKey:@"paths"];
    NSMutableArray *pathColors = [drawView valueForKey:@"pathColors"];
    NSMutableArray *strokeMarkers = [drawView valueForKey:@"strokeMarkers"];
    
    if ([strokeMarkers count] > 0) {
        NSInteger lastMarkerIndex = [strokeMarkers count] - 1;
        NSInteger startIndex = [[strokeMarkers objectAtIndex:lastMarkerIndex] integerValue];
        NSInteger endIndex = [paths count] - 1;
        NSInteger count = endIndex - startIndex + 1;
        
        if (count > 0 && count <= [paths count]) {
            NSRange removeRange = NSMakeRange(startIndex, count);
            [paths removeObjectsInRange:removeRange];
            [pathColors removeObjectsInRange:removeRange];
            [strokeMarkers removeObjectAtIndex:lastMarkerIndex];
        }
    }
    
    [drawView invalidateStrokeCache];
    [drawView setNeedsDisplay:YES];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"Add stroke with %ld segments", (long)segmentCount];
}

- (void)dealloc {
    [strokePaths release];
    [strokeColors release];
    [super dealloc];
}
@end

// Erase Stroke Command
@implementation EraseStrokeCommand

- (id)initWithDrawView:(DrawView *)view strokeMarkerIndex:(NSInteger)index {
    self = [super initWithDrawView:view];
    if (self) {
        markerIndex = index;
        erasedPaths = [[NSMutableArray alloc] init];
        erasedColors = [[NSMutableArray alloc] init];
        
        // Save the stroke data before erasing
        NSMutableArray *paths = [view valueForKey:@"paths"];
        NSMutableArray *pathColors = [view valueForKey:@"pathColors"];
        NSMutableArray *strokeMarkers = [view valueForKey:@"strokeMarkers"];
        
        if (index >= 0 && index < [strokeMarkers count]) {
            originalStartIndex = [[strokeMarkers objectAtIndex:index] integerValue];
            NSInteger endIndex;
            
            if (index < [strokeMarkers count] - 1) {
                endIndex = [[strokeMarkers objectAtIndex:index + 1] integerValue] - 1;
            } else {
                endIndex = [paths count] - 1;
            }
            
            // Save the paths and colors
            for (NSInteger i = originalStartIndex; i <= endIndex; i++) {
                [erasedPaths addObject:[[paths objectAtIndex:i] copy]];
                [erasedColors addObject:[[pathColors objectAtIndex:i] copy]];
            }
        }
    }
    return self;
}

- (void)execute {
    // Erase the stroke
    NSMutableArray *paths = [drawView valueForKey:@"paths"];
    NSMutableArray *pathColors = [drawView valueForKey:@"pathColors"];
    NSMutableArray *strokeMarkers = [drawView valueForKey:@"strokeMarkers"];
    
    // Find the current marker index for this stroke
    NSInteger currentMarkerIndex = -1;
    for (NSInteger i = 0; i < [strokeMarkers count]; i++) {
        if ([[strokeMarkers objectAtIndex:i] integerValue] == originalStartIndex) {
            currentMarkerIndex = i;
            break;
        }
    }
    
    if (currentMarkerIndex >= 0 && currentMarkerIndex < [strokeMarkers count]) {
        NSInteger startIndex = [[strokeMarkers objectAtIndex:currentMarkerIndex] integerValue];
        NSInteger endIndex;
        
        if (currentMarkerIndex < [strokeMarkers count] - 1) {
            endIndex = [[strokeMarkers objectAtIndex:currentMarkerIndex + 1] integerValue] - 1;
        } else {
            endIndex = [paths count] - 1;
        }
        
        NSInteger segmentCount = endIndex - startIndex + 1;
        
        // Remove the segments
        NSRange removeRange = NSMakeRange(startIndex, segmentCount);
        [paths removeObjectsInRange:removeRange];
        [pathColors removeObjectsInRange:removeRange];
        
        // Update markers after this one
        for (NSInteger j = currentMarkerIndex + 1; j < [strokeMarkers count]; j++) {
            NSInteger oldIndex = [[strokeMarkers objectAtIndex:j] integerValue];
            [strokeMarkers replaceObjectAtIndex:j 
                                    withObject:[NSNumber numberWithInteger:oldIndex - segmentCount]];
        }
        
        // Remove the marker
        [strokeMarkers removeObjectAtIndex:currentMarkerIndex];
    }
    
    [drawView invalidateStrokeCache];
    [drawView setNeedsDisplay:YES];
}

- (void)undo {
    // Restore the erased stroke
    NSMutableArray *paths = [drawView valueForKey:@"paths"];
    NSMutableArray *pathColors = [drawView valueForKey:@"pathColors"];
    NSMutableArray *strokeMarkers = [drawView valueForKey:@"strokeMarkers"];
    
    // Find insertion point
    NSInteger insertIndex = originalStartIndex;
    if (insertIndex > [paths count]) {
        insertIndex = [paths count];
    }
    
    // Update markers that will be after this stroke
    for (NSInteger i = 0; i < [strokeMarkers count]; i++) {
        NSInteger markerValue = [[strokeMarkers objectAtIndex:i] integerValue];
        if (markerValue >= insertIndex) {
            [strokeMarkers replaceObjectAtIndex:i 
                                    withObject:[NSNumber numberWithInteger:markerValue + [erasedPaths count]]];
        }
    }
    
    // Add the marker for this stroke
    NSInteger insertMarkerIndex = 0;
    for (NSInteger i = 0; i < [strokeMarkers count]; i++) {
        if ([[strokeMarkers objectAtIndex:i] integerValue] > originalStartIndex) {
            break;
        }
        insertMarkerIndex = i + 1;
    }
    [strokeMarkers insertObject:[NSNumber numberWithInteger:originalStartIndex] atIndex:insertMarkerIndex];
    
    // Insert all the paths and colors
    for (NSInteger i = 0; i < [erasedPaths count]; i++) {
        [paths insertObject:[erasedPaths objectAtIndex:i] atIndex:insertIndex + i];
        [pathColors insertObject:[erasedColors objectAtIndex:i] atIndex:insertIndex + i];
    }
    
    [drawView invalidateStrokeCache];
    [drawView setNeedsDisplay:YES];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"Erase stroke with %lu segments", (unsigned long)[erasedPaths count]];
}

- (void)dealloc {
    [erasedPaths release];
    [erasedColors release];
    [super dealloc];
}
@end

// Add Text Command
@implementation AddTextCommand

- (id)initWithDrawView:(DrawView *)view textField:(NSTextField *)field color:(NSColor *)color {
    self = [super initWithDrawView:view];
    if (self) {
        textField = [field retain];
        textColor = [color retain];
        textIndex = -1;
    }
    return self;
}

- (void)execute {
    NSMutableArray *textFields = [drawView valueForKey:@"textFields"];
    NSMutableArray *textFieldColors = [drawView valueForKey:@"textFieldColors"];
    
    [drawView addSubview:textField];
    [textFields addObject:textField];
    [textFieldColors addObject:textColor];
    textIndex = [textFields count] - 1;
    
    [drawView setNeedsDisplay:YES];
}

- (void)undo {
    NSMutableArray *textFields = [drawView valueForKey:@"textFields"];
    NSMutableArray *textFieldColors = [drawView valueForKey:@"textFieldColors"];
    
    if (textIndex >= 0 && textIndex < [textFields count]) {
        NSTextField *field = [textFields objectAtIndex:textIndex];
        [field removeFromSuperview];
        [textFields removeObjectAtIndex:textIndex];
        [textFieldColors removeObjectAtIndex:textIndex];
    }
    
    [drawView setNeedsDisplay:YES];
}

- (NSString *)description {
    return @"Add text field";
}

- (void)dealloc {
    [textField release];
    [textColor release];
    [super dealloc];
}
@end

// Erase Text Command
@implementation EraseTextCommand

- (id)initWithDrawView:(DrawView *)view textFieldIndex:(NSInteger)index {
    self = [super initWithDrawView:view];
    if (self) {
        NSMutableArray *textFields = [view valueForKey:@"textFields"];
        NSMutableArray *textFieldColors = [view valueForKey:@"textFieldColors"];
        
        if (index >= 0 && index < [textFields count]) {
            textField = [[textFields objectAtIndex:index] retain];
            textColor = [[textFieldColors objectAtIndex:index] retain];
            originalIndex = index;
            originalFrame = [textField frame];
        }
    }
    return self;
}

- (void)execute {
    // Only execute if we have a valid text field
    if (!textField) {
        return;
    }
    
    NSMutableArray *textFields = [drawView valueForKey:@"textFields"];
    NSMutableArray *textFieldColors = [drawView valueForKey:@"textFieldColors"];
    
    // Find the text field in the array
    NSInteger index = [textFields indexOfObject:textField];
    if (index != NSNotFound) {
        [textField removeFromSuperview];
        [textFields removeObjectAtIndex:index];
        [textFieldColors removeObjectAtIndex:index];
    }
    
    [drawView setNeedsDisplay:YES];
}

- (void)undo {
    // Only undo if we have a valid text field
    if (!textField || !textColor) {
        return;
    }
    
    NSMutableArray *textFields = [drawView valueForKey:@"textFields"];
    NSMutableArray *textFieldColors = [drawView valueForKey:@"textFieldColors"];
    
    // Restore the text field at the correct position
    if (originalIndex <= [textFields count]) {
        [textField setFrame:originalFrame];
        [drawView addSubview:textField];
        
        if (originalIndex < [textFields count]) {
            [textFields insertObject:textField atIndex:originalIndex];
            [textFieldColors insertObject:textColor atIndex:originalIndex];
        } else {
            [textFields addObject:textField];
            [textFieldColors addObject:textColor];
        }
    }
    
    [drawView setNeedsDisplay:YES];
}

- (NSString *)description {
    return @"Erase text field";
}

- (void)dealloc {
    [textField release];
    [textColor release];
    [super dealloc];
}
@end

// Edit Text Command
@implementation EditTextCommand

- (id)initWithDrawView:(DrawView *)view textField:(NSTextField *)field oldText:(NSString *)old newText:(NSString *)new {
    self = [super initWithDrawView:view];
    if (self) {
        textField = [field retain];
        oldText = [old copy];
        newText = [new copy];
        oldFont = [[field font] retain];
        oldColor = [[field textColor] retain];
    }
    return self;
}

- (void)execute {
    [textField setStringValue:newText];
    if (newFont) [textField setFont:newFont];
    if (newColor) [textField setTextColor:newColor];
    [drawView setNeedsDisplay:YES];
}

- (void)undo {
    [textField setStringValue:oldText];
    if (oldFont) [textField setFont:oldFont];
    if (oldColor) [textField setTextColor:oldColor];
    [drawView setNeedsDisplay:YES];
}

- (NSString *)description {
    return @"Edit text";
}

- (void)dealloc {
    [textField release];
    [oldText release];
    [newText release];
    [oldFont release];
    [newFont release];
    [oldColor release];
    [newColor release];
    [super dealloc];
}
@end

// Move Stroke Command
@implementation MoveStrokeCommand

- (id)initWithDrawView:(DrawView *)view strokeIndices:(NSArray *)indices offset:(NSPoint)off originalPaths:(NSArray *)origPaths {
    self = [super initWithDrawView:view];
    if (self) {
        strokeIndices = [indices retain];
        offset = off;
        originalPaths = [[NSMutableArray alloc] initWithArray:origPaths];
        movedPaths = [[NSMutableArray alloc] init];
        
        // Store the current (moved) state of the paths
        NSMutableArray *paths = [drawView valueForKey:@"paths"];
        NSMutableArray *strokeMarkers = [drawView valueForKey:@"strokeMarkers"];
        
        for (NSDictionary *strokeInfo in origPaths) {
            NSNumber *strokeIndexNum = [strokeInfo objectForKey:@"index"];
            NSInteger sIndex = [strokeIndexNum integerValue];
            
            if (sIndex >= 0 && sIndex < [strokeMarkers count]) {
                NSInteger startIndex = [[strokeMarkers objectAtIndex:sIndex] integerValue];
                NSInteger endIndex;
                if (sIndex < [strokeMarkers count] - 1) {
                    endIndex = [[strokeMarkers objectAtIndex:sIndex + 1] integerValue] - 1;
                } else {
                    endIndex = [paths count] - 1;
                }
                
                // Store copies of current (moved) paths
                NSMutableArray *strokePaths = [NSMutableArray array];
                for (NSInteger i = startIndex; i <= endIndex; i++) {
                    NSBezierPath *pathCopy = [[paths objectAtIndex:i] copy];
                    [strokePaths addObject:pathCopy];
                    [pathCopy release];
                }
                
                [movedPaths addObject:@{@"index": strokeIndexNum, @"paths": strokePaths}];
            }
        }
    }
    return self;
}

- (void)execute {
    // Restore the moved state (for redo)
    NSMutableArray *paths = [drawView valueForKey:@"paths"];
    NSMutableArray *strokeMarkers = [drawView valueForKey:@"strokeMarkers"];
    
    for (NSDictionary *strokeInfo in movedPaths) {
        NSNumber *strokeIndexNum = [strokeInfo objectForKey:@"index"];
        NSInteger sIndex = [strokeIndexNum integerValue];
        NSArray *strokePaths = [strokeInfo objectForKey:@"paths"];
        
        if (sIndex >= 0 && sIndex < [strokeMarkers count]) {
            NSInteger startIndex = [[strokeMarkers objectAtIndex:sIndex] integerValue];
            NSInteger endIndex;
            if (sIndex < [strokeMarkers count] - 1) {
                endIndex = [[strokeMarkers objectAtIndex:sIndex + 1] integerValue] - 1;
            } else {
                endIndex = [paths count] - 1;
            }
            
            // Replace paths with the moved versions
            NSInteger pathIdx = 0;
            for (NSInteger i = startIndex; i <= endIndex && pathIdx < [strokePaths count]; i++, pathIdx++) {
                NSBezierPath *movedPath = [[strokePaths objectAtIndex:pathIdx] copy];
                [paths replaceObjectAtIndex:i withObject:movedPath];
                [movedPath release];
            }
        }
    }
    
    [drawView invalidateStrokeCache];
    [drawView setNeedsDisplay:YES];
}

- (void)undo {
    // Restore the original state
    NSMutableArray *paths = [drawView valueForKey:@"paths"];
    NSMutableArray *strokeMarkers = [drawView valueForKey:@"strokeMarkers"];
    
    for (NSDictionary *strokeInfo in originalPaths) {
        NSNumber *strokeIndexNum = [strokeInfo objectForKey:@"index"];
        NSInteger sIndex = [strokeIndexNum integerValue];
        NSArray *strokePaths = [strokeInfo objectForKey:@"paths"];
        
        if (sIndex >= 0 && sIndex < [strokeMarkers count]) {
            NSInteger startIndex = [[strokeMarkers objectAtIndex:sIndex] integerValue];
            NSInteger endIndex;
            if (sIndex < [strokeMarkers count] - 1) {
                endIndex = [[strokeMarkers objectAtIndex:sIndex + 1] integerValue] - 1;
            } else {
                endIndex = [paths count] - 1;
            }
            
            // Replace paths with the original versions
            NSInteger pathIdx = 0;
            for (NSInteger i = startIndex; i <= endIndex && pathIdx < [strokePaths count]; i++, pathIdx++) {
                NSBezierPath *originalPath = [[strokePaths objectAtIndex:pathIdx] copy];
                [paths replaceObjectAtIndex:i withObject:originalPath];
                [originalPath release];
            }
        }
    }
    
    [drawView invalidateStrokeCache];
    [drawView setNeedsDisplay:YES];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"Move %lu strokes", (unsigned long)[strokeIndices count]];
}

- (void)dealloc {
    [strokeIndices release];
    [originalPaths release];
    [movedPaths release];
    [super dealloc];
}
@end

// Move Text Command
@implementation MoveTextCommand

- (id)initWithDrawView:(DrawView *)view textField:(NSTextField *)field fromPosition:(NSPoint)oldPos toPosition:(NSPoint)newPos {
    self = [super initWithDrawView:view];
    if (self) {
        textField = [field retain];
        oldPosition = oldPos;
        newPosition = newPos;
    }
    return self;
}

- (void)execute {
    NSRect frame = [textField frame];
    frame.origin = newPosition;
    [textField setFrame:frame];
    [drawView setNeedsDisplay:YES];
}

- (void)undo {
    NSRect frame = [textField frame];
    frame.origin = oldPosition;
    [textField setFrame:frame];
    [drawView setNeedsDisplay:YES];
}

- (NSString *)description {
    return @"Move text field";
}

- (void)dealloc {
    [textField release];
    [super dealloc];
}
@end

// Clear All Command
@implementation ClearAllCommand

- (id)initWithDrawView:(DrawView *)view {
    self = [super initWithDrawView:view];
    if (self) {
        // Save current state
        NSMutableArray *paths = [view valueForKey:@"paths"];
        NSMutableArray *pathColors = [view valueForKey:@"pathColors"];
        NSMutableArray *strokeMarkers = [view valueForKey:@"strokeMarkers"];
        NSMutableArray *textFields = [view valueForKey:@"textFields"];
        NSMutableArray *textFieldColors = [view valueForKey:@"textFieldColors"];
        NSMutableArray *redoStack = [view valueForKey:@"redoStack"];
        
        savedPaths = [[NSMutableArray alloc] init];
        savedColors = [[NSMutableArray alloc] init];
        savedMarkers = [[NSMutableArray alloc] initWithArray:strokeMarkers];
        savedTextFields = [[NSMutableArray alloc] initWithArray:textFields];
        savedTextColors = [[NSMutableArray alloc] initWithArray:textFieldColors];
        savedRedoStack = [[NSMutableArray alloc] initWithArray:redoStack];
        
        // Deep copy paths and colors
        for (NSInteger i = 0; i < [paths count]; i++) {
            [savedPaths addObject:[[paths objectAtIndex:i] copy]];
            [savedColors addObject:[[pathColors objectAtIndex:i] copy]];
        }
    }
    return self;
}

- (void)execute {
    NSMutableArray *paths = [drawView valueForKey:@"paths"];
    NSMutableArray *pathColors = [drawView valueForKey:@"pathColors"];
    NSMutableArray *strokeMarkers = [drawView valueForKey:@"strokeMarkers"];
    NSMutableArray *textFields = [drawView valueForKey:@"textFields"];
    NSMutableArray *textFieldColors = [drawView valueForKey:@"textFieldColors"];
    NSMutableArray *redoStack = [drawView valueForKey:@"redoStack"];
    
    // Remove all text fields from view
    for (NSTextField *field in textFields) {
        [field removeFromSuperview];
    }
    
    // Clear everything
    [paths removeAllObjects];
    [pathColors removeAllObjects];
    [strokeMarkers removeAllObjects];
    [textFields removeAllObjects];
    [textFieldColors removeAllObjects];
    
    // Clear the redo stack when clearing all
    [redoStack removeAllObjects];
    
    [drawView invalidateStrokeCache];
    [drawView setNeedsDisplay:YES];
}

- (void)undo {
    NSMutableArray *paths = [drawView valueForKey:@"paths"];
    NSMutableArray *pathColors = [drawView valueForKey:@"pathColors"];
    NSMutableArray *strokeMarkers = [drawView valueForKey:@"strokeMarkers"];
    NSMutableArray *textFields = [drawView valueForKey:@"textFields"];
    NSMutableArray *textFieldColors = [drawView valueForKey:@"textFieldColors"];
    
    // Restore all paths
    for (NSInteger i = 0; i < [savedPaths count]; i++) {
        [paths addObject:[savedPaths objectAtIndex:i]];
        [pathColors addObject:[savedColors objectAtIndex:i]];
    }
    
    // Restore markers
    for (NSNumber *marker in savedMarkers) {
        [strokeMarkers addObject:marker];
    }
    
    // Restore text fields
    for (NSInteger i = 0; i < [savedTextFields count]; i++) {
        NSTextField *field = [savedTextFields objectAtIndex:i];
        [drawView addSubview:field];
        [textFields addObject:field];
        [textFieldColors addObject:[savedTextColors objectAtIndex:i]];
    }
    
    // We'll be added to redo stack by DrawView's undo method,
    // but we need to restore the saved redo stack after that happens
    [self performSelector:@selector(restoreRedoStackAfterUndo) withObject:nil afterDelay:0.0];
    
    [drawView invalidateStrokeCache];
    [drawView setNeedsDisplay:YES];
}

- (void)restoreRedoStackAfterUndo {
    NSMutableArray *redoStack = [drawView valueForKey:@"redoStack"];
    
    // Replace the entire redo stack with our saved one
    // This removes ourselves and restores the previous redo history
    [redoStack removeAllObjects];
    for (id command in savedRedoStack) {
        [redoStack addObject:command];
    }
}

- (NSString *)description {
    return @"Clear all";
}

- (void)dealloc {
    [savedPaths release];
    [savedColors release];
    [savedMarkers release];
    [savedTextFields release];
    [savedTextColors release];
    [savedRedoStack release];
    [super dealloc];
}
@end