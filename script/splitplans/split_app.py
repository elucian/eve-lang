SRC = 'code/evetx/src/app.zig'
STRUCT = 'App'
TYPES = 'app/types.zig'
TYPES_RANGE = (22, 737)
def head(name, feat, purpose):
    return ['//! @eve-module evetx.app.' + name, '//! @feature ' + feat, '//! @decision D-173', '//! @see code/evetx/src/app.zig:App',
            '//! ' + purpose,
            ]
IMPORT_PREFIX = open('code/evetx/src/app.zig', encoding='utf-8').read().split('\n')[2:20]
IMPORT_PREFIX = [l for l in IMPORT_PREFIX if l.startswith('const ')]
TYPES_HEAD = ['//! @eve-module evetx.app.types', '//! @feature F-TLS-24', '//! @decision D-173', '//! @see code/evetx/src/app.zig:App',
              '//! The types of the state of evetx (focus, overlays, actions, tabs, log, run job) and the menus; `app.zig` re-exports them.']
T24, T27, T28 = 'F-TLS-24', 'F-TLS-27', 'F-TLS-28'
specs = [
 ('files', 1255, 1506, T24, 'Files and tabs: open, close, save, and the list of a folder.'),
 ('sqlite', 1507, 1842, T28, 'SQLite databases in the tree: tables, overview, reading and changing them.'),
 ('newfile', 1843, 2317, T24, 'New files, wizards, import, and Save As of a table.'),
 ('data', 2318, 2544, T28, 'The DATA menu: append, delete and edit records.'),
 ('structure', 2545, 2954, T28, 'The structure of a SQLite table: columns, indexes, apply.'),
 ('props', 2955, 3311, T24, 'Properties, rename, move, and which menu commands are enabled.'),
 ('filter', 3312, 3688, T28, 'The filter of a table.'),
 ('tables', 3689, 4091, T28, 'Close project, delete, create and drop table, alter table, the SQL tab and its target, the tree.'),
 ('run', 4092, 4709, T27, 'Breakpoints, running a script, the debugger and the console.'),
 ('session', 4710, 5043, T24, 'The session file and the console commands of the machine.'),
 ('search', 5044, 5156, T24, 'The two searches (names, text), replace and go to line.'),
 ('menu', 5157, 5315, T24, 'Overlays and the main menu.'),
 ('panels', 5316, 5751, T24, 'Panels, windows, layout, split bars and scroll bars.'),
 ('settings', 5752, 6084, T24, 'Options, themes and the settings dialog.'),
 ('dialogs', 6085, 6465, T24, 'Auto save, undo, the tab menu, and the project and folder dialogs.'),
 ('keys', 6466, 7109, T24, 'The keyboard: what each key does in each panel.'),
 ('mouse', 7110, 7310, T24, 'The mouse: clicks, drags, scroll.'),
 ('tree', 7311, 7996, T24, 'Marks and moving files in the tree.'),
]
CHUNKS = [('app/%s.zig' % n, a, b, head(n, f, p)) for (n, a, b, f, p) in specs]
