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

@end