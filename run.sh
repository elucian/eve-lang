#!/usr/bin/env bash
# Build the Eve VM, run the conformity tests, and start the parts of eve.
#   ./run.sh build            compile the modules and install bin/eve.exe
#   ./run.sh unit             zig unit tests of the VM
#   ./run.sh 1                all tests of level1 (also: level1, 2, 3, all)
#   ./run.sh a01              one test (b01 is in level2, and so on); a prefix runs all matches
#   ./run.sh release [minor]  bump the version label (patch by default), build and test
#   ./run.sh check 1          dry run: only check the syntax of level1 (eve --check), no execution
#   ./run.sh -q 1             options go to script/runtest.py
#   ./run.sh eve <args>       bin/eve with the arguments; also evevm, evecp, evedb, eveux:
#                             bin/eve vm|cp|db|ux <args> (D-163), from any folder: paths stay relative to it
#   ./run.sh                  this help
export MSYS_NO_PATHCONV=1
root="$(cd "$(dirname "$0")" && pwd)"
# the shortcuts of the parts keep the working folder of the caller
case "$1" in
  eve)   shift; exec "$root/bin/eve" "$@" ;;
  evevm) shift; exec "$root/bin/eve" vm "$@" ;;
  evecp) shift; exec "$root/bin/eve" cp "$@" ;;
  evedb) shift; exec "$root/bin/eve" db "$@" ;;
  eveux) shift; exec "$root/bin/eve" ux "$@" ;;
esac
cd "$root" || exit 1
case "$1" in
  "" | -h | --help) sed -n "2,12p" "$0" | sed 's/^# \{0,1\}//' ;;
  build) zig build -p . ;;
  unit)  zig build test ;;
  release) shift; python script/release.py "$@" ;;
  check) shift; python script/runtest.py --check "$@" ;;
  *)     python script/runtest.py "$@" ;;
esac
