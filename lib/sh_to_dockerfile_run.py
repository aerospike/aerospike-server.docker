#!/usr/bin/env python3
"""Convert a bash install script to a Dockerfile inline RUN \\ block.

Usage:  python3 sh_to_dockerfile_run.py <script.sh>
Output: Dockerfile RUN \\ block printed to stdout.

Output format (matches DOI-accepted reference Dockerfile structure)
-------------------------------------------------------------------
# Install Aerospike Server and Tools
# hadolint ignore=DL3003,DL3008,DL3041,SC2015
RUN \\
  { \\
    # Section name.
    stmt1; \\
    stmt2; \\
  }; \\
  { \\
    # Next section.
    ...
  }; \\
  echo "done";

Sections are delimited in the bash source by triplets of the form:
    # ----...---- (10+ dashes)
    # Section name
    # ----...---- (10+ dashes)

Each triplet becomes a  { }  compound command block in the output.

Conversion rules (per line inside a section body)
--------------------------------------------------
- Strip shebang (#!) and top-level `set -` lines.
- Strip block-separator triplets (they become section boundaries).
- Remove `function` keyword from function definitions.
- Comments (#): append ` \\` (no semicolon; comment runs to physical EOL).
- Lines already ending with `\\` (multi-line commands): kept as-is;
  the original bash `\\<newline>` becomes the Dockerfile continuation.
- Block-opener endings (`{`, `do`, `then`, `case ... in`): ` \\`.
- Control keywords at line start (`else`, `elif`): ` \\`.
- Block-closer keywords (`fi`, `done`, `esac`, `}`, `};`): `; \\`.
- Pipeline/logical endings (`|`, `||`, `&&`): ` \\`.
- `;;` (case double-semicolon): ` \\`.
- Lines already ending with `;`: ` \\`.
- All other statements: `; \\`.
- Last content line of the entire block: no suffix.
"""

import re
import sys
import pathlib


# ---------------------------------------------------------------------------
# Suffix helpers
# ---------------------------------------------------------------------------

def _is_block_opener(s: str) -> bool:
    """True for lines that open a bash block (no `;` needed before the `\\`)."""
    if s.endswith("{"):
        return True
    if re.search(r"\bdo$", s):
        return True
    if re.search(r"\bthen$", s):
        return True
    if re.match(r"^\s*case\b", s):  # case ... in
        return True
    return False


def _is_control_keyword(s: str) -> bool:
    """True for `else`/`elif` — always preceded by a `;`-terminated statement."""
    return bool(re.match(r"^(else|elif)\b", s))


def _is_block_closer(s: str) -> bool:
    """True for lines that close a bash block (need `;` before the `\\`)."""
    return bool(re.match(r"^(fi|done|esac)\b", s)) or s in ("}", "};")


# ---------------------------------------------------------------------------
# Section parsing
# ---------------------------------------------------------------------------

_SEP_RE = re.compile(r"^#\s*-{10,}\s*$")


def _split_sections(lines: list[str]) -> list[tuple[str, list[str]]]:
    """Split filtered lines into [(section_name, body_lines), ...].

    A section is delimited by a triplet:
        # --------...--------
        # Section name
        # --------...--------
    Everything before the first triplet becomes a nameless preamble section.
    Everything after the last triplet's closing separator becomes the last
    section's body.
    """
    sep_idxs = [i for i, ln in enumerate(lines) if _SEP_RE.match(ln.strip())]

    sections: list[tuple[str, list[str]]] = []
    prev_body_end = 0  # start index for the next search pass
    i = 0

    while i < len(sep_idxs):
        s0 = sep_idxs[i]

        # Any content before this separator is a nameless preamble.
        # Skip preambles that are entirely comments — these are file-level
        # documentation headers (copyright, expected ARGs, etc.) that belong
        # in the source file but add no value when inlined into a Dockerfile.
        preamble = [ln for ln in lines[prev_body_end:s0] if ln.strip()]
        if preamble and not all(ln.lstrip().startswith("#") for ln in preamble):
            sections.append(("", preamble))

        # Try to form a triplet: sep[i] / name_line / sep[i+1]
        if (
            i + 1 < len(sep_idxs)
            and sep_idxs[i + 1] == s0 + 2
            and not _SEP_RE.match(lines[s0 + 1].strip())  # middle line is the name
        ):
            name = lines[s0 + 1].strip().lstrip("#").strip()
            body_start = sep_idxs[i + 1] + 1
            # Body ends at the next opening separator or end of content
            body_end = sep_idxs[i + 2] if i + 2 < len(sep_idxs) else len(lines)
            body = [ln for ln in lines[body_start:body_end] if ln.strip()]
            sections.append((name, body))
            prev_body_end = body_end
            i += 2  # consume both separators of this triplet
        else:
            # Orphaned separator — skip
            prev_body_end = s0 + 1
            i += 1

    # Any remaining lines after all section triplets
    remaining = [ln for ln in lines[prev_body_end:] if ln.strip()]
    if remaining:
        sections.append(("", remaining))

    return sections


# ---------------------------------------------------------------------------
# Line-level suffix logic
# ---------------------------------------------------------------------------

def _line_suffix(stripped: str, s: str, is_last: bool) -> str:
    """Return (prefix + stripped + suffix) for one content line inside a { } block.

    `stripped` is the whitespace-stripped line content.
    `s` is the rstripped-but-indent-preserved original line.
    `is_last` is True for the very last content line of the entire RUN block.
    """
    # All section content gets 4-space base indent + original indent
    orig_indent = len(s) - len(s.lstrip())
    pfx = "    " + " " * orig_indent

    if is_last:
        return pfx + stripped

    if stripped.startswith("#"):
        # Comment — backslash only (no semicolon; comment runs to EOL in bash)
        return pfx + stripped + " \\"

    if s.rstrip().endswith("\\"):
        # Already has backslash continuation (e.g. multi-line apt-get install)
        return pfx + stripped

    if _is_block_opener(stripped):
        return pfx + stripped + " \\"

    if _is_control_keyword(stripped):
        return pfx + stripped + " \\"

    if _is_block_closer(stripped):
        return pfx + (stripped if stripped.endswith(";") else stripped + ";") + " \\"

    if stripped.endswith(";;"):
        return pfx + stripped + " \\"

    if re.search(r"[|&]$", stripped):
        return pfx + stripped + " \\"

    if stripped.endswith(";"):
        return pfx + stripped + " \\"

    return pfx + stripped + "; \\"


# ---------------------------------------------------------------------------
# Main converter
# ---------------------------------------------------------------------------

def sh_to_dockerfile_run(
    script_text: str,
    hadolint_ignore: str = "DL3003,DL3008,DL3041,SC2015",
) -> str:
    """Return the Dockerfile `RUN \\` block for the given bash script text."""
    lines = script_text.splitlines()

    # Pass 1: filter and normalise
    filtered: list[str] = []
    for line in lines:
        if line.startswith("#!"):                  # shebang
            continue
        if re.match(r"^set\s+-", line):            # top-level set flags
            continue
        line = re.sub(r"^(\s*)function\s+(\w)", r"\1\2", line)  # drop `function`
        filtered.append(line)

    # Strip surrounding blank lines
    while filtered and not filtered[0].strip():
        filtered.pop(0)
    while filtered and not filtered[-1].strip():
        filtered.pop()

    # Parse into named sections
    sections = _split_sections(filtered)

    # Build output
    result: list[str] = [
        "# Install Aerospike Server and Tools",
        f"# hadolint ignore={hadolint_ignore}",
        "RUN \\",
    ]

    for name, body in sections:
        result.append("  { \\")
        if name:
            result.append(f"    # {name}.")
        for line in body:
            s = line.rstrip()
            stripped = s.lstrip()
            # Never mark a section body line as the global last — all section
            # body lines are followed by `  }; \` and must keep their suffix.
            result.append(_line_suffix(stripped, s, is_last=False))
        result.append("  }; \\")

    # Replace the very last `}; \` with `}; \` and append `  echo "done";`
    # (the last section's closing brace still needs `\` because echo follows)
    result.append('  echo "done";')

    return "\n".join(result) + "\n"


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: sh_to_dockerfile_run.py <script.sh>", file=sys.stderr)
        sys.exit(1)
    text = pathlib.Path(sys.argv[1]).read_text()
    print(sh_to_dockerfile_run(text), end="")
