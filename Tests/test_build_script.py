"""Exercise the build wrapper with fake Xcode tools, never an Apple SDK build."""
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = shutil.which("bash")
if os.name == "nt":
    git_bash = Path("C:/Program Files/Git/bin/bash.exe")
    BASH = str(git_bash) if git_bash.exists() else None


@unittest.skipUnless(BASH, "Bash is required for build-wrapper tests")
class BuildScriptTests(unittest.TestCase):
    def run_build(self, mode):
        with tempfile.TemporaryDirectory(prefix="extenddesk-build-test-") as temporary:
            project = Path(temporary)
            (project / "scripts").mkdir()
            (project / "MacCompanion").mkdir()
            binary = project / "bin"
            binary.mkdir()
            for name in ("build-mac.sh", "build_diagnostics.py"):
                shutil.copyfile(ROOT / "scripts" / name, project / "scripts" / name)
            stubs = {
                "xcodegen": "#!/bin/sh\nexit 0\n",
                "python3": '#!/bin/sh\nexec "$BUILD_TEST_PYTHON" "$@"\n',
                "xcodebuild": """#!/bin/sh
case "$PWD" in
  */MacCompanion)
    if [ "$BUILD_TEST_MODE" = "mac-fails" ]; then
      echo 'LinkApp.swift:20:3: error: mock Mac compiler diagnostic'
      exit 7
    fi
    ;;
  *)
    if [ "$BUILD_TEST_MODE" = "ios-fails" ]; then
      echo 'PhotosController.swift:257:17: error: mock iOS compiler diagnostic'
      exit 42
    fi
    ;;
esac
echo '** BUILD SUCCEEDED **'
exit 0
""",
            }
            for name, body in stubs.items():
                path = binary / name
                path.write_text(body, encoding="utf-8", newline="\n")
                path.chmod(0o755)
            environment = os.environ.copy()
            environment["BUILD_TEST_PYTHON"] = sys.executable.replace("\\", "/")
            environment["BUILD_TEST_MODE"] = mode
            result = subprocess.run(
                [BASH, "--noprofile", "--norc", "-c", 'export PATH="$PWD/bin:$PATH"; bash scripts/build-mac.sh'],
                cwd=project, env=environment, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=30,
            )
            logs = {path.name: path.read_text(encoding="utf-8") for path in (project / "build/logs").glob("*.log")}
            return result, logs

    def test_ios_failure_preserves_exit_code_and_does_not_build_mac(self):
        result, logs = self.run_build("ios-fails")
        self.assertEqual(result.returncode, 42, result.stdout + result.stderr)
        self.assertEqual(len(logs), 1)
        self.assertIn("mock iOS compiler diagnostic", next(iter(logs.values())))
        self.assertIn("Compiler/build error diagnostics", result.stdout)

    def test_mac_failure_preserves_exit_code_and_both_logs(self):
        result, logs = self.run_build("mac-fails")
        self.assertEqual(result.returncode, 7, result.stdout + result.stderr)
        self.assertEqual(len(logs), 2)
        self.assertIn("mock Mac compiler diagnostic", result.stdout)

    def test_success_builds_both_targets(self):
        result, logs = self.run_build("success")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(logs), 2)
        self.assertTrue(all("BUILD SUCCEEDED" in value for value in logs.values()))


if __name__ == "__main__":
    unittest.main()
