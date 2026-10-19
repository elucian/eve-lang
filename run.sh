#!/usr/bin/env bash
# Build the Eve VM, run the conformity tests, and start the parts of eve.
#   ./run.sh build            build eve and evevm (bin/eve.exe, bin/evevm.exe, lib/): no tests
#   ./run.sh build <part>...  build only the named parts: eve, evevm, evedb, evetx, eveux (evewp has no build yet)
#   ./run.sh build all        build every part: eve, evevm, evedb, evetx, eveux
#   ./run.sh build manual     refresh the generated manual and tutorial pages from spec and source
#   ./run.sh tx               stop the running eve programs, build evetx and install bin/evetx.exe
#   ./run.sh ux               stop the running eve programs, build eveux and install bin/eveux.exe
#   ./run.sh stop             stop the eve programs that run from bin/
#   ./run.sh unit             zig unit tests of the VM
#   ./run.sh size             size of the repository: tracked files, history, ignored folders (script/repsize.py)
#   ./run.sh 1                all tests of level1 (also: level1, 2, 3, all)
#   ./run.sh a01              one test (b01 is in level2, and so on); a prefix runs all matches
#   ./run.sh bump [minor]     bump the version label (patch by default), build and test (script/release.py)
#   ./run.sh dist             build the Windows distribution in dist/ and its zip (script/dist.py)
#   ./run.sh release          publish the zip of dist/ as the GitHub release of the version (gh; script/publish.py)
#   ./run.sh check 1          dry run: only check the syntax of level1 (eve --check), no execution
#   ./run.sh -q 1             options go to script/runtest.py
#   ./run.sh eve <args>       bin/eve with the arguments; also evevm, evecp, evedb, eveux, evewp:
#                             bin/eve vm|cp|db|-ux <args> (D-163; evewp is the web door), from any folder: paths stay relative to it
#   ./run.sh                  this help
export MSYS_NO_PATHCONV=1
root="$(cd "$(dirname "$0")" && pwd)"
# the shortcuts of the parts keep the working folder of the caller
case "$1" in
  eve)   shift; exec "$root/bin/eve" "$@" ;;
  evevm) shift; exec "$root/bin/eve" vm "$@" ;;
  evecp) shift; exec "$root/bin/eve" cp "$@" ;;
  evedb) shift; exec "$root/bin/eve" db "$@" ;;
  eveux) shift; exec "$root/bin/eve" -ux "$@" ;;
  evewp) shift; exec "$root/bin/eve" --serve "$@" ;;
esac
cd "$root" || exit 1
# A running program locks its .exe on Windows, and the build then fails with AccessDenied.
stop_eve() {
  case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*) powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$root/script/stop_eve.ps1")" -Bin "$(cygpath -w "$root/bin")" ;;
    *) pkill -f "$root/bin/" 2>/dev/null; true ;;
  esac
}
# one part of `build`: a zig build of its own folder (eve and evevm are steps of the root build.zig)
build_part() {
  case "$1" in
    eve | evevm) stop_eve; zig build "$1" -p . ;;
    evedb) stop_eve; (cd comp/evedb && zig build -p ../..) ;;
    evetx) stop_eve; (cd comp/evetx && zig build -p ../..) ;;
    eveux) stop_eve; (cd comp/eveux && zig build -p ../..) ;;
    evewp) echo "build evewp: there is no build yet, evewp is a design (comp/evewp/README.md)" >&2; return 1 ;;
    manual) build_manual ;;
    *) echo "build: unknown part '$1' (eve evevm evedb evetx eveux all manual)" >&2; return 1 ;;
  esac
}
# the generated parts of the manual and the tutorial: from spec/ (keywords, features) and from the source (lib/doc)
build_manual() {
  python script/genkeywords.py && python comp/evetx/gen_keywords.py && zig build doc &&
    python script/genpages.py && python script/genmanual.py && python script/relnotes.py --manual
}
case "$1" in
  "" | -h | --help) sed -n "2,21p" "$0" | sed 's/^# \{0,1\}//' ;;
  build) shift; [ $# -eq 0 ] && set -- eve evevm
    for p in "$@"; do
      if [ "$p" = all ]; then
        for q in eve evevm evedb evetx eveux; do build_part "$q" || exit 1; done
      else
        build_part "$p" || exit 1
      fi
    done ;;
  tx)    build_part evetx ;;
  ux)    build_part eveux ;;
  stop)  stop_eve ;;
  unit)  zig build test ;;
  size)  shift; python script/repsize.py "$@" ;;
  bump)    shift; python script/release.py "$@" ;;
  dist)    shift; stop_eve; python script/dist.py "$@" ;;
  release) shift; python script/publish.py "$@" ;;
  check) shift; python script/runtest.py --check "$@" ;;
  *)     python script/runtest.py "$@" ;;
esac
