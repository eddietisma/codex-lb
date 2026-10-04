

[local source maintenance]
- Keep local fixes as a linear stack of small, separate commits directly on `main`. Do not create feature branches or squash the fix commits unless the user explicitly requests it.
- Keep upstream source under `source/`. Import each upstream update in a separate commit and record its upstream revision. Retain or replay each local fix individually so it can be reviewed, reapplied, or dropped independently.
- Drop a local fix only after verifying that upstream contains an equivalent correction.
- Keep deployment/configuration commits separate from source fixes. Pin Docker Compose to the source revision that was tested and deployed.
- For this private deployment repository, these rules also apply to `source/`. Vendored upstream branching and pull-request instructions apply only when contributing upstream.

[rtk]
- Skip `rtk` for GitHub metadata updates. When creating or editing GitHub issues, pull requests, comments, review comments, labels, milestones, or other live GitHub state, call `gh` directly from PowerShell instead of wrapping it with `rtk`. This includes `gh issue edit`, `gh pr edit`, `gh api -X PATCH/POST/DELETE`, `gh label`, `gh issue comment`, `gh pr comment`, and verification reads done immediately before or after those updates.
- Use `F:\.tmp` for temporary Markdown/JSON bodies, write UTF-8 without BOM when possible, and pass file contents or `--body-file`/`--input` payloads to `gh` rather than inline shell-quoted Markdown. Continue using `rtk` for ordinary local repo inspection, builds, tests, and non-GitHub shell commands unless a narrower instruction says otherwise.
- When routing commands through `rtk`, prefer installed Microsoft Coreutils executables for simple file/text operations to avoid PowerShell quoting issues. Use `rtk powershell -NoProfile -Command "..."` only when PowerShell cmdlets or PowerShell-specific features are required.

@C:\Users\sonicue\.codex\RTK.md
