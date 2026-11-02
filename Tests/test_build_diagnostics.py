import importlib.util
from pathlib import Path
import unittest

script = Path(__file__).resolve().parents[1] / "scripts/build_diagnostics.py"
spec = importlib.util.spec_from_file_location("build_diagnostics", script)
diagnostics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diagnostics)


class BuildDiagnosticTests(unittest.TestCase):
    def test_user_warning_and_failed_summary_are_not_a_root_error(self):
        log = """48 | DispatchQueue.main.async { [weak self] in
warning: 'weak' ownership of capture 'self' differs from implicitly-captured strong reference in outer scope
** BUILD FAILED **
The following build commands failed:
SwiftEmitModule normal arm64 Emitting module for ExtendDesk
"""
        self.assertEqual(diagnostics.error_blocks(log), [])

    def test_source_error_includes_context_and_deduplicates_architectures(self):
        error = "/Users/test/Downloads/extends-display/Sources/App.swift:12:8: error: cannot find type 'Missing' in scope"
        blocks = diagnostics.error_blocks(f"SwiftCompile arm64\n{error}\n12 | let value: Missing\n   |        ^\nSwiftCompile x86_64\n{error}")
        self.assertEqual(len(blocks), 1)
        self.assertIn("let value: Missing", blocks[0])

    def test_driver_error_and_ansi_are_preserved_without_escape_codes(self):
        blocks = diagnostics.error_blocks("\x1b[31merror: emit-module command failed with exit code 1\x1b[0m\nDetails")
        self.assertEqual(len(blocks), 1)
        self.assertNotIn("\x1b", blocks[0])

    def test_warning_quoting_word_error_is_not_a_diagnostic(self):
        self.assertEqual(diagnostics.error_blocks("source.swift:1:1: warning: text contains error: in a quoted example"), [])


if __name__ == "__main__":
    unittest.main()
