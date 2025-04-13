#import "TabletEvents.h"

NSString *kProximityNotification = @"Proximity Event Notification"; 

NSString *kVendorID = @"vendorID";
NSString *kTabletID = @"tabletID";
NSString *kPointerID = @"pointerID";
NSString *kDeviceID = @"deviceID";
NSString *kSystemTabletID = @"systemTabletID";
NSString *kVendorPointerType = @"vendorPointerType";
NSString *kPointerSerialNumber = @"pointerSerialNumber";
NSString *kCapabilityMask = @"capabilityMask";
NSString *kPointerType = @"pointerType";
NSString *kEnterProximity = @"enterProximity"; 

@implementation NSEvent (TabletEvents) 

- (BOOL)isEventClassTablet {
    NSEventType eventType = [self type];
    if (eventType == 23 || // NSTabletPointEventType
        eventType == 24) { // NSTabletProximityEventType
        return YES;
    }
    return NO;
}

- (BOOL)isEventClassMouse {
    NSEventType eventType = [self type];
    if (eventType == 5 ||  // NSMouseMovedEventType
        eventType == 6 ||  // NSLeftMouseDraggedEventType
        eventType == 7 ||  // NSRightMouseDraggedEventType
        eventType == 27 || // NSOtherMouseDraggedEventType
        eventType == 1 ||  // NSLeftMouseDownEventType
        eventType == 3 ||  // NSRightMouseDownEventType
        eventType == 25 || // NSOtherMouseDownEventType
        eventType == 2 ||  // NSLeftMouseUpEventType
        eventType == 4 ||  // NSRightMouseUpEventType
        eventType == 26) { // NSOtherMouseUpEventType
        return YES;
    }
    return NO;
}

- (BOOL)isTabletPointerEvent {
    if ([self isEventClassMouse]) {
        if ([self subtype] == 1) { // NSTabletPointEventSubtype
            return YES;
        }
    }

    if ([self type] == 23) { // NSTabletPointEventType
        return YES;
    }

    return NO;
}

- (BOOL)isTabletProximityEvent {
    if ([self isEventClassMouse]) {
        if ([self subtype] == 2) { // NSTabletProximityEventSubtype
            return YES;
        }
    }

    if ([self type] == 24) { // NSTabletProximityEventType
        return YES;
    }

    return NO;
}

- (float)rawTabletPressure {
   return [self pressure] * 65535.0f;
}

- (float)rotationInRadians {
   return [self rotation] * (float)(M_PI/180.0);
}

@end