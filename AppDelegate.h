#import <Cocoa/Cocoa.h>

@class OverlayWindow;
@class ControlPanel;
@class DrawView;

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate> {
    id eventMonitor;
    CFMachPortRef eventTap;
    CFRunLoopSourceRef runLoopSource;
    NSStatusItem *statusItem;
    NSMutableDictionary *keyDownTimes;
}

@property (nonatomic, retain) OverlayWindow *overlayWindow;
@property (nonatomic, retain) ControlPanel *controlPanel;
@property (nonatomic, retain) DrawView *drawView;
@property (nonatomic, assign) pid_t wacomDriverPID;
@property (nonatomic, retain) NSStatusItem *statusItem;
@property (nonatomic, retain) NSDate *lastUndoKeyTime;
@property (nonatomic, assign) BOOL isUndoKeyDown;
@property (nonatomic, assign) BOOL isNormalModeKeyDown; // Track Cmd+; state
@property (nonatomic, retain) NSTimer *undoHoldTimer;

- (pid_t)findWacomDriverPID;
- (void)setupStatusBarMenu;
- (void)openControls:(id)sender;
- (void)clearDrawing:(id)sender;
- (void)showKeyboardShortcuts:(id)sender;

@end