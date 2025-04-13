#import <Cocoa/Cocoa.h>
#import "TabletApplication.h"
#import "AppDelegate.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // Create our custom TabletApplication
        NSApplication *sharedApp = [TabletApplication sharedApplication];
        
        // Create and set the app delegate
        AppDelegate *delegate = [[AppDelegate alloc] init];
        [sharedApp setDelegate:delegate];
        
        // Activate the application
        [NSApp finishLaunching];
        [NSApp activateIgnoringOtherApps:YES];
        
        // Run the app
        [NSApp run];
    }
    
    return 0;
}