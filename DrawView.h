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
    BOOL mErasing;
    NSPoint lastErasePoint;
    BOOL hasLastErasePoint;
    NSArray *presetColors;
    NSInteger currentColorIndex;
}

@property (nonatomic, strong) NSColor *strokeColor;
@property (nonatomic, assign) CGFloat lineWidth;
@property (nonatomic, assign) BOOL erasing;

- (void)clear;
- (void)mouseEvent:(NSEvent *)event;
- (NSPoint)convertScreenPointToView:(NSPoint)screenPoint;
- (void)undo;
- (void)redo;
- (BOOL)canUndo;
- (BOOL)canRedo;
- (void)handleProximity:(NSNotification *)proxNotice;
- (void)eraseStrokeAtPoint:(NSPoint)point;
- (void)resetEraseTracking;
- (void)toggleToNextColor;

@end