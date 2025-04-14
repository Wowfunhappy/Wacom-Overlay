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
    
    // Smoothing related variables
    NSMutableArray *pointBuffer;
    NSInteger smoothingLevel;
    BOOL enableSmoothing;
    
    // Stroke selection and dragging variables
    NSInteger selectedStrokeIndex;
    BOOL isStrokeSelected;
    BOOL isDraggingStroke;
    NSPoint dragStartPoint;
    NSMutableArray *relatedStrokeIndices; // For tracking connected strokes (same color, intersecting)
}

@property (nonatomic, strong) NSColor *strokeColor;
@property (nonatomic, assign) CGFloat lineWidth;
@property (nonatomic, assign) BOOL erasing;
@property (nonatomic, readonly) NSArray *presetColors;
@property (nonatomic, assign) NSInteger currentColorIndex;
@property (nonatomic, assign) NSInteger smoothingLevel;
@property (nonatomic, assign) BOOL enableSmoothing;

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
- (void)setPresetColorAtIndex:(NSInteger)index toColor:(NSColor *)color;
- (NSPoint)smoothPoint:(NSPoint)point;
- (void)clearSmoothingBuffer;
- (NSInteger)findStrokeAtPoint:(NSPoint)point;
- (void)moveSelectedStroke:(NSPoint)offset;
- (BOOL)shouldAllowMouseEvent:(NSEvent *)event atPoint:(NSPoint)point;
- (void)findRelatedStrokes:(NSInteger)strokeIndex;
- (void)findConnectedStrokes:(NSInteger)strokeIndex withColor:(NSColor *)selectedColor processedStrokes:(NSMutableArray *)processedStrokes;
- (BOOL)doStrokesIntersect:(NSInteger)strokeIndex1 strokeIndex2:(NSInteger)strokeIndex2;
- (CGFloat)findMinimumDistanceBetweenPath:(NSBezierPath *)path1 andPath:(NSBezierPath *)path2;
- (NSArray *)getSamplePointsFromPath:(NSBezierPath *)path;
- (NSPoint)pointAtIndex:(NSInteger)index forPath:(NSBezierPath *)path;
- (NSPoint)evaluateBezierForT:(CGFloat)t startPt:(NSPoint)p0 controlPt1:(NSPoint)p1 controlPt2:(NSPoint)p2 endPt:(NSPoint)p3;

@end