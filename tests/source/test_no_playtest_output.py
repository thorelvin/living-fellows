"""Playtest output stays out of the repository: no tracked file may match the ignore rules."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]


def tracked_but_ignored():
    """Return tracked paths matching .gitignore, or None outside a git checkout."""
    try:
        inside = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--is-inside-work-tree"],
                                capture_output=True, text=True, check=False)
    except FileNotFoundError:
        return None
    if inside.returncode != 0 or inside.stdout.strip() != "true":
        return None
    listed = subprocess.run(["git", "-C", str(ROOT), "ls-files", "-ci", "--exclude-standard"],
                            capture_output=True, text=True, check=True)
    return [line for line in listed.stdout.splitlines() if line.strip()]


class NoPlaytestOutput(unittest.TestCase):
    def test_no_tracked_file_matches_the_ignore_rules(self):
        paths = tracked_but_ignored()
        if paths is None:
            self.skipTest("not a git checkout")
        self.assertEqual(paths, [], "Untrack these with git rm --cached and summarize them in docs/: "
                         + ", ".join(paths[:20]))

    def test_rules_cover_screenshots_and_run_logs(self):
        rules = (ROOT / ".gitignore").read_text(encoding="utf-8").splitlines()
        for rule in ("/artifacts/**/*.png", "/artifacts/**/*events.txt", "/artifacts/**/*summary.txt",
                     "/artifacts/**/provenance.txt", "/artifacts/**/project-gate.txt"):
            self.assertIn(rule, rules)


if __name__ == "__main__":
    unittest.main()
