# multi-ai-collab

两个 AI 通过**文件邮箱**协作做一件大事:一个 **Reviewer/Architect (R)** + 一个 **Executor (E)**。
把模板丢进项目的 `handoff/` 目录,再各发一句启动 prompt,两边就能跑起来。

从一次 4 天的无人机局部路径规划重构里提炼出来的(2900 行代码、11 个仿真场景、Production-Ready 门全过)。
真正值钱的是协作机制 + [`LESSONS.md`](LESSONS.md) 里的 9 条踩坑总结。

## 5 分钟接通

1. **把 `handoff/` 复制到你的项目**:
   ```bash
   cp -r handoff/ /path/to/your-project/
   ```
2. **补两份项目专属文档**。`handoff/` 里现在有通用的 `PROTOCOL.md` / `EXECUTOR_LOOP.md` /
   `REVIEWER_LOOP.md` / `INDEX.md`,你还需要加:
   - `REQUIREMENTS.md` —— 用户的真实需求 + 安全边界 + 数值验收门(R 负责保持同步)
   - `ARCHITECTURE.md` —— 项目不变量、与其他系统的契约、out-of-scope 边界
   - 在 `PROTOCOL.md` 末尾加项目专属"红线"
3. **把 R 端事件监听脚本丢到 E 主机**:
   ```bash
   scp scripts/r_watch.sh user@<E-HOST>:/tmp/
   # 编辑顶上两行 WORKSPACE / LOG_DIR 改成你项目的路径
   ```
4. **启动 E**(在 Codex / Cursor 等 agent 会话里):
   > 读 `<workspace>/handoff/PROTOCOL.md` 和 `EXECUTOR_LOOP.md`,你是 E,开始干。
5. **启动 R**(在你的 IDE assistant 里):
   > 读 `<workspace>/handoff/PROTOCOL.md` 和 `REVIEWER_LOOP.md`,我是 R。

之后 R 大部分时间待机,E 出报告/问题/halt 时被事件唤醒;E 在自己会话里循环干活,每轮先 cat `FOR_E.md`。

## 仓库结构

```
multi-ai-collab/
├── README.md             ← 你在这
├── LESSONS.md            ← 9 条踩坑,动手前过一遍
├── LICENSE               ← MIT
├── handoff/              ← 直接 cp 到你项目里
│   ├── PROTOCOL.md       ← 角色 / 文件 / 阻塞流程 / FOR_E 邮箱
│   ├── EXECUTOR_LOOP.md  ← E 的常驻指令(含自驱模式)
│   ├── REVIEWER_LOOP.md  ← R 的常驻指令
│   └── INDEX.md          ← 状态追踪模板(初始空)
└── scripts/
    └── r_watch.sh        ← R 端事件监听(跑在 E 主机上)
```

## 机制怎么工作

- **`handoff/`** 是 R 和 E 之间**唯一通道**。每个文件只有一个所有者(见 `PROTOCOL.md`)。
- **R 写 spec / review;E 写 report / question。** R 不动源码不 commit,E 独占 git 操作。
- **`FOR_E.md`** 是 R 的中途邮箱。E 每轮迭代头部 `cat` 一次,有内容就处理 + 删掉。
- **Halt 协议**:E 卡住时写 `step-N-question.md` + `touch handoff/.halt`,R 回答完清 halt,E 下次继续。
- **`r_watch.sh`** 跑在 E 主机,发生有意义的事(commit / question / halt / 长时间 idle)就 emit 一行。
  R 的 harness 接事件唤醒,不再定时轮询。

## 项目专属定制点

通用机制不动,**只有 3 处要按项目改**:

| 文件 | 你填什么 |
|---|---|
| `REQUIREMENTS.md` | 用户真实目标 + 安全红线 + 数值验收门 |
| `ARCHITECTURE.md` | 项目不变量、对外接口契约、out-of-scope 边界 |
| `PROTOCOL.md` 末尾"项目专属红线"段 | 你这个领域的硬"never"规则 |

其他(`EXECUTOR_LOOP.md` / `REVIEWER_LOOP.md` / `INDEX.md` / `r_watch.sh` / FOR_E 邮箱约定 /
question-halt 协议)都通用。

## 动手前先读

[`LESSONS.md`](LESSONS.md) —— 9 条具体的坑,不读会再踩一遍:
base64 跨编码层、agent 并不是真自循环、事件驱动 vs 定时轮询、sim=real 底线、
打地鼠是该退一步而不是修更快、要度量你**真正在意**的事、迟滞作软偏置 vs 显式状态机、
承诺架构 vs 每帧重算、Production-Ready 留余量。

## License

MIT。
