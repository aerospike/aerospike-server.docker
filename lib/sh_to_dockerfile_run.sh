#!/usr/bin/env bash
# Convert a bash install script into a Dockerfile inline RUN \ block.
# Defines _sh_to_dockerfile_run(script_path [hadolint_ignore]).
# Copyright 2014-2025 Aerospike, Inc. Licensed under Apache-2.0. See LICENSE.

# _sh_to_dockerfile_run <script_path> [<hadolint_ignore_rules>]
#
# Converts a bash install script into a Dockerfile RUN \ block with
# { } compound-command sections (DOI-accepted pattern).
#
# Sections in the bash source are delimited by triplets of the form:
#   # --------...--------  (comment line of 10+ dashes)
#   # Section name
#   # --------...--------
#
# Output format:
#   # Install Aerospike Server and Tools
#   # hadolint ignore=DL3003,...
#   RUN \
#     { \
#       # Section name.
#       stmt1; \
#       ...
#     }; \
#     echo "done";
#
# Conversion rules (per line):
#   shebang / top-level `set -`    stripped entirely
#   `function` keyword             stripped (e.g. `function _f()` -> `_f()`)
#   file-header comment preamble   stripped (all-comment lines before first section)
#   comment (#)                    append ` \`   (no semicolon; runs to EOL)
#   line already ending with \     kept as-is (multi-line cmd continuation)
#   block opener (ends {/do/then, starts `case`)   append ` \`
#   else / elif                    append ` \`
#   block closer (fi/done/esac/}/};)               append `; \`
#   case `;;` terminator           append ` \`
#   pipeline/logical end (| || &&) append ` \`
#   line already ending with `;`   append ` \`
#   anything else                  append `; \`
#   last line of entire block      no suffix (hardcoded `echo "done";`)
function _sh_to_dockerfile_run() {
    local script_path=$1
    local hadolint_ignore="${2:-DL3003,DL3008,DL3041,SC2015}"

    awk -v hadolint="${hadolint_ignore}" '
    # -------------------------------------------------------------------
    # is_sep: true when the line is a section-separator comment
    #   Format: "#" + optional spaces + 10 or more dashes, nothing else.
    #   Uses only substr/length for portability (no {n,m} quantifiers).
    # -------------------------------------------------------------------
    function is_sep(line,    s, i, n, c) {
        if (substr(line, 1, 1) != "#") return 0
        s = line
        sub(/^#[[:space:]]*/, "", s)
        n = length(s)
        if (n < 10) return 0
        for (i = 1; i <= n; i++) {
            c = substr(s, i, 1)
            if (c != "-") return 0
        }
        return 1
    }

    # -------------------------------------------------------------------
    # line_out: return the Dockerfile continuation line for one body line.
    # Prepends 4-space base indent + original indentation from the source.
    # -------------------------------------------------------------------
    function line_out(raw,    stripped, i, c, n, pfx) {
        # Measure original leading whitespace
        n = 0
        for (i = 1; i <= length(raw); i++) {
            c = substr(raw, i, 1)
            if (c == " " || c == "\t") n++
            else break
        }
        stripped = substr(raw, n + 1)
        pfx = "    "
        for (i = 1; i <= n; i++) pfx = pfx " "

        # Already has backslash continuation (e.g. multi-line apt-get install)
        if (raw ~ /\\[[:space:]]*$/) return pfx stripped

        # Comment — backslash only (comment text runs to physical EOL)
        if (stripped ~ /^#/) return pfx stripped " \\"

        # Block openers: no semicolon before the backslash
        if (stripped ~ /\{[[:space:]]*$/)                   return pfx stripped " \\"
        if (stripped ~ /(^|[[:space:]])do[[:space:]]*$/)    return pfx stripped " \\"
        if (stripped ~ /(^|[[:space:]])then[[:space:]]*$/)  return pfx stripped " \\"
        if (stripped ~ /^case[[:space:]]/)                  return pfx stripped " \\"

        # Control-flow keywords that follow a prior statement (else/elif)
        if (stripped ~ /^else([[:space:]]|$)/)              return pfx stripped " \\"
        if (stripped ~ /^elif([[:space:]]|$)/)              return pfx stripped " \\"

        # Block closers: must have a semicolon before the backslash
        if (stripped ~ /^fi([[:space:]]|$)/    ||
            stripped ~ /^done([[:space:]]|$)/  ||
            stripped ~ /^esac([[:space:]]|$)/  ||
            stripped == "}"                    ||
            stripped == "};") {
            if (stripped ~ /;[[:space:]]*$/) return pfx stripped " \\"
            return pfx stripped "; \\"
        }

        # case pattern double-semicolon
        if (stripped ~ /;;[[:space:]]*$/)                   return pfx stripped " \\"

        # Pipeline or logical-operator continuation
        if (stripped ~ /[|&][[:space:]]*$/)                 return pfx stripped " \\"

        # Already semicolon-terminated
        if (stripped ~ /;[[:space:]]*$/)                    return pfx stripped " \\"

        # Default: append semicolon
        return pfx stripped "; \\"
    }

    # -------------------------------------------------------------------
    # flush_section: emit the current buffered section as a { } block.
    # -------------------------------------------------------------------
    function flush_section(    i) {
        if (sec_n == 0 && sec_name == "") return
        print "  { \\"
        if (sec_name != "") print "    # " sec_name "."
        for (i = 1; i <= sec_n; i++) print line_out(sec_lines[i])
        print "  }; \\"
        # Reset buffer
        sec_n    = 0
        sec_name = ""
        delete sec_lines
    }

    # -------------------------------------------------------------------
    # BEGIN: initialise state and print the RUN block header.
    # -------------------------------------------------------------------
    BEGIN {
        state        = "preamble"   # preamble | saw_sep1 | saw_name | in_body
        sec_name     = ""
        pending_name = ""
        sec_n        = 0
        print "# Install Aerospike Server and Tools"
        print "# hadolint ignore=" hadolint
        print "RUN \\"
    }

    # Strip shebang line
    /^#!/ { next }

    # Strip top-level `set -` flags
    /^set[[:space:]]+-/ { next }

    {
        # Strip the `function` keyword from function definitions.
        # match() sets RSTART/RLENGTH (POSIX); no gawk extensions needed.
        if (match($0, /function[[:space:]]+/)) {
            $0 = substr($0, 1, RSTART - 1) substr($0, RSTART + RLENGTH)
        }
        line = $0

        # ------ Separator line ------
        if (is_sep(line)) {
            if (state == "preamble") {
                # First separator opens the first section triplet
                state = "saw_sep1"
            } else if (state == "saw_name") {
                # Closing separator of triplet — begin collecting body
                flush_section()        # flush prior section (no-op for first)
                sec_name = pending_name
                sec_n    = 0
                delete sec_lines
                state    = "in_body"
            } else if (state == "in_body") {
                # Opening separator of the next section triplet
                flush_section()
                state = "saw_sep1"
            }
            next
        }

        # ------ Reading section name (line after opening separator) ------
        if (state == "saw_sep1") {
            pending_name = line
            sub(/^#[[:space:]]*/, "", pending_name)
            state = "saw_name"
            next
        }

        # Skip blank lines everywhere
        if (line ~ /^[[:space:]]*$/) next

        # Skip preamble content (file-header comments before first section)
        if (state == "preamble") next

        # ------ Collecting section body ------
        if (state == "in_body") {
            sec_n++
            sec_lines[sec_n] = line
        }
    }

    # ------ END: flush last section, then emit the final statement ------
    END {
        flush_section()
        print "  echo \"done\";"
    }
    ' "$script_path"
}
