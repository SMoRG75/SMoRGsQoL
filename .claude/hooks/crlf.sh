#!/usr/bin/env bash
# PostToolUse hook (Write|Edit|MultiEdit): give files Claude writes in this
# project CRLF line endings, matching the Windows checkout (.gitattributes).
# Shell scripts stay LF (bash can't run CRLF scripts); unix2dos itself skips
# binary files.

file=$(perl -MJSON::PP -0777 -ne 'my $d = decode_json($_); print $d->{tool_input}{file_path} // ""')
[ -n "$file" ] || exit 0
file=$(cygpath -u "$file")
[ -f "$file" ] || exit 0

project=$(cygpath -u "${CLAUDE_PROJECT_DIR:-$PWD}")
case "${file,,}/" in
    "${project,,}"/*) ;;
    *) exit 0 ;;
esac

case "${file,,}" in
    *.sh|*.png|*.jpg|*.jpeg|*.tga|*.blp|*.ttf|*.otf|*.mp3|*.ogg|*.wav|*.zip) exit 0 ;;
esac

unix2dos -q "$file"
