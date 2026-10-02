#!/usr/bin/env bash
# Build the Eve VM and run the conformity tests.
#   ./run.sh build            compile evevm/ and install bin/eve.exe
#   ./run.sh unit             zig unit tests of the VM
#   ./run.sh 1                all tests of level1 (also: level1, 2, 3, all)
#   ./run.sh a01              one test (b01 is in level2, and so on); a prefix runs all matches
#   ./run.sh release [minor]  bump the version label (patch by default), build and test
#   ./run.sh check 1          dry run: only check the syntax of level1 (eve --check), no execution
#   ./run.sh -q 1             options go to script/runtest.py
#   ./run.sh                  this help
cd "$(dirname "$0")" || exit 1
export MSYS_NO_PATHCONV=1
case "$1" in
  "" | -h | --help) sed -n "2,10p" "$0" | sed 's/^# \{0,1\}//' ;;
  build) (cd evevm && zig build -p ..) ;;
  unit)  (cd evevm && zig build test) ;;
  release) shift; python script/release.py "$@" ;;
  check) shift; python script/runtest.py --check "$@" ;;
  *)     python script/runtest.py "$@" ;;
esac
