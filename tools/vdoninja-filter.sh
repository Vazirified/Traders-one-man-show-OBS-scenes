#!/bin/sh
# Git clean/smudge filter that keeps VDO.Ninja stream IDs out of commits.
#
#   clean   (on git add)      vdo.ninja/?v=REAL_ID  ->  vdo.ninja/?v=__VDO_NINJA_STREAM_ID__
#   smudge  (on checkout)     placeholder  ->  the ID in local git config vdoninja.streamid
#
# Wired up by install.ps1 in .git/config (never pushed):
#   filter.vdoninja.clean  = sh tools/vdoninja-filter.sh clean
#   filter.vdoninja.smudge = sh tools/vdoninja-filter.sh smudge
# With no ID configured, the placeholder is left as-is.

placeholder=__VDO_NINJA_STREAM_ID__

case "$1" in
  clean)
    exec sed -E '/vdo\.ninja/ s#([?&](v|view|push)=)[^&"]+#\1'"$placeholder"'#g'
    ;;
  smudge)
    id=$(git config vdoninja.streamid)
    exec sed "s/$placeholder/${id:-$placeholder}/g"
    ;;
  *)
    echo "usage: $0 clean|smudge" >&2
    exit 2
    ;;
esac
