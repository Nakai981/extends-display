"""Summarize real Xcode error diagnostics without mistaking warnings for failures."""
from pathlib import Path
import re
import sys

ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
ERROR = re.compile(r"\b(?:fatal\s+)?error:\s", re.IGNORECASE)


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
        blocks = error_blocks(path.read_text(encoding="utf-8", errors="replace"))
    except OSError as error:
        print(f"Cannot read build log: {error}", file=sys.stderr)
        return 2
    print(f"\nFull build log: {path.resolve()}")
    if blocks:
        print("Compiler/build error diagnostics (warnings excluded):\n")
        print("\n\n".join(blocks))
    else:
        print("No error: diagnostics found in this log. A warning or BUILD FAILED summary alone does not identify the failed command's cause.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
