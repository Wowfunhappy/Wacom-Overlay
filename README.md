# Wacom Overlay

A simple application that creates a transparent overlay window for drawing with a Wacom tablet. The application allows the tablet to draw on screen while the mouse continues to function normally.

## Features

- Transparent overlay window covers the entire screen
- Tablet input is captured for drawing with pressure sensitivity
- Mouse input passes through normally to other applications
- Adjustable line width and color
- Control panel with clear button and quit button

## Requirements

- Mac OS X 10.9 Mavericks
- Command Line Tools for OS X 10.9
- Wacom tablet with drivers installed

## Building

To build the application:

1. Open Terminal
2. Navigate to the project directory
3. Run `make`
4. The application will be built as WacomOverlay.app

See COMPILE.txt for detailed instructions.

## Usage

1. Launch WacomOverlay.app
2. Use your Wacom tablet pen to draw on the screen
3. Your mouse will continue to work normally for other applications
4. Use the control panel to change drawing color and line width
5. Click "Clear Drawing" to erase everything
6. Click "Quit" to exit the application

## Known Limitations

- This app was designed specifically for OS X 10.9 Mavericks
- It may not work with newer versions of the Wacom tablet drivers
- The app does not save drawings

## Source Files

- `main.m` - Application entry point
- `AppDelegate.h/m` - Application delegate
- `TabletApplication.h/m` - Custom NSApplication subclass to handle tablet events
- `TabletEvents.h/m` - NSEvent category for tablet-specific event handling
- `OverlayWindow.h/m` - Transparent overlay window
- `DrawView.h/m` - Custom view for drawing tablet strokes
- `ControlPanel.h/m` - Control panel window with buttons and color picker

## Credits

This application uses concepts from the Wacom Scribble Demo sample code.