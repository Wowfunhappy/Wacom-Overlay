#import "AppDelegate.h"
#import "OverlayWindow.h"
#import "TabletEvents.h"
#import "ControlPanel.h"
#import "DrawView.h"
#import "TabletApplication.h"

@interface AppDelegate ()
@property (strong) OverlayWindow *overlayWindow;
@property (strong) ControlPanel *controlPanel;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Create the overlay window that will receive tablet events
    self.overlayWindow = [[OverlayWindow alloc] initWithContentRect:[[NSScreen mainScreen] frame]
                                                          styleMask:0 // NSBorderlessWindowMask
                                                            backing:NSBackingStoreBuffered
                                                              defer:NO];
    
    // Set window to be transparent and pass-through mouse events
    [self.overlayWindow setOpaque:NO];
    [self.overlayWindow setAlphaValue:1.0];
    [self.overlayWindow setBackgroundColor:[NSColor clearColor]];
    
    // Get the draw view from the overlay window
    DrawView *drawView = (DrawView *)[self.overlayWindow contentView];
    
    // Create and show the control panel
    self.controlPanel = [[ControlPanel alloc] initWithDrawView:drawView];
    [self.controlPanel makeKeyAndOrderFront:nil];
    
    // Show the overlay window
    [self.overlayWindow makeKeyAndOrderFront:nil];
    
    // Connect overlay window with TabletApplication
    TabletApplication *app = (TabletApplication *)NSApp;
    [app setOverlayWindow:self.overlayWindow];
    
    // Register for notifications
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillTerminate:)
                                                 name:NSApplicationWillTerminateNotification
                                               object:nil];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Clean up by removing notification observers
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// Clean up memory
- (void)dealloc {
    [self.overlayWindow release];
    [self.controlPanel release];
    [super dealloc];
}

@end