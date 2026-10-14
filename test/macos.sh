#!/usr/bin/env bash
#
# macos.sh — run test/run.sh on Linux as macOS would run it: under GNU bash 3.2.57 (the bash macOS ships as
# /bin/bash), with Apple's awk (awk-40, built from its source) and a uname that says Darwin, so the scripts take their
# macOS branches. Apple's awk compares strings with strcoll, and macOS's strcoll in a UTF-8 locale gives no weight of
# its own to a character beyond Latin-1, so all emoji compare equal: the awk is built with a strcoll that does the
# same. For working on the workflow with no macOS machine and no CI on one. Windows (Git Bash) is not covered.
#
# The tools are built once, from sources pinned by their SHA-256, into ${XDG_CACHE_HOME:-~/.cache}/workflow-test/macos:
# it needs curl, gcc, make and sha256sum, and a minute. Delete that folder to build them again.
#
# Usage: bash test/macos.sh      Exit: test/run.sh's (0 = every check passed). 2 = the tools could not be built, or
#                                this is not Linux (UNKNOWN, never a pass).

set -uo pipefail
WF=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fail() { echo "UNKNOWN: $*" >&2; exit 2; }
[ "$(uname -s)" = Linux ] || fail "macos.sh builds Linux programs; on macOS, run /bin/bash test/run.sh"

C=${XDG_CACHE_HOME:-$HOME/.cache}/workflow-test/macos
BASH_URL=https://ftp.gnu.org/gnu/bash/bash-3.2.57.tar.gz
BASH_SHA=3fa9daf85ebf35068f090ce51283ddeeb3c75eb5bc70b1a4a7cb05868bfe06a4
# bash 3.2.57's y.tab.c predates its parse.y: the parser is made again, with byacc (no yacc on most machines).
YACC_URL=https://invisible-island.net/archives/byacc/byacc-20260126.tgz
YACC_SHA=b618c5fb44c2f5f048843db90f7d1b24f78f47b07913c8c7ba8c942d3eb24b00
AWK_URL=https://github.com/apple-oss-distributions/awk/archive/refs/tags/awk-40.tar.gz
AWK_SHA=0254582eb68d292348fb825036d601eac609ad83967e6e0b65a61c0249965809

fetch() { # <url> <sha256> <file>: downloaded once, and kept only when its SHA-256 is the pinned one
  [ -f "$3" ] && return 0
  curl -sSfL -o "$3.part" "$1" || fail "cannot download $1"
  [ "$(sha256sum "$3.part" | cut -d' ' -f1)" = "$2" ] || { rm -f "$3.part"; fail "$1 is not the pinned file (SHA-256)"; }
  mv "$3.part" "$3"
}

if [ ! -x "$C/bin/bash" ] || [ ! -x "$C/bin/awk" ] || [ ! -x "$C/bin/uname" ]; then
  for t in curl gcc make sha256sum; do command -v "$t" >/dev/null || fail "$t is needed to build the tools"; done
  rm -rf "$C/build" "$C/bin" && mkdir -p "$C/dl" "$C/build" "$C/bin" "$C/shim" || fail "cannot write $C"
  fetch "$BASH_URL" "$BASH_SHA" "$C/dl/bash-3.2.57.tar.gz"
  fetch "$YACC_URL" "$YACC_SHA" "$C/dl/byacc-20260126.tgz"
  fetch "$AWK_URL" "$AWK_SHA" "$C/dl/awk-40.tar.gz"
  echo "Building bash 3.2.57 and Apple's awk into $C, once (log: $C/build.log)"
  (cd "$C/build" && tar xzf ../dl/byacc-20260126.tgz && cd byacc-20260126 && ./configure && make) \
    >"$C/build.log" 2>&1 || fail "byacc did not build: $C/build.log"
  # gcc 14 and later refuse the old C of bash 3.2 by default: build it as C89, warnings off.
  (cd "$C/build" && tar xzf ../dl/bash-3.2.57.tar.gz && cd bash-3.2.57 && rm -f y.tab.c y.tab.h &&
    CFLAGS="-O1 -std=gnu89 -w" ./configure --without-bash-malloc --disable-nls &&
    make YACC="$C/build/byacc-20260126/yacc -d" CFLAGS_FOR_BUILD="-g -std=gnu89 -w" && cp bash "$C/bin/bash") \
    >>"$C/build.log" 2>&1 || fail "bash 3.2.57 did not build: $C/build.log"
  # Apple's awk on Linux: its xlocale.h, fmtcheck and __collate_lookup_l are macOS's; strcoll is macOS's in UTF-8.
  printf '%s\n' '#include <locale.h>' '#include <wctype.h>' '#include <wchar.h>' >"$C/shim/xlocale.h"
  cat >"$C/shim/macos.c" <<'EOF'
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include <locale.h>
void __collate_lookup_l(wchar_t *t, int *len, int *prim, int *sec, locale_t l) { (void)l; *len = 1; *prim = *t; *sec = 0; }
/* macOS's strcoll in a UTF-8 locale: a character beyond Latin-1 has no weight of its own, so all of them compare
   equal (all emoji, for one); in a one-byte locale, the bytes. */
static long weight(wchar_t c) { return c < 0x100 ? (long)c : 0x100; }
int macos_strcoll(const char *a, const char *b) {
  mbstate_t sa, sb; wchar_t ca, cb; size_t na, nb;
  if (MB_CUR_MAX == 1) return strcmp(a, b);
  memset(&sa, 0, sizeof sa); memset(&sb, 0, sizeof sb);
  for (;;) {
    na = mbrtowc(&ca, a, MB_CUR_MAX, &sa); nb = mbrtowc(&cb, b, MB_CUR_MAX, &sb);
    if (na == (size_t)-1 || na == (size_t)-2 || nb == (size_t)-1 || nb == (size_t)-2) return strcmp(a, b);
    if (weight(ca) != weight(cb)) return weight(ca) < weight(cb) ? -1 : 1;
    if (ca == 0) return 0;
    a += na; b += nb;
  }
}
EOF
  (cd "$C/build" && tar xzf ../dl/awk-40.tar.gz && cd awk-awk-40/src &&
    gcc -O1 -w -D_GNU_SOURCE '-Dfmtcheck(f,d)=(f)' -Dstrcoll=macos_strcoll -I"$C/shim" -o "$C/bin/awk" \
      $(ls *.c | grep -v maketab.c) "$C/shim/macos.c" -lm) >>"$C/build.log" 2>&1 ||
    fail "Apple's awk did not build: $C/build.log"
  printf '%s\n' '#!/bin/sh' '# uname -s as on macOS; anything else as here.' \
    'case $* in "" | -s) echo Darwin ;; *) exec /usr/bin/uname "$@" ;; esac' >"$C/bin/uname"
  chmod +x "$C/bin/uname" || fail "cannot write $C/bin/uname"
fi

# A macOS session's locale: en_US.UTF-8 where this machine has it.
lang=C.UTF-8
locale -a 2>/dev/null | grep -qix 'en_US.utf-\{0,1\}8' && lang=en_US.UTF-8
echo "As on macOS: $("$C/bin/bash" -c 'echo bash $BASH_VERSION'), Apple's $("$C/bin/awk" --version), uname -s Darwin, LANG=$lang"
exec env -u LC_ALL LANG="$lang" PATH="$C/bin:$PATH" "$C/bin/bash" "$WF/test/run.sh"
