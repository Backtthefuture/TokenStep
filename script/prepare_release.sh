#!/usr/bin/env bash
set -euo pipefail

# Prepares the release documents for a new version, the edits
# docs/RELEASE.md lists under "Publish to GitHub":
#
#   - CHANGELOG.md gets the version's entry at the top.
#   - README.md's "最新版本" section, DMG links and example version move to it.
#   - script/build_swiftui_and_run.sh defaults to it.
#
# The release notes are written by hand. When docs/RELEASE_NOTES_<version>.md
# does not exist yet, this creates a template and stops so it can be filled in.
# Nothing is committed.
#
# Usage:
#   script/prepare_release.sh <version> "<CHANGELOG title>" "<one-paragraph summary>"
#
# Example:
#   script/prepare_release.sh 0.2.20 "修复额度与刘海卡片细节" "额度窗口过了重置时间显示「已重置」……"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $# -ne 3 ]]; then
  sed -n '15,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
fi

VERSION="$1"
TITLE="$2"
SUMMARY="$3"
NOTES="$ROOT_DIR/docs/RELEASE_NOTES_$VERSION.md"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must look like 0.2.20, got: $VERSION" >&2
  exit 2
fi

if [[ ! -f "$NOTES" ]]; then
  cat > "$NOTES" <<EOF
# TokenStep $VERSION

$SUMMARY

- **要点**：说明。

Token、金额与额度的统计口径不变。
EOF
  echo "Created $NOTES from a template. Fill it in, then run this again." >&2
  exit 1
fi

python3 - "$ROOT_DIR" "$VERSION" "$TITLE" "$SUMMARY" <<'PY'
import re
import sys
from pathlib import Path

root, version, title, summary = Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]


def version_key(value):
    return tuple(int(part) for part in value.split("."))


def fail(message):
    sys.exit(f"prepare_release: {message}")


notes_path = root / f"docs/RELEASE_NOTES_{version}.md"
if not notes_path.read_text().startswith(f"# TokenStep {version}\n"):
    fail(f"{notes_path.name} must start with '# TokenStep {version}'")

build_path = root / "script/build_swiftui_and_run.sh"
build = build_path.read_text()
match = re.search(r'VERSION="\$\{TOKENSTEP_VERSION:-([0-9.]+)\}"', build)
if not match:
    fail("could not find the default VERSION in build_swiftui_and_run.sh")
current = match.group(1)
if version_key(version) <= version_key(current):
    fail(f"{version} is not newer than the current {current}")

link = f"详见 [{version} 发布说明](docs/RELEASE_NOTES_{version}.md)。"
paragraph = summary.rstrip()
if not paragraph.endswith(("。", ".", "！", "？")):
    paragraph += "。"

# CHANGELOG: new entry above the first version heading.
changelog_path = root / "CHANGELOG.md"
changelog = changelog_path.read_text()
if f"## {version} 更新" in changelog:
    fail(f"CHANGELOG.md already has an entry for {version}")
first = re.search(r"^## \d+\.\d+\.\d+ ", changelog, re.M)
if not first:
    fail("could not find a version heading in CHANGELOG.md")
entry = f"## {version} 更新：{title}\n\n{paragraph}{link}\n\n"
changelog = changelog[: first.start()] + entry + changelog[first.start():]

# README: the latest-version section, DMG links and the packaging example.
readme_path = root / "README.md"
readme = readme_path.read_text()
readme, sections = re.subn(
    rf"## 最新版本：{re.escape(current)}\n\n.*?\n\n",
    f"## 最新版本：{version}\n\n{paragraph}{link}\n\n",
    readme,
    count=1,
    flags=re.S,
)
if sections != 1:
    fail(f"could not find '## 最新版本：{current}' in README.md")
dmg_links = readme.count(f"TokenStep-{current}.dmg")
if dmg_links == 0:
    fail(f"README.md has no TokenStep-{current}.dmg links")
readme = readme.replace(f"TokenStep-{current}.dmg", f"TokenStep-{version}.dmg")
readme = readme.replace(f"TOKENSTEP_VERSION={current}", f"TOKENSTEP_VERSION={version}")

build = build.replace(match.group(0), f'VERSION="${{TOKENSTEP_VERSION:-{version}}}"')

changelog_path.write_text(changelog)
readme_path.write_text(readme)
build_path.write_text(build)
print(f"{current} -> {version}: CHANGELOG entry, README section and {dmg_links} DMG links, build default.")
PY

"$ROOT_DIR/script/test_release_contract.sh"
git -C "$ROOT_DIR" status --short -- CHANGELOG.md README.md script/build_swiftui_and_run.sh "docs/RELEASE_NOTES_$VERSION.md"
