SRC = 'code/evecp/src/parser.zig'
STRUCT = 'Parser'
TYPES = 'parser/consts.zig'
TYPES_RANGE = (38, 73)
_src = open(SRC, encoding='utf-8').read().split('\n')
IMPORT_PREFIX = [l.replace('pub const', 'const', 1) for l in _src[26:36] if l.startswith(('const ', 'pub const '))]
def head(name, purpose):
    return ['//! @eve-module parser.' + name, '//! @spec spec/syntax/grammar.md', '//! @feature F-VM-01', '//! @decision D-179',
            '//! @see code/evecp/src/parser.zig:Parser', '//! ' + purpose]
TYPES_HEAD = head('consts', 'Reserved words, the block end words and the number helper the parser parts share.')
specs = [
 ('literals', 216, 460, 'Strings, interpolation, characters and text literals.'),
 ('routines', 461, 631, 'Type names, parameters and routines.'),
 ('expr', 632, 983, 'Expressions, from `or` to a primary.'),
 ('statements', 984, 1556, 'Blocks, declarations, loops, if, match, SQL declarations and every statement.'),
 ('classes', 1557, 1737, 'Classes, traits and adopt.'),
 ('modules', 1738, 1908, 'Declarations in a driver, import, export, module, apply, start.'),
 ('aspects', 1909, 2056, 'Parallel blocks, aspects, macros and the script entry.'),
]
CHUNKS = [('parser/%s.zig' % n, a, b, head(n, p)) for (n, a, b, p) in specs]
