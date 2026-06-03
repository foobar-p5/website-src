#!/bin/sh

set -e

verbose=1

log() {
    [ "$verbose" = 1 ] && echo "$1"
}

err() {
    echo "[error] $1" >&2
}

setup() {
    d=$(dirname "$0")
    cf="$d/config.env"
    
    if [ ! -f "$cf" ]; then
        err "config.env not found in $d"
        exit 1
    fi
    
    while IFS='=' read -r k val; do
        case "$k" in
            TITLE) TITLE="$val" ;;
            FOOTER) FOOTER="$val" ;;
            OUTPUT) OUTPUT="$val" ;;
            INPUT) INPUT="$val" ;;
            NAVDIR) NAVDIR="$val" ;;
            NAVFILE) NAVFILE="$val" ;;
            NAVCURRENT) NAVCURRENT="$val" ;;
        esac
    done < "$cf"
    
    case "$OUTPUT" in
        /*) ;;
        ~*) OUTPUT="$HOME${OUTPUT#\~}" ;;
        *) OUTPUT="$d/$OUTPUT" ;;
    esac
    
    case "$INPUT" in
        /*) ;;
        ~*) INPUT="$HOME${INPUT#\~}" ;;
        *) INPUT="$d/$INPUT" ;;
    esac
    
    export TITLE FOOTER OUTPUT INPUT NAVDIR NAVFILE NAVCURRENT
    
    if [ -z "$TITLE" ] || [ -z "$FOOTER" ] || [ -z "$OUTPUT" ] || [ -z "$INPUT" ] || [ -z "$NAVDIR" ] || [ -z "$NAVFILE" ] || [ -z "$NAVCURRENT" ]; then
        err "missing variables in config.env"
        exit 1
    fi
    
    log "TITLE=$TITLE"
    log "INPUT=$INPUT"
    log "OUTPUT=$OUTPUT"
    log "NAVDIR=$NAVDIR"
    log "NAVFILE=$NAVFILE"
    log "NAVCURRENT=$NAVCURRENT"
    
    if [ ! -d "$INPUT" ]; then
        err "source directory not found: $INPUT"
        exit 1
    fi
    if [ ! -f "$INPUT/template.html" ]; then
        err "template.html not found in $INPUT"
        exit 1
    fi
    
    rm -rf "$OUTPUT"
    mkdir -p "$OUTPUT"
    log "setup complete"
}

cpstat() {
    log "copying static files from $INPUT..."
    
    copyfiles() {
        for f in "$1"/* "$1"/.[!.]*; do
            [ -e "$f" ] || continue
            if [ -d "$f" ]; then
                copyfiles "$f"
            elif [ -f "$f" ]; then
                case "$f" in
                    *.md|*/template.html) continue ;;
                    *)
                        rel="${f#$INPUT/}"
                        mkdir -p "$(dirname "$OUTPUT/$rel")"
                        cp "$f" "$OUTPUT/$rel"
                        log "  copied $f -> $OUTPUT/$rel"
                        ;;
                esac
            fi
        done
    }
    
    copyfiles "$INPUT"
    log "static copy complete"
}

md2h() {
    cmark -t html "$1" | sed 's/&quot;/"/g; s/&#39;/'"'"'/g'
}

tname() {
    name=${1##*/}
    name=${name%.md}
    echo "$name" | tr '-' ' '
}

bnav() {
    dir="$1"
    cur="$2"
    depth="$3"
    indent=""
    i=0
    while [ "$i" -lt "$depth" ]; do
        indent="${indent}  "
        i=$((i + 1))
    done

    for item in "$dir"/*; do
        [ ! -e "$item" ] && continue
        name=$(basename "$item")

        if [ -d "$item" ]; then
            if [ -f "$item/index.md" ]; then
                dp="${item#$INPUT}"
                [ -z "$dp" ] && dp="/"
                echo "${indent}<li><a href=\"${dp}/index.html\">${name}${NAVDIR}</a>"
            else
                echo "${indent}<li>${name}${NAVDIR}"
            fi
            echo "${indent}  <ul>"
            bnav "$item" "$cur" $((depth + 1))
            echo "${indent}  </ul>"
            echo "${indent}</li>"
        elif [ -f "$item" ] && [ "${item%.md}" != "$item" ]; then
            [ "$name" = "index.md" ] && continue
            rel="${item#$INPUT/}"
            rel="${rel%.md}.html"
            title=$(tname "$item")
            if [ "/$rel" = "$cur" ]; then
                echo "${indent}<li><a href=\"/$rel\" class=\"active-page\"><span class=\"active-indicator\">${NAVCURRENT}</span>${title}</a></li>"
            else
                echo "${indent}<li><a href=\"/$rel\">${NAVFILE}${title}</a></li>"
            fi
        fi
    done
}

rnav() {
    echo "<ul>"
    bnav "$INPUT" "$1" 1
    echo "</ul>"
}

apply() {
    awk -v t="$TITLE" -v n="$1" -v c="$2" -v f="$FOOTER" '
    {
        gsub(/\{\{TITLE\}\}/, t)
        gsub(/\{\{NAV\}\}/, n)
        gsub(/\{\{CONTENT\}\}/, c)
        gsub(/\{\{FOOTER\}\}/, f)
        print
    }
    ' "$INPUT/template.html"
}

main() {
    setup
    
    S="$INPUT"
    S="${S#./}"
    S="${S%/}"
    log "using source directory: $S"
    
    cpstat

    procmd() {
        for f in "$1"/*; do
            [ -e "$f" ] || continue
            if [ -d "$f" ]; then
                procmd "$f"
            elif [ -f "$f" ] && [ "${f##*.}" = "md" ]; then
                f="${f#./}"
                r="${f#$S/}"
                r="${r%.md}.html"
                mkdir -p "$(dirname "$OUTPUT/$r")"
                h=$(md2h "$f")
                c="/$r"
                apply "$(rnav "$c")" "$h" > "$OUTPUT/$r"
                log "wrote $OUTPUT/$r"
            fi
        done
    }
    
    procmd "$S"
    log "build complete"
}

main
