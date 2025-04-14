#import <Cocoa/Cocoa.h>

@class OverlayWindow;
@class ControlPanel;
@class DrawView;

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate> {
    id eventMonitor;
    CFMachPortRef eventTap;
    CFRunLoopSourceRef runLoopSource;
    NSStatusItem *statusItem;
}

@property (nonatomic, retain) OverlayWindow *overlayWindow;
@property (nonatomic, retain) ControlPanel *controlPanel;
@property (nonatomic, retain) DrawView *drawView;
@property (nonatomic, assign) pid_t wacomDriverPID;
@property (nonatomic, retain) NSStatusItem *statusItem;

- (pid_t)findWacomDriverPID;
- (void)setupStatusBarMenu;
- (void)openControls:(id)sender;
- (void)clearDrawing:(id)sender;

@end