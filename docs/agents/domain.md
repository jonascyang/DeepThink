# Domain docs

本仓库采用 single-context：一套产品术语和根目录 docs/adr/ 决定记录。

## 阅读顺序

- 理解产品范围时，先读 docs/PRD.md。
- 术语先读 CONTEXT.md，沿用其中的定义和避免使用的近义词。
- 根目录 GLOSSARY.md 若存在，也应读取；当前术语定义仍以 CONTEXT.md 为准，不另建重复词表。
- 阅读 docs/adr/ 中与当前工作相关的决定。提出与 ADR 冲突的方案时，明确指出冲突和重开讨论的理由。
- GLOSSARY.md 或其他可选领域文档不存在时，直接继续，不把缺失当成问题，不为凑齐结构提前创建。

## 后续布局

保持一个根目录 GLOSSARY.md 和 docs/adr/，不引入多上下文目录或 GLOSSARY-MAP.md。
只有实际出现需要新增的术语或决定时，才由 domain-modeling 按已有定义维护。
