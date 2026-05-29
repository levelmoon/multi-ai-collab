# 两 AI 协作协议(PROTOCOL)

本仓库由两个 AI 协作完成:**R(Reviewer/Architect)** + **E(Executor)**。
本文件是契约,`handoff/` 里其他所有文件都从这里派生。

## 角色

| 角色 | 写什么 | 拥有什么 |
|---|---|---|
| **R** | spec.md, review.md, answer.md, FOR_E.md | 架构决策、step 准入 |
| **E** | report.md, question.md, 源代码, commits | 实现、git 状态 |

**R 永不**编辑源代码,**永不** `git commit`。
**E 永不**修改本文件或两份 loop 文件(`EXECUTOR_LOOP.md` / `REVIEWER_LOOP.md`)。

## 文件清单

```
handoff/
  PROTOCOL.md           ← 规则(R 写一次)
  ARCHITECTURE.md       ← 项目不变量(R, 持久)
  REQUIREMENTS.md       ← 权威用户需求(R, 同步)
  EXECUTOR_LOOP.md      ← E 的常驻指令(R, 持久)
  REVIEWER_LOOP.md      ← R 的常驻指令(R, 持久)
  INDEX.md              ← 状态追踪,两边追加
  step-N-spec.md        ← R: 这一 step 做什么
  step-N-report.md      ← E: 做了什么 + 结果
  step-N-review.md      ← R: LGTM 或 needs-revision
  step-N-question.md    ← E: 卡住,需要 R 裁决(临时)
  step-N-answer.md      ← R: 回答 E 的问题
  FOR_E.md              ← R: 中途纠偏(E 消费 + 删除)
  .halt                 ← 标志位,任一方设;E 在循环头部检查
```

## 标准节奏

```
R 写 step-N-spec.md
       ↓
E 读 spec、应用、build、test、commit
       ↓
E 写 step-N-report.md
       ↓
R 读 report + git diff,写 step-N-review.md
       ↓
LGTM → R 写 step-(N+1)-spec.md
needs-revision → E 改、新 commits、更新 report
```

## FOR_E.md(中途邮箱)

R 在 E 正在干活时发现某件事**必须让 E 在做完当前 step 前知道**,就写 `FOR_E.md`。
E **必须**在每次迭代头部(每次大动作 / 每次跑测试前)`cat handoff/FOR_E.md`。
处理完后**删掉它**,并在当前 report 草稿里记一行"已消费 FOR_E.md 于 <时间>"。

## Question / halt 流程

E 撞上架构问题或反复失败时:

1. E 写 `step-N-question.md`,描述卡点 + 证据 + 给 R 2-3 个候选方向。
2. E `touch handoff/.halt` 然后退出。
3. R 读 question,做决定,写 `step-N-answer.md`,清掉 `.halt` + 删掉 question 文件。
4. E 下次启动时读 answer 继续。

E **不应**在第一次验收失败就 halt。同一失败族最多重试 3 次,还过不去再 halt + 写 question。

## 通用红线(项目无关)

- E 只在工作分支提交,**永不** `git push origin`(除非 spec 明示)。
- E 永不修改本文件或两份 loop 文件;R 永不编辑 `src/` 下源代码。
- 每个 step 的 commit message 前缀 `[step-N]`,便于回溯。
- E 永不 `git add -A` / `git add .`,**只精确 add** 具体文件,避免用户的 WIP 混进来。
- 两边都可以自由读 workspace 里任何文件。
- `handoff/` 所有文件两边都可读;写遵守上面的所有者表。

## 项目专属红线

> 替换本段为你这个项目的硬"never"规则。例如:
>
> - 永不修改 `<critical_module.cpp>`。
> - 永不启用 `<dangerous_flag>=true`。
> - 永不在 runtime 代码里依赖仿真专属信号。
> - 永不改 X 模块与 Y 模块之间的对外接口。
>
> 加多少条都行,只要你这个项目真的有。这些是"如果某个 spec 提到了它,立即 halt + question"的级别。
