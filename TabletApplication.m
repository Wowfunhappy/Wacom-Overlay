#import "TabletApplication.h"
#import "TabletEvents.h"
#import "OverlayWindow.h"

@implementation TabletApplication

- (void)setOverlayWindow:(OverlayWindow *)window {
    overlayWindow = window; // No retain - window is owned by AppDelegate
}

- (void)sendEvent:(NSEvent *)theEvent {
    if ([theEvent isEventClassTablet]) {
        NSLog(@"TabletApplication: Received tablet event: %@", [theEvent description]);
        
        if ([theEvent isTabletProximityEvent]) {
            [self handleProximityEvent:theEvent];
        }
        
        // Direct tablet events specifically to our overlay window if it's tablet related
        if (overlayWindow != nil && ([theEvent isTabletPointerEvent] || [theEvent isTabletProximityEvent])) {
            // For tablet events, send them directly to our window
            [overlayWindow sendEvent:theEvent];
            return; // Skip normal event processing
        }
    }
    
    // Process all other events normally
    [super sendEvent:theEvent];
}

- (void)handleProximityEvent:(NSEvent *)theEvent {
    NSLog(@"TabletApplication: Handling proximity event");
    
    NSUInteger vendorID = [theEvent vendorID];
    NSUInteger tabletID = [theEvent tabletID];
    NSUInteger pointingDeviceID = [theEvent pointingDeviceID];
    NSUInteger deviceID = [theEvent deviceID];
    NSUInteger systemTabletID = [theEvent systemTabletID];
    NSUInteger vendorPointingDeviceType = [theEvent vendorPointingDeviceType];
    NSUInteger pointingDeviceSerialNumber = [theEvent pointingDeviceSerialNumber];
    NSUInteger capabilityMask = [theEvent capabilityMask];
    NSPointingDeviceType pointingDeviceType = [theEvent pointingDeviceType];
    BOOL enteringProximity = [theEvent isEnteringProximity];
    
    NSLog(@"Tablet details - deviceID: %lu, entering: %d, type: %lu", 
         (unsigned long)deviceID, enteringProximity, (unsigned long)pointingDeviceType);
    
    // Set up the keys for the dictionary
    NSArray *keys = [NSArray arrayWithObjects:
                     kVendorID,
                     kTabletID,
                     kPointerID,
                     kDeviceID,
                     kSystemTabletID,
                     kVendorPointerType,
                     kPointerSerialNumber,
                     kCapabilityMask,
                     kPointerType,
                     kEnterProximity,
                     nil];
    
    // Setup the data aligned with the keys to create the Dictionary
    NSArray *values = [NSArray arrayWithObjects:
                       [NSValue valueWithBytes:&vendorID objCType:@encode(UInt16)],
                       [NSValue valueWithBytes:&tabletID objCType:@encode(UInt16)],
                       [NSValue valueWithBytes:&pointingDeviceID objCType:@encode(UInt16)],
                       [NSValue valueWithBytes:&deviceID objCType:@encode(UInt16)],
                       [NSValue valueWithBytes:&systemTabletID objCType:@encode(UInt16)],
                       [NSValue valueWithBytes:&vendorPointingDeviceType objCType:@encode(UInt16)],
                       [NSValue valueWithBytes:&pointingDeviceSerialNumber objCType:@encode(UInt32)],
                       [NSValue valueWithBytes:&capabilityMask objCType:@encode(UInt32)],
                       [NSValue valueWithBytes:&pointingDeviceType objCType:@encode(UInt8)],
                       [NSValue valueWithBytes:&enteringProximity objCType:@encode(UInt8)],
                       nil];
    
    // Create the dictionary and post notification
    NSDictionary *proximityDict = [NSDictionary dictionaryWithObjects:values forKeys:keys];
    [[NSNotificationCenter defaultCenter] postNotificationName:kProximityNotification object:self userInfo:proximityDict];
}

- (void)dealloc {
    // Don't release overlayWindow - we don't own it
    [super dealloc];
}

@end