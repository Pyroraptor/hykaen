# Hykaen — Claude Code / AEF Agent Instructions

## Commit hygiene: data files MUST be committed

After writing or modifying any file under `data/` (e.g. `.tres` character/encounter/spell
resources), you MUST stage and commit those files before ending your session.

The test gate (pytest) runs against the working tree, so it will pass even if data files
are only written to disk but not committed. The reviewer checks `git log` / `git status`
and will BLOCK the feature if data files exist only as working-tree edits.

**Required pattern before finishing any implementation step:**

```bash
git status          # confirm all expected files are listed
git add data/       # stage all data-directory changes
git add <other modified files>
git commit -m "feat(...): ..."
git status          # verify working tree is clean
```

Do NOT assume data files were committed by a previous step — always run `git status`
at the end of your session and commit anything that is still modified.
