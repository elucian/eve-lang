"""Writes the SVG drawings of evetx into code/evetx/design/ (design for review, 2026-10-13, revision 3).

Run from the repository root:  python code/evetx/design/gen_svg.py
"""
import re
import calendar
from xml.sax.saxutils import escape

W, H = 1240, 790
BG, PANEL, DEEP, LINE = '#0f141a', '#161c24', '#0c1015', '#3b4756'
TXT, DIM, BRIGHT = '#a9b7c6', '#6c7a89', '#e6edf3'
BAR, BAR2, BLUE, GREEN, RED, AMBER = '#243447', '#1a2531', '#5aa9e6', '#58c08a', '#d9534f', '#e0b341'
KW, STR, NUM, COM = '#c792ea', '#98c379', '#d19a66', '#6c7a89'
KEYWORDS = r'driver|process|is|end|return|for|loop|in|if|then|else|function|print|database|table|while'


class Svg:
    def __init__(self, title, caption, w=W, h=H):
        self.w, self.h = w, h
        self.p = []
        self.title = title
        self.add(f'<rect width="{w}" height="{h}" fill="{BG}"/>')
        self.text(20, 26, title, BRIGHT, size=18, bold=True)
        self.text(20, 44, caption, '#8fa3b8')

    def add(self, s):
        self.p.append(s)

    def text(self, x, y, s, fill=TXT, size=None, bold=False, anchor=None):
        a = f' font-size="{size}"' if size else ''
        a += ' font-weight="bold"' if bold else ''
        a += f' text-anchor="{anchor}"' if anchor else ''
        self.add(f'<text x="{x}" y="{y}" fill="{fill}"{a} xml:space="preserve">{escape(s)}</text>')

    def rect(self, x, y, w, h, fill='none', stroke=None, rx=0, sw=1):
        st = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ''
        r = f' rx="{rx}"' if rx else ''
        self.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{fill}"{st}{r}/>')

    def line(self, x1, y1, x2, y2, stroke=LINE, arrow=False):
        m = ' marker-end="url(#arr)"' if arrow else ''
        self.add(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{stroke}"{m}/>')

    def inset(self, x, y, w, h, fill=DEEP):
        """A bordered, inset box: dark top and left edges, light bottom and right edges."""
        self.rect(x, y, w, h, fill)
        self.line(x, y + 0.5, x + w, y + 0.5, '#04070a')
        self.line(x + 0.5, y, x + 0.5, y + h, '#04070a')
        self.line(x, y + h - 0.5, x + w, y + h - 0.5, '#566577')
        self.line(x + w - 0.5, y, x + w - 0.5, y + h, '#566577')

    def field(self, x, y, w, value, h=22, hot=False, ph=None):
        self.rect(x, y, w, h, DEEP, BLUE if hot else LINE)
        if value:
            self.text(x + 8, y + h / 2 + 5, value + ('█' if hot else ''), BRIGHT)
        elif ph:
            self.text(x + 8, y + h / 2 + 5, ph, '#4b5866')

    def code(self, x, y, s):
        out, pos = [], 0
        pat = re.compile(r'(#.*$|\*\*.*$)|("[^"]*")|(\b\d+(?:\.\d+)?\b)|(\b(?:%s)\b)' % KEYWORDS)
        for m in pat.finditer(s):
            if m.start() > pos:
                out.append((s[pos:m.start()], TXT))
            col = COM if m.group(1) else STR if m.group(2) else NUM if m.group(3) else KW
            out.append((m.group(0), col))
            pos = m.end()
        if pos < len(s):
            out.append((s[pos:], TXT))
        spans = ''.join(f'<tspan fill="{c}">{escape(t)}</tspan>' for t, c in out)
        self.add(f'<text x="{x}" y="{y}" xml:space="preserve">{spans}</text>')

    def button(self, x, y, w, label, kind='plain', h=26):
        fill, stroke, col = {'ok': ('#2f6f4f', GREEN, '#ffffff'), 'plain': ('#1d2733', LINE, TXT),
                             'off': ('#161c24', '#2a3441', '#4b5866'), 'stop': ('#6b2b2b', RED, '#ffffff'),
                             'hot': ('#2b4a6b', BLUE, '#ffffff')}[kind]
        self.rect(x, y, w, h, fill, stroke, 3)
        self.text(x + w / 2, y + h / 2 + 5, label, col, anchor='middle', bold=(kind in ('ok', 'hot', 'stop')))

    def dialog(self, x, y, w, h, title, hint='Esc closes'):
        self.add('<g filter="url(#sh)">')
        self.rect(x, y, w, h, '#1b2330', BLUE, 4, 2)
        self.rect(x + 1, y + 1, w - 2, 26, '#2b4a6b')
        self.text(x + 12, y + 19, title, '#ffffff', bold=True)
        self.text(x + w - 12, y + 19, hint, '#cfe3f5', anchor='end')
        self.add('</g>')

    def popup(self, x, y, w, h):
        self.add('<g filter="url(#sh)">')
        self.rect(x, y, w, h, '#1b2330', BLUE, 3, 1)
        self.add('</g>')

    def save(self, path):
        head = (f'<?xml version="1.0" encoding="UTF-8"?>\n<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" '
                f'height="{self.h}" viewBox="0 0 {self.w} {self.h}" font-family="Consolas, \'Courier New\', monospace" '
                f'font-size="13">\n<title>{escape(self.title)}</title>\n<defs>'
                '<marker id="arr" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto">'
                '<path d="M0,0 L8,4 L0,8 z" fill="#8fa3b8"/></marker>'
                '<filter id="sh" x="-5%" y="-5%" width="110%" height="115%">'
                '<feDropShadow dx="3" dy="4" stdDeviation="3" flood-opacity="0.5"/></filter></defs>\n')
        open(path, 'w', encoding='utf-8', newline='').write(head + '\n'.join(self.p) + '\n</svg>\n')


# ------------------------------------------------------------------ the common screen
TREE = [  # indent, glyph, label, colour, tag
    (0, '▾', 'sales_etl', BRIGHT, ''),
    (1, '▸', 'asp/', TXT, ''),
    (1, '▾', 'db/', TXT, ''),
    (2, ' ', 'local.db', '#e0b341', ''),
    (2, ' ', 'staging.duckdb', '#e0b341', ''),
    (1, '▾', 'doc/', TXT, ''),
    (2, ' ', 'README.md', TXT, ''),
    (2, ' ', 'flow.svg', TXT, ''),
    (2, ' ', 'logo.png', TXT, ''),
    (2, ' ', 'intro.mp4', TXT, ''),
    (1, '▸', 'lib/', TXT, ''),
    (1, '▾', 'proc/', TXT, 'srv'),
    (2, ' ', 'load_orders.eve', TXT, ''),
    (2, ' ', 'clean_names.eve', TXT, ''),
    (1, '▾', 'server/', TXT, 'srv'),
    (2, ' ', 'sales_load.eve', TXT, ''),
    (1, '▸', 'sql/', TXT, 'srv'),
    (1, '▸', 'web/', TXT, 'srv'),
    (1, ' ', 'eve.cfg', TXT, ''),
    (1, ' ', 'eve.env', DIM, 'ign'),
    (1, ' ', 'sales_etl.eve', TXT, ''),
]
BOTTOM_TABS = ['Console', 'Watch', 'Stderr', 'Stdout', 'Breaks']
X0, Y0 = 20, 56                      # the terminal frame (1200 x 714)
SB = (30, 122, 270, 596)             # sidebar x, y, w, h
ED = (310, 122, 900)                 # editor tabs x, y, w
EB = (310, 146, 900, 282)            # editor body
TB_Y = 434                           # debug buttons
BT = (310, 468, 900)                 # bottom tabs
BB = (310, 492, 900, 226)            # bottom body
SY = 726                             # the status bar


def screen(svg, machine=2, tree_sel=None, tabs=('sales_load.eve',), tab_active=0, bottom_active=0,
           state=('Ready: connection: prod', GREEN), name='server/sales_load.eve', pos='Ln 8, Col 12',
           toolbar='idle', project='sales_etl', find='', replace='', menu_open=False, find_hot=False,
           tree_find='', scope='code', tree_hot=False):
    svg.rect(X0, Y0, 1200, 714, PANEL, LINE, 6, 2)
    # title bar: the title is a button that opens the main menu
    svg.rect(X0 + 1, Y0 + 1, 1198, 26, BAR)
    if menu_open:
        svg.rect(X0 + 1, Y0 + 1, 96, 26, '#2b4a6b')
    svg.text(32, 75, 'evetx ▾', '#ffffff' if menu_open else BRIGHT, bold=True)
    svg.text(120, 75, f'project: {project}')
    for i, (key, nm) in enumerate([('F1', 'local'), ('F2', 'prod'), ('F3', 'test')]):
        x = 880 + i * 112
        on = (i + 1) == machine
        svg.rect(x, 61, 104, 18, '#2f6f4f' if on else '#1d2733', GREEN if on else LINE, 3)
        svg.text(x + 52, 74, f'{key} {nm}', '#ffffff' if on else TXT, anchor='middle', bold=on)
    # tool bar under the title bar: two searches, each aligned with the panel it searches
    svg.rect(X0 + 1, 84, 1198, 32, BAR2)
    svg.line(X0 + 1, 116, X0 + 1199, 116)
    svg.line(305, 86, 305, 114)                          # the divider between the two contexts
    svg.text(34, 105, 'Files', '#8fa3b8')
    svg.field(76, 90, 218, tree_find, 22, tree_hot, ph='file names')
    ph = {'code': 'find in code', 'tables': 'find a table', 'data': 'find in data'}[scope]
    svg.text(318, 105, 'Find', '#8fa3b8')
    svg.field(358, 90, 270, find, 22, find_hot, ph=ph)
    svg.rect(572, 93, 52, 16, '#243447', LINE, 2)         # the scope tag inside the field
    svg.text(598, 105, scope, '#8fa3b8', size=10, anchor='middle')
    on = 'plain' if scope == 'code' else 'off'
    svg.text(642, 105, 'Replace', '#8fa3b8' if scope == 'code' else '#4b5866')
    svg.field(710, 90, 190, replace if scope == 'code' else '', 22, False, ph='replace with' if scope == 'code' else None)
    svg.button(910, 89, 80, 'Replace', on, 24)
    svg.button(998, 89, 100, 'Replace all', on, 24)
    svg.button(1170, 89, 32, '#', 'plain', 24)
    # sidebar
    sx, sy, sw, sh = SB
    svg.rect(sx, sy, sw, sh, DEEP, LINE)
    items = TREE
    svg.text(sx + 10, sy + 18, 'Project files', BRIGHT, bold=True)
    if tree_find:
        names = [it[2] for it in items if it[2].lower().startswith(tree_find.lower()) and it[2] != 'sales_etl']
        at = names.index(tree_sel) + 1 if tree_sel in names else 1
        svg.text(sx + sw - 10, sy + 18, f'{at} of {len(names)}', AMBER, anchor='end')
    svg.line(sx, sy + 26, sx + sw, sy + 26)
    for i, (ind, gl, label, col, tag) in enumerate(items):
        y = sy + 46 + i * 20
        if label == tree_sel:
            svg.rect(sx + 1, y - 14, sw - 2, 19, '#2b4a6b')
            col = '#ffffff'
        svg.text(sx + 10 + ind * 16, y, gl, DIM)
        k = 0 if (tree_find and label != 'sales_etl' and label.lower().startswith(tree_find.lower())) else -1
        if k >= 0 and label != 'sales_etl':               # the matched part in amber
            pre, mid, post = label[:k], label[k:k + len(tree_find)], label[k + len(tree_find):]
            svg.add(f'<text x="{sx + 26 + ind * 16}" y="{y}" xml:space="preserve"><tspan fill="{col}">{escape(pre)}</tspan>'
                    f'<tspan fill="{AMBER}" font-weight="bold">{escape(mid)}</tspan><tspan fill="{col}">{escape(post)}</tspan></text>')
        else:
            svg.text(sx + 26 + ind * 16, y, label, col)
        if tag == 'srv':
            svg.add(f'<circle cx="{sx + sw - 18}" cy="{y - 4}" r="4" fill="{BLUE}"/>')
        if tag == 'ign':
            svg.text(sx + sw - 54, y, 'ignored', DIM)
    svg.text(sx + 10, sy + sh - 30, '●', BLUE)
    svg.text(sx + 24, sy + sh - 30, 'server side: sent by upload', DIM)
    svg.text(sx + 10, sy + sh - 12, '▸ ▾ Enter or click: open / close', DIM)
    # editor tabs
    ex, ey, ew = ED
    svg.rect(ex, ey, ew, 24, DEEP, LINE)
    x = ex + 2
    for i, t in enumerate(tabs):
        w = 24 + 8 * len(t)
        svg.rect(x, ey + 2, w, 20, BAR if i == tab_active else '#161c24')
        svg.text(x + 10, ey + 17, t, '#ffffff' if i == tab_active else TXT, bold=(i == tab_active))
        svg.text(x + w - 14, ey + 17, '×', DIM)
        x += w + 4
    svg.rect(*EB, DEEP, LINE)
    # debug buttons
    tx = 310
    states = {'idle': ('ok', 'off', 'off', 'off', 'off'), 'paused': ('off', 'hot', 'hot', 'hot', 'stop'),
              'running': ('off', 'off', 'off', 'off', 'stop')}[toolbar]
    labels = [('▶ Run', 112, 'F5'), ('↓ Step into', 124, 'F11'), ('↑ Step out', 124, 'S-F11'),
              ('▶▶ Continue', 124, 'F8'), ('■ Stop', 96, 'S-F5')]
    for (lab, w, key), st in zip(labels, states):
        svg.button(tx, TB_Y, w, lab, st, 28)
        svg.text(tx + w + 4, TB_Y + 18, key, '#4b5866', size=10)
        tx += w + 40
    svg.text(1210, TB_Y + 18, 'F9 breakpoint', DIM, anchor='end', size=11)
    # bottom tabs
    bx, by, bw = BT
    svg.rect(bx, by, bw, 24, DEEP, LINE)
    x = bx + 2
    for i, t in enumerate(BOTTOM_TABS):
        w = 24 + 8 * len(t)
        svg.rect(x, by + 2, w, 20, BAR if i == bottom_active else '#161c24')
        svg.text(x + 12, by + 17, t, '#ffffff' if i == bottom_active else TXT, bold=(i == bottom_active))
        x += w + 4
    svg.rect(*BB, DEEP, LINE)
    statusbar(svg, state, name, pos)


def statusbar(svg, state, name, pos):
    """The bordered, inset status bar: state | name of the file or table | place | ? and settings."""
    svg.inset(30, SY, 1180, 34, '#0e141b')
    cells = [(30, 300, state[0], state[1], True), (330, 420, name, BRIGHT, False), (750, 330, pos, TXT, False)]
    for x, w, t, col, bold in cells:
        svg.text(x + 12, SY + 22, t, col, bold=bold)
    svg.line(330, SY + 5, 330, SY + 29, '#04070a'); svg.line(331, SY + 5, 331, SY + 29, '#566577')
    svg.line(750, SY + 5, 750, SY + 29, '#04070a'); svg.line(751, SY + 5, 751, SY + 29, '#566577')
    svg.line(1080, SY + 5, 1080, SY + 29, '#04070a'); svg.line(1081, SY + 5, 1081, SY + 29, '#566577')
    svg.button(1092, SY + 4, 52, '?', 'plain', 26)
    svg.button(1152, SY + 4, 52, '⚙', 'plain', 26)
    svg.text(1086, SY - 4, 'Ctrl+/ help', '#4b5866', size=10, anchor='middle')


def editor_code(svg, lines, first=1, bps=(), current=None, hot=None):
    bx, by, bw, bh = EB
    for i, s in enumerate(lines):
        n = first + i
        y = by + 20 + i * 18
        if n == current:
            svg.rect(bx + 1, y - 14, bw - 2, 18, '#4a3f12')
        if n == hot:
            svg.rect(bx + 1, y - 14, bw - 2, 18, '#1f3550')
        if n in bps:
            svg.add(f'<circle cx="{bx + 14}" cy="{y - 4}" r="5" fill="{RED}"/>')
        if n == current:
            svg.text(bx + 24, y, '▶', AMBER, bold=True)
        svg.text(bx + 62, y, str(n), DIM, anchor='end')
        svg.code(bx + 74, y, s)


CODE = [
    '#!',
    '# Load the orders of the day into the staging tables',
    'driver sales_load is',
    '  process main is',
    '    db is database("db/local.db");',
    '    total is 0;',
    '    for order in db.orders loop',
    '      total is total + order.amount;',
    '      print("order", order.id, order.amount);',
    '    end loop;',
    '    print("total", total);',
    '    return;',
    '  end main;',
    'end sales_load;',
]


def console(svg, lines, cmd='', note=None):
    """The console of evevm (manual/usage.md, "The screen"): output with its own scrollback above,
    then a rule, the command line `eve:> `, a rule. The state of the machine is in the status bar."""
    bx, by, bw, bh = BB
    top = by + 6
    for i, (s, c) in enumerate(lines[-9:]):
        svg.text(bx + 10, top + 14 + i * 17, s, c or TXT)
    # scrollbar of the upper part
    svg.rect(bx + bw - 12, by + 4, 8, bh - 56, '#161c24', LINE)
    svg.rect(bx + bw - 11, by + 4 + (bh - 56) * 0.55, 6, (bh - 56) * 0.45 - 1, '#3b4756')
    if note:
        svg.text(bx + bw - 22, by + bh - 62, note, '#4b5866', size=10, anchor='end')
    svg.line(bx, by + bh - 46, bx + bw, by + bh - 46, '#566577')
    svg.text(bx + 10, by + bh - 26, 'eve:> ', GREEN, bold=True)
    svg.text(bx + 58, by + bh - 26, cmd, BRIGHT)
    if cmd is not None:
        svg.text(bx + 58 + 7.8 * len(cmd), by + bh - 26, '█', BLUE)
    svg.line(bx, by + bh - 12, bx + bw, by + bh - 12, '#566577')
    svg.text(bx + 10, by + bh - 2, 'PgUp/PgDn scroll · Ctrl+↑/↓ history · Tab completes', '#4b5866', size=10)


CONSOLE_MAIN = [
    ('eve:> select prod', None), ('Ready: connection: prod', GREEN),
    ('eve:> upload', None), ('upload proc/load_orders.eve ... ok', None), ('upload server/sales_load.eve ... ok', None),
    ('upload done: 2 sent, 5 unchanged, 1 local only', GREEN),
    ('eve:> run sales_load.eve', None), ('(F2) runs on prod: the program is on the server', DIM),
    ('order 1041 25.00', None), ('order 1042 12.50', None), ('total 37.50', None),
    ('run finished, exit 0, 1.2 s', GREEN),
]


# ------------------------------------------------------------------ 1. main screen
def main_screen():
    s = Svg('evetx: the Eve text UI (libvaxis), the main screen — design for level 6, `eve -tx`',
            'Left: names that start with the typed letters, the tree goes to the match. Right: code, tables or data. # jumps to a line or record.')
    screen(s, tree_sel='sales_load.eve', tabs=('sales_etl.eve', 'sales_load.eve', 'local.db ▪ tables'), tab_active=1,
           find='total', replace='sum', find_hot=False, tree_find='sal', tree_hot=True)
    editor_code(s, CODE, bps=(7,))
    console(s, CONSOLE_MAIN, 'run sales_load.eve', note='↑ 24 lines')
    s.save('code/evetx/design/design.svg')


# ------------------------------------------------------------------ 2. paused at a breakpoint, Watch
def debug_screen():
    s = Svg('evetx: debugging — paused at a breakpoint, Watch tab',
            'The run stopped on line 8 (yellow arrow). Run is off; step into, step out, continue and stop are on. The status bar says Paused.')
    screen(s, tree_sel='sales_load.eve', tabs=('sales_etl.eve', 'sales_load.eve'), tab_active=1, bottom_active=1,
           toolbar='paused', state=('Paused · connection: prod', AMBER), pos='Ln 8, Col 5')
    editor_code(s, CODE, bps=(7, 11), current=8)
    bx, by, bw, bh = BB
    s.text(bx + 10, by + 20, 'Expression', '#8fa3b8'); s.text(bx + 330, by + 20, 'Value', '#8fa3b8'); s.text(bx + 620, by + 20, 'Type', '#8fa3b8')
    s.line(bx, by + 28, bx + bw, by + 28)
    rows = [('total', '25.50', 'Decimal'), ('order.id', '1042', 'Integer'), ('order.amount', '12.50', 'Decimal'),
            ('db', 'Database("db/local.db")', 'Database'), ('total + order.amount', '38.00', 'Decimal')]
    for i, (a, b, c) in enumerate(rows):
        y = by + 48 + i * 20
        if i == 1:
            s.rect(bx + 1, y - 14, bw - 2, 19, '#1f3550')
        s.text(bx + 10, y, a, BRIGHT)
        s.text(bx + 330, y, b, STR if b[0].isdigit() else TXT)
        s.text(bx + 620, y, c, DIM)
    s.text(bx + 10, by + 48 + 5 * 20 + 6, '+ add expression (Enter)      Del removes the selected one', DIM, size=12)
    s.text(bx + 10, by + bh - 10, 'values come from vm.inspect of the paused session (F-TLS-04, vm.suspend / vm.resume)', '#4b5866', size=11)
    s.save('code/evetx/design/design-debug.svg')


# ------------------------------------------------------------------ 3. Breaks tab
def breaks_screen():
    s = Svg('evetx: the Breaks tab — select a breakpoint, remove it, or double-click to jump to it',
            'Every breakpoint of the project in one list. Enter or a double click opens the file at that line.')
    screen(s, tree_sel='sales_load.eve', tabs=('sales_etl.eve', 'sales_load.eve', 'load_orders.eve'), tab_active=1,
           bottom_active=4, pos='Ln 11, Col 1')
    editor_code(s, CODE, bps=(7, 11), hot=11)
    bx, by, bw, bh = BB
    s.text(bx + 10, by + 20, 'On', '#8fa3b8'); s.text(bx + 50, by + 20, 'File : line', '#8fa3b8'); s.text(bx + 300, by + 20, 'Source', '#8fa3b8')
    s.line(bx, by + 28, bx + bw, by + 28)
    rows = [('[x]', 'server/sales_load.eve : 7', 'for order in db.orders loop'),
            ('[x]', 'server/sales_load.eve : 11', 'print("total", total);'),
            ('[ ]', 'proc/load_orders.eve : 14', 'insert_row(order);')]
    for i, (on, loc, src) in enumerate(rows):
        y = by + 48 + i * 20
        if i == 1:
            s.rect(bx + 1, y - 14, bw - 2, 19, '#2b4a6b')
        s.text(bx + 10, y, on, GREEN if on == '[x]' else DIM)
        s.text(bx + 50, y, loc, '#ffffff' if i == 1 else TXT)
        s.text(bx + 300, y, src, '#ffffff' if i == 1 else DIM)
    s.button(bx + 10, by + bh - 40, 110, 'Remove', 'plain')
    s.button(bx + 130, by + bh - 40, 130, 'Remove all', 'plain')
    s.button(bx + 270, by + bh - 40, 110, 'Go to', 'hot')
    s.text(bx + 400, by + bh - 22, 'Space switches on or off · Del removes · double click / Enter jumps', DIM, size=12)
    s.save('code/evetx/design/design-breaks.svg')


# ------------------------------------------------------------------ 4. database: table list
def db_tables_screen():
    s = Svg('evetx: a database file selected — the list of its tables opens in a tab',
            'Selecting local.db opens a tab with the tables. The right-hand search (scope: tables) filters them. Browse the data (a new tab) or edit the structure (a dialog).')
    screen(s, tree_sel='local.db', tabs=('sales_load.eve', 'local.db ▪ tables'), tab_active=1,
           name='db/local.db · tables', pos='Table 1 of 1: orders', find='ord', scope='tables')
    bx, by, bw, bh = EB
    s.text(bx + 12, by + 22, 'local.db   SQLite 3.54   db/local.db   1 of 4 tables match "ord"', BRIGHT, bold=True)
    s.text(bx + 12, by + 52, 'Table', '#8fa3b8'); s.text(bx + 260, by + 52, 'Columns', '#8fa3b8')
    s.text(bx + 380, by + 52, 'Rows', '#8fa3b8'); s.text(bx + 500, by + 52, 'Kind', '#8fa3b8')
    s.line(bx, by + 60, bx + bw, by + 60)
    rows = [('orders', '9', '1,204', 'table')]
    for i, r in enumerate(rows):
        y = by + 82 + i * 22
        s.rect(bx + 1, y - 15, bw - 2, 21, '#2b4a6b')
        for x, v in zip((12, 260, 380, 500), r):
            if x == 12:
                s.add(f'<text x="{bx + x}" y="{y}" xml:space="preserve"><tspan fill="{AMBER}" font-weight="bold">ord</tspan><tspan fill="#ffffff">ers</tspan></text>')
            else:
                s.text(bx + x, y, v, '#ffffff')
    s.button(bx + 12, by + bh - 44, 190, 'Enter  Browse data', 'hot')
    s.button(bx + 214, by + bh - 44, 190, 'S  Edit structure…', 'plain')
    s.button(bx + 416, by + bh - 44, 150, 'N  New table…', 'plain')
    s.text(bx + 590, by + bh - 26, 'Search filters tables. Structure: a dialog.', DIM, size=12)
    console(s, [('eve:> db describe orders', None), ('orders: 9 columns, 1,204 rows, primary key id', None)], '')
    s.save('code/evetx/design/design-db.svg')


# ------------------------------------------------------------------ 5. table data tab
def goto_popup(svg, title, value, hint):
    """The small prompt of the # button, under the button, at the right of the bar."""
    x, y, w, h = 900, 120, 310, 96
    svg.popup(x, y, w, h)
    svg.text(x + 12, y + 22, title, '#ffffff', bold=True)
    svg.field(x + 12, y + 32, w - 24, value, 22, True)
    svg.text(x + 12, y + 78, hint, DIM, size=11)


def db_data_screen():
    s = Svg('evetx: the data of a table opens in a new tab',
            'Browse only. The right search is global: every column, * inside the text, a number by number. # jumps to a record.')
    screen(s, tree_sel='local.db', tabs=('sales_load.eve', 'local.db ▪ tables', 'orders ▪ data'), tab_active=2,
           name='db/local.db · orders · data', pos='Record 1043 of 1,204 · Field: status', find='op*n', scope='data')
    bx, by, bw, bh = EB
    s.text(bx + 12, by + 22, 'orders   3 rows match  op*n   (of 1,204)', BRIGHT, bold=True)
    cols = [('id', 12), ('customer_id', 84), ('product', 220), ('quantity', 380), ('amount', 480), ('created', 600), ('status', 760)]
    for n, x in cols:
        s.text(bx + x, by + 52, n, '#8fa3b8')
    s.line(bx, by + 60, bx + bw, by + 60)
    data = [('1043', '203', 'P-0120', '5', '62.50', '2026-10-13 09:10', 'open'),
            ('1045', '41', 'P-0007', '3', '37.50', '2026-10-13 09:21', 'open'),
            ('1048', '203', 'P-0310', '4', '35.60', '2026-10-13 09:44', 'open')]
    for i, row in enumerate(data):
        y = by + 82 + i * 22
        if i == 0:
            s.rect(bx + 1, y - 15, bw - 2, 21, '#1f3550')
        for (n, x), v in zip(cols, row):
            if n == 'status':
                if i == 0:
                    s.rect(bx + x - 4, y - 15, 76, 21, '#2b4a6b', BLUE)
                s.add(f'<text x="{bx + x}" y="{y}" xml:space="preserve"><tspan fill="{AMBER}" font-weight="bold">{v}</tspan></text>')
            else:
                s.text(bx + x, y, v, '#ffffff' if i == 0 else (NUM if n in ('quantity', 'amount', 'id') else TXT))
    s.line(bx, by + bh - 30, bx + bw, by + bh - 30)
    s.text(bx + 12, by + bh - 10, 'search: every column · * stands for any text · a number matches by number (id, quantity, amount) · PgUp/PgDn page · s sort', DIM, size=12)
    goto_popup(s, 'Go to record', '1050', 'Enter: record number or id; Esc closes')
    console(s, [('eve:> db query "select * from orders where status like \'op%n\'"', None), ('3 rows', None)], '')
    s.save('code/evetx/design/design-data.svg')


def goto_screen():
    s = Svg('evetx: the # button — go to a line, or to a record',
            'In an editor # asks for a line number and jumps to it; in a data tab it asks for a record number or an id.')
    screen(s, tree_sel='sales_load.eve', tabs=('sales_etl.eve', 'sales_load.eve'), tab_active=1, pos='Ln 11, Col 1')
    editor_code(s, CODE, bps=(7,), hot=11)
    goto_popup(s, 'Go to line', '11', 'Enter jumps to the line (1 to 14); Esc closes')
    console(s, CONSOLE_MAIN[:6], '')
    s.save('code/evetx/design/design-goto.svg')


def filecard_screen():
    s = Svg('evetx: a file card for binary files — images, SVG, audio, video: no preview',
            'Text files open in the editor (Markdown too, as source). Any other file opens a card with its facts. Rendered views are in eveux (eve -ux).')
    screen(s, tree_sel='flow.svg', tabs=('README.md', 'logo.png', 'flow.svg'), tab_active=2,
           name='doc/flow.svg', pos='SVG image · 3.1 KB')
    bx, by, bw, bh = EB
    cx, cy, cw, ch = bx + 200, by + 36, 500, 200
    s.rect(cx, cy, cw, ch, '#10161d', LINE, 4)
    s.text(cx + 24, cy + 40, '▣', '#4b5866', size=34)
    s.text(cx + 80, cy + 34, 'flow.svg', BRIGHT, size=16, bold=True)
    s.text(cx + 80, cy + 54, 'SVG image', TXT)
    for i, (k, v) in enumerate((('Path', 'doc/flow.svg'), ('Size', '3.1 KB (3,182 bytes)'), ('Modified', '2026-10-13 09:41'),
                                ('Side', 'local (not sent by upload)'))):
        s.text(cx + 24, cy + 96 + i * 20, k, DIM); s.text(cx + 110, cy + 96 + i * 20, v, TXT)
    s.text(cx + 24, cy + 188, 'No preview in evetx. The rendered file is shown by eveux (eve -ux).', DIM, size=12)
    s.text(bx + 716, by + 52, 'Also cards:', DIM, size=12)
    for i, t in enumerate(('logo.png · PNG · 48 KB', 'intro.mp4 · MP4 · 12 MB', 'a.zip · archive · 2 MB')):
        s.text(bx + 716, by + 72 + i * 18, t, DIM, size=12)
    console(s, CONSOLE_MAIN[:4], '')
    s.save('code/evetx/design/design-filecard.svg')


# ------------------------------------------------------------------ 6. structure grid (type list open) and 7. calendar
FIELDS = [  # name, type, not null, key, default
    ('id', 'INTEGER', 'x', 'PK', ''),
    ('customer_id', 'INTEGER', 'x', 'FK', ''),
    ('product', 'TEXT', 'x', '', ''),
    ('quantity', 'INTEGER', 'x', '', '1'),
    ('amount', 'DECIMAL(12,2)', 'x', '', ''),
    ('created', 'TIMESTAMP', 'x', '', 'now'),
]
GX, GY = 350, 196                    # the grid
COLS = [('#', 40), ('Name', 190), ('Type', 190), ('Not null', 80), ('Key', 70), ('Default', 210)]
ROWH = 30


def grid_dialog(s, sel_row, sel_col, page='Fields 1–6 of 9 · page 1 of 2', changes='1 change pending: amount → total_amount'):
    dx, dy, dw, dh = 330, 140, 820, 560
    s.dialog(dx, dy, dw, dh, 'Structure of orders   (db/local.db, SQLite)', 'Esc cancels')
    s.text(dx + 16, dy + 50, page, BRIGHT, bold=True)
    s.text(dx + dw - 16, dy + 50, 'arrows move · Enter edits · Space switches a box', DIM, anchor='end', size=11)
    x = GX
    for name, w in COLS:                                   # header cells
        s.rect(x, GY, w, ROWH, BAR, LINE)
        s.text(x + 8, GY + 20, name, '#ffffff', bold=True)
        x += w
    for r, f in enumerate(FIELDS):
        y = GY + ROWH * (r + 1)
        x = GX
        vals = [str(r + 1), f[0], f[1], '[x]' if f[2] else '[ ]', f[3] or '—', f[4]]
        for c, ((name, w), v) in enumerate(zip(COLS, vals)):
            hot = (r == sel_row and c == sel_col)
            s.rect(x, y, w, ROWH, '#243b57' if hot else '#10161d', BLUE if hot else LINE, 0, 2 if hot else 1)
            s.text(x + 8, y + 20, v, '#ffffff' if hot else (DIM if c == 0 else TXT))
            if name == 'Type':                             # the drop-down button of the cell
                s.rect(x + w - 28, y + 3, 24, ROWH - 6, '#1d2733', LINE, 2)
                s.text(x + w - 16, y + 20, '▾', TXT, anchor='middle')
            if name == 'Default' and f[1] in ('TIMESTAMP', 'DATE', 'TIME'):   # the calendar button
                s.rect(x + w - 28, y + 3, 24, ROWH - 6, '#1d2733', LINE, 2)
                s.text(x + w - 16, y + 20, '▦', AMBER, anchor='middle')
            x += w
    s.text(dx + 16, GY + ROWH * 7 + 24, changes, AMBER, size=12)
    s.text(dx + dw - 16, GY + ROWH * 7 + 24, '[S] show SQL', AMBER, size=12, anchor='end')
    by2 = dy + dh - 44
    s.button(dx + 14, by2, 150, '◄ Previous page', 'off')
    s.button(dx + 176, by2, 130, 'Next page ►', 'hot')
    s.button(dx + 318, by2, 130, '+ Add field', 'plain')
    s.button(dx + 460, by2, 130, '− Remove field', 'plain')
    s.button(dx + dw - 224, by2, 100, 'Apply', 'ok')
    s.button(dx + dw - 114, by2, 100, 'Cancel', 'plain')


def structure_screen():
    s = Svg('evetx: the structure of a table — a grid with headers and bordered cells; the type is chosen from a list',
            'One row per field, one column per attribute. The button in the Type cell opens the list of types; the Default cell of a date or time has a calendar button.')
    screen(s, tree_sel='local.db', tabs=('sales_load.eve', 'local.db ▪ tables', 'orders ▪ data'), tab_active=1,
           name='db/local.db · orders · structure', pos='Field 5 of 9: amount · Type')
    bx, by, bw, bh = EB
    s.text(bx + 12, by + 22, 'local.db   4 tables', BRIGHT, bold=True)
    grid_dialog(s, 4, 2)
    # drop-down list of types under the Type cell of row 5 (index 4)
    cx = GX + 40 + 190
    cy = GY + ROWH * 5 + ROWH
    types = ['INTEGER', 'BIGINT', 'DECIMAL(p,s)', 'REAL', 'TEXT', 'BOOLEAN', 'DATE', 'TIME', 'TIMESTAMP', 'BLOB']
    s.popup(cx, cy, 190, 22 * len(types) + 8)
    for i, t in enumerate(types):
        y = cy + 6 + i * 22
        if t.startswith('DECIMAL'):
            s.rect(cx + 2, y, 186, 22, '#2b4a6b')
        s.text(cx + 10, y + 16, t, '#ffffff' if t.startswith('DECIMAL') else TXT)
    s.text(cx + 204, cy + 110, 'The list is the types of the engine of this file', DIM, size=11)
    s.text(cx + 204, cy + 124, '(SQLite or DuckDB); ↑↓ Enter chooses, Esc closes.', DIM, size=11)
    s.save('code/evetx/design/design-structure.svg')


def calendar_screen():
    s = Svg('evetx: the default value of a date or time field has a calendar',
            'The calendar button of the Default cell opens a date picker; a time row for TIMESTAMP and TIME; Now and Today give expressions of the engine.')
    screen(s, tree_sel='local.db', tabs=('sales_load.eve', 'local.db ▪ tables', 'orders ▪ data'), tab_active=1,
           name='db/local.db · orders · structure', pos='Field 6 of 9: created · Default')
    bx, by, bw, bh = EB
    s.text(bx + 12, by + 22, 'local.db   4 tables', BRIGHT, bold=True)
    grid_dialog(s, 5, 5, changes='no changes')
    px, py = GX + 40 + 190 + 190 + 80 + 70 - 120, GY + ROWH * 6 + ROWH + 4
    s.popup(px, py, 300, 284)
    s.text(px + 14, py + 24, '◄', TXT); s.text(px + 150, py + 24, 'October 2026', BRIGHT, bold=True, anchor='middle'); s.text(px + 286, py + 24, '►', TXT, anchor='end')
    for i, d in enumerate(('Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su')):
        s.text(px + 24 + i * 38, py + 52, d, '#8fa3b8', anchor='middle')
    weeks = calendar.Calendar(0).monthdayscalendar(2026, 10)
    for r, wk in enumerate(weeks):
        for c, d in enumerate(wk):
            if not d:
                continue
            x, y = px + 24 + c * 38, py + 78 + r * 24
            if d == 13:
                s.rect(x - 16, y - 16, 32, 22, '#2b4a6b', BLUE)
            s.text(x, y, str(d), '#ffffff' if d == 13 else (AMBER if c >= 5 else TXT), anchor='middle')
    s.line(px + 8, py + 208, px + 292, py + 208)
    s.text(px + 14, py + 232, 'Time', DIM)
    s.field(px + 60, py + 216, 100, '09:30:00', 22)
    s.button(px + 14, py + 250, 70, 'Today', 'plain', 24); s.button(px + 92, py + 250, 60, 'Now', 'plain', 24)
    s.button(px + 160, py + 250, 60, 'Clear', 'plain', 24); s.button(px + 228, py + 250, 60, 'OK', 'ok', 24)
    s.save('code/evetx/design/design-calendar.svg')


# ------------------------------------------------------------------ 8. main menu
MENU = [  # (label, shortcut) ; None = a rule; strings alone = a section name
    ('File', None),
    ('Open project…', 'Ctrl+O'), ('New file', 'Ctrl+N'), ('Save', 'Ctrl+S'), ('Save As…', 'Ctrl+Shift+S'),
    ('Close tab', 'Ctrl+W'), ('Quit', 'Ctrl+Q'),
    ('Edit', None),
    ('Undo', 'Ctrl+Z'), ('Redo', 'Ctrl+Y'), ('Find', 'Ctrl+F'), ('Replace', 'Ctrl+H'),
    ('Run', None),
    ('Run', 'F5'), ('Step into', 'F11'), ('Step out', 'Shift+F11'), ('Continue', 'F8'), ('Stop', 'Shift+F5'), ('Breakpoint', 'F9'),
    ('Machine', None),
    ('Connect…', 'Ctrl+K'), ('Upload…', 'Ctrl+U'), ('Next machine', 'Ctrl+→'),
    ('Help', None),
    ('Help', 'Ctrl+/'), ('Settings…', 'Ctrl+,'),
]


def menu_screen():
    s = Svg('evetx: the main menu — a click on the title, or Ctrl+Enter, with the shortcuts',
            'Sections File, Edit, Run, Machine, Help in one list; arrows and Enter, or the first letter; Esc closes. The shortcuts are proposed.')
    screen(s, tree_sel='sales_load.eve', tabs=('sales_etl.eve', 'sales_load.eve'), tab_active=1, menu_open=True)
    editor_code(s, CODE, bps=(7,))
    console(s, CONSOLE_MAIN[:6], '')
    x0, y0, w = 21, 83, 330
    n_items = sum(1 for _, k in MENU if k is not None)
    n_sec = sum(1 for _, k in MENU if k is None)
    h = n_items * 20 + n_sec * 26 + 12
    s.popup(x0, y0, w, h)
    y = y0 + 8
    for label, key in MENU:
        if key is None:
            s.text(x0 + 12, y + 18, label.upper(), '#8fa3b8', size=11, bold=True)
            s.line(x0 + 70, y + 14, x0 + w - 10, y + 14)
            y += 26
        else:
            if label == 'Save As…':
                s.rect(x0 + 2, y, w - 4, 20, '#2b4a6b')
            s.text(x0 + 24, y + 15, label, '#ffffff' if label == 'Save As…' else TXT)
            s.text(x0 + w - 14, y + 15, key, '#ffffff' if label == 'Save As…' else DIM, anchor='end')
            y += 20
    s.save('code/evetx/design/design-menu.svg')


# ------------------------------------------------------------------ 9. help dialog
def help_screen():
    s = Svg('evetx: the help dialog — Ctrl+/ (or the ? button of the status bar)',
            'The keys in groups, for the context that is open; Esc or Ctrl+/ closes it.')
    screen(s, tree_sel='sales_load.eve', tabs=('sales_etl.eve', 'sales_load.eve'), tab_active=1)
    editor_code(s, CODE, bps=(7,))
    console(s, CONSOLE_MAIN[:6], '')
    dx, dy, dw, dh = 260, 150, 720, 520
    s.dialog(dx, dy, dw, dh, 'Help — keys', 'Esc or Ctrl+/ closes')
    groups_l = [('Machines', ['F1  local machine', 'F2  remote machine', 'F3  another machine', 'Ctrl+←  Ctrl+→  previous, next machine', 'Ctrl+K  connect   Ctrl+U  upload']),
                ('Run and debug', ['F5  run            F8  continue', 'F11  step into     Shift+F11  step out', 'Shift+F5  stop      F9  breakpoint']),
                ('Console', ['Ctrl+↑  Ctrl+↓  previous, next command', 'PgUp  PgDn  scroll the output', 'Tab  complete (server code on a remote)'])]
    groups_r = [('Files and editing', ['Ctrl+S  save        Ctrl+Shift+S  save as', 'Ctrl+Z  undo        Ctrl+Y  redo', 'Ctrl+F  find        Ctrl+H  replace', 'Ctrl+W  close tab   Ctrl+O  open project']),
                ('Windows', ['Ctrl+Enter  main menu (or click the title)', 'Ctrl+/  this help', 'Ctrl+,  settings (the gear)', 'Ctrl+Q  quit']),
                ('Tables', ['Enter  browse data     S  structure', 'N  new table          /  filter'])]
    for col, groups in ((dx + 20, groups_l), (dx + 370, groups_r)):
        y = dy + 56
        for title, items in groups:
            s.text(col, y, title, BLUE, bold=True)
            s.line(col, y + 6, col + 320, y + 6)
            for i, it in enumerate(items):
                s.text(col + 6, y + 26 + i * 18, it, TXT, size=12)
            y += 26 + len(items) * 18 + 22
    s.text(dx + 20, dy + dh - 16, 'Where the terminal cannot tell a key (Ctrl+Enter, Ctrl+/), F10 opens the menu and F12 the help.', DIM, size=11)
    s.save('code/evetx/design/design-help.svg')


# ------------------------------------------------------------------ 10. dialogs and data flow
def dialogs():
    s = Svg('evetx: project dialog, connect dialog, upload and the data flow',
            'The dialogs around the IDE screen: choose a project from the user cache, connect with a hidden password, upload the server side.')
    s.dialog(20, 70, 600, 330, 'Select project  (Ctrl+O)')
    s.text(34, 110, 'Filter:'); s.rect(90, 96, 510, 20, DEEP, LINE); s.text(98, 111, 'sal', BRIGHT); s.text(122, 111, '█', BLUE)
    s.text(34, 140, 'name            machine   last opened         path', '#8fa3b8')
    s.line(34, 146, 606, 146)
    s.rect(30, 152, 580, 20, '#2b4a6b')
    s.text(34, 166, 'sales_etl       prod      today 09:12         C:\\work\\sales_etl', '#ffffff')
    s.text(34, 188, 'sales_report    test      yesterday           C:\\work\\sales_report')
    s.text(34, 210, 'salesforce_in   local     3 days ago          D:\\eve\\salesforce_in')
    s.text(34, 232, '(3 of 14 projects)', DIM)
    s.text(34, 330, 'Source: the user cache …/eve/meta/eve.db (SQLite, table project). Deleting it loses nothing.', DIM, size=11)
    s.button(34, 350, 90, 'Open', 'ok'); s.button(136, 350, 90, 'New…'); s.button(238, 350, 100, 'Browse…'); s.button(350, 350, 100, 'Forget')
    s.dialog(660, 70, 540, 200, 'Connect to prod  (F2, or Ctrl+K)')
    s.text(676, 120, 'Username'); s.rect(770, 106, 410, 20, DEEP, LINE); s.text(778, 121, 'ana', BRIGHT)
    s.text(676, 156, 'Password'); s.rect(770, 142, 410, 20, DEEP, BLUE); s.text(778, 157, '********', BRIGHT); s.text(850, 157, '█', BLUE)
    s.text(676, 188, 'The user name is in clear, the password is shown as stars and is never kept.', DIM, size=11)
    s.text(676, 202, 'Not asked when eve.env has an entry for prod (one entry per machine, JSON).', DIM, size=11)
    s.button(676, 220, 100, 'Connect', 'ok'); s.button(788, 220, 100, 'Cancel')
    s.dialog(660, 296, 540, 160, 'Upload to prod  (Ctrl+U)')
    s.text(676, 338, 'what would be sent (changed files only)', '#8fa3b8')
    s.line(676, 344, 1184, 344)
    s.text(676, 362, 'proc/load_orders.eve        changed', TXT); s.text(1100, 362, 'server', BLUE)
    s.text(676, 380, 'sql/schema.sql              new', TXT); s.text(1100, 380, 'server', BLUE)
    s.text(676, 398, 'lib/text.eve                changed', TXT); s.text(1100, 398, 'imported', AMBER)
    s.text(676, 414, '5 in sync, 1 local only. Sent: web/ proc/ sql/ server/ + what they import.', DIM, size=11)
    s.button(676, 422, 100, 'Send', 'ok', 26); s.button(788, 422, 130, 'Dry run', 'plain', 26); s.button(930, 422, 100, 'Cancel', 'plain', 26)
    s.text(20, 440, 'Data flow', BRIGHT, size=15, bold=True)
    s.rect(240, 462, 190, 56, BAR, BLUE, 5, 2)
    s.text(335, 484, 'evetx', '#ffffff', bold=True, anchor='middle'); s.text(335, 504, 'model · update · view', TXT, size=11, anchor='middle')
    s.rect(20, 462, 150, 56, '#1d2733', LINE, 5)
    s.text(95, 484, 'libvaxis', TXT, anchor='middle'); s.text(95, 504, 'terminal, keys, mouse', DIM, size=11, anchor='middle')
    s.line(240, 490, 171, 490, arrow=True)
    for i, (n, col) in enumerate((('local', GREEN), ('prod', GREEN), ('test', RED))):
        x = 60 + i * 150
        s.rect(x, 620, 120, 56, '#1d2733', col, 5)
        s.text(x + 60, 642, n, BRIGHT, anchor='middle'); s.text(x + 60, 662, 'vm.*  db.*', DIM, size=11, anchor='middle')
        s.line(335 + (i - 1) * 40, 518, x + 60, 620, arrow=True)
    s.text(20, 706, 'JSON-RPC 2.0 (code/evecm/wire): IPC locally, plain HTTP on loopback or', DIM, size=11)
    s.text(20, 720, 'behind a reverse proxy remotely. One client task per machine.', DIM, size=11)
    s.rect(560, 462, 300, 120, '#1d2733', AMBER, 5, 2)
    s.text(574, 484, 'user cache (SQLite)', '#ffffff', bold=True)
    s.text(574, 504, '…/eve/meta/eve.db', TXT, size=12)
    s.text(574, 522, 'project · machine · history', TXT, size=12)
    s.text(574, 538, 'upload manifest (file hashes)', TXT, size=12)
    s.text(574, 568, 'no passwords, no tokens', '#d98c8c', size=12)
    s.rect(440, 536, 100, 46, '#1d2733', LINE, 5)
    s.text(490, 556, 'Meta', TXT, anchor='middle'); s.text(490, 572, 'interface', DIM, size=11, anchor='middle')
    s.line(430, 500, 490, 536, arrow=True)
    s.line(540, 559, 560, 559, arrow=True)
    s.text(440, 600, 'in evecm; SQLite in evedb;', DIM, size=11); s.text(440, 614, 'cmd connects them', DIM, size=11)
    s.rect(900, 462, 300, 170, '#161c24', LINE, 5)
    s.text(914, 484, 'Keys', BRIGHT, bold=True)
    for i, t in enumerate(('Ctrl+Enter menu · Ctrl+/ help · Ctrl+, settings', 'F1 local · F2 remote 1 · F3 remote 2',
                           'Ctrl+←/→ next machine', 'Ctrl+↑/↓ command history', 'F5 run · F8 continue · F9 breakpoint',
                           'F11 step into · Shift+F11 step out', 'Shift+F5 stop · Ctrl+O project · Ctrl+U upload')):
        s.text(914, 506 + i * 18, t, TXT, size=12)
    s.save('code/evetx/design/design-dialogs.svg')


if __name__ == '__main__':
    main_screen(); debug_screen(); breaks_screen(); db_tables_screen(); db_data_screen()
    structure_screen(); calendar_screen(); menu_screen(); help_screen(); goto_screen(); filecard_screen(); dialogs()
    print('12 drawings written to code/evetx/design/')
