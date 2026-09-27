#!/usr/bin/env bash
# PostToolUse hook (Write|Edit|MultiEdit): give files Claude writes in this
# project CRLF line endings, matching the Windows checkout (.gitattributes).
# Files that .gitattributes keeps LF (shell scripts, video captions) are
# converted to LF instead; unix2dos/dos2unix skip binary files.

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
    *.png|*.jpg|*.jpeg|*.tga|*.blp|*.ttf|*.otf|*.mp3|*.ogg|*.wav|*.zip|*.mp4) exit 0 ;;
esac

# Follow the eol attribute from .gitattributes (e.g. "*.sh text eol=lf").
eol=$(cd "$project" && git check-attr eol -- "$file" 2>/dev/null | sed 's/.*: eol: //')
if [ "$eol" = "lf" ]; then
    dos2unix -q "$file"
else
    unix2dos -q "$file"
fi
