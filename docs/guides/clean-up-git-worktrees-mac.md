---
layout: guide
title: "Clean up old Git worktrees on macOS"
description: "Find Git worktrees created by AI coding agents. Check for local changes, preserve ignored files such as .env, and reclaim disk space from old checkouts."
permalink: /guides/clean-up-git-worktrees-mac/
---

Run `git worktree list` from the repository to find linked checkouts left by AI coding agents. Before removing a worktree, check its branch and status, confirm that its work has been saved, and copy any ignored files you still need. Ignored files such as `.env` and local databases usually live only in that checkout.

## Check the checkout before removing it

```sh
git worktree list
git -C "/path/to/worktree" status --short --ignored
```

Use the path reported by Git. In the status output, `??` marks untracked files and `!!` marks ignored files. Check for local edits, confirm the branch's commits are where you want them, and save the ignored files you will need. If a dev server is running from the checkout, [finish the session and stop its processes](../stop-leftover-ai-agent-dev-servers-mac/) first.

When a linked worktree is clean and disposable, remove it with Git:

```sh
git worktree remove "/path/to/worktree"
```

If Git refuses, review the reason before proceeding. The command registers the removal with Git and leaves the branch in the repository. [Git worktree documentation](https://git-scm.com/docs/git-worktree) · [Git status documentation](https://git-scm.com/docs/git-status)

## Slim a worktree or recycle it with SpawnSweep

Open **Storage** to see worktree status and size by repository.

- **Slim** deletes eligible, rebuildable folders such as ignored `node_modules` or `.next` while keeping the checkout, source and local configuration. When you return to the worktree, reinstall dependencies or rebuild generated files.
- **Recycle** previews the removal of an eligible worktree and saves ignored files that cannot be rebuilt, such as `.env` and local databases. **Restore** can recreate the checkout and put those saved files back during your configured retention period. Reinstall dependencies after restoring.

Use Slim when you anticipate returning to a branch but want its dependencies off disk. Review the Recycle preview when the checkout has served its purpose. [SpawnSweep cleanup rules](../../#safety)
