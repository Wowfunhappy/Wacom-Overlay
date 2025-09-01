#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

@class DrawView;

// Protocol for all undo/redo commands
@protocol UndoCommand <NSObject>
- (void)execute;
- (void)undo;
- (NSString *)description;
@end

// Base class for undo commands
@interface UndoCommand : NSObject <UndoCommand> {
    DrawView *drawView;
}
@property (nonatomic, assign) DrawView *drawView;
- (id)initWithDrawView:(DrawView *)view;
@end

// Command for adding a stroke
@interface AddStrokeCommand : UndoCommand {
    NSMutableArray *strokePaths;
    NSMutableArray *strokeColors;
    NSInteger markerIndex;
    NSInteger segmentCount;
}
- (id)initWithDrawView:(DrawView *)view paths:(NSArray *)paths colors:(NSArray *)colors markerIndex:(NSInteger)marker;
@end

// Command for erasing a stroke
@interface EraseStrokeCommand : UndoCommand {
    NSMutableArray *erasedPaths;
    NSMutableArray *erasedColors;
    NSInteger markerIndex;
    NSInteger originalStartIndex;
}
- (id)initWithDrawView:(DrawView *)view strokeMarkerIndex:(NSInteger)index;
@end

// Command for adding text
@interface AddTextCommand : UndoCommand {
    NSTextField *textField;
    NSColor *textColor;
    NSInteger textIndex;
}
- (id)initWithDrawView:(DrawView *)view textField:(NSTextField *)field color:(NSColor *)color;
@end

// Command for erasing text
@interface EraseTextCommand : UndoCommand {
    NSTextField *textField;
    NSColor *textColor;
    NSInteger originalIndex;
    NSRect originalFrame;
}
- (id)initWithDrawView:(DrawView *)view textFieldIndex:(NSInteger)index;
@end

// Command for editing text
@interface EditTextCommand : UndoCommand {
    NSTextField *textField;
    NSString *oldText;
    NSString *newText;
    NSFont *oldFont;
    NSFont *newFont;
    NSColor *oldColor;
    NSColor *newColor;
}
- (id)initWithDrawView:(DrawView *)view textField:(NSTextField *)field oldText:(NSString *)oldText newText:(NSString *)newText;
@end

// Command for moving strokes
@interface MoveStrokeCommand : UndoCommand {
    NSArray *strokeIndices;
    NSPoint offset;
    NSMutableArray *originalPaths;
    NSMutableArray *movedPaths;
}
- (id)initWithDrawView:(DrawView *)view strokeIndices:(NSArray *)indices offset:(NSPoint)offset originalPaths:(NSArray *)origPaths;
@end

// Command for moving text
@interface MoveTextCommand : UndoCommand {
    NSTextField *textField;
    NSPoint oldPosition;
    NSPoint newPosition;
}
- (id)initWithDrawView:(DrawView *)view textField:(NSTextField *)field fromPosition:(NSPoint)oldPos toPosition:(NSPoint)newPos;
@end

// Command for clearing all
@interface ClearAllCommand : UndoCommand {
    NSMutableArray *savedPaths;
    NSMutableArray *savedColors;
    NSMutableArray *savedMarkers;
    NSMutableArray *savedTextFields;
    NSMutableArray *savedTextColors;
    NSMutableArray *savedRedoStack;
}
- (id)initWithDrawView:(DrawView *)view;
@end