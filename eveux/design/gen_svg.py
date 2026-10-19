"""Writes the SVG drawings of eveux into eveux/design/ (design for review, 2026-10-18).

Run from the repository root:  python eveux/design/gen_svg.py
The drawings are of a native window (dvui), 1400 x 860 pixels; the colors are those of the evetx drawings so the two
tools share one theme. Change a drawing here and run the script again, or edit an SVG by hand.
"""
import re
from xml.sax.saxutils import escape

W, H = 1400, 860
BG, PANEL, DEEP, LINE = '#0f141a', '#161c24', '#0c1015', '#3b4756'
TXT, DIM, BRIGHT = '#a9b7c6', '#6c7a89', '#e6edf3'
BAR, BAR2, BLUE, GREEN, RED, AMBER = '#243447', '#1a2531', '#5aa9e6', '#58c08a', '#d9534f', '#e0b341'
KW, STR, NUM, COM, TYPE, FN = '#c792ea', '#98c379', '#d19a66', '#6c7a89', '#56b6c2', '#61afef'
EVE_KW = r'primary|aspect|process|is|end|return|for|loop|in|if|then|else|do|done|function|procedure|print|from|use|export|module|new|let|recover|raise|job|class|method|public|expect'

X0, Y0, WW, WH = 20, 56, 1360, 782           # the window
EXP_W, SIDE_W = 262, 290                      # explorer and right side bar
BODY_Y = Y0 + 30 + 26 + 36                    # below title, menu and tool bars
BODY_H = Y0 + WH - 26 - BODY_Y                # above the status bar
ED_X = X0 + EXP_W
ED_W = WW - EXP_W - SIDE_W
SIDE_X = ED_X + ED_W
BOT_H = 190


class Svg:
    def __init__(self, title, caption, w=W, h=H):
        self.w, self.h, self.p, self.title = w, h, [], title
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

    def line(self, x1, y1, x2, y2, stroke=LINE, arrow=False, dash=False):
        m = ' marker-end="url(#arr)"' if arrow else ''
        d = ' stroke-dasharray="4 3"' if dash else ''
        self.add(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{stroke}"{m}{d}/>')

    def circle(self, x, y, r, fill):
        self.add(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}"/>')

    def field(self, x, y, w, value, h=24, hot=False, ph=None):
        self.rect(x, y, w, h, DEEP, BLUE if hot else LINE, 3)
        if value:
            self.text(x + 8, y + h / 2 + 5, value + ('█' if hot else ''), BRIGHT)
        elif ph:
            self.text(x + 8, y + h / 2 + 5, ph, '#4b5866')

    def button(self, x, y, w, label, kind='plain', h=26):
        fill, stroke, col = {'ok': ('#2f6f4f', GREEN, '#ffffff'), 'plain': ('#1d2733', LINE, TXT),
                             'off': ('#161c24', '#2a3441', '#4b5866'), 'stop': ('#6b2b2b', RED, '#ffffff'),
                             'hot': ('#2b4a6b', BLUE, '#ffffff')}[kind]
        self.rect(x, y, w, h, fill, stroke, 4)
        self.text(x + w / 2, y + h / 2 + 5, label, col, anchor='middle', bold=(kind in ('ok', 'hot', 'stop')))

    def dialog(self, x, y, w, h, title, hint='Esc closes'):
        self.add('<g filter="url(#sh)">')
        self.rect(x, y, w, h, '#1b2330', BLUE, 6, 2)
        self.rect(x + 1, y + 1, w - 2, 30, '#2b4a6b', rx=5)
        self.text(x + 14, y + 21, title, '#ffffff', bold=True)
        self.text(x + w - 14, y + 21, hint, '#cfe3f5', anchor='end')
        self.add('</g>')

    def popup(self, x, y, w, h):
        self.add('<g filter="url(#sh)">')
        self.rect(x, y, w, h, '#1b2330', BLUE, 4, 1)
        self.add('</g>')

    def code(self, x, y, s, lang='eve'):
        pats = {
            'eve': r'(#.*$|\*\*.*$)|("[^"]*")|(\b\d+(?:\.\d+)?\b)|(\b(?:%s)\b)' % EVE_KW,
            'sql': r'(--.*$)|(\'[^\']*\')|(\b\d+(?:\.\d+)?\b)|(\b(?:select|from|where|group|by|order|join|on|as|and|or|not|sum|count|insert|into|values|create|table)\b)',
            'js': r'(//.*$)|("[^"]*"|\'[^\']*\'|`[^`]*`)|(\b\d+(?:\.\d+)?\b)|(\b(?:const|let|var|function|return|if|else|for|of|import|export|from|async|await|new|class)\b)',
            'html': r'(<!--.*-->)|("[^"]*")|(\b\d+\b)|(</?[a-zA-Z0-9]+|/?>)',
            'css': r'(/\*.*\*/)|("[^"]*")|(\b\d+(?:\.\d+)?(?:px|em|rem|%%)?\b)|([.#]?[a-z-]+(?=\s*[{:]))',
            'md': r'(^\s*#+ .*$)|(`[^`]*`)|(\*\*[^*]+\*\*)|(^\s*[-*] )',
            'json': r'(\b__none__\b)|("[^"]*")|(\b\d+(?:\.\d+)?\b)|(\b(?:true|false|null)\b)',
        }
        out, pos = [], 0
        for m in re.finditer(pats[lang], s):
            if m.start() > pos:
                out.append((s[pos:m.start()], TXT))
            col = COM if m.group(1) else STR if m.group(2) else NUM if m.group(3) else KW
            if lang in ('html', 'css') and m.group(4):
                col = TYPE if lang == 'html' else FN
            if lang == 'md' and m.group(0).lstrip().startswith('#'):
                col = BLUE
            out.append((m.group(0), col))
            pos = m.end()
        if pos < len(s):
            out.append((s[pos:], TXT))
        spans = ''.join(f'<tspan fill="{c}">{escape(t)}</tspan>' for t, c in out)
        self.add(f'<text x="{x}" y="{y}" xml:space="preserve">{spans}</text>')

    def save(self, name):
        head = (f'<?xml version="1.0" encoding="UTF-8"?>\n<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" '
                f'height="{self.h}" viewBox="0 0 {self.w} {self.h}" font-family="Consolas, \'Courier New\', monospace" '
                f'font-size="13">\n<title>{escape(self.title)}</title>\n<defs>'
                '<marker id="arr" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto">'
                '<path d="M0,0 L8,4 L0,8 z" fill="#8fa3b8"/></marker>'
                '<filter id="sh" x="-5%" y="-5%" width="110%" height="115%">'
                '<feDropShadow dx="3" dy="4" stdDeviation="3" flood-opacity="0.5"/></filter></defs>\n')
        open(f'eveux/design/{name}', 'w', encoding='utf-8', newline='').write(head + '\n'.join(self.p) + '\n</svg>\n')


# ------------------------------------------------------------------ the common window
TREE = [  # indent, glyph, label, colour, tag
    (0, '▾', 'sales_etl', BRIGHT, ''),
    (1, '▸', 'asp/', TXT, ''),
    (1, '▾', 'db/', TXT, ''),
    (2, '▤', 'local.db', AMBER, ''),
    (1, '▾', 'doc/', TXT, ''),
    (2, '¶', 'README.md', TXT, ''),
    (2, '▣', 'flow.svg', TXT, ''),
    (2, '▣', 'logo.png', TXT, ''),
    (2, '▶', 'intro.mp4', TXT, ''),
    (1, '▸', 'lib/', TXT, ''),
    (1, '▾', 'server/', TXT, 'srv'),
    (2, '◆', 'sales_load.eve', TXT, ''),
    (1, '▾', 'sql/', TXT, 'srv'),
    (2, '▤', 'orders.sql', TXT, ''),
    (1, '▾', 'web/', TXT, 'srv'),
    (2, '‹›', 'index.html', TXT, ''),
    (2, 'js', 'app.js', TXT, ''),
    (2, '{}', 'style.css', TXT, ''),
    (1, '·', 'eve.cfg', TXT, ''),
    (1, '·', 'eve.env', DIM, 'ign'),
    (1, '◆', 'sales_etl.eve', TXT, ''),
]
MENUS = ['File', 'Edit', 'View', 'Run', 'Debug', 'Database', 'Source', 'Tools', 'Window', 'Help']


# D-195: the tool bar follows the active file. Each entry is (label, width, role); a role is a button kind of Svg.button, or
# 'sep' (a gap), 'field' (a drop-down), 'text' (a note). The slot "Run" is one place whose meaning follows the file.
TOOLBARS = {
    'eve': [('▶ Run', 74, 'run'), ('■ Stop', 74, 'stop'), ('⏵ Debug', 84, 'dbg'), ('sep', 14, 'sep'), ('✓ Check', 82, 'use'),
            ('⚗ Test', 74, 'use'), ('sep', 14, 'sep'), ('⇪ Deploy…', 100, 'use')],
    'sql': [('local (SQLite) ▾', 150, 'field'), ('▶ Run', 74, 'ok'), ('▶▶ Script', 90, 'plain'), ('Explain', 74, 'plain'), ('sep', 14, 'sep'),
            ('Commit', 74, 'off'), ('Rollback', 82, 'off'), ('transaction: none', 140, 'text')],
    'db': [('Describe', 84, 'plain'), ('Structure…', 96, 'plain'), ('sep', 14, 'sep'), ('Import…', 78, 'plain'), ('Export…', 78, 'plain'),
           ('sep', 14, 'sep'), ('⟳ Refresh', 90, 'plain'), ('read only', 80, 'text')],
    'data': [('Grid', 60, 'hot'), ('Text', 60, 'plain'), ('sep', 14, 'sep'), ('filter ▾', 200, 'field'), ('sep', 14, 'sep'),
             ('Load into table…', 130, 'plain'), ('Save as…', 84, 'plain')],
    'doc': [('Source', 70, 'plain'), ('Split', 64, 'hot'), ('Preview', 74, 'plain'), ('sep', 14, 'sep'), ('Open in browser', 124, 'plain'),
            ('Hints', 64, 'plain')],
    'image': [('−', 36, 'plain'), ('100%', 64, 'plain'), ('+', 36, 'plain'), ('Fit', 52, 'hot'), ('sep', 14, 'sep'), ('Rotate', 72, 'plain'),
              ('Copy', 64, 'plain'), ('1200 × 630', 90, 'text')],
    'media': [('⏮', 40, 'plain'), ('▶ Play', 74, 'hot'), ('⏭', 40, 'plain'), ('sep', 14, 'sep'), ('🔊 80%', 80, 'plain'), ('1×', 48, 'plain'),
              ('sep', 14, 'sep'), ('00:12 / 03:48', 110, 'text')],
}


def toolbar_strip(svg, x, y, w, kind, state='idle'):
    """One tool bar: the buttons of a file kind. For an Eve file the state (idle, run, debug) turns buttons on and off, and the
    step buttons appear only while debugging, so the bar never shows a button that cannot be used."""
    svg.rect(x, y, w, 36, PANEL)
    svg.line(x, y + 36, x + w, y + 36)
    bx = x + 11
    items = list(TOOLBARS[kind])
    if kind == 'eve' and state == 'debug':
        at = [i for i, it in enumerate(items) if it[2] == 'sep'][0]
        items[at:at] = [(lab, 64, 'step') for lab in ('↷ Over', '↓ Into', '↑ Out', '⏩ Go')]
    for lab, wd, role in items:
        if role == 'sep':
            bx += wd
            continue
        if role == 'text':
            svg.text(bx, y + 23, lab, DIM)
        elif role == 'field':
            svg.field(bx, y + 6, wd, lab, 24)
        else:
            if kind == 'eve':
                look = {'run': 'ok' if state == 'idle' else 'off', 'stop': 'stop' if state != 'idle' else 'off',
                        'dbg': 'plain' if state == 'idle' else 'off', 'step': 'hot',
                        'use': 'off' if state == 'debug' else 'plain'}[role]
            else:
                look = role
            svg.button(bx, y + 5, wd, lab, look)
        bx += wd + 6
    svg.text(x + w - 56, y + 23, '⌕', TXT, anchor='end', size=16)
    svg.text(x + w - 20, y + 23, '⚙', TXT, anchor='end', size=16)


KIND_OF_LANG = {'Eve': 'eve', 'SQL': 'sql', 'SQLite': 'db', 'Markdown': 'doc', 'HTML': 'doc', 'PNG': 'image', 'MP4': 'media'}


def window(svg, project='sales_etl', machine='local', menu_open=None, toolbar='idle', state=('Ready', GREEN),
           pos='Ln 8, Col 12', lang='Eve', check=('check ok', GREEN), kind=None):
    """The frame of the window: title bar, menu bar, tool bar (it follows the file, D-195), status bar."""
    svg.rect(X0, Y0, WW, WH, PANEL, LINE, 8, 2)
    svg.rect(X0 + 1, Y0 + 1, WW - 2, 30, BAR, rx=7)
    svg.rect(X0 + 10, Y0 + 8, 16, 16, BLUE, rx=3)
    svg.text(X0 + 14, Y0 + 21, 'e', '#ffffff', bold=True)
    svg.text(X0 + 36, Y0 + 21, f'eveux  —  {project}', BRIGHT, bold=True)
    for i, g in enumerate(('—', '☐', '✕')):
        svg.text(X0 + WW - 100 + i * 32, Y0 + 21, g, '#ff7b72' if g == '✕' else TXT, anchor='middle')
    # menu bar
    my = Y0 + 31
    svg.rect(X0 + 1, my, WW - 2, 26, BAR2)
    x = X0 + 12
    for m in MENUS:
        wd = 14 + len(m) * 8
        if m == menu_open:
            svg.rect(x - 6, my + 2, wd, 22, '#2b4a6b', rx=3)
        svg.text(x, my + 18, m, '#ffffff' if m == menu_open else TXT)
        x += wd + 4
    # tool bar
    ty = my + 26
    svg.rect(X0 + 1, ty, WW - 2, 36, PANEL)
    svg.line(X0 + 1, ty + 36, X0 + WW - 1, ty + 36)
    toolbar_strip(svg, X0 + 1, ty, WW - 2, kind or KIND_OF_LANG.get(lang, 'eve'), toolbar)
    # status bar
    sy = Y0 + WH - 26
    svg.rect(X0 + 1, sy, WW - 2, 25, BAR, rx=6)
    svg.circle(X0 + 16, sy + 13, 5, state[1])
    svg.text(X0 + 28, sy + 17, f'{state[0]}: {machine}', BRIGHT)
    svg.text(X0 + 330, sy + 17, check[0], check[1])
    svg.text(X0 + 560, sy + 17, 'Eve 0.0.6', DIM)
    svg.text(X0 + 700, sy + 17, 'git: master ✓', DIM)
    svg.text(X0 + WW - 20, sy + 17, f'{pos}   {lang}   LF   UTF-8   2 spaces', TXT, anchor='end')


def explorer(svg, sel=None, items=TREE, title='Explorer', find=''):
    svg.rect(X0, BODY_Y, EXP_W, BODY_H, DEEP, LINE)
    svg.text(X0 + 10, BODY_Y + 18, title, BRIGHT, bold=True)
    svg.text(X0 + EXP_W - 12, BODY_Y + 18, '⟳  ⊞  ⊟', DIM, anchor='end')
    svg.line(X0, BODY_Y + 26, X0 + EXP_W, BODY_Y + 26)
    if find:
        svg.field(X0 + 8, BODY_Y + 32, EXP_W - 16, find, 22, True)
    base = BODY_Y + 66 if find else BODY_Y + 46
    for i, (ind, gl, label, col, tag) in enumerate(items):
        y = base + i * 20
        if label == sel:
            svg.rect(X0 + 1, y - 14, EXP_W - 2, 19, '#2b4a6b')
            col = '#ffffff'
        svg.text(X0 + 10 + ind * 16, y, gl, DIM)
        svg.text(X0 + 30 + ind * 16, y, label, col)
        if tag == 'srv':
            svg.circle(X0 + EXP_W - 16, y - 4, 4, BLUE)
        if tag == 'ign':
            svg.text(X0 + EXP_W - 50, y, 'ignored', DIM)
    svg.circle(X0 + 14, BODY_Y + BODY_H - 16, 4, BLUE)
    svg.text(X0 + 26, BODY_Y + BODY_H - 12, 'server side: sent by deploy', DIM)


def tabs(svg, names, active, x=None, y=None, w=None):
    x = ED_X if x is None else x
    y = BODY_Y if y is None else y
    w = ED_W if w is None else w
    svg.rect(x, y, w, 28, BAR2)
    cx = x + 4
    for i, n in enumerate(names):
        wd = 30 + len(n) * 8
        on = i == active
        svg.rect(cx, y + 3, wd, 25, '#1b2330' if on else BAR2, LINE if on else None, 3)
        if on:
            svg.line(cx + 1, y + 3, cx + wd - 1, y + 3, BLUE)
        svg.text(cx + 10, y + 20, n, BRIGHT if on else DIM)
        svg.text(cx + wd - 14, y + 20, '×', DIM)
        cx += wd + 4


def editor(svg, lines, lang='eve', first=1, bps=(), current=None, x=None, y=None, w=None, h=None, hot=None):
    x = ED_X if x is None else x
    y = (BODY_Y + 28) if y is None else y
    w = ED_W if w is None else w
    h = (BODY_H - 28 - BOT_H) if h is None else h
    svg.rect(x, y, w, h, DEEP, LINE)
    svg.rect(x, y, 56, h, '#10161d')
    for i, ln in enumerate(lines):
        ly = y + 20 + i * 19
        n = first + i
        if n == current:
            svg.rect(x + 1, ly - 14, w - 2, 19, '#2a3a1f')
            svg.text(x + 8, ly, '▶', AMBER)
        if n in bps:
            svg.circle(x + 12, ly - 4, 5, RED)
        svg.text(x + 48, ly, str(n), DIM, anchor='end')
        svg.code(x + 66, ly, ln, lang)
    if hot:
        hy = y + 20 + (hot[0] - first) * 19
        svg.rect(x + 66 + hot[1] * 7.8, hy - 14, 2, 18, BRIGHT)
    # minimap and scroll bar
    svg.rect(x + w - 14, y, 14, h, '#10161d')
    svg.rect(x + w - 12, y + 6, 10, 70, '#2b3644', rx=3)


def bottom(svg, names, active, lines=(), x=None, w=None):
    x = ED_X if x is None else x
    w = ED_W if w is None else w
    y = BODY_Y + BODY_H - BOT_H
    svg.rect(x, y, w, 26, BAR2)
    cx = x + 6
    for i, n in enumerate(names):
        wd = 24 + len(n) * 8
        on = i == active
        if on:
            svg.rect(cx, y + 2, wd, 24, '#1b2330', LINE, 3)
        svg.text(cx + 10, y + 18, n, BRIGHT if on else DIM)
        cx += wd + 4
    svg.rect(x, y + 26, w, BOT_H - 26, DEEP, LINE)
    for i, (t, col) in enumerate(lines):
        svg.text(x + 12, y + 46 + i * 18, t, col)


def side(svg, title, sections):
    svg.rect(SIDE_X, BODY_Y, SIDE_W, BODY_H, PANEL, LINE)
    y = BODY_Y
    for name, rows, hh in sections:
        svg.rect(SIDE_X, y, SIDE_W, 24, BAR2)
        svg.text(SIDE_X + 10, y + 17, name, BRIGHT, bold=True)
        for i, (t, col) in enumerate(rows):
            svg.text(SIDE_X + 14, y + 44 + i * 19, t, col)
        y += hh
        svg.line(SIDE_X, y, SIDE_X + SIDE_W, y)


ESALES = [
    '# sales load: read the orders file and load the table',
    'primary aspect sales_load is',
    '  from lib use (money);',
    '  class Order = {id: Integer, region: String, amount: Decimal} <: Record;',
    '',
    '  process main is',
    '    new total := 0.0;',
    '    for r in csv.read!(:Order)("data/orders.csv") do',
    '      let total += r.amount;           ** sum the amounts',
    '    done;',
    '    print "total: {money.format(total)}";',
    '  recover',
    '    print "failed: {$error.message}";',
    '  return;',
    'end sales_load;',
]
OUTLINE = [('▾ sales_load (aspect)', BRIGHT), ('   Order (class)', TXT), ('   main (process)', TXT), ('▸ imports: money', DIM)]
PROBLEMS = [('✓ no problems in this file', GREEN)]


def main_screen():
    s = Svg('eveux: the main window', 'explorer, tabbed editor with live checks, outline, bottom panel, status bar. The check and the outline come from the compiler linked into the program.')
    window(s)
    explorer(s, 'sales_load.eve')
    tabs(s, ['sales_load.eve', 'orders.sql', 'index.html', 'README.md'], 0)
    editor(s, ESALES, bps=(8,), hot=(9, 24))
    bottom(s, ['Console', 'Output', 'Problems', 'Watch', 'Breaks', 'Log'], 0,
           [('eve:> run server/sales_load.eve', GREEN), ('total: 1,240.50 EUR', TXT), ('eve:> ', TXT)])
    side(s, '', [('Outline', OUTLINE, 150), ('Problems', PROBLEMS, 110), ('Docs (hover)', [('csv.read!(:Row)(path)', FN), ('a stream of records', DIM)], 130),
                 ('Jobs', [('sales_load  daily 02:00', TXT), ('last: ok  3.1 s', GREEN)], 150)])
    s.save('design.svg')


def debug_screen():
    s = Svg('eveux: debugging', 'paused at a breakpoint: yellow line, Run off, the step buttons on; Variables, Watch and Call stack at the right.')
    window(s, toolbar='debug', state=('Paused', AMBER), pos='Ln 9, Col 5')
    explorer(s, 'sales_load.eve')
    tabs(s, ['sales_load.eve', 'orders.sql'], 0)
    editor(s, ESALES, bps=(8,), current=9)
    bottom(s, ['Console', 'Output', 'Problems', 'Watch', 'Breaks', 'Log'], 3,
           [('total > 1000                        False', TXT), ('r.region = "north"             True', TXT), ('(Add watch ...)', DIM)])
    side(s, '', [('Variables', [('▾ globals', BRIGHT), ('   total   0.0', TXT), ('▾ locals (main)', BRIGHT), ('   r   Order', TXT), ('     id 7  region "north"', DIM), ('     amount 120.50', DIM)], 190),
                 ('Call stack', [('main      line 9', AMBER), ('sales_load  line 1', TXT)], 100),
                 ('Breakpoints', [('● sales_load.eve:8', RED), ('○ orders.sql:3 (disabled)', DIM)], 100)])
    s.save('design-debug.svg')


def md_screen():
    s = Svg('eveux: Markdown preview', 'Source, Split or Preview; the preview scrolls with the cursor and follows the links of the project.')
    window(s, lang='Markdown', pos='Ln 5, Col 1', check=('3 headings', DIM))
    explorer(s, 'README.md')
    tabs(s, ['sales_load.eve', 'README.md'], 1)
    hw = ED_W // 2
    s.rect(ED_X, BODY_Y + 28, ED_W, 30, PANEL, LINE)
    for i, (lab, k) in enumerate((('Source', 'plain'), ('Split', 'hot'), ('Preview', 'plain'))):
        s.button(ED_X + 8 + i * 84, BODY_Y + 30, 78, lab, k, 24)
    s.text(ED_X + ED_W - 12, BODY_Y + 48, 'rendered by eveux', DIM, anchor='end')
    md = ['# Sales ETL', '', 'Loads the orders of the day and **checks** them.', '',
          '- read `data/orders.csv`', '- sum by region', '- write `out/report.json`', '',
          '```eve', 'new total := 0.0;', '```', '', '| region | total |', '|---|---|', '| north | 120.50 |']
    editor(s, md, lang='md', x=ED_X, y=BODY_Y + 58, w=hw, h=BODY_H - 58 - BOT_H, current=None)
    rx, ry, rw, rh = ED_X + hw, BODY_Y + 58, ED_W - hw, BODY_H - 58 - BOT_H
    s.rect(rx, ry, rw, rh, '#f4f6f8', LINE)
    s.text(rx + 20, ry + 40, 'Sales ETL', '#1b2330', size=26, bold=True)
    s.line(rx + 20, ry + 50, rx + rw - 20, ry + 50, '#c8d0d8')
    s.text(rx + 20, ry + 80, 'Loads the orders of the day and ', '#2b3644', size=14)
    s.text(rx + 290, ry + 80, 'checks', '#2b3644', size=14, bold=True)
    s.text(rx + 350, ry + 80, 'them.', '#2b3644', size=14)
    for i, t in enumerate(('read data/orders.csv', 'sum by region', 'write out/report.json')):
        s.circle(rx + 30, ry + 112 + i * 24, 3, '#2b3644')
        s.text(rx + 44, ry + 117 + i * 24, t, '#2b3644', size=14)
    s.rect(rx + 20, ry + 190, rw - 40, 40, '#e3e8ee', '#c8d0d8', 3)
    s.text(rx + 32, ry + 215, 'new total := 0.0;', '#7a3e9d')
    s.rect(rx + 20, ry + 250, 240, 24, '#dde3ea', '#b8c2cc')
    s.text(rx + 30, ry + 267, 'region', '#1b2330', bold=True); s.text(rx + 150, ry + 267, 'total', '#1b2330', bold=True)
    s.rect(rx + 20, ry + 274, 240, 24, '#f4f6f8', '#b8c2cc')
    s.text(rx + 30, ry + 291, 'north', '#2b3644'); s.text(rx + 150, ry + 291, '120.50', '#2b3644')
    bottom(s, ['Console', 'Output', 'Problems', 'Log'], 1, [('(no output)', DIM)])
    side(s, '', [('Outline', [('▾ Sales ETL', BRIGHT), ('   Install', TXT), ('   Usage', TXT)], 130),
                 ('Links', [('data/orders.csv  ✓', GREEN), ('out/report.json  ✗ missing', RED)], 110)])
    s.save('design-preview-md.svg')


def html_screen():
    s = Svg('eveux: HTML preview', 'a page of the project drawn by the HTML renderer of eveux (a subset, no scripts); Open in browser shows the real thing.')
    window(s, lang='HTML', pos='Ln 4, Col 18', check=('2 hints', AMBER))
    explorer(s, 'index.html')
    tabs(s, ['sales_load.eve', 'index.html', 'app.js', 'style.css'], 1)
    hw = ED_W // 2
    s.rect(ED_X, BODY_Y + 28, ED_W, 30, PANEL, LINE)
    for i, (lab, k) in enumerate((('Source', 'plain'), ('Split', 'hot'), ('Preview', 'plain'))):
        s.button(ED_X + 8 + i * 84, BODY_Y + 30, 78, lab, k, 24)
    s.button(ED_X + ED_W - 190, BODY_Y + 30, 178, 'Open in browser ⤢', 'plain', 24)
    html = ['<!doctype html>', '<html lang="en">', '<head><title>Sales</title>', '  <link rel="stylesheet" href="style.css">',
            '</head>', '<body>', '  <h1 id="title">Daily sales</h1>', '  <p class="note">Updated 02:00</p>',
            '  <button id="reload">Reload</button>', '  <script src="app.js"></script>', '</body>', '</html>']
    editor(s, html, lang='html', x=ED_X, y=BODY_Y + 58, w=hw, h=BODY_H - 58 - BOT_H)
    rx, ry, rw, rh = ED_X + hw, BODY_Y + 58, ED_W - hw, BODY_H - 58 - BOT_H
    s.rect(rx, ry, rw, 28, BAR2, LINE)
    s.field(rx + 8, ry + 2, rw - 200, 'file:///sales_etl/web/index.html', 24)
    s.text(rx + rw - 180, ry + 19, '⟳ reload   📱 360   🖥 1280', TXT)
    s.rect(rx, ry + 28, rw, rh - 28, '#ffffff', LINE)
    s.text(rx + 24, ry + 80, 'Daily sales', '#202830', size=28, bold=True)
    s.text(rx + 24, ry + 110, 'Updated 02:00', '#6b7682', size=14)
    s.rect(rx + 24, ry + 130, 90, 28, '#e8edf2', '#9aa7b4', 4)
    s.text(rx + 69, ry + 149, 'Reload', '#202830', anchor='middle')
    s.rect(rx + 24, ry + rh - 70, rw - 48, 26, '#fff4d6', '#e0b341', 3)
    s.text(rx + 34, ry + rh - 52, 'Preview limits: no scripts run; CSS subset; images and fonts of the project', '#7a5b00', size=12)
    bottom(s, ['Console', 'Output', 'Problems', 'Log'], 2,
           [('index.html:9  hint: button has no type attribute', AMBER), ('app.js: referenced script found', GREEN)])
    side(s, '', [('Outline', [('▾ html', BRIGHT), ('   head', TXT), ('   body', TXT), ('     h1#title', DIM), ('     p.note', DIM), ('     button#reload', DIM)], 180),
                 ('Preview', [('Engine: eveux HTML subset', TXT), ('Scripts: off', DIM), ('Width: fit', DIM)], 110)])
    s.save('design-preview-html.svg')


def image_screen():
    s = Svg('eveux: image and SVG viewer', 'PNG, JPEG, GIF, BMP and SVG open in a viewer tab: fit, zoom, pixel info; an SVG can also be edited as source.')
    window(s, lang='PNG', pos='1200 × 630', check=('84 KB', DIM))
    explorer(s, 'logo.png')
    tabs(s, ['sales_load.eve', 'logo.png', 'flow.svg'], 1)
    x, y, w, h = ED_X, BODY_Y + 28, ED_W, BODY_H - 28
    s.rect(x, y, w, 30, PANEL, LINE)
    for i, lab in enumerate(('Fit', '100%', '＋', '－', '⟲ rotate', '▦ grid')):
        s.button(x + 8 + i * 74, y + 3, 68, lab, 'hot' if i == 0 else 'plain', 24)
    s.text(x + w - 12, y + 20, 'zoom 62%', DIM, anchor='end')
    s.rect(x, y + 30, w, h - 30, '#1a2028', LINE)
    for r in range(16):
        for c in range(30):
            if (r + c) % 2 == 0:
                s.rect(x + 100 + c * 20, y + 60 + r * 20, 20, 20, '#2a323c')
    s.rect(x + 160, y + 120, 480, 252, '#2b4a6b', BLUE, 4)
    s.text(x + 400, y + 262, 'logo.png', '#ffffff', anchor='middle', size=30, bold=True)
    s.text(x + 400, y + 292, '1200 × 630', '#cfe3f5', anchor='middle')
    side(s, '', [('Info', [('logo.png', BRIGHT), ('PNG  1200 × 630', TXT), ('84 KB', TXT), ('RGBA 8 bit', DIM), ('modified 2026-10-12', DIM)], 150),
                 ('Pixel', [('x 412  y 138', TXT), ('#2B4A6B  alpha 255', DIM)], 100),
                 ('Actions', [('Reveal in folder', FN), ('Copy path', FN), ('Insert in Markdown  ![](...)', FN)], 110)])
    bottom(s, ['Console', 'Output', 'Log'], 1, [('(no output)', DIM)])
    s.save('design-preview-image.svg')


def media_screen():
    s = Svg('eveux: audio and video player', 'a player tab for the formats the system can decode; no editing. Where a format is not supported the file card offers Open with the system.')
    window(s, lang='MP4', pos='00:12 / 03:48', check=('1920 × 1080, H.264', DIM))
    explorer(s, 'intro.mp4')
    tabs(s, ['sales_load.eve', 'intro.mp4', 'theme.mp3'], 1)
    x, y, w, h = ED_X, BODY_Y + 28, ED_W, BODY_H - 28
    s.rect(x, y, w, h - 110, '#05080b', LINE)
    s.rect(x + 100, y + 30, w - 200, h - 190, '#0f1620', LINE)
    s.circle(x + w / 2, y + (h - 110) / 2, 36, '#2b4a6b')
    s.text(x + w / 2 + 4, y + (h - 110) / 2 + 12, '▶', '#ffffff', size=32, anchor='middle')
    cy = y + h - 100
    s.rect(x, cy, w, 100, PANEL, LINE)
    s.rect(x + 20, cy + 18, w - 40, 6, '#2a3441', rx=3)
    s.rect(x + 20, cy + 18, 60, 6, BLUE, rx=3)
    s.circle(x + 80, cy + 21, 7, BRIGHT)
    for i, lab in enumerate(('⏮', '⏪', '⏸', '⏩', '⏭')):
        s.text(x + 40 + i * 40, cy + 62, lab, BRIGHT, size=20)
    s.text(x + 260, cy + 60, '00:12 / 03:48', TXT)
    s.text(x + 420, cy + 60, '1.0×  ▾', TXT)
    s.text(x + 520, cy + 60, '🔊', TXT)
    s.rect(x + 548, cy + 54, 90, 6, '#2a3441', rx=3); s.rect(x + 548, cy + 54, 60, 6, GREEN, rx=3)
    s.text(x + w - 20, cy + 60, '⛶ fullscreen', TXT, anchor='end')
    side(s, '', [('Media', [('intro.mp4', BRIGHT), ('video H.264  1920 × 1080', TXT), ('audio AAC  stereo', TXT), ('3 min 48 s   41 MB', DIM)], 150),
                 ('Chapters', [('00:00  Title', TXT), ('00:40  The load', TXT), ('02:10  Results', TXT)], 110),
                 ('Note', [('decoded by the system', DIM), ('(Media Foundation on', DIM), ('Windows)', DIM)], 100)])
    bottom(s, ['Console', 'Output', 'Log'], 1, [('(no output)', DIM)])
    s.save('design-preview-media.svg')


def db_screen():
    s = Svg('eveux: a database in tabs', 'a database file in the tree opens its tables; a double click opens the data in a grid with paging, sort and filter.')
    window(s, lang='SQLite', pos='orders: 12,408 rows', check=('read only', DIM))
    explorer(s, 'local.db')
    tabs(s, ['local.db', 'orders'], 1)
    x, y, w, h = ED_X, BODY_Y + 28, ED_W, BODY_H - 28
    s.rect(x, y, w, 32, PANEL, LINE)
    s.field(x + 8, y + 4, 220, '', 24, ph='filter: amount > 100')
    for i, lab in enumerate(('SQL', 'Structure', 'Export', '⟳')):
        s.button(x + 240 + i * 90, y + 3, 84, lab, 'plain', 26)
    s.text(x + w - 12, y + 21, 'rows 1–100 of 12,408   ◀ 1 ▶', TXT, anchor='end')
    cols = [('id', 'Integer', 70), ('region', 'String', 150), ('amount', 'Decimal', 120), ('created', 'Instant', 230), ('paid', 'Logic', 80)]
    gx, gy = x, y + 32
    s.rect(gx, gy, w, h - 32 - BOT_H + 130, DEEP, LINE)
    cx = gx
    for nm, ty, wd in cols:
        s.rect(cx, gy, wd, 36, BAR2, LINE)
        s.text(cx + 8, gy + 15, nm, BRIGHT, bold=True)
        s.text(cx + 8, gy + 30, ty, TYPE, size=11)
        cx += wd
    rows = [('1', 'north', '120.50', '2026-10-01T08:14:02Z', 'True'), ('2', 'south', '88.00', '2026-10-01T08:20:41Z', 'False'),
            ('3', 'north', '310.25', '2026-10-01T09:03:12Z', 'True'), ('4', 'east', '41.99', '2026-10-01T09:11:55Z', 'True'),
            ('5', 'west', '—', '2026-10-01T09:30:00Z', 'False'), ('6', 'north', '75.00', '2026-10-02T07:55:20Z', 'True')]
    for r, row in enumerate(rows):
        cx = gx
        ry = gy + 36 + r * 26
        if r == 2:
            s.rect(gx, ry, sum(c[2] for c in cols), 26, '#2b4a6b')
        for (nm, ty, wd), val in zip(cols, row):
            col = DIM if val == '—' else (NUM if ty in ('Integer', 'Decimal') else TXT)
            s.text(cx + (wd - 10 if ty in ('Integer', 'Decimal') else 8), ry + 18, val, col, anchor='end' if ty in ('Integer', 'Decimal') else None)
            s.line(cx, ry + 26, cx + wd, ry + 26, '#1d2733')
            cx += wd
    side(s, '', [('Tables', [('▾ local.db', BRIGHT), ('   customers   2,310', TXT), ('   orders     12,408', AMBER), ('   products      188', TXT), ('   v_totals  (view)', DIM)], 180),
                 ('Columns of orders', [('id  Integer  key', TXT), ('region  String', TXT), ('amount  Decimal(10,2)', TXT), ('created  Instant', TXT), ('paid  Logic', TXT)], 160)])
    bottom(s, ['Console', 'Output', 'Log'], 1, [('select * from orders where amount > 100 limit 100   (4 ms)', DIM)])
    s.save('design-db.svg')


def sql_screen():
    s = Svg('eveux: SQL tab', 'the tool bar of a SQL file: Ctrl+Enter runs the statement under the cursor; the result grid shows Eve types; a statement that changes data waits for Commit or Rollback.')
    window(s, lang='SQL', pos='Ln 3, Col 31', check=('local.db', DIM))
    explorer(s, 'orders.sql')
    tabs(s, ['sales_load.eve', 'orders.sql'], 1)
    x, y, w = ED_X, BODY_Y + 28, ED_W
    sql = ['-- sales by region', 'select region, sum(amount) as total, count(*) as n',
           'from orders', 'where created >= \'2026-10-01\'', 'group by region', 'order by total desc;']
    editor(s, sql, lang='sql', x=x, y=y, w=w, h=192)
    gy = y + 192
    s.rect(x, gy, w, 28, BAR2, LINE)
    for i, lab in enumerate(('Results', 'Messages', 'Plan', 'History')):
        s.text(x + 14 + i * 90, gy + 19, lab, BRIGHT if i == 0 else DIM)
    cols = [('region', 'String', 200), ('total', 'Decimal', 180), ('n', 'Integer', 100)]
    s.rect(x, gy + 28, w, 300, DEEP, LINE)
    cx = x
    for nm, ty, wd in cols:
        s.rect(cx, gy + 28, wd, 36, BAR2, LINE)
        s.text(cx + 8, gy + 43, nm, BRIGHT, bold=True)
        s.text(cx + 8, gy + 58, ty, TYPE, size=11)
        cx += wd
    for r, row in enumerate((('north', '1,240.50', '31'), ('south', '988.00', '27'), ('east', '455.99', '12'))):
        cx = x
        for (nm, ty, wd), val in zip(cols, row):
            s.text(cx + (wd - 10 if ty != 'String' else 8), gy + 84 + r * 26, val, NUM if ty != 'String' else TXT, anchor='end' if ty != 'String' else None)
            cx += wd
    s.text(x + 12, gy + 28 + 300 - 12, '3 rows, 4 ms   ·   copy as TSV  ·  export CSV, JSON, Eve DataSet', DIM)
    side(s, '', [('Connections', [('● local (SQLite)', GREEN), ('○ test (evedb://…)', TXT), ('○ prod (PostgreSQL)', TXT)], 120),
                 ('History', [('select region, sum…  ✓', TXT), ('update orders set…  rolled back', DIM)], 120)])
    bottom(s, ['Console', 'Output', 'Log'], 2, [('(no output)', DIM)])
    s.save('design-sql.svg')


def toolbar_screen():
    s = Svg('eveux: one tool bar that follows the file', 'The active tab decides the buttons. Run is one slot: F5 runs an Eve file in the local machine, Ctrl+Enter runs a SQL statement. Nothing that cannot be used is shown.')
    rows = [('Eve file', 'eve', 'idle', '.eve'), ('Eve file, running', 'eve', 'run', 'Stop is on, Run and Debug are off'),
            ('Eve file, debugging', 'eve', 'debug', 'the step buttons appear only here'), ('SQL file', 'sql', 'idle', '.sql: the connection, one Run, the transaction'),
            ('Database table', 'db', 'idle', 'a table of a SQLite file, read only'), ('Data file', 'data', 'idle', '.csv .tsv .json .dbf'),
            ('Document', 'doc', 'idle', '.md .html: Source, Split or Preview'), ('Image', 'image', 'idle', '.png .jpg .gif .svg'),
            ('Audio and video', 'media', 'idle', '.mp4 .mp3 .wav')]
    y = 66
    for title, kind, state, note in rows:
        s.text(20, y + 14, title, BRIGHT, bold=True)
        s.text(240, y + 14, note, DIM, size=12)
        toolbar_strip(s, 20, y + 22, 1360, kind, state)
        y += 70
    s.text(20, y + 14, 'Not in the bar: a machine selector (code is local; remote machines are in Tools > Machines and in the Deploy dialog), a search field (Ctrl+Shift+F, the ⌕ icon), a second Run (SQL had its own).', TXT, size=12)
    s.save('design-toolbar.svg')


def structure_screen():
    s = Svg('eveux: the structure dialog', 'a grid with headers and bordered cells; the type is chosen from a list; a date or time default has a calendar; the changes are applied as SQL.')
    window(s, lang='SQLite', pos='orders', check=('read only', DIM))
    explorer(s, 'local.db')
    tabs(s, ['local.db', 'orders'], 1)
    x, y, w, h = 300, 190, 780, 420
    s.dialog(x, y, w, h, 'Structure of orders', 'Esc closes')
    heads = [('Name', 180), ('Type', 150), ('Null', 70), ('Default', 180), ('Key', 60)]
    cx = x + 16
    for hd, wd in heads:
        s.rect(cx, y + 46, wd, 26, BAR2, LINE)
        s.text(cx + 8, y + 64, hd, BRIGHT, bold=True)
        cx += wd
    rows = [('id', 'Integer', '', '', '🔑'), ('region', 'String', '', "''", ''), ('amount', 'Decimal(10,2)', '✓', '0', ''),
            ('created', 'Instant  ▾', '', 'now', ''), ('paid', 'Logic', '', 'False', '')]
    for r, row in enumerate(rows):
        cx = x + 16
        for (hd, wd), val in zip(heads, row):
            s.rect(cx, y + 72 + r * 28, wd, 28, DEEP, '#2a3441')
            s.text(cx + 8, y + 91 + r * 28, val, TXT)
            cx += wd
    s.popup(x + 16 + 180 + 150 + 70, y + 72 + 3 * 28 + 4, 210, 150)
    s.text(x + 16 + 400 + 14, y + 72 + 3 * 28 + 24, '‹  October 2026  ›', BRIGHT)
    s.text(x + 16 + 400 + 14, y + 72 + 3 * 28 + 46, 'Mo Tu We Th Fr Sa Su', DIM, size=11)
    s.text(x + 16 + 400 + 14, y + 72 + 3 * 28 + 66, ' 5  6  7  8  9 10 11', TXT, size=11)
    s.text(x + 16 + 400 + 14, y + 72 + 3 * 28 + 86, '12 13 14 15 16 17 18', TXT, size=11)
    s.rect(x + 16 + 400 + 34, y + 72 + 3 * 28 + 92, 22, 16, '#2b4a6b')
    s.text(x + 16 + 400 + 14, y + 72 + 3 * 28 + 106, '19 20 21 22 23 24 25', TXT, size=11)
    s.text(x + 16, y + h - 74, 'alter table orders add column note String;', STR)
    s.button(x + w - 330, y + h - 44, 100, 'Add field', 'plain')
    s.button(x + w - 220, y + h - 44, 100, 'Apply', 'ok')
    s.button(x + w - 110, y + h - 44, 96, 'Cancel', 'plain')
    s.save('design-structure.svg')


def git_screen():
    s = Svg('eveux: source control', 'status, side-by-side diff, stage, commit and branches; every action is the git program run in the project folder; merge conflicts are left to your Git tool.')
    window(s, lang='Eve', pos='Ln 9, Col 5', check=('2 changed', AMBER))
    explorer(s, 'sales_load.eve')
    tabs(s, ['sales_load.eve ↔ HEAD', 'orders.sql'], 0)
    x, y, w, h = ED_X, BODY_Y + 28, ED_W, BODY_H - 28 - BOT_H
    s.rect(x, y, w, 28, PANEL, LINE)
    s.text(x + 10, y + 19, 'Working tree', BRIGHT)
    s.text(x + w // 2 + 10, y + 19, 'HEAD (a1f3c9e  load orders)', DIM)
    s.rect(x, y + 28, w // 2, h - 28, DEEP, LINE)
    s.rect(x + w // 2, y + 28, w // 2, h - 28, DEEP, LINE)
    left = ['    new total := 0.0;', '    for r in csv.read!(:Order)("data/orders.csv") do',
            '      let total += r.amount;           ** sum', '    done;', '    print "total: {money.format(total)}";']
    right = ['    new total := 0.0;', '    for r in csv.read!(:Order)("orders.csv") do',
             '      let total += r.amount;', '    done;', '    print "total: {total}";']
    for i, (a, b) in enumerate(zip(left, right)):
        ly = y + 28 + 22 + i * 19
        chg = a != b
        if chg:
            s.rect(x + 1, ly - 14, w // 2 - 2, 19, '#1f3a2a')
            s.rect(x + w // 2 + 1, ly - 14, w // 2 - 2, 19, '#40222a')
        s.code(x + 12, ly, a)
        s.code(x + w // 2 + 12, ly, b)
        if chg:
            s.text(x + w // 2 - 14, ly, '+', GREEN, anchor='end')
            s.text(x + w - 14, ly, '−', RED, anchor='end')
    bottom(s, ['Console', 'Output', 'Problems', 'Log'], 0, [('git status --porcelain=v2     (2 files)', DIM), ('git diff -- server/sales_load.eve', DIM)])
    side(s, '', [('Source control   ⎇ master', [('Changes (2)', BRIGHT), ('  M  server/sales_load.eve', AMBER), ('  M  web/index.html', AMBER), ('Staged (0)', DIM), ('Untracked (1)', BRIGHT), ('  ?  doc/notes.txt', DIM)], 200),
                 ('Commit', [('message:', DIM)], 70),
                 ('', [], 0)])
    s.field(SIDE_X + 12, BODY_Y + 200 + 38, SIDE_W - 24, 'load orders from data/', 24, True)
    s.button(SIDE_X + 12, BODY_Y + 200 + 70, 100, 'Stage all', 'plain')
    s.button(SIDE_X + 120, BODY_Y + 200 + 70, 150, 'Commit  Ctrl+Enter', 'ok')
    s.text(SIDE_X + 14, BODY_Y + 200 + 130, 'Branches:  master ✓   dev   release', TXT, size=12)
    s.text(SIDE_X + 14, BODY_Y + 200 + 150, 'History   Pull   Push (git remote)', FN, size=12)
    s.save('design-git.svg')


def deploy_screen():
    s = Svg('eveux: deploy', 'the server side of the project goes to a machine or to an evewp application: a diff against what is there, a check under the rules of the target, then an atomic switch.')
    window(s, pos='Ln 9, Col 5')
    explorer(s, 'sales_load.eve')
    tabs(s, ['sales_load.eve'], 0)
    editor(s, ESALES)
    x, y, w, h = 190, 150, 960, 590
    s.dialog(x, y, w, h, 'Deploy sales_etl', 'Esc closes')
    s.text(x + 18, y + 54, 'Target', DIM)
    s.field(x + 80, y + 38, 260, 'prod  (etl1.example.com:4042)', 26)
    s.text(x + 360, y + 54, '▾  application', DIM)
    s.field(x + 470, y + 38, 200, 'shop  (evewp)', 26)
    s.text(x + 690, y + 54, 'from', DIM)
    s.field(x + 730, y + 38, 200, 'master a1f3c9e  clean ✓', 26)
    s.rect(x + 14, y + 80, 600, 250, DEEP, LINE)
    s.text(x + 24, y + 100, 'Files', BRIGHT, bold=True)
    s.text(x + 596, y + 100, '3 changed · 1 added · 1 removed', DIM, anchor='end')
    for i, (st, nm, col, sz) in enumerate((('M', 'server/sales_load.eve', AMBER, '1.2 KB'), ('M', 'proc/load_orders.eve', AMBER, '0.8 KB'),
                                           ('M', 'web/index.html', AMBER, '0.5 KB'), ('A', 'web/app.js', GREEN, '2.1 KB'),
                                           ('D', 'web/old.css', RED, ''), (' ', '12 files unchanged', DIM, ''))):
        s.text(x + 24, y + 128 + i * 24, '☑' if st != ' ' else ' ', TXT)
        s.text(x + 48, y + 128 + i * 24, st, col, bold=True)
        s.text(x + 70, y + 128 + i * 24, nm, col if st == ' ' else TXT)
        s.text(x + 590, y + 128 + i * 24, sz, DIM, anchor='end')
    s.rect(x + 630, y + 80, 316, 250, DEEP, LINE)
    s.text(x + 642, y + 100, 'Checks on the target', BRIGHT, bold=True)
    for i, (t, c) in enumerate((('✓ compile: 5 files', GREEN), ('✓ capabilities: fs, net', GREEN), ('! 1 pending migration', AMBER),
                                ('   db migrate not run by deploy', DIM), ('✓ health path /healthz', GREEN))):
        s.text(x + 642, y + 128 + i * 24, t, c)
    s.rect(x + 14, y + 344, 600, 170, DEEP, LINE)
    s.text(x + 24, y + 364, 'Versions on prod', BRIGHT, bold=True)
    for i, (v, t, who, on) in enumerate((('43', 'a1f3c9e load orders', 'ana', ''), ('42', '77be10d fix totals', 'ana', 'active'),
                                         ('41', 'c9d0aa2 first release', 'bo', ''))):
        s.text(x + 24, y + 392 + i * 24, ('● ' if on else '  ') + 'v' + v, GREEN if on else TXT)
        s.text(x + 90, y + 392 + i * 24, t, TXT)
        s.text(x + 420, y + 392 + i * 24, who, DIM)
        s.button(x + 500, y + 376 + i * 24, 100, 'Activate', 'plain', 20)
    s.rect(x + 630, y + 344, 316, 170, DEEP, LINE)
    s.text(x + 642, y + 364, 'Options', BRIGHT, bold=True)
    for i, t in enumerate(('☑ check before switching', '☑ keep 5 versions', '☐ run db migrate after', '☐ restart the machine')):
        s.text(x + 642, y + 392 + i * 24, t, TXT)
    s.button(x + w - 360, y + h - 48, 100, 'Dry run', 'plain')
    s.button(x + w - 250, y + h - 48, 130, 'Deploy', 'ok')
    s.button(x + w - 110, y + h - 48, 96, 'Cancel', 'plain')
    s.save('design-deploy.svg')


def new_screen():
    s = Svg('eveux: new file and new project', 'templates for Eve, web files, SQL and documents; a new Eve file starts from a checked skeleton, a new project from `project new`.')
    window(s, pos='Ln 1, Col 1')
    explorer(s, 'web/')
    tabs(s, ['sales_load.eve'], 0)
    editor(s, ESALES)
    x, y, w, h = 230, 140, 900, 560
    s.dialog(x, y, w, h, 'New', 'Esc closes')
    s.rect(x + 14, y + 44, 200, h - 110, DEEP, LINE)
    for i, (t, on) in enumerate((('Project', False), ('Eve', True), ('Web', False), ('Data', False), ('Documents', False))):
        if on:
            s.rect(x + 15, y + 52 + i * 28, 198, 26, '#2b4a6b')
        s.text(x + 28, y + 70 + i * 28, t, '#ffffff' if on else TXT)
    items = [('◆', 'Aspect (primary)'), ('◆', 'Aspect (exclusive)'), ('▣', 'Module'), ('▢', 'Class'), ('▤', 'Test (uses test)'),
             ('‹›', 'HTML page'), ('js', 'JavaScript module'), ('{}', 'CSS style sheet'), ('▤', 'SQL script'), ('{ }', 'JSON file'),
             ('¶', 'Markdown document'), ('◇', 'evewp application')]
    for i, (g, t) in enumerate(items):
        cx = x + 232 + (i % 3) * 218
        cy = y + 52 + (i // 3) * 82
        sel = i == 6
        s.rect(cx, cy, 206, 70, '#1d2733' if not sel else '#2b4a6b', LINE if not sel else BLUE, 5)
        s.text(cx + 14, cy + 36, g, AMBER, size=22)
        s.text(cx + 14, cy + 58, t, '#ffffff' if sel else TXT)
    s.text(x + 232, y + h - 112, 'Name', DIM); s.field(x + 290, y + h - 130, 260, 'cart.js', 26, True)
    s.text(x + 570, y + h - 112, 'Folder', DIM); s.field(x + 630, y + h - 130, 240, 'web/', 26)
    s.text(x + 232, y + h - 74, 'Creates web/cart.js with an empty module, opens it, and adds it to the deploy list.', DIM, size=12)
    s.button(x + w - 220, y + h - 48, 100, 'Create', 'ok')
    s.button(x + w - 110, y + h - 48, 96, 'Cancel', 'plain')
    s.save('design-new.svg')


def menu_screen():
    s = Svg('eveux: menus', 'one table holds the menu items, the shortcuts and the command palette (Ctrl+Shift+P). Run is always local; Tools > Deploy sends a tested project to a machine.')
    window(s, menu_open='Run')
    explorer(s, 'sales_load.eve')
    tabs(s, ['sales_load.eve'], 0)
    editor(s, ESALES)
    x, y = X0 + 12 + 4 * 0 + 14 + 4 * 8 + 4 + 14 + 8 * 4 + 12 + 14 + 8 * 4 + 30, Y0 + 57
    items = [('Check', 'F6'), ('Run', 'F5'), ('Run with arguments…', 'Ctrl+F5'), ('Stop', 'Shift+F5'), ('─', ''),
             ('Load into the machine', ''), ('Dismiss', ''), ('─', ''), ('Generate docs', ''), ('Run tests of the project', 'Ctrl+T'),
             ('─', ''), ('Command palette…', 'Ctrl+Shift+P')]
    s.popup(x, y, 300, 28 + len(items) * 24)
    for i, (t, k) in enumerate(items):
        yy = y + 24 + i * 24
        if t == '─':
            s.line(x + 10, yy - 6, x + 290, yy - 6)
            continue
        if t == 'Run':
            s.rect(x + 2, yy - 16, 296, 22, '#2b4a6b')
        s.text(x + 16, yy, t, '#ffffff' if t == 'Run' else TXT)
        s.text(x + 284, yy, k, DIM, anchor='end')
    # the other menus as a table at the right
    tx = 740
    s.text(tx, 200, 'Other menus', BRIGHT, bold=True)
    rows = [('File', 'New…, Open project, Open recent, Save, Save all, Close, Settings, Exit'),
            ('Edit', 'Undo, Redo, Cut, Copy, Paste, Find, Replace, Find in files, Go to line, Toggle comment, Format'),
            ('View', 'Explorer, Outline, Bottom panel, Preview (Source/Split/Preview), Zoom, Theme, Full screen'),
            ('Debug', 'Start, Step over, Step into, Step out, Continue, Stop, Toggle breakpoint, Add watch'),
            ('Database', 'New SQL tab, Connect, Refresh, Describe table, Import file, Export result'),
            ('Source', 'Status, Diff, Stage, Commit, Branches, History, Pull, Push'),
            ('Tools', 'Deploy…, Machines, Login, Eve console, Options of the project'),
            ('Window', 'Split right, Split down, Close others, Reset layout'),
            ('Help', 'Eve manual, Tutorial (browser), Shortcuts, Check for updates, About')]
    for i, (m, t) in enumerate(rows):
        s.text(tx, 230 + i * 26, m, FN, bold=True)
        s.text(tx + 90, 230 + i * 26, t, TXT, size=12)
    s.save('design-menu.svg')


def dialogs_screen():
    s = Svg('eveux: login, settings, find in files, about', 'the small dialogs. A login belongs to a machine; the password never reaches the window: the local machine keeps it in the keyring.')
    window(s)
    explorer(s, 'sales_load.eve')
    tabs(s, ['sales_load.eve'], 0)
    editor(s, ESALES)
    s.dialog(60, 110, 400, 330, 'Log in to prod', 'Esc closes')
    s.button(80, 160, 360, 'Sign in with the company account (single sign-on)', 'hot', 30)
    s.text(80, 220, 'or user and password of the machine', DIM)
    s.text(80, 252, 'User', DIM); s.field(150, 236, 280, 'ana', 26)
    s.text(80, 292, 'Password', DIM); s.field(150, 276, 280, '••••••••', 26, True)
    s.text(80, 332, '☑ remember on this computer (keyring)', TXT)
    s.text(80, 356, 'Five failed logins lock the account for 15 minutes.', DIM, size=12)
    s.button(230, 396, 100, 'Log in', 'ok'); s.button(340, 396, 100, 'Cancel', 'plain')
    s.dialog(480, 110, 440, 330, 'Settings', 'Ctrl+,')
    for i, (k, v) in enumerate((('Theme', 'Dark  ▾'), ('Font', 'Consolas 13  ▾'), ('Tab size', '2'), ('Format on save', '☑'),
                                ('Backend', 'SDL3  (restart)'), ('Local machine', 'eve  (beside eveux)'), ('Git', 'git  (found)'), ('Language', 'English  ▾'))):
        s.text(500, 164 + i * 30, k, DIM)
        s.field(650, 148 + i * 30, 250, v, 24)
    s.button(700, 396, 100, 'OK', 'ok'); s.button(810, 396, 100, 'Cancel', 'plain')
    s.dialog(940, 110, 420, 330, 'Find in files', 'Esc closes')
    s.field(956, 150, 388, 'recover', 26, True)
    s.text(956, 200, '☐ case   ☐ whole word   ☐ regex      in: whole project', DIM, size=12)
    for i, (f, t) in enumerate((('server/sales_load.eve:12', 'recover'), ('asp/clean.eve:8', 'recover'), ('lib/money.eve:30', '** recover a bad amount'))):
        s.text(956, 244 + i * 40, f, FN)
        s.text(970, 262 + i * 40, t, TXT, size=12)
    s.text(956, 410, '3 matches in 3 files', DIM)
    s.dialog(60, 470, 400, 200, 'About eveux', 'Esc closes')
    s.text(80, 520, 'eveux 0.0  —  the Eve native workbench', BRIGHT)
    s.text(80, 546, 'local machine   eve 0.0.6', TXT); s.text(80, 566, 'dvui 0.6.0-dev  ·  Zig 0.17', TXT); s.text(80, 586, 'prod   eve 0.0.6   ana (single sign-on)', TXT)
    s.text(80, 640, '(c) 2026 Sage-Code Laboratory', DIM, size=12)
    s.save('design-dialogs.svg')


def arch_screen():
    s = Svg('eveux: architecture', 'one window thread, a few worker threads, the compiler linked in, the Eve machine as a child process.', 1400, 760)
    s.rect(30, 70, 640, 650, PANEL, LINE, 6)
    s.text(46, 96, 'eveux.exe  (one process, Zig)', BRIGHT, bold=True)
    s.rect(50, 112, 600, 150, DEEP, BLUE, 5)
    s.text(64, 134, 'UI thread: the dvui frame loop', BLUE, bold=True)
    s.text(64, 156, 'draws only; reads model snapshots; sends commands', TXT, size=12)
    for i, t in enumerate(('shell + docking', 'editor widget', 'preview widgets', 'grid + tree', 'dialogs')):
        s.rect(64 + (i % 3) * 190, 172 + (i // 3) * 40, 180, 30, '#1d2733', LINE, 3)
        s.text(154 + (i % 3) * 190, 192 + (i // 3) * 40, t, TXT, anchor='middle')
    s.rect(50, 282, 600, 130, DEEP, GREEN, 5)
    s.text(64, 304, 'Embedded Eve services (evecm + evecp linked in, no VM)', GREEN, bold=True)
    for i, t in enumerate(('lexer + parser', 'check (live diagnostics)', 'outline + symbols', 'docs of ** comments', 'format (later)')):
        s.rect(64 + (i % 3) * 190, 318 + (i // 3) * 40, 180, 30, '#1d2733', LINE, 3)
        s.text(154 + (i % 3) * 190, 338 + (i // 3) * 40, t, TXT, anchor='middle', size=12)
    s.rect(50, 432, 600, 130, DEEP, AMBER, 5)
    s.text(64, 454, 'Worker threads (queues to and from the UI thread)', AMBER, bold=True)
    for i, t in enumerate(('machine link (JSON-RPC)', 'file watcher + scan', 'git runner', 'decoders: image, media', 'search in files')):
        s.rect(64 + (i % 3) * 190, 468 + (i // 3) * 40, 180, 30, '#1d2733', LINE, 3)
        s.text(154 + (i % 3) * 190, 488 + (i // 3) * 40, t, TXT, anchor='middle', size=12)
    s.rect(50, 582, 600, 120, DEEP, LINE, 5)
    s.text(64, 604, 'Shared with evetx (module evecl)', BRIGHT, bold=True)
    s.text(64, 628, 'text buffer · Eve scanner + keywords · project tree · machine client', TXT, size=12)
    s.text(64, 648, 'regex · grid model · sqlstruct · user cache eve.db · colors', TXT, size=12)
    s.line(350, 262, 350, 282, arrow=True); s.line(350, 412, 350, 432, arrow=True)
    s.rect(760, 110, 280, 120, PANEL, LINE, 6)
    s.text(776, 136, 'Local Eve machine', BRIGHT, bold=True)
    s.text(776, 160, 'eve --stdio  (child process)', TXT, size=12)
    s.text(776, 180, 'run · debug · sessions · db', DIM, size=12)
    s.text(776, 200, 'git · deploy · keyring · logins', DIM, size=12)
    s.line(650, 495, 700, 495); s.line(700, 495, 700, 200); s.line(700, 200, 760, 200, arrow=True)
    s.text(708, 330, 'JSON-RPC 2.0, one', DIM, size=11); s.text(708, 346, 'message a line', DIM, size=11)
    s.rect(760, 290, 280, 90, PANEL, LINE, 6)
    s.text(776, 316, 'Servers', BRIGHT, bold=True)
    s.text(776, 340, 'eve -s (HTTP, WebSocket, SSH stdio)', TXT, size=12)
    s.text(776, 360, 'evedb child (managed) · evewp apps', DIM, size=12)
    s.line(900, 230, 900, 290, arrow=True)
    s.rect(1080, 110, 290, 120, PANEL, LINE, 6)
    s.text(1096, 136, 'Operating system', BRIGHT, bold=True)
    s.text(1096, 160, 'window · GPU · clipboard', TXT, size=12)
    s.text(1096, 180, 'native file dialogs · fonts', TXT, size=12)
    s.text(1096, 200, 'media decoders (Media Foundation …)', TXT, size=12)
    s.rect(1080, 290, 290, 90, PANEL, LINE, 6)
    s.text(1096, 316, 'The project on disk', BRIGHT, bold=True)
    s.text(1096, 340, 'files · .git · eve.cfg · eve.env', TXT, size=12)
    s.text(1096, 360, 'user cache eve.db (layout, machines)', DIM, size=12)
    s.line(650, 530, 1050, 530); s.line(1050, 530, 1050, 400); s.line(1050, 400, 1225, 400); s.line(1225, 400, 1225, 380, arrow=True)
    s.text(760, 440, 'Rules', BRIGHT, bold=True)
    for i, t in enumerate(('The UI thread never waits: no file, no process, no network in a frame.',
                           'A script runs in the child machine, never in eveux: a loop cannot freeze the window.',
                           'The compiler in the process only reads text: parse, check, outline, docs.',
                           'The window never sees a password or a token: the local machine holds them.',
                           'Each preview is a widget over a decoder on a worker thread; a failure shows a card.',
                           'Code is local. A remote machine receives a deployed bundle and is operated (status, schedules, logs), never edited.')):
        s.text(760, 468 + i * 24, '· ' + t, TXT, size=12)
    s.save('design-architecture.svg')


if __name__ == '__main__':
    main_screen(); debug_screen(); md_screen(); html_screen(); image_screen(); media_screen(); db_screen(); sql_screen()
    structure_screen(); git_screen(); deploy_screen(); new_screen(); menu_screen(); dialogs_screen(); arch_screen(); toolbar_screen()
    print('16 drawings written to eveux/design/')
