# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Wacom Overlay is a macOS application that allows drawing with a Wacom tablet on top of all other applications while preserving normal mouse functionality. The app was written almost entirely by Claude Code and targets macOS 10.9 Mavericks with Wacom Drivers 6.3.18-4.

## Build Commands

- **Build the app**: `make`
- **Clean build artifacts**: `make clean`
- **Run the app**: `open "Wacom Overlay.app"`

There are no test, lint, or package management commands in this project.

## Architecture

The application follows a classic Objective-C/Cocoa architecture:

### Core Components

1. **TabletApplication** (`TabletApplication.h/m`) - Custom NSApplication subclass that:
   - Manages global event monitors for tablet input
   - Handles proximity events when the pen enters/leaves tablet range
   - Manages custom cursor display with color indicators
   - Uses CoreGraphics private APIs for cursor control

2. **AppDelegate** (`AppDelegate.h/m`) - Main application controller that:
   - Sets up the overlay window and status bar menu
   - Monitors keyboard shortcuts (undo/redo via ⌘Z/⇧⌘Z, normal mode via F14)
   - Manages the Wacom driver PID for event filtering
   - Coordinates between drawing view and control panel

3. **DrawView** (`DrawView.h/m`) - The main drawing canvas that:
   - Handles all drawing operations with NSBezierPath storage
   - Implements stroke selection and dragging
   - Manages text annotations with NSTextField overlays
   - Uses CGLayer caching for performance optimization
   - Supports undo/redo with separate stacks for strokes and text
   - Implements erasing by stroke intersection detection

4. **OverlayWindow** (`OverlayWindow.h/m`) - Transparent fullscreen window that:
   - Ignores all mouse events to allow click-through
   - Stays above all other windows
   - Hosts the DrawView

5. **ControlPanel** (`ControlPanel.h/m`) - Settings window for:
   - Line width adjustment (1-50 points)
   - Color selection with 10 preset colors
   - Text size adjustment (10-100 points)

### Event Flow

1. Tablet events are captured by TabletApplication's global monitors
2. Events are filtered based on Wacom driver PID
3. Drawing events are passed to DrawView via mouseEvent:
4. Mouse events from non-tablet sources pass through the overlay
5. Keyboard shortcuts are intercepted by AppDelegate's event tap

### Key Features Implementation

- **Pressure Sensitivity**: Tablet pressure is read from NSEvent and applied to stroke width
- **Straight Lines**: Hold Shift while drawing to create straight lines
- **Text Mode**: ⇧⌘⌥T creates text fields that can be moved and edited
- **Stroke Dragging**: Click and drag strokes with mouse; connected strokes of same color move together
- **Performance**: Uses CGLayer caching to optimize redrawing of completed strokes

## Important Notes

- The app requires Accessibility permissions in System Preferences
- Express Keys should be configured: ⌘Z (undo), ⇧⌘Z (redo), F14 (disable drawing)
- Pen buttons should be set to: ⌘D (change color), Erase
- The undo/redo shortcuts only work when activated via the tablet
- Hold undo to clear all drawing