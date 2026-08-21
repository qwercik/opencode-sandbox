# TODO — Full Symlink Support

## Current Status

The script detects and mounts **only top-level symlinks** in `$PWD` (one level deep).

```bash
for entry in "$PWD"/*; do
  [ -L "$entry" ] || continue
  target=$(readlink -f "$entry")
  EXTRA_MOUNTS+=(-v "$target:/project/$PROJECT_NAME/$(basename "$entry")")
done
```

## What's Missing

### 1. Nested Symlinks

If `project1` is a symlink, and inside it there's `project1/src/link -> /real/target` — the second one won't be mounted. Inside the container it appears as a broken symlink.

Solution: after mounting a top-level symlink, scan its resolved target (`readlink -f`) recursively.

### 2. `find -L` + `-type l` Trap

`find -L "$PWD" -type l` with `-L` and `-type l` finds **only broken** symlinks. Working symlinks are treated as their target type. Must use `find` without `-L` or use Python's `os.path.islink`.

### 3. Bash Subshell Issues

With pipe (`find ... | while read ...`), variables assigned inside `while` are not visible in the parent. Solutions:
- process substitution: `while ... done < <(find ...)`
- temporary file: `find ... > /tmp/mounts && while ... done < /tmp/mounts`
- inline Python (returns string on stdout)

### 4. Mount Ordering

The order of `-v` flags in Docker matters — parent must be mounted before child. Currently `for entry in "$PWD"/*` works because glob doesn't guarantee order, but for a single level it doesn't matter (no parent-child relationships among top-level entries). For nested symlinks — sorting by depth is needed.

### 5. Escape Prevention from Workspace

`find -L` could follow a symlink to `/etc` and scan further. In that case, symlinks found inside `/etc` have a parent outside the workspace — they must be filtered using `case "$link_dir_real" in "$PWD"/*)`.

## Recommendation

If nested symlinks are actually needed, rewrite the block in inline Python:

```bash
EXTRA_MOUNTS=$(python3 -c "
import os, sys
workdir = os.path.realpath('$PWD')
seen = set()
mounts = []

def scan(root):
    for dirpath, dirnames, filenames in os.walk(root):
        for entry in dirnames + filenames:
            path = os.path.join(dirpath, entry)
            if os.path.islink(path):
                target = os.path.realpath(path)
                if target in seen:
                    continue
                seen.add(target)
                rel = os.path.relpath(path, workdir)
                mounts.append(f'-v {target}:/project/$PROJECT_NAME/{rel}')
                if os.path.isdir(target):
                    scan(target)

scan(workdir)
print(' '.join(mounts))
")
```

Advantages: no subshell issues, no `:` in paths, no sorting problems. Recursion in Python is cleaner.