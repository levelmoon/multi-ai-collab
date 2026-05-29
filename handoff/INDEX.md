# 协作状态

权威引用:
- 协议:`PROTOCOL.md`
- 架构:`ARCHITECTURE.md` *(项目专属,R 写)*
- 需求:`REQUIREMENTS.md` *(项目专属,R 同步)*
- Halt 开关:`touch handoff/.halt`(两边都可设)

## 状态行

状态变化时追加新行,旧行留作历史。每个 step **最新一行**胜出。

```
step-N | spec=YYYY-MM-DD✓ | apply=⏳ | report=⏳ | review=⏳ | commits=- | branch=<分支> | notes=...
```

符号:`✓` 完成、`⏳` 等待中、`✗` 失败/驳回、`→` 进行中。

## 现在轮到谁

> 一句话:轮到谁、TA 在干什么。状态变化时更新。例如:
>
> *E 在 apply step-2(committed_path 骨架);R 待机等 report。*

## 历史

> 可选:关键转折点带日期记一笔。例如:
>
> - 2026-05-27 16:00 —— 初始化,baseline commit `<sha>`。
> - 2026-05-28 11:20 —— R 发现 E 改动了候选生成,写 FOR_E.md 让回退;E 恢复成功。
