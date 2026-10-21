1. Move replace in Edit, 
2. Remove title on File tree I want unintrerupted borders
3. If no project is open, the file tree is empty
4. The main left pannel when no window is open show a logo centered EVE-TX under it: Text User Interface, under it (c) Sage-Code Laboratory.
5. Create Window menu, with a list of windows that are open, to select one, dynamic. (last options) with a separator bar. Above it: Select, Close, Modify, Freeze. When user select to Modify user can use mouse button to change width of sidebar and height of main pannel 2 active splitters. When user select freeze or press escape the windows freeze size.
When user press Shift+Tab or press select in window the active pannel change. Rotate. When user press alt tab, the active tab change in top right pannel (main pannel) or run pannel depending which one is active.
F1 - local, F2 - F3 must be removed. Instead we have menu Machine. The machines will be selected with Alt+1, Alt+2, Alt+3
Window can be changed with Ctrl+1, Ctrl+2 ... in order they are open.
Add vertical scrollbar and horizontal scrollbar to the main window.
Help text are files, make files available in manual folder. The shortcuts is a fake file that appears in main editor pannel with title Shortcuts and user can close it like a normal window.
Each The Tree has a title bar under the border like the main pannel to be symetric and it has an X button that hide the tree. The main mappel haz a maximize button + and a close button x the same like bottom pannel. I can remove the bottom pannel (Tools Pannel). Let's name pannels: Tree Pannel, Main Pannel, Tools Pannel. In the Window menu show the 3 pannels with a checbox if they are visible or hidden (not checked) user can reactivate them.

---

Status 2026-10-14 (second pass): done, all in `src/app.zig` and `src/view.zig`. 1 Replace is in EDIT. 2 The tree has an uninterrupted border; its title bar (Files · project) is under it, with the × button. 3 Without a folder on the command line the tree is empty; File > Open project (Ctrl+O) asks for a folder. 4 The Main Panel with no window shows the EVE-TX logo, "Text User Interface" and "(c) Sage-Code Laboratory". 5 WINDOW menu: Select, Close, Modify, Freeze, the three panels with check boxes, then the open windows (Ctrl+1 to Ctrl+9); Modify moves the two borders with the mouse or the arrow keys, Esc or Freeze keeps the sizes; Shift+Tab rotates the panels; Alt+Tab and Ctrl+Tab change the window (Main Panel) or the tab (Tools Panel); F1 to F3 are gone, the MACHINE menu uses Alt+1 to Alt+3; both scroll bars are in the editor; Shortcuts, Manual and Tutorial are read-only windows made from `manual/evetx/*.txt` (copied into the program at build time); the panels are Tree Panel, Main Panel and Tools Panel, each with × (and + for Main and Tools). **Limits:** Windows takes Alt+Tab for itself (use Ctrl+Tab); Ctrl+digit needs a terminal that tells them apart from the digit.
