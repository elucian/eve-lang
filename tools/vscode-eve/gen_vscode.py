#!/usr/bin/env python3
"""Writes the TextMate grammar of the VS Code extension from the specification.

Run from the repository root:  python tools/vscode-eve/gen_vscode.py
Source: spec/lexical/keywords.json (classified by script/genkeywords.py) and the lists below.
Written (generated, do not edit): tools/vscode-eve/syntaxes/eve.tmLanguage.json, tools/vscode-eve/language-configuration.json
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "script"))
import genkeywords  # noqa: E402

EXTRA_KEYWORDS = ["print", "read", "write"]        # statements of the parser, not words of keywords.json (D-086)
TYPES = """Byte Short Integer Natural Huge Real Float Decimal Rational String Text Symbol Logic Table Rune Record Ordinal
Variant Date Time Instant Duration Array List Object Class Lambda Function DataSet DataMap HashMap Folder File Type
Secret Channel Memory Stream Iterable Comparable Printable Bytes Connection Atomic Error Warning""".split()
CONSTANTS = ["True", "False", "Null", "null"]
# finer scopes for single words (everything else of the group "keyword" is keyword.other)
FLOW = {"abort", "break", "exit", "panic", "raise", "resume", "retry", "skip", "stop", "yield", "return", "over", "pass"}
DECLARATION = {"aspect", "class", "constructor", "def", "destructor", "function", "generator", "method", "module",
               "procedure", "process", "trait", "set", "new"}
MODIFIER = {"public", "protected", "private", "async", "external", "primary", "exclusive", "concurrent", "managed",
            "cached", "temporary", "direct"}
# longest first: the first alternative that matches wins
OPERATORS = ["..<", ">..<", "...", "..", "><", "=~", "!~", ":=", "==", "<>", "=>", "<:", ":>", "<-", "->", "<+", "+>",
             "<=", ">=", "&&", "||", "+=", "-=", "*=", "/=", "%=", "^=", "+", "-", "*", "/", "^", "%", "&", "|", "<", ">",
             "=", "!", "?", ":", "~"]


NL = chr(10)
B = chr(92)  # a backslash; written this way so no editor or tool halves a doubled backslash


def alt(words):
    return "|".join(sorted(set(words)))


def grammar():
    g = genkeywords.classify()
    keyword = set(g["keyword"]) | set(EXTRA_KEYWORDS)
    flow = sorted(keyword & FLOW)
    decl = sorted(keyword & DECLARATION)
    modifier_any = sorted(keyword & MODIFIER)
    other = sorted(keyword - FLOW - DECLARATION - MODIFIER)
    opening = sorted(set(g["opening"]) | MODIFIER & set(g["opening"]))
    control = sorted(set(g["control"]) | set(g["constant"]))
    patterns = [
        {"include": "#comments"},
        {"include": "#strings"},
        {"include": "#symbols"},
        {"include": "#numbers"},
        {"include": "#variables"},
        {"include": "#keywords"},
        {"include": "#types"},
        {"include": "#functions"},
        {"include": "#operators"},
    ]
    repo = {
        "comments": {"patterns": [
            {"name": "markup.heading.2.eve", "match": "^##.*$"},
            {"name": "markup.heading.1.eve", "match": "^#.*$"},
            {"name": "comment.line.double-asterisk.eve", "match": r"\*\*.*$"},
            {"name": "comment.block.expression.eve", "begin": r"\(\*\*", "end": r"\*\*\)"},
            {"name": "comment.block.eve", "begin": r"/\*", "end": r"\*/"},
        ]},
        "strings": {"patterns": [
            {"name": "string.quoted.triple.eve", "begin": '"""', "end": '"""', "patterns": [{"include": "#string-content"}]},
            {"name": "string.quoted.double.eve", "begin": '"', "end": '"', "patterns": [{"include": "#string-content"}]},
        ]},
        "string-content": {"patterns": [
            {"name": "constant.character.escape.eve", "match": B + B + "."},
            {"name": "constant.character.escape.eve", "match": r"&[A-Za-z_][A-Za-z0-9_]*;"},
            {"name": "meta.interpolation.eve", "begin": r"\{", "end": r"\}", "beginCaptures": {"0": {"name": "punctuation.section.interpolation.begin.eve"}},
             "endCaptures": {"0": {"name": "punctuation.section.interpolation.end.eve"}},
             "patterns": [{"include": "#numbers"}, {"include": "#variables"}, {"include": "#keywords"}, {"include": "#operators"}]},
        ]},
        "symbols": {"patterns": [
            {"name": "string.quoted.single.eve", "match": "'(?:[^'" + B + B + B + "n]|" + B + B + ".)*'"},
            {"name": "constant.character.eve", "match": r"\bU\+[0-9A-Fa-f]+\b"},
        ]},
        "numbers": {"patterns": [
            {"name": "constant.numeric.hex.eve", "match": r"\b0[xX][0-9a-fA-F_]+[bBsShHdD]?\b"},
            {"name": "constant.numeric.binary.eve", "match": r"\b0[bB][01_]+\b"},
            {"name": "constant.numeric.decimal.eve", "match": r"\b[0-9][0-9_]*(?:\.[0-9][0-9_]*)?(?:[eE][+-]?[0-9]+)?[dDbBsShH]?\b"},
        ]},
        "variables": {"patterns": [
            {"name": "variable.language.system.eve", "match": r"\$[A-Za-z_][A-Za-z0-9_]*"},
            {"name": "variable.parameter.reference.eve", "match": r"@[A-Za-z_][A-Za-z0-9_]*"},
        ]},
        "keywords": {"patterns": [
            {"name": "constant.language.eve", "match": r"\b(?:" + alt(CONSTANTS) + r")\b"},
            {"name": "keyword.control.eve", "match": r"\b(?:" + alt(control) + r")\b"},
            {"name": "keyword.control.flow.eve", "match": r"\b(?:" + alt(flow) + r")\b"},
            {"name": "storage.type.eve", "match": r"\b(?:" + alt(decl) + r")\b"},
            {"name": "storage.modifier.eve", "match": r"\b(?:" + alt(modifier_any) + r")\b"},
            {"name": "keyword.operator.word.eve", "match": r"\b(?:" + alt(g["operator"]) + r")\b"},
            {"name": "keyword.other.eve", "match": r"\b(?:" + alt(other) + r")\b"},
            # contextual words (D-116) are keywords only where a declaration opens
            {"name": "storage.modifier.eve", "match": r"^\s*(?:" + alt(opening) + r")\b"},
        ]},
        "types": {"patterns": [
            {"name": "support.type.eve", "match": r"\b(?:" + alt(TYPES) + r")\b"},
            {"name": "entity.name.type.eve", "match": r"\b[A-Z][A-Za-z0-9_]*\b"},
        ]},
        "functions": {"patterns": [
            {"name": "entity.name.function.eve", "match": r"\b[a-z_][A-Za-z0-9_]*!?(?=\s*\()"},
        ]},
        "operators": {"patterns": [
            {"name": "keyword.operator.eve", "match": "|".join(__import__("re").escape(o) for o in OPERATORS)},
        ]},
    }
    return {
        "$schema": "https://raw.githubusercontent.com/martinring/tmlanguage/master/tmlanguage.json",
        "name": "Eve",
        "scopeName": "source.eve",
        "fileTypes": ["eve"],
        "_generated": "by tools/vscode-eve/gen_vscode.py from spec/lexical/keywords.json: do not edit by hand",
        "patterns": patterns,
        "repository": repo,
    }


def language_configuration():
    b = B
    return {
        "comments": {"lineComment": "**", "blockComment": ["/*", "*/"]},
        "brackets": [["(", ")"], ["[", "]"], ["{", "}"]],
        "autoClosingPairs": [
            {"open": "(", "close": ")"}, {"open": "[", "close": "]"}, {"open": "{", "close": "}"},
            {"open": '"', "close": '"', "notIn": ["string", "comment"]},
            {"open": "'", "close": "'", "notIn": ["string", "comment"]},
            {"open": "/*", "close": " */", "notIn": ["string"]},
        ],
        "surroundingPairs": [["(", ")"], ["[", "]"], ["{", "}"], ['"', '"'], ["'", "'"]],
        "wordPattern": "[$@]?[A-Za-z_][A-Za-z0-9_]*!?",
        "indentationRules": {
            # `process main is`, `if x do`, `else`, `recover`, ...: the next line goes in
            "increaseIndentPattern": "(" + b + "bis|" + b + "bdo|" + b + "bthen|" + b + "belse|^" + b + "s*initialize|^" + b + "s*recover|^" + b + "s*finalize)" + b + "s*(" + b + "*" + b + "*.*)?$",
            # `done;`, `return;`, `end name;`, `else`, `recover`, `finalize` close or turn the block
            "decreaseIndentPattern": "^" + b + "s*(done|return|end|else|recover|finalize)" + b + "b",
        },
        "folding": {"markers": {"start": "^" + b + "s*(/" + b + "*|(" + b + "*" + b + "*)", "end": "(" + b + "*/|" + b + "*" + b + "*))"}},
    }


def main():
    (ROOT / "tools" / "vscode-eve" / "language-configuration.json").write_text(
        json.dumps(language_configuration(), indent=2) + NL, encoding="utf-8", newline=NL)
    out = ROOT / "tools" / "vscode-eve" / "syntaxes" / "eve.tmLanguage.json"
    out.write_text(json.dumps(grammar(), indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    out.write_text(json.dumps(grammar(), indent=2, ensure_ascii=False) + NL, encoding="utf-8", newline=NL)


if __name__ == "__main__":
    main()
