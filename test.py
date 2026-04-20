#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3
import concurrent.futures
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Literal

Kind = Literal["app", "pkg", "binary"]
BuildResult = tuple[Kind, str, float, str | None]

CASKS: list[tuple[Kind, str]] = [
    ("app", "1kc-razer"),
    ("app", "0-ad"),
    ("app", "86box"),
    ("app", "1password@7"),
    ("app", "affinity"),
    ("app", "alfred"),
    ("app", "ammonite"),
    ("app", "fauxpas"),
    ("pkg", "alfaview"),
    ("pkg", "aquaskk"),
    ("binary", "7777"),
    ("binary", "akuity"),
]
MAX_PARALLEL = int(os.environ.get("TEST_JOBS", "4"))


def is_mach_o(path: Path) -> bool:
    mime = subprocess.check_output(
        ["file", "-b", "--mime-type", path], text=True
    ).strip()
    return mime == "application/x-mach-binary"


def check_output(kind: Kind, store: Path) -> None:
    if kind == "binary":
        bin_dir = store / "bin"
        files = [p for p in bin_dir.iterdir() if p.is_file()]
        assert files, f"no files in {bin_dir}"
        for f in files:
            assert os.access(f, os.X_OK) and is_mach_o(f), (
                f"{f} not an executable Mach-O"
            )
        return

    apps = store / "Applications"
    bundles = list(apps.glob("*.app")) if apps.is_dir() else []
    assert bundles or (kind == "pkg" and (store / "Library").is_dir()), (
        f"no payload in {store}"
    )
    for bundle in bundles:
        macos = bundle / "Contents" / "MacOS"
        assert (bundle / "Contents" / "Info.plist").is_file(), (
            f"missing Info.plist in {bundle}"
        )
        assert macos.is_dir(), f"missing {macos}"
        assert any(is_mach_o(p) for p in macos.iterdir() if p.is_file()), (
            f"no Mach-O in {macos}"
        )


def build(kind: Kind, cask: str) -> BuildResult:
    start = time.monotonic()
    proc = subprocess.run(
        ["nix", "build", f".#{cask}", "--no-link", "--print-out-paths"],
        capture_output=True,
        text=True,
    )
    duration = time.monotonic() - start
    try:
        assert proc.returncode == 0, proc.stderr
        check_output(kind, Path(proc.stdout.strip().splitlines()[-1]))
        return kind, cask, duration, None
    except AssertionError as e:
        return kind, cask, duration, str(e)


def main() -> int:
    os.chdir(Path(__file__).resolve().parent)
    print(f"building {len(CASKS)} casks, {MAX_PARALLEL} at once\n", flush=True)

    passed = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_PARALLEL) as pool:
        futures = [pool.submit(build, kind, cask) for kind, cask in CASKS]
        for future in concurrent.futures.as_completed(futures):
            kind, cask, duration, error = future.result()
            status = "FAIL" if error else "PASS"
            line = f"[{status}] {kind} {cask} in {duration:.1f}s"
            if error:
                line += f"\n  {error}"
            print(line, flush=True)
            passed += not error

    print(f"\nPassed: {passed}/{len(CASKS)}")
    return 0 if passed == len(CASKS) else 1


if __name__ == "__main__":
    sys.exit(main())
