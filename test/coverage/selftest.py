#!/usr/bin/env python3
"""TEST-25: can the coverage wiring go red?

The nightly coverage job is report-only, so it is deliberately not part of
check-all's hard gates. That makes its *wiring* the thing worth pinning: a job
that was deleted, no longer runs the script, or stops uploading its artifact
must be reported as a failure, not silently leave the project without a
coverage report. This selftest checks the real files and then mutates each
piece in memory to prove the check can fail (the G5 negative-fixture rule).

Usage:  python3 test/coverage/selftest.py
Exit:   0 all real checks pass and every mutation is caught; 1 otherwise.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
NIGHTLY = ROOT / ".github/workflows/nightly.yml"
RUNNER = ROOT / "test/coverage/run.sh"


def job_block(text: str, name: str):
    """The 2-space-indented YAML block of job `name`, or None."""
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if re.fullmatch(r"  " + re.escape(name) + r":\s*", line):
            j = i + 1
            while j < len(lines):
                # A new job starts at the same 2-space indentation with a key
                # followed by a colon; step names are indented further.
                if re.match(r"^  [A-Za-z0-9_-]+:\s*$", lines[j]):
                    break
                j += 1
            return "\n".join(lines[i:j])
    return None


def check(nightly: str, runner: str):
    errors = []
    job = job_block(nightly, "coverage")
    if job is None:
        errors.append("nightly.yml: no 'coverage:' job")
    else:
        if not re.search(r"runs-on:\s*\S+", job):
            errors.append("nightly.yml coverage job: no runs-on")
        if "test/coverage/run.sh" not in job:
            errors.append("nightly.yml coverage job: does not run test/coverage/run.sh")
        if "upload-artifact" not in job:
            errors.append("nightly.yml coverage job: does not upload an artifact")
        if not re.search(r"path:\s*.*coverage", job):
            errors.append("nightly.yml coverage job: artifact path does not name the coverage output")
    if "--coverage" not in runner:
        errors.append("test/coverage/run.sh: no --coverage instrumentation")
    if "gcov" not in runner:
        errors.append("test/coverage/run.sh: no gcov invocation")
    if "summary.txt" not in runner:
        errors.append("test/coverage/run.sh: no summary.txt output")
    if "exit 1" not in runner:
        errors.append("test/coverage/run.sh: no hard failure path for a broken report")
    return errors


def selftest():
    nightly = NIGHTLY.read_text(encoding="utf-8")
    runner = RUNNER.read_text(encoding="utf-8")
    failures = []

    errors = check(nightly, runner)
    if errors:
        failures.append("real wiring is red: " + "; ".join(errors))

    # Each mutation removes one load-bearing piece; the check must name it.
    job = job_block(nightly, "coverage")
    mutations = [
        ("no coverage job", nightly.replace(job, "") if job else nightly,
         runner, "no 'coverage:' job"),
        ("no artifact upload", nightly.replace("upload-artifact", "upload-nothing"),
         runner, "does not upload an artifact"),
        ("script not run", nightly.replace("test/coverage/run.sh", "true"),
         runner, "does not run test/coverage/run.sh"),
        ("no gcov", nightly, runner.replace("gcov", "true"), "no gcov"),
        ("no instrumentation", nightly, runner.replace("--coverage", ""),
         "no --coverage"),
    ]
    for name, n, r, needle in mutations:
        errs = check(n, r)
        if not errs:
            failures.append(f"mutation '{name}' was not caught")
        elif not any(needle in e for e in errs):
            failures.append(f"mutation '{name}' failed for the wrong reason: {errs}")

    if failures:
        for f in failures:
            print("FAIL coverage-wiring: " + f, file=sys.stderr)
        return 1
    print(f"coverage-wiring: 1 real check + {len(mutations)} negative mutations, all as expected")
    return 0


if __name__ == "__main__":
    sys.exit(selftest())
