#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

WORKDIR="${WORKDIR:-$ROOT_DIR/workdir}"
NETBIRD_DIR="${NETBIRD_DIR:-$WORKDIR/repos/netbird}"
SOURCE_CFG="$NETBIRD_DIR/.goreleaser.yaml"
SOURCE_UI_CFG="$NETBIRD_DIR/.goreleaser_ui.yaml"
SOURCE_UI_DARWIN_CFG="$NETBIRD_DIR/.goreleaser_ui_darwin.yaml"
TARGET_CFG="$NETBIRD_DIR/.goreleaser.awg.yaml"
TARGET_NFPM_CFG="$NETBIRD_DIR/.goreleaser.awg.nfpm.yaml"
TARGET_UI_DARWIN_CFG="$NETBIRD_DIR/.goreleaser_ui_darwin.awg.yaml"

if [[ ! -f "$SOURCE_CFG" ]]; then
  echo "[error] source goreleaser config not found: $SOURCE_CFG"
  exit 1
fi

if [[ ! -f "$SOURCE_UI_CFG" ]]; then
  echo "[error] source goreleaser ui config not found: $SOURCE_UI_CFG"
  exit 1
fi

if [[ ! -f "$SOURCE_UI_DARWIN_CFG" ]]; then
  echo "[error] source goreleaser darwin ui config not found: $SOURCE_UI_DARWIN_CFG"
  exit 1
fi

python3 - "$SOURCE_CFG" "$SOURCE_UI_CFG" "$TARGET_CFG" "$TARGET_NFPM_CFG" <<'PY'
from pathlib import Path
import re
import sys

root_src = Path(sys.argv[1]).read_text(encoding="utf-8", errors="surrogateescape").splitlines(keepends=True)
ui_src = Path(sys.argv[2]).read_text(encoding="utf-8", errors="surrogateescape").splitlines(keepends=True)

target_main_path = Path(sys.argv[3])
target_nfpm_path = Path(sys.argv[4])

root_build_ids = {"netbird"}
ui_build_ids = {"netbird-ui-windows-amd64"}
allowed_universal_ids = set()

top_key = re.compile(r"^([a-zA-Z_][a-zA-Z0-9_-]*):")
top_list_item = re.compile(r"^  - ")
id_line = re.compile(r"^\s{2,4}(?:-\s*)?id:\s*([^\s#]+)")


def split_sections(lines):
    sections = {}
    i = 0
    while i < len(lines):
        m = top_key.match(lines[i])
        if not m:
            i += 1
            continue
        key = m.group(1)
        j = i + 1
        while j < len(lines):
            n = top_key.match(lines[j])
            if n:
                break
            j += 1
        sections[key] = lines[i:j]
        i = j
    return sections


def split_list_block(block_lines):
    if not block_lines:
        return [], []
    header = [block_lines[0]]
    items = []
    current = []
    saw_item = False

    for line in block_lines[1:]:
        if top_list_item.match(line):
            saw_item = True
            if current:
                items.append(current)
            current = [line]
            continue
        if saw_item:
            current.append(line)
        else:
            header.append(line)

    if current:
        items.append(current)
    return header, items


def item_id(item_lines):
    for line in item_lines:
        m = id_line.match(line)
        if m:
            return m.group(1)
    return None


def item_build_refs(item_lines):
    refs = set()
    in_builds = False
    for line in item_lines:
        if re.match(r"^    builds:\s*$", line) or re.match(r"^  -\s*builds:\s*$", line):
            in_builds = True
            continue
        if in_builds:
            m = re.match(r"^      -\s*([^\s#]+)", line)
            if m:
                refs.add(m.group(1))
                continue
            if re.match(r"^    [^ ]", line) or re.match(r"^  -\s*[a-zA-Z_][a-zA-Z0-9_-]*:\s*$", line):
                in_builds = False
    return refs


def rewrite_item_build_refs(item_lines, allowed_build_ids):
    out = []
    in_builds = False
    kept_build_refs = 0

    for line in item_lines:
        if re.match(r"^    builds:\s*$", line) or re.match(r"^  -\s*builds:\s*$", line):
            in_builds = True
            kept_build_refs = 0
            out.append(line)
            continue

        if in_builds:
            m = re.match(r"^      -\s*([^\s#]+)", line)
            if m:
                if m.group(1) in allowed_build_ids:
                    out.append(line)
                    kept_build_refs += 1
                continue

            if re.match(r"^    [^ ]", line) or re.match(r"^  -\s*[a-zA-Z_][a-zA-Z0-9_-]*:\s*$", line):
                if kept_build_refs == 0:
                    return []
                in_builds = False
                out.append(line)
                continue

            out.append(line)
            continue

        out.append(line)

    if in_builds and kept_build_refs == 0:
        return []

    return out


def filter_block_by_ids(block_lines, allowed_ids):
    header, items = split_list_block(block_lines)
    kept = []
    for item in items:
        identifier = item_id(item)
        if identifier in allowed_ids:
            kept.extend(item)
    if not kept:
        return []
    return header + kept


def map_items(block_lines, mapper):
    header, items = split_list_block(block_lines)
    out_items = []
    for item in items:
        mapped = mapper(item)
        if mapped:
            out_items.append(mapped)
    if not out_items:
        return []
    out = list(header)
    for item in out_items:
        out.extend(item)
    return out


def filter_block_by_build_refs(block_lines, allowed_build_ids):
    header, items = split_list_block(block_lines)
    kept = []
    for item in items:
        updated_item = rewrite_item_build_refs(item, allowed_build_ids)
        if not updated_item:
            continue
        refs = item_build_refs(updated_item)
        if refs & allowed_build_ids:
            kept.extend(updated_item)
    if not kept:
        return []
    return header + kept


def merge_list_blocks(block_a, block_b):
    if not block_a and not block_b:
        return []
    if not block_a:
        return block_b
    if not block_b:
        return block_a

    header_a, items_a = split_list_block(block_a)
    _, items_b = split_list_block(block_b)

    merged = list(header_a)
    for item in items_a:
        merged.extend(item)
    for item in items_b:
        merged.extend(item)
    return merged


def netbird_binary_archives_block():
    return [
        "archives:\n",
        "  - id: netbird-binaries\n",
        "    builds:\n",
        "      - netbird\n",
        "    name_template: \"{{ .ProjectName }}_{{ .Version }}_{{ .Os }}_{{ .Arch }}\"\n",
        "    formats:\n",
        "      - binary\n",
    ]


def normalize_block(block):
    if not block:
        return []
    out = list(block)
    if not out[-1].endswith("\n"):
        out[-1] += "\n"
    return out


def restrict_netbird_build(item_lines):
    if item_id(item_lines) != "netbird":
        return item_lines

    out = []
    i = 0
    while i < len(item_lines):
        line = item_lines[i]

        if re.match(r"^    goos:\s*$", line):
            out.append(line)
            out.append("      - linux\n")
            i += 1
            while i < len(item_lines) and re.match(r"^      - ", item_lines[i]):
                i += 1
            continue

        if re.match(r"^    goarch:\s*$", line):
            out.append(line)
            out.append("      - amd64\n")
            out.append("      - arm64\n")
            i += 1
            while i < len(item_lines) and re.match(r"^      - ", item_lines[i]):
                i += 1
            continue

        if re.match(r"^    ignore:\s*$", line):
            i += 1
            while i < len(item_lines):
                if re.match(r"^      - ", item_lines[i]):
                    i += 1
                    while i < len(item_lines) and re.match(r"^        ", item_lines[i]):
                        i += 1
                    continue
                break
            continue

        out.append(line)
        i += 1

    return out


def strip_extra_files_block(block_lines):
    if not block_lines:
        return []

    out = []
    i = 0
    while i < len(block_lines):
        line = block_lines[i]
        if re.match(r"^\s{2}extra_files:\s*$", line):
            i += 1
            while i < len(block_lines) and re.match(r"^\s{4}- ", block_lines[i]):
                i += 1
            continue
        out.append(line)
        i += 1
    nonempty = [line for line in out if line.strip()]
    if len(nonempty) == 1 and re.match(r"^checksum:\s*$", nonempty[0]):
        return []
    return out


def ensure_release_overwrite(block_lines):
    if not block_lines:
        return ["release:\n", "  replace_existing_artifacts: true\n"]

    out = [block_lines[0]]
    has_replace_flag = False
    i = 1
    while i < len(block_lines):
        line = block_lines[i]
        if re.match(r"^\s{2}extra_files:\s*$", line):
            i += 1
            while i < len(block_lines) and re.match(r"^\s{4}- ", block_lines[i]):
                i += 1
            continue
        if re.match(r"^\s{2}replace_existing_artifacts:\s*(true|false)\s*$", line):
            if not has_replace_flag:
                out.append("  replace_existing_artifacts: true\n")
                has_replace_flag = True
            i += 1
            continue
        out.append(line)
        i += 1

    if not has_replace_flag:
        out.insert(1, "  replace_existing_artifacts: true\n")
    return out


def package_snapshot_block():
    return [
        "snapshot:\n",
        "  version_template: \"{{ .Env.NETBIRD_PACKAGE_VERSION }}\"\n",
    ]


def package_dist_block():
    return [
        "dist: dist-nfpm\n",
    ]


def netbird_archlinux_nfpms_block():
    return [
        "nfpms:\n",
        "  - maintainer: Netbird <dev@netbird.io>\n",
        "    description: Netbird client.\n",
        "    homepage: https://netbird.io/\n",
        "    id: netbird-archlinux\n",
        "    bindir: /usr/bin\n",
        "    builds:\n",
        "      - netbird\n",
        "    formats:\n",
        "      - archlinux\n",
        "\n",
        "    scripts:\n",
        "      postinstall: \"release_files/post_install.sh\"\n",
        "      preremove: \"release_files/pre_remove.sh\"\n",
    ]


root_sections = split_sections(root_src)
ui_sections = split_sections(ui_src)

root_builds = filter_block_by_ids(root_sections.get("builds", []), root_build_ids)
root_builds = map_items(root_builds, restrict_netbird_build)
ui_builds = filter_block_by_ids(ui_sections.get("builds", []), ui_build_ids)
merged_builds = merge_list_blocks(root_builds, ui_builds)

merged_archives = netbird_binary_archives_block()

root_nfpms = filter_block_by_build_refs(root_sections.get("nfpms", []), root_build_ids)
ui_nfpms = []
merged_nfpms = merge_list_blocks(root_nfpms, ui_nfpms)
merged_nfpms = merge_list_blocks(merged_nfpms, netbird_archlinux_nfpms_block())

universal_binaries = filter_block_by_ids(root_sections.get("universal_binaries", []), allowed_universal_ids)

sections_in_order = [
    root_sections.get("version", []),
    root_sections.get("project_name", []),
    merged_builds,
    universal_binaries,
    merged_archives,
    merged_nfpms,
    strip_extra_files_block(root_sections.get("checksum", [])),
    ensure_release_overwrite(root_sections.get("release", [])),
]

out_main = []
for block in sections_in_order:
    norm = normalize_block(block)
    if not norm:
        continue
    out_main.extend(norm)
    if out_main and out_main[-1].strip() != "":
        out_main.append("\n")

if out_main and out_main[-1].strip() == "":
    out_main.pop()

target_main_path.write_text("".join(out_main), encoding="utf-8", errors="surrogateescape")

sections_nfpm = [
    root_sections.get("version", []),
    root_sections.get("project_name", []),
    package_dist_block(),
    root_builds,
    merged_nfpms,
    package_snapshot_block(),
]

out_nfpm = []
for block in sections_nfpm:
    norm = normalize_block(block)
    if not norm:
        continue
    out_nfpm.extend(norm)
    if out_nfpm and out_nfpm[-1].strip() != "":
        out_nfpm.append("\n")

if out_nfpm and out_nfpm[-1].strip() == "":
    out_nfpm.pop()

target_nfpm_path.write_text("".join(out_nfpm), encoding="utf-8", errors="surrogateescape")
PY

python3 - "$SOURCE_UI_DARWIN_CFG" "$TARGET_UI_DARWIN_CFG" <<'PY'
from pathlib import Path
import re
import sys

src = Path(sys.argv[1]).read_text(encoding="utf-8", errors="surrogateescape").splitlines(keepends=True)
dst = Path(sys.argv[2])

top_key = re.compile(r"^([a-zA-Z_][a-zA-Z0-9_-]*):")
top_list_item = re.compile(r"^  - ")
id_line = re.compile(r"^\s{2,4}(?:-\s*)?id:\s*([^\s#]+)")


def split_sections(lines):
    sections = {}
    i = 0
    while i < len(lines):
        m = top_key.match(lines[i])
        if not m:
            i += 1
            continue
        key = m.group(1)
        j = i + 1
        while j < len(lines):
            if top_key.match(lines[j]):
                break
            j += 1
        sections[key] = lines[i:j]
        i = j
    return sections


def split_list_block(block_lines):
    if not block_lines:
        return [], []
    header = [block_lines[0]]
    items = []
    current = []
    saw_item = False
    for line in block_lines[1:]:
        if top_list_item.match(line):
            saw_item = True
            if current:
                items.append(current)
            current = [line]
            continue
        if saw_item:
            current.append(line)
        else:
            header.append(line)
    if current:
        items.append(current)
    return header, items


def item_id(item_lines):
    for line in item_lines:
        m = id_line.match(line)
        if m:
            return m.group(1)
    return None


def filter_block_by_ids(block_lines, allowed_ids):
    header, items = split_list_block(block_lines)
    kept = []
    for item in items:
        if item_id(item) in allowed_ids:
            kept.extend(item)
    if not kept:
        return []
    return header + kept


def strip_gomips(item_lines):
    out = []
    i = 0
    while i < len(item_lines):
        line = item_lines[i]
        if re.match(r"^    gomips:\s*$", line):
            i += 1
            while i < len(item_lines) and re.match(r"^      - ", item_lines[i]):
                i += 1
            continue
        out.append(line)
        i += 1
    return out


def map_items(block_lines, mapper):
    header, items = split_list_block(block_lines)
    out_items = []
    for item in items:
        mapped = mapper(item)
        if mapped:
            out_items.append(mapped)
    if not out_items:
        return []
    out = list(header)
    for item in out_items:
        out.extend(item)
    return out


def normalize_block(block):
    if not block:
        return []
    out = list(block)
    if not out[-1].endswith("\n"):
        out[-1] += "\n"
    return out


def literal_block(lines):
    return [f"{line}\n" if not line.endswith("\n") else line for line in lines]


sections = split_sections(src)
builds = filter_block_by_ids(sections.get("builds", []), {"netbird-ui-darwin"})
builds = map_items(builds, strip_gomips)

out_blocks = [
    sections.get("version", []),
    sections.get("project_name", []),
    builds,
    literal_block(["archives: []"]),
    literal_block(["checksum:", "  disable: true"]),
    literal_block(["changelog:", "  disable: true"]),
]

out = []
for block in out_blocks:
    norm = normalize_block(block)
    if not norm:
        continue
    out.extend(norm)
    if out and out[-1].strip() != "":
        out.append("\n")

if out and out[-1].strip() == "":
    out.pop()

dst.write_text("".join(out), encoding="utf-8", errors="surrogateescape")
PY

# Force AWG version suffix in binaries regardless of which git tag goreleaser resolves.
for cfg in "$TARGET_CFG" "$TARGET_NFPM_CFG" "$TARGET_UI_DARWIN_CFG"; do
  perl -0pi -e 's/github\.com\/netbirdio\/netbird\/version\.version=\{\{\.Version\}\}/github.com\/netbirdio\/netbird\/version.version=\{\{ .Env.NETBIRD_RELEASE_TAG \}\}/g' "$cfg"
done

echo "[ok] generated goreleaser config: $TARGET_CFG"
echo "[ok] generated goreleaser config: $TARGET_NFPM_CFG"
echo "[ok] generated goreleaser config: $TARGET_UI_DARWIN_CFG"
