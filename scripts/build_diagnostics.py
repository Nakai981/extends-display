"""Summarize real Xcode error diagnostics without mistaking warnings for failures."""
from pathlib import Path
import os
import re
import sys

ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
ERROR = re.compile(r"\b(?:fatal\s+)?error:\s", re.IGNORECASE)
SOURCE_ERROR = re.compile(r"^(?P<file>.+?):(?P<line>\d+):(?P<column>\d+):\s*(?:fatal\s+)?error:\s*(?P<message>.*)$")


def github_annotations(log: str, workspace: str, limit: int = 8) -> list[str]:
    """Expose source diagnostics in the public CI check, not just private job logs."""
    results = []
    seen = set()
    prefix = workspace.replace("\\", "/").rstrip("/") + "/"

    def escape(value, prop=False):
        value = value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
        return value.replace(":", "%3A").replace(",", "%2C") if prop else value

    for line in ANSI.sub("", log).splitlines():
        match = SOURCE_ERROR.match(line)
        if not match or line in seen:
            continue
        seen.add(line)
        source = match["file"].replace("\\", "/")
        properties = ""
        if workspace and source.startswith(prefix):
            source = source[len(prefix):]
            properties = f' file={escape(source, True)},line={match["line"]},col={match["column"]}'
        results.append(f'::error{properties}::{escape(match["message"])}')
        if len(results) >= limit:
            break
    return results


def error_blocks(log: str, limit: int = 8) -> list[str]:
    lines = ANSI.sub("", log).splitlines()
    results = []
    seen = set()
    for index, line in enumerate(lines):
        match = ERROR.search(line)
        if not match or "warning:" in line[:match.start()].lower():
            continue
        # Architecture-parallel builds often repeat the same diagnostic.
        key = line.strip()
        if key in seen:
            continue
        seen.add(key)
        start = max(0, index - 1)
        end = min(len(lines), index + 7)
        results.append("\n".join(lines[start:end]))
        if len(results) >= limit:
            break
    return results


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: python3 scripts/build_diagnostics.py <xcodebuild.log>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    try:
        log = path.read_text(encoding="utf-8", errors="replace")
        blocks = error_blocks(log)
    except OSError as error:
        print(f"Cannot read build log: {error}", file=sys.stderr)
        return 2
    print(f"\nFull build log: {path.resolve()}")
    if blocks:
        print("Compiler/build error diagnostics (warnings excluded):\n")
        print("\n\n".join(blocks))
    else:
        print("No error: diagnostics found in this log. A warning or BUILD FAILED summary alone does not identify the failed command's cause.")
    if os.environ.get("GITHUB_ACTIONS") == "true":
        for annotation in github_annotations(log, os.environ.get("GITHUB_WORKSPACE", "")):
            print(annotation)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
