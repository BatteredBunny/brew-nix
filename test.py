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
    ("app", "1kc-razer"),  # multi-partition HFS dmg, digit-start token
    ("app", "86box"),  # zip, digit-start token
    ("app", "1password@7"),  # zip, @-versioned token
    ("app", "rectangle"),  # HFS dmg wrapped in a volume-name folder
    ("app", "appcleaner"),  # zip
    ("app", "alfred"),  # tar.gz
    ("app", "ammonite"),  # tar.xz
    ("app", "fauxpas"),  # tar.bz2
    ("app", "kitty"),  # APFS dmg
    ("app", "sabaki"),  # 7z
    ("app", "raycast"),  # dmg fetched from URL with no archive extension
    ("app", "whatsapp"),  # extensionless zip with nested framework links
    ("pkg", "alfaview"),  # flat pkg
    ("pkg", "aquaskk"),  # flat pkg
    ("pkg", "sage"),  # dmg with both .app and .pkg
    ("pkg", "tailscale-app"), # pkg with pbzx
    ("binary", "7777"),  # bare Mach-O (no archive extension)
    ("binary", "ngrok"),  # binary inside zip
    ("binary", "fly"),  # binary inside .tgz
    ("binary", "rar"),  # binary inside tar.gz
    ("binary", "matterhorn"),  # binary inside tar.bz2
    ("binary", "aws-vault-binary"),  # binary inside dmg
]
MAX_PARALLEL = int(os.environ.get("TEST_JOBS", "4"))

VARIATIONS: list[tuple[str, str, str, bool]] = [
    ("vlc", "x86_64-darwin", "arm64", False),
    ("vlc", "x86_64-darwin", "intel64", True),
    ("vlc", "aarch64-darwin", "arm64", True),
    ("audacity", "x86_64-darwin", "x86_64", True),
    ("audacity", "aarch64-darwin", "arm64", True),
    ("gimp", "x86_64-darwin", "x86_64", True),
    ("gimp", "aarch64-darwin", "arm64", True),
    ("visual-studio-code", "x86_64-darwin", "darwin-arm64", False),
    ("visual-studio-code", "aarch64-darwin", "darwin-arm64", True),
]


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


def check_run(kind: Kind, cask: str) -> tuple[Kind, str, str | None]:
    proc = subprocess.run(
        ["nix", "build", f".#{cask}", "--no-link", "--print-out-paths"],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        return kind, cask, proc.stderr.strip()
    store = Path(proc.stdout.strip().splitlines()[-1])
    proc = subprocess.run(
        ["nix", "eval", "--raw", f".#{cask}.meta.mainProgram"],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        return kind, cask, proc.stderr.strip()
    main_program = proc.stdout.strip()
    if kind == "pkg" and not (store / "bin").is_dir():
        return kind, cask, None
    entry = store / "bin" / main_program
    try:
        assert entry.is_file(), f"bin/{main_program} missing"
        assert os.access(entry, os.X_OK), f"bin/{main_program} not executable"
        return kind, cask, None
    except AssertionError as e:
        return kind, cask, str(e)


def check_variation(
    cask: str, system: str, needle: str, want: bool
) -> tuple[str, str | None]:
    label = f"{cask} {system} url {'has' if want else 'lacks'} {needle!r}"
    proc = subprocess.run(
        ["nix", "eval", "--raw", f".#packages.{system}.{cask}.src.url"],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        return label, proc.stderr.strip()
    url = proc.stdout.strip()
    if (needle in url) != want:
        return label, f"got {url}"
    return label, None


def run_variations() -> int:
    print(
        f"checking {len(VARIATIONS)} url variations, {MAX_PARALLEL} at once", flush=True
    )
    passed = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_PARALLEL) as pool:
        futures = [
            pool.submit(check_variation, cask, system, needle, want)
            for cask, system, needle, want in VARIATIONS
        ]
        for future in concurrent.futures.as_completed(futures):
            label, error = future.result()
            status = "FAIL" if error else "PASS"
            line = f"[{status}] {label}"
            if error:
                line += f"\n  {error}"
            print(line, flush=True)
            passed += not error
    return passed


def run_builds() -> int:
    print(f"\nbuilding {len(CASKS)} casks, {MAX_PARALLEL} at once\n", flush=True)
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
    return passed


def run_runs() -> int:
    print(
        f"\nverifying mainProgram for {len(CASKS)} casks, {MAX_PARALLEL} at once\n",
        flush=True,
    )
    passed = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_PARALLEL) as pool:
        futures = [pool.submit(check_run, kind, cask) for kind, cask in CASKS]
        for future in concurrent.futures.as_completed(futures):
            kind, cask, error = future.result()
            status = "FAIL" if error else "PASS"
            line = f"[{status}] {kind} {cask} mainProgram"
            if error:
                line += f"\n  {error}"
            print(line, flush=True)
            passed += not error
    return passed


def main() -> int:
    os.chdir(Path(__file__).resolve().parent)
    passed = run_variations() + run_builds() + run_runs()
    total = len(VARIATIONS) + len(CASKS) * 2
    print(f"\nPassed: {passed}/{total}")
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
