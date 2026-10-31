# Issue tracker: GitHub

本仓库的需求、问题和规格存放在 jonascyang/DeepThink 的 GitHub Issues，使用 `gh` CLI 操作。

## Conventions

以下命令在本仓库内执行；在其他目录执行时，显式添加 `--repo jonascyang/DeepThink`。

- 创建：`gh issue create --title "<标题>" --body-file <正文文件>`
- 查看：`gh issue view <编号> --json number,title,body,labels,comments`
- 列出：`gh issue list --state open --json number,title,body,labels,comments`
- 评论：`gh issue comment <编号> --body-file <正文文件>`
- 标签：`gh issue edit <编号> --add-label "<标签>"` 或 `--remove-label "<标签>"`
- 关闭：`gh issue close <编号>`

多行正文先写入临时文件，再用 `--body-file` 提交。标签映射见 `triage-labels.md`。

子问题使用 `gh issue create --parent <父编号>`，或 `gh issue edit <父编号> --add-sub-issue <子编号>`。
不支持子问题时，在子问题正文顶部写 `Part of #<父编号>`，并在父问题中维护清单。

## Pull requests as a triage surface

PRs as a request surface: no.

## Skill operations

- “publish to the issue tracker”：创建 GitHub issue。
- “fetch the relevant ticket”：读取对应 GitHub issue。

## Wayfinding operations

- Map：单个 issue，标签 `wayfinder:map`，正文维护 Notes、Decisions-so-far、Fog。
- Child ticket：关联到 Map 的子问题，使用 `wayfinder:<type>` 标签；type 为 research、prototype、grilling 或 task。
- Blocking：优先用 GitHub 原生依赖。以 `gh api --method POST repos/jonascyang/DeepThink/issues/<子编号>/dependencies/blocked_by -F issue_id=<阻塞问题数据库ID>` 添加；数据库 ID 用 `gh api repos/jonascyang/DeepThink/issues/<编号> --jq .id` 获取。
- 无原生依赖时，在正文顶部写 `Blocked by: #<编号>`。所有阻塞问题关闭后才算解除阻塞。
- Frontier：按 Map 中的顺序选择首个未关闭、无未解除阻塞且无人负责的子问题。
- Claim：`gh issue edit <编号> --add-assignee @me`。
- Resolve：评论结果、关闭子问题，再把结论摘要和链接补入 Map 的 Decisions-so-far。
