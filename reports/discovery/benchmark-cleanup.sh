#!/bin/bash
# Run against a committed public source snapshot. All writes go to a scratch directory.
set -euo pipefail

source_root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
revision=$(git -C "$source_root" rev-parse HEAD)
python=$(command -v python3)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/spawnsweep-benchmark.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
scratch=$(cd "$scratch" && pwd -P)

mkdir "$scratch/source"
git -C "$source_root" archive "$revision" Package.swift Sources/SpawnSweep | tar -xf - -C "$scratch/source"
cp "$source_root/reports/discovery/CleanupBenchmark.swift" "$scratch/source/Sources/SpawnSweep/App/"
"$python" -I - "$scratch/source/Sources/SpawnSweep/App/SpawnSweepApp.swift" <<'PYTHON'
import sys
from pathlib import Path

entry = Path(sys.argv[1])
source = entry.read_text()
anchor = "        let args = CommandLine.arguments\n"
if source.count(anchor) != 1:
    raise SystemExit("SpawnSweep entry point changed. Inspect it before running the benchmark.")
entry.write_text(source.replace(anchor, anchor + "        if args.contains(\"--cleanup-fixture\") { CleanupBenchmark.run(); return }\n"))
PYTHON
swift build --package-path "$scratch/source" >&2

unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
printf 'Source revision: %s\n' "$revision"
printf 'Environment: macOS %s, %s\n' "$(sw_vers -productVersion)" "$(uname -m)"
printf 'fixture_run,eligible_worktrees,processes_stopped,ports_released,disk_bytes_removed,cleanup_ms\n'

for run in 1 2 3; do
    sample="$scratch/run-$run"
    repo="$sample/repo"
    tree="$sample/.codex/worktrees/finished-task"
    mkdir -p "$repo" "$(dirname "$tree")"
    git -C "$repo" init -q -b main --template=
    printf 'node_modules/\n.env\n' > "$repo/.gitignore"
    printf 'export const fixture = true;\n' > "$repo/app.js"
    git -C "$repo" add .gitignore app.js
    git -C "$repo" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm 'Add fixture files'
    git -C "$repo" worktree add -q -b codex/finished-task "$tree"
    mkdir "$tree/node_modules"
    dd if=/dev/urandom of="$tree/node_modules/fixture.bin" bs=1048576 count=16 2>/dev/null
    printf 'FIXTURE_VALUE=test-only\n' > "$tree/.env"

    SPAWNSWEEP_FIXTURE_TREE="$tree" "$scratch/source/.build/debug/SpawnSweep" --cleanup-fixture "$repo" "$tree" "$python" "$run"
done
