"""S3.6: check spec/syntax/grammar.md against the example scripts.

usage: python script/grammarcheck.py [files or dirs ...]   (default: test/level1 test/level2)
needs the Python package lark (pip install lark)
Writes the converted grammar to temp/eve.lark. A test whose /*@expect*/ block says "syntax_error": true must be
refused; anything else must parse. Extracts the ebnf blocks of spec/syntax/*.md, converts them to a Lark grammar, tokenizes each
.eve file with a small lexer that follows spec/lexical/lexical.md, and reports parse failures.
"""
import json, re, sys, glob, os
from lark import Lark, Token
from lark.exceptions import UnexpectedInput, UnexpectedEOF, UnexpectedToken

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

# ---------------------------------------------------------------- grammar
def ebnf_blocks():
    out = []
    for f in sorted(glob.glob("spec/syntax/*.md")):
        t = open(f, encoding="utf-8").read().replace("\r\n", "\n")
        out += re.findall(r"```ebnf\n(.*?)```", t, re.S)
    return "\n".join(out)

SYMS = ["..<", ">..<", ">..", "==", "<>", "=>", "<=", ">=", ":>", "<:", "..", "&&", "||", "><", "=~", "+-",
        "::", ":=", "+=", "-=", "*=", "/=", "%=", "^=", "+>", "<+", ">>", "<<", "->", "<-",
        ",", ":", ".", ";", "=", "?", "%", "^", "*", "-", "+", "/", "<", ">", "&", "|", "!", "@", "(", ")", "[", "]", "{", "}"]
SYMS.sort(key=len, reverse=True)

def term_name(lit):
    if re.fullmatch(r"[A-Za-z_]+", lit):
        return "K_" + lit.upper()
    if lit == "@self":
        return "ATSELF"
    return "S%d_" % (SYMS.index(lit)) if lit in SYMS else "X_" + re.sub(r"\W", "", lit)

DECL_TERMS = {"sysname": "SYSNAME", "string": "STRING", "text": "TEXT", "rune": "RUNE",
              "shebang": "SHEBANG", "integer": "INTEGER"}

def convert(src):
    src = re.sub(r"\(\*.*?\*\)", "", src, flags=re.S)
    toks = re.findall(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'|[A-Za-z][A-Za-z0-9-]*|[=,;|()\[\]{}]', src)
    rules, i = {}, 0
    while i < len(toks):
        name = toks[i]; assert toks[i + 1] == "=", (name, toks[i + 1])
        j = i + 2; body = []
        while toks[j] != ";":
            body.append(toks[j]); j += 1
        rules.setdefault(name, []).append(body)
        i = j + 1
    rules.setdefault("name", [])
    lits, undefined, lines = set(), set(), []
    for name, alts in rules.items():
        if name == "name": continue
        parts = []
        for body in alts:
            o = []
            for t in body:
                if t[0] in "\"'":
                    lit = t[1:-1].encode().decode("unicode_escape") if "\\" in t else t[1:-1]
                    lits.add(lit); o.append(term_name(lit))
                elif t == ",": pass
                elif t == "{": o.append("(")
                elif t == "}": o.append(")*")
                elif t in "()[]|": o.append(t)
                elif t == "=": raise SystemExit("stray = in " + name)
                else:
                    if t in DECL_TERMS: o.append(DECL_TERMS[t])
                    elif t == "number": o.append("number")
                    else:
                        if t not in rules: undefined.add(t)
                        o.append(t.replace("-", "_"))
            parts.append(" ".join(o))
        lines.append("%s: %s" % (name.replace("-", "_"), "\n   | ".join(parts)))
    lines.append("number: NUMBER | INTEGER")
    ctx = ["K_" + w.upper() for w in sorted(CTX)]
    lines.append("name: " + " | ".join(["NAME"] + ctx))
    rules.pop("name", None)
    decl = ["%declare " + " ".join(sorted(set(DECL_TERMS.values()) | {"NUMBER", "NAME"} | {"K_" + w.upper() for w in CTX} | {term_name(l) for l in lits}))]
    return "\n".join(decl + lines), lits, undefined

# ---------------------------------------------------------------- lexer
_KW = json.load(open("spec/lexical/keywords.json"))["items"]
KW = {i["id"] for i in _KW}
CTX = {i["id"] for i in _KW if i.get("contextual")}     # contextual keywords are also valid names (D-116)
NUM = re.compile(r"0[xX][0-9a-fA-F]+|0[bB][01]+|\d+\.\d+(?:[eE][+-]?\d+)?[drfbwnz]?|\d+[eE][+-]?\d+|\d+[drfbwnz]?")
NAME = re.compile(r"[A-Za-z][A-Za-z0-9_]*")

class LexErr(Exception):
    pass

def lex(text, lits):
    t = text.replace("\r\n", "\n").lstrip("﻿")
    out, i, n, line = [], 0, len(t), 1
    def add(typ, val, ln): out.append(Token(typ, val, line=ln, column=0))
    if t.startswith("#!"):
        add("SHEBANG", "#!", 1)
        i = t.find("\n"); i = n if i < 0 else i
    bol = True if not t.startswith("#!") else False
    while i < n:
        c = t[i]
        if c == "\n":
            line += 1; i += 1; bol = True; continue
        if c in " \t\r":
            i += 1; bol = False if False else bol;
            if c in " \t": bol = False
            continue
        if c == "#" and bol:
            i = t.find("\n", i); i = n if i < 0 else i; continue
        bol = False
        if t.startswith("(**", i):
            j = t.find("**)", i + 3)
            if j < 0: raise LexErr("unterminated (** at line %d" % line)
            line += t.count("\n", i, j); i = j + 3; continue
        if t.startswith("/*", i):
            j = t.find("*/", i + 2)
            if j < 0: raise LexErr("unterminated /* at line %d" % line)
            line += t.count("\n", i, j); i = j + 2; continue
        if t.startswith("**", i):
            i = t.find("\n", i); i = n if i < 0 else i; continue
        if t.startswith('"""', i):
            j = t.find('"""', i + 3)
            if j < 0: raise LexErr("unterminated text at line %d" % line)
            add("TEXT", "text", line); line += t.count("\n", i, j); i = j + 3; continue
        if c == '"':
            j, regex = i + 1, t.startswith("/", i + 1)
            depth, inner = 0, ""   # a placeholder {...} may hold quoted literals (D-120)
            while True:
                if j >= n or t[j] == "\n": raise LexErr("unterminated string at line %d" % line)
                if t[j] == "\\": j += 2; continue
                if depth == 0:
                    if t[j] == '"': break
                    if t[j] == "{" and not regex: depth = 1
                elif inner:
                    if t[j] == inner: inner = ""
                elif t[j] in "\"'": inner = t[j]
                elif t[j] == "{": depth += 1
                elif t[j] == "}": depth -= 1
                j += 1
            add("STRING", t[i:j + 1], line); i = j + 1
            # a string followed at once by a type suffix is a number literal ("1,000"z)
            if i < n and t[i] in "drfbwnz" and not (i + 1 < n and (t[i + 1].isalnum() or t[i+1] == "_")):
                out[-1] = Token("NUMBER", "str", line=line, column=0); i += 1
            continue
        if c == "'":
            m = re.match(r"''|'(?:\\x[0-9a-fA-F]{2}|\\u\{[0-9a-fA-F]+\}|\\.|[^'\\\n])'", t[i:])
            if not m: raise LexErr("bad rune at line %d" % line)
            add("RUNE", m.group(), line); i += len(m.group()); continue
        m = re.match(r"U\+[0-9A-Fa-f]{4,6}", t[i:])
        if m: add("RUNE", m.group(), line); i += len(m.group()); continue
        if c.isdigit():
            m = NUM.match(t, i)
            v = m.group()
            add("INTEGER" if v.isdigit() else "NUMBER", v, line); i += len(v); continue
        if c == "_" and not (i + 1 < n and (t[i + 1].isalnum() or t[i + 1] == "_")):
            add("K__", "_", line); i += 1; continue
        if c == "$":
            m = NAME.match(t, i + 1)
            if m: add("SYSNAME", "$" + m.group(), line); i += 1 + len(m.group()); continue
        if t.startswith("@self", i) and not NAME.match(t, i + 5 - 0) is None and False:
            pass
        if t.startswith("@self", i) and not (i + 5 < n and (t[i + 5].isalnum() or t[i + 5] == "_")):
            add("ATSELF", "@self", line); i += 5; continue
        m = NAME.match(t, i)
        if m:
            w = m.group()
            if w in KW: add("K_" + w.upper(), w, line)
            else: add("NAME", w, line)
            i += len(w); continue
        for s in SYMS:
            if t.startswith(s, i):
                add(term_name(s), s, line); i += len(s); break
        else:
            raise LexErr("bad character %r at line %d" % (c, line))
    return out

from lark.lexer import Lexer
class EveLexer(Lexer):
    def __init__(self, conf): pass
    def lex(self, data):
        yield from data

def main():
    g, lits, undefined = convert(ebnf_blocks())
    open("temp/eve.lark", "w", encoding="utf-8").write(g)
    if undefined: print("UNDEFINED in the grammar:", sorted(undefined))
    kw_missing = {l for l in lits if re.fullmatch(r"[a-z]+", l) and l not in KW}
    if kw_missing: print("literals that are not in keywords.json:", sorted(kw_missing))
    parser = Lark(g, start="file", parser="earley", lexer=EveLexer, ambiguity="resolve")
    args = sys.argv[1:] or ["test/level1", "test/level2"]
    files = []
    for a in args:
        files += sorted(glob.glob(a + "/**/*.eve", recursive=True)) if os.path.isdir(a) else [a]
    ok = 0; sem = []
    for f in files:
        src = open(f, encoding="utf-8").read()
        top = os.path.dirname(f)
        if os.path.basename(top) in ("asp", "lib"): top = os.path.dirname(top)
        pat = r'"syntax_error"\s*:\s*true'
        neg = any(re.search(pat, open(g, encoding="utf-8").read()) for g in glob.glob(top + "/**/*.eve", recursive=True)) if "level2" in f else bool(re.search(pat, src))
        try:
            toks = lex(src, lits)
            parser.parse(toks)
            if neg: sem.append(f)
            ok += 1
        except Exception as e:
            if neg: ok += 1; continue
            if isinstance(e, LexErr): print("LEX  %s: %s" % (f, e))
            elif isinstance(e, UnexpectedToken): print("FAIL %s: line %s, unexpected %s %r; expected %s" % (f, e.token.line, e.token.type, e.token.value, sorted(e.expected)[:6]))
            elif isinstance(e, UnexpectedEOF): print("FAIL %s: unexpected end of file" % f)
            else: print("ERR  %s: %s" % (f, str(e).splitlines()[0][:150]))
    print("%d files are refused by the compile step but accepted by the grammar (semantic checks): %s" % (len(sem), " ".join(os.path.basename(x)[:3] for x in sem)))
    print("%d/%d files parse" % (ok, len(files)))

main()
