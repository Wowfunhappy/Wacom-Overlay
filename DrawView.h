#import <Cocoa/Cocoa.h>

@interface DrawView : NSView {
    NSMutableArray *paths;
    NSMutableArray *pathColors;
    NSMutableArray *strokeMarkers;
    NSMutableArray *undoPaths;
    NSMutableArray *undoPathColors;
    NSMutableArray *undoStrokeMarkers;
    NSBezierPath *currentPath;
    NSColor *strokeColor;
    CGFloat lineWidth;
    NSPoint lastPoint;
}

@property (nonatomic, strong) NSColor *strokeColor;
@property (nonatomic, assign) CGFloat lineWidth;

- (void)clear;
- (void)mouseEvent:(NSEvent *)event;
- (NSPoint)convertScreenPointToView:(NSPoint)screenPoint;
- (void)undo;
- (void)redo;
- (BOOL)canUndo;
- (BOOL)canRedo;

@end