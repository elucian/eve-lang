SRC = 'code/evetx/src/view.zig'
MODDIR = 'view'
IMPORT_LINES = (3, 21)
REEXPORT = []
def head(name, purpose):
    return ['//! @eve-module evetx.view.' + name, '//! @feature F-TLS-24', '//! @decision D-173', '//! @see code/evetx/src/view.zig:draw', '//! ' + purpose]
specs = [
 ('widgets', 23, 98, 'The drawing primitives: sub windows, boxes, text, buttons and fields that record their hit rectangles.'),
 ('sidebar', 296, 486, 'The files tree panel and the scroll bars.'),
 ('main_panel', 487, 644, 'The main panel: tab strip, logo, editor area and folder list.'),
 ('table_area', 645, 839, 'The grid of a table window.'),
 ('editor', 840, 1049, 'The code editor window and its scroll bars.'),
 ('syntax', 1050, 1219, 'Colors for Eve and SQL code and the selection.'),
 ('tools', 1220, 1600, 'The file card, the debug bar, the tools panel (console, watch, breaks, SQL) and the status bar.'),
 ('dialogs', 1601, 2118, 'The dialogs: filter, tab menu, properties, confirm, new file, wizards, structure of a table.'),
 ('menu', 2119, 2208, 'The drop down menus.'),
 ('settings', 2209, 2459, 'The settings dialog: theme, colors and timers.'),
 ('find_dialogs', 2460, 2636, 'About, go to, the two searches, replace, Save As and the project and folder dialogs.'),
 ('syntax', 2637, 2643, ''),
 ('find_dialogs', 2644, 2660, ''),
]
CHUNKS = [(n, a, b, head(n, p)) for (n, a, b, p) in specs]
