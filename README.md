# Wacom Overlay

I'm a teacher. I don't like writing on the whiteboard, so I bought a Wacom tablet to write on instead. Then I realized I needed a way to quickly switch between drawing and clicking. I wanted to be able to draw with my Wacom tablet without loosing the ability to click on things with my normal mouse. I could not find an existing app which was able to do this very simple thing!

**This application was 98% written by Claude Code!** I have not even looked at most of the code myself.

The app was tested on Mac OS X 10.9 Mavericks with a Wacom Intuos P S CTL-490 and Wacom Drivers 6.3.18-4.

## Setup
- Add this application to System Preferences → Security & Privacy → Privacy → Accessibility.
- Set three of your tablet's express keys to ⌘Z for undo, ⇧⌘Z for redo, and ⌘D to change color.
  - These shortcuts will _only_ work if they are activated by your tablet!

## Known Issues
- You cannot "undo" an erase to bring the stroke back.
  - Claude absolutely could not figure this out for some reason! After a bunch of back and forth, I gave up.

## Todo
- Keyboard shortcut to clear drawing (works on Keyboard or Tablet)
- Keyboard shortcut that can be held down to make pen act like mouse (Tablet only) 
- Confirm app doesn't break with multiple monitors.
- Change cursor when pen is near tablet to indicate current color and/or eraser mode
- Add ability to create text boxes? (Would be useful for teaching.)

This code is dedicated to the Public Domain, or licensed under Creative Commons Zero, or the Unlicense, or whatever other maximally-permissive license you find most convenient. Again, I did not write it!

### Credits

This application uses concepts from the Wacom Scribble Demo sample code.
Menu bar icon by FontAwesome
