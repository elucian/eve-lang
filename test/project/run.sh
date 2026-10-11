#!/bin/sh
# Special test of `project init` and `project new` (F-TLS-23): it works on real folders.
# It removes the old work folder, makes the projects again, then checks that the folders and the
# files exist, that a second init keeps the files of the author, that `new` refuses a folder that
# is not empty, and that no project made under this versioned folder got a .git of its own.
# usage: sh test/project/run.sh [path-to-eve]      (default: bin/eve.exe of the repository)
# Exit status: 0 when every check passes, 1 otherwise. The work folder is test/project/work/ (ignored by git).

here=$(cd "$(dirname "$0")" && pwd)
eve=${1:-$here/../../bin/eve.exe}
work=$here/work
fails=0
checks=0

ok() { checks=$((checks + 1)); }
bad() { checks=$((checks + 1)); fails=$((fails + 1)); echo "FAIL: $1"; }
has_dir() { if [ -d "$1" ]; then ok; else bad "folder missing: ${1#$here/}"; fi; }
has_file() { if [ -f "$1" ]; then ok; else bad "file missing: ${1#$here/}"; fi; }
no_path() { if [ ! -e "$1" ]; then ok; else bad "should not exist: ${1#$here/}"; fi; }
has_text() { if grep -qF -- "$2" "$1" 2>/dev/null; then ok; else bad "${1#$here/} lacks: $2"; fi; }

[ -x "$eve" ] || { echo "ERROR: eve not found: $eve"; exit 2; }

# 1. clean start
rm -rf "$work"
mkdir -p "$work"
cd "$work" || exit 2

# 2. project init on a folder that does not exist
out=$("$eve" --project init shop 2>&1); code=$?
[ "$code" = 0 ] && ok || bad "init exit code $code"
case $out in *"project init: shop: 14 created, 0 kept"*) ok ;; *) bad "init summary: $out" ;; esac
case $out in *"inside a repository, kept"*) ok ;; *) bad "git line missing: $out" ;; esac

# 3. the folders and the files of the layout
for d in db log meta data/in data/out test asp lib src doc web; do has_dir "$work/shop/$d"; done
for f in shop.eve eve.cfg meta/project.json .gitignore; do has_file "$work/shop/$f"; done
has_text "$work/shop/eve.cfg" 'core_db = "db/local.db"'
has_text "$work/shop/eve.cfg" 'fallback_log = "log/eve.log"'
has_text "$work/shop/meta/project.json" '"name": "shop"'
has_text "$work/shop/.gitignore" 'db/*.db'
has_text "$work/shop/shop.eve" 'driver shop is'
no_path "$work/shop/config"

# 4. versioned parent: no .git in the new project
no_path "$work/shop/.git"

# 5. the first driver is a correct script
"$eve" --check shop/shop.eve >/dev/null 2>&1 && ok || bad "check of shop.eve fails"

# 6. init over an older project: add what is missing, keep what the author wrote
echo "mine" > "$work/shop/eve.cfg"
echo "my notes" > "$work/shop/doc/notes.txt"
rm -rf "$work/shop/web" "$work/shop/log"
out=$("$eve" --project init shop 2>&1); code=$?
[ "$code" = 0 ] && ok || bad "second init exit code $code"
has_dir "$work/shop/web"
has_dir "$work/shop/log"
has_file "$work/shop/web/.gitkeep"
[ "$(cat "$work/shop/eve.cfg")" = "mine" ] && ok || bad "eve.cfg was overwritten"
[ "$(cat "$work/shop/doc/notes.txt")" = "my notes" ] && ok || bad "doc/notes.txt was touched"

# 7. init on a folder that is not empty and is not a project yet
mkdir old
echo "keep me" > old/readme.txt
"$eve" --project init old >/dev/null 2>&1 && ok || bad "init of a non-empty folder fails"
[ "$(cat old/readme.txt)" = "keep me" ] && ok || bad "old/readme.txt was changed"
has_dir "$work/old/db"
has_file "$work/old/old.eve"

# 8. new refuses a folder that is not empty, and writes nothing
mkdir full
echo "x" > full/a.txt
out=$("$eve" --project new full 2>&1); code=$?
[ "$code" = 73 ] && ok || bad "new on a full folder: exit code $code, expected 73"
no_path "$work/full/db"
no_path "$work/full/meta"

# 9. new on a folder that does not exist works, and a folder name that is not an identifier is cleaned
"$eve" --project new "my-shop" >/dev/null 2>&1 && ok || bad "new on a new folder fails"
has_file "$work/my-shop/my_shop.eve"

# 10. usage errors
"$eve" --project >/dev/null 2>&1; [ "$?" = 64 ] && ok || bad "project without arguments should exit 64"
"$eve" --project init >/dev/null 2>&1; [ "$?" = 64 ] && ok || bad "project init without a folder should exit 64"

if [ "$fails" = 0 ]; then
  echo "PASS: project init and project new, $checks checks"
  exit 0
fi
echo "FAIL: $fails of $checks checks"
exit 1
