#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import "AppDelegate.h"

@interface DrawView : NSView <NSTextFieldDelegate> {
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
    
    // Straight line drawing variables
    BOOL isShiftKeyDown;
    NSPoint straightLineStartPoint;
    NSBezierPath *straightLinePath; // For preview during drag
    CGFloat straightLineWidth; // To store the width at the time shift was pressed
    
    // Text annotation variables
    NSMutableArray *textAnnotations; // Array of dictionaries with text, position, attributes
    NSMutableArray *textColors; // Colors for each text annotation
    NSMutableArray *undoTextAnnotations;
    NSMutableArray *undoTextColors;
    BOOL isTextInputMode;
    BOOL isEditingText;
    NSTextField *activeTextField;
    NSInteger selectedTextIndex;
    NSPoint textInputPosition;
    NSInteger originalWindowLevel;
    CGFloat textSize;
}

@property (nonatomic, strong) NSColor *strokeColor;
@property (nonatomic, assign) CGFloat lineWidth;
@property (nonatomic, assign) CGFloat textSize;
@property (nonatomic, assign) BOOL erasing;
@property (nonatomic, readonly) NSArray *presetColors;
@property (nonatomic, assign) NSInteger currentColorIndex;
@property (nonatomic, assign) NSInteger smoothingLevel;
@property (nonatomic, assign) BOOL enableSmoothing;
@property (nonatomic, assign) NSInteger backgroundMode; // 0=Clear, 1=White, 2=Black

- (void)clear;
- (void)mouseEvent:(NSEvent *)event;
- (void)mouseMoved:(NSEvent *)event;
- (NSPoint)convertScreenPointToView:(NSPoint)screenPoint;
- (void)undo;
- (void)redo;
- (BOOL)canUndo;
- (BOOL)canRedo;
- (void)handleProximity:(NSNotification *)proxNotice;
- (void)eraseStrokeAtPoint:(NSPoint)point;
- (void)eraseTextAtPoint:(NSPoint)point;
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
- (CGPathRef)CGPathFromNSBezierPath:(NSBezierPath *)path;

// Text annotation methods
- (void)startTextInputAtPoint:(NSPoint)point;
- (void)finishTextInput;
- (void)cancelTextInput;
- (NSInteger)findTextAnnotationAtPoint:(NSPoint)point;
- (NSRect)boundsForTextAnnotation:(NSDictionary *)annotation;
- (void)moveSelectedText:(NSPoint)offset;
- (void)drawTextAnnotations;
- (void)enterTextInputMode;
- (void)exitTextInputMode;
- (void)resetToDefaults;

@end