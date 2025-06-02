# Wacom Overlay

I'm a teacher. I don't like writing on the whiteboard, so I bought a Wacom tablet to write on instead. Then I realized I needed a way to quickly switch between drawing and clicking. I wanted to be able to draw with my Wacom tablet without loosing the ability to click on things with my normal mouse. I could not find an existing app which was able to do this very simple thing!

**This application was 98% written by Claude Code!** I have not even looked at most of the code myself.

The app was tested on Mac OS X 10.9 Mavericks with Wacom Drivers 6.3.18-4 and the following Wacom tablets:
- Wacom Intuos P S CTL-490
- Wacom Intuos PT M CTH-690

## Setup
- Add this application to System Preferences → Security & Privacy → Privacy → Accessibility.
- Set three of your tablet's express keys to ⌘Z for undo, ⇧⌘Z for redo, and F14 which can be held down to temporarily disable drawing.
- Set one of the buttons on your pen to ⌘D for change color, and the other to Erase.

## Additional Notes
- The ⌘Z and ⇧⌘Z shortcuts for undo and redo will _only_ work if they are activated by your tablet (such as via an Express Key).
- Hold down the undo shortcut to clear your drawing.
- Hold down ⇧Shift to draw a straight line.
- Press ⇧⌘⌥T to create a text box.
- You can click and drag strokes with your mouse to move them around. Overlapping strokes of the same color will move together.

## Known Issues
- You cannot "undo" an erase to bring the stroke back.
  - Claude 3.7 absolutely could not figure this out for some reason! After a bunch of back and forth, I gave up.
  - Todo: Try again with Claude 4.
- If you use your tablet as a touchpad and hover over a stroke, the cursor won't change to a hand, as it will with a standard mouse. (Todo.)

## Todo 
- Confirm app doesn't break with multiple monitors.
- Change cursor on eraser mode.

This code is dedicated to the Public Domain, or licensed under Creative Commons Zero, or the Unlicense, or whatever other maximally-permissive license you find most convenient. Again, I did not write it!

## Credits
This application uses concepts from the Wacom Scribble Demo sample code.
Menu bar icon by FontAwesome
