# 2026-09-24 实施状态

本文件对照根目录的[项目完善计划](../PROJECT_PLAN.zh-CN.md)。该计划是最初的
工作分解；当前实现以源码、测试和[格式契约](FORMAT.md)为准。

| 阶段 | 本轮结果 | 证据 |
| --- | --- | --- |
| P0 基线 | 完成；固定源码计数脚本与本地验证命令 | `tools/count_core.py`、`VALIDATION.md` |
| P1 类型 | 完成计划中主要数值/时间类型，并扩展 Large/Fixed 类型 | `types.mbt`、`columns.mbt`、PyArrow fixtures |
| P2 构建与复用 | 完成类型化 builder、批次/Table 操作、独立消费模块 | `builders.mbt`、`table.mbt`、`examples/consumer` |
| P3 递归布局 | 完成 List/Struct，扩展 LargeList、FixedSizeList、Map | `columns.mbt`、`schema_validation.mbt`、嵌套测试 |
| P4 字典 | 完成受限的顶层 Int32 索引 Utf8/Binary 字典、stream 更新与 file 索引 | `dictionary.mbt`、字典测试 |
| P5 增量/工具 | 完成增量 stream reader、逐批 writer、file writer、检查器和摘要 | `incremental.mbt`、`file_writer.mbt`、`inspector.mbt` |
| P6 展示 | 完成两个小型文件工作流、基准与核心行数门禁 | `tools/workflow.py`、`bench/`、CI |

核心手写生产 `.mbt` 按 `tools/count_core.py` 统计为 **5,110 有效行**、
5,647 物理行，超过内部 4,000 有效行目标。排除测试、命令、示例、生成接口、
依赖和文档；“有效行”定义为非空且非 `//` 开头的行。它是可复核的仓库统计
口径，不声称等同于比赛官方口径。

本轮本地 `moon test --target all` 四后端各 41 项通过，PyArrow Native/JS
各 128 个独立断言通过；两个文件工作流在 Native/JS 均通过。CI 已加入
独立消费、工作流和行数门禁，远端运行结果需以 GitHub Actions 实际记录为准。

计划中的建议性质量指标尚未全部达到：41 个 MoonBit 测试少于建议的 100
个独立语义案例；128 个互操作断言/后端不等同于 200 个独立场景；尚未形成
核心覆盖率 85% 的可靠报告，也没有第三方下游反馈。已完成的文件工作流
通过十六进制命令行参数传送小文件，不能作为大文件 I/O 的证明。性能基准
只记录一台 Windows 机器的一次 debug 构建测量；没有优化前后对照。

下一阶段按[路线图](ROADMAP.zh-CN.md)补真实 I/O 适配、外部消费反馈和
覆盖率/官方集成语料，再决定发布新 Mooncakes 版本。当前 `moon.mod` 仍为
0.1.0；GitHub 开发分支的功能不能写作已发布包的功能。

本地 `moon publish --dry-run` 已完成打包、解包和包内 `moon check`，但随后
访问 Mooncakes 发布 API 时返回 request/response body 错误，命令最终失败。
因此发布候选检查尚未完整通过，也未执行实际发布。
