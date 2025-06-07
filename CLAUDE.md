# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

- **Build the application**: `make`
- **Clean build**: `make clean`
- **Run the application**: `open WacomOverlay.app` or `./WacomOverlay.app/Contents/MacOS/WacomOverlay`

## Architecture Overview

This is a macOS application that creates a transparent drawing overlay for Wacom tablets. Key architectural points:

1. **Custom NSApplication Subclass**: The app uses `TabletApplication` instead of NSApplication to handle tablet events globally. This is configured in Info.plist with NSPrincipalClass.

2. **Event Interception**: Uses CGEventTap at the system level to intercept all input events. The tap callback in AppDelegate.m determines whether events are tablet events (consumed for drawing) or mouse events (passed through).

3. **Transparent Overlay**: `OverlayWindow` is a borderless window at NSScreenSaverWindowLevel that covers the entire screen but is configured to ignore mouse events, allowing clicks to pass through to applications below.

4. **Drawing Logic**: All drawing happens in `DrawView` which handles pressure-sensitive strokes, undo/redo, eraser mode, and stroke selection. Drawing uses NSBezierPath with pressure data from tablet events.

5. **Tablet Event Detection**: The `TabletEvents` category extends NSEvent to detect whether an event comes from a tablet or mouse by checking for NSEventSubtypeTabletPoint.

## Critical Implementation Details

- **Accessibility Permissions Required**: The app needs to be added to System Preferences → Security & Privacy → Accessibility for CGEventTap to work.

- **Event Flow**: CGEventTapCallback → Check if tablet event → If yes, send to DrawView and consume → If no, check for stroke selection or pass through.

- **Pen Button Handling**: The pen button switches to eraser mode. This is detected in DrawView's mouseDown by checking event.buttonMask.

- **Keyboard Shortcuts**: Only work when triggered from the Wacom tablet (not regular keyboard) due to how events are filtered by process ID.

- **No Wacom SDK**: The app cleverly uses macOS's built-in tablet event support instead of the Wacom SDK, making it simpler and more maintainable.

## Common Development Tasks

- **Testing Drawing**: Run the app and use a Wacom tablet to draw. Hold F14 to switch to normal mouse mode.
- **Debugging Events**: Look at the CGEventTapCallback in AppDelegate.m - this is where all system events flow through.
- **Modifying Drawing Behavior**: Most drawing logic is in DrawView.m's mouse event handlers.
- **Adding New Features**: Consider the transparent overlay nature - anything added must not interfere with click-through behavior.