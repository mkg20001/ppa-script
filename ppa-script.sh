#!/bin/bash

set -e

DISTS=""

ARCHS="amd64 arm64 armel armhf i386 mips mipsel mips64el ppc64el s390x" # https://www.debian.org/ports/

l() { # TODO: better log
  echo "$(date +%s): $*"
}

log() {
  l "$@"
}

_tmp_init() {
  op="$PWD"
  tmp="/tmp/$$.$RANDOM"
  mkdir "$tmp"
  cd "$tmp"
}

_tmp_exit() {
  cd "$op"
  rm -rf "$tmp"
}

_set() {
  n="$1"
  shift
  declare -g "$n"="$*"
}

_get() {
  n="$1"
  echo "${!n}"
}

_ap() {
  if [ -z "$(_get $1)" ]; then
    _set "$1" "$2"
  else
    _set "$1" "$(_get $1) $2"
  fi
}

_db_() {
  f="$OUT_R/.db/$1"
  if [ ! -e "$f" ]; then
    touch "$f"
  fi
}

_db_w() {
  _db_ "$1"
  c=$(cat "$f" | grep -v "^$2=" || echo "")
  k="$2"
  shift
  shift
  echo "$c
$k=$*" > "$f"
}

_db_r() {
  _db_ "$1"
  cat "$f" | grep "^$2=" | sed "s|^$2=||" || echo ""
}

_db_a() {
  _db_ "$1"
  cur=$(_db_r "$1" "$2")
  if [ -z "$cur" ]; then
    _db_w "$1" "$2" "$3"
  else
    _db_w "$1" "$2" "$cur $3"
  fi
}

from_gh() {
  :
}

c_file() {
  if [ -z "$(_get F_$1)" ]; then
    _set "F_$1" "$2"
  else
  _set "F_$1" "$(_get F_$1)
$2"
  fi
}

w_file() {
  mkdir -p $(dirname "$OUT/$2")
  _get "F_$1" > "$OUT/$2"
}

ap_var() {
  c_file "$1" "$2: $(_get $3)"
}

add_dist() { # ARGS: <dist-code> <origin> <label> [<desc>] [<suite>] [<version>] [<codename>]
  log "ppa: Add $1 ($2) '$3'"
  DISTS="$DISTS $1"
  _set "ARCHS_$1" ""
  _set "COMPS_$1" ""
  _set "DIST_$1_ORIGIN" "$2"
  _set "DIST_$1_LABEL" "$3"
  if [ -z "$2" ]; then
    _set "DIST_$1_DESC" "$(ubuntu-distro-info --series=$1 -f)"
  else
    _set "DIST_$1_DESC" "$2"
  fi
  if [ -z "$5" ]; then
    _set "DIST_$1_SUITE" "$1"
  else
    _set "DIST_$1_SUITE" "$5"
  fi
  if [ -z "$6" ]; then
    _set "DIST_$1_VERSION" "$(ubuntu-distro-info --series=$1 -r | sed "s| .*||g")"
  else
    _set "DIST_$1_VERSION" "$6"
  fi
  if [ -z "$7" ]; then
    _set "DIST_$1_CODENAME" "$1"
  else
    _set "DIST_$1_CODENAME" "$7"
  fi
}

add_comp() { # ARGS: <dist> <comp>
  log "ppa->$1: Add arch $2"
  _ap "COMPS_$1" "$2"
}

add_arch() { # ARGS: <dist> <comp>
  log "ppa->$1: Add component $2"
  _ap "ARCHS_$1" "$2"
}

hash_files() {
  algo="$1"
  algoname="$2"
  c_file "$dist" "$algoname:"
  for f in $(find "$OUT/dists/$dist" -type f); do
    r=$("${algo}sum" "$f" | sed "s| .*||g")
    rp=${f/"$OUT/dists/$dist/"/}
    size=$(du -b "$f" | sed "s|\t.*||g")
    while [ "${#size}" != "16" ]; do
      size=" $size"
    done
    c_file "$dist" " $r $size $rp"
  done
}

_init() {
  l "ppa: Loading repo @ $OUT"
  mkdir -p "$OUT/pool"
  mkdir -p "$OUT/.db"
  rm -rf "$OUT/.tmp"
  mkdir -p "$OUT/.tmp"
  OUT_R="$OUT"
  OUT="$OUT_R/.tmp"
}

fin() {
  log "ppa: Updating repo files"
  for dist in $DISTS; do
    ap_var "$dist" "Origin" "DIST_${dist}_ORIGIN"
    ap_var "$dist" "Label" "DIST_${dist}_LABEL"
    ap_var "$dist" "Suite" "DIST_${dist}_SUITE"
    ap_var "$dist" "Version" "DIST_${dist}_VERSION"
    ap_var "$dist" "Codename" "DIST_${dist}_CODENAME"
    c_file "$dist" "Date: $(date -Ru | sed "s|+0000|UTC|")"
    c_file "$dist" "Architectures: $(_get ARCHS_${dist})"
    c_file "$dist" "Components: $(_get COMPS_${dist})"
    ap_var "$dist" "Description" "DIST_${dist}_DESC"

    for comp in $(_get "COMPS_$dist"); do
      for arch in $(_get "ARCHS_$dist"); do
        log "ppa->$dist->$comp->$arch: Generating Release & Packages"
        ap_var "${dist}_${comp}_${arch}" "Archive" "dist"
        ap_var "${dist}_${comp}_${arch}" "Version" "DIST_${dist}_VERSION"
        ap_var "${dist}_${comp}_${arch}" "Component" "comp"
        ap_var "${dist}_${comp}_${arch}" "Origin" "DIST_${dist}_ORIGIN"
        ap_var "${dist}_${comp}_${arch}" "Label" "DIST_${dist}_LABEL"
        ap_var "${dist}_${comp}_${arch}" "Architecture" "arch"
        w_file "${dist}_${comp}_${arch}" "dists/$dist/$comp/binary-$arch/Release"

        _tmp_init
        for pkg in $(_db_r "${dist}_${comp}_${arch}_pkg" "files"); do
          ln "$OUT_R/pool/$pkg" "$tmp/$pkg"
        done
        sc_pkg=$(dpkg-scanpackages .)
        echo "$sc_pkg" | gzip > "$OUT/dists/$dist/$comp/binary-$arch/Packages.gz"
        echo "$sc_pkg" | xz > "$OUT/dists/$dist/$comp/binary-$arch/Packages.xz"
        _tmp_exit
      done
    done

    log "ppa->$dist: Hashing"

    hash_files "md5" "MD5Sum"
    hash_files "sha1" "SHA1"
    hash_files "sha256" "SHA256"

    w_file "$dist" "dists/$dist/Release"

    log "ppa->$dist: Signing"

    gpg2 --armor --output "$OUT/dists/$dist/InRelease"   --clearsign   "$OUT/dists/$dist/Release"
    gpg2 --armor --output "$OUT/dists/$dist/Release.gpg" --detach-sign "$OUT/dists/$dist/Release"
  done

  log "ppa: Replacing files"

  _tmp_init
  if [ -e "$OUT_R/dists" ]; then
    mv "$OUT_R/dists" "$tmp"
  fi
  mv "$OUT/dists" "$OUT_R/dists"
  _tmp_exit
  rm -rf "$OUT"

  log "DONE!"
}

# Pkg add

add_pkg_file() { # ARGS: <filename> <arch> <comp> <dist=*>
  FILE="$1"
  ARCH="$2"
  COMP="$3"
  DIST="$4"
  name=$(basename "$FILE")
  log "ppa: Adding $name (arch=$ARCH, comp=$COMP, dist=$DIST)"
  [ -z "$DIST" ] && DIST="$DISTS"
  cp "$name" "$OUT_R/pool/" # TODO: rm outdated
  for dist in $DIST; do
    if [ -z "$COMP" ]; then
      COMP2=$(_get "COMPS_$dist")
    else
      COMP2="$COMP"
    fi
    for comp in $COMP2; do
      if [ -z "$ARCH" ]; then
        ARCH2=$(_get "ARCHS_$dist")
      else
        ARCH2="$ARCH"
      fi
      for arch in $ARCH2; do
        _db_a "${dist}_${comp}_${arch}_pkg" "files" "$name"
        log "ppa->$dist->$comp->$arch: Adding $name"
      done
    done
  done
}

add_url() {
  PKG="$1"
  URL="$2"
  ARCH="$3"
  COMP="$4"
  DIST="$5"
  log "url->$PKG: Adding $URL (arch=$ARCH, comp=$COMP, dist=$DIST)"
  v="LATEST_${ARCH}_${COMP}_${DIST}"
  v2="FILE_${ARCH}_${COMP}_${DIST}"
  cpkg=$(_db_r "_$PKG" "$v")
  cfile=$(_db_r "_$PKG" "$v2")
  if [ "$cpkg" != "$URL" ]; then
    log "url->$PKG: Update..."
    if [ ! -z "$cfile" ]; then
      rm "$OUT_R/pool/$cfile"
      # TODO: cleanup from pkg lists
    fi
    _tmp_init
    wget "$URL"
    f=$(dir "$tmp")
    add_pkg_file "$tmp/$f" "$ARCH" "$COMP" "$DIST"
    _tmp_exit
    _db_w "_$PKG" "$v" "$URL"
    _db_w "_$PKG" "$v2" "$f"
  else
    log "url->$PKG: Up-to-date!"
  fi

}

add_url_auto() {
  PKG="$1"
  URL="$2"
  COMP="$3"
  DIST="$4"
  for arch in $ARCHS; do
    if basename "$URL" | grep "[^a-z]$arch[^a-z]" > /dev/null; then
      ARCH="$arch"
    fi
  done
  if [ -z "$ARCH" ]; then
    log "url->$PKG: Failed to autodetect arch for $URL"
    exit 2
  fi
  add_url "$PKG" "$URL" "$ARCH" "$COMP" "$DIST"
}

add_gh_pkg() {
  PKG="$1"
  REPO="$2"
  COMP="$3"
  DIST="$4"
  ARCH_HINT="$5"
  for deb in $(curl -s https://api.github.com/repos/$REPO/releases/latest?per_page=100 | jq -c ".assets[] | [ .browser_download_url ]" | grep -o "https.*.deb"); do
    if [ ! -z "$ARCH_HINT" ]; then
      add_url "$PKG" "$deb" "$ARCH_HINT" "$COMP" "$DIST"
    else
      add_url_auto "$PKG" "$deb" "$COMP" "$DIST"
    fi
  done
}

. config.sh # TODO: make this more dynamic
