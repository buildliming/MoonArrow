# MoonArrow · 月矢

**纯 MoonBit 实现的 Apache Arrow IPC 交换层。** 无 Arrow C/C++ 运行时或
FFI 依赖，可在 Native、JavaScript、Wasm、Wasm-GC 后端构建和测试。
项目模块为 `shunge/arrow`，适合在 MoonBit 程序与 Python 等数据工具之间
交换列式批次。

> 当前仓库是 **0.1.0 之后的未发布开发版本**。Mooncakes 上的 `0.1.0`
> 只有初始七种基础类型；本页的新功能需从本仓库源码使用。它是 Arrow IPC
> 的明确子集，不代表完整 Arrow 规范实现。

## 当前开发版能力

| 领域 | 范围 |
| --- | --- |
| 标量 | Null、Boolean、Int8/16/32/64、UInt8/16/32/64、Float32/64、Date32/64、Timestamp、Duration、Utf8/Binary、LargeUtf8/LargeBinary、FixedSizeBinary |
| 复合类型 | List、LargeList、FixedSizeList、Struct、Map；顶层 Int32 索引且值为 Utf8/Binary 的 Dictionary |
| IPC | Stream/file 读写、V4/V5 读取、文件 footer 索引、字典消息、分块输入与逐批输出 |
| 数据操作 | 类型化逐行构建、Table/RecordBatch 投影与筛选、切片、拼接、重分块、行读取、统计摘要和索引检查 |
| 验证 | 四后端 MoonBit 测试；Native/JS 的 PyArrow 双向互操作与两个文件工作流 |

支持范围、边界、内存所有权和错误语义见[格式契约](docs/FORMAT.md)。
压缩 IPC、Decimal、零拷贝、真实文件/网络 I/O 适配器与完整 Apache Arrow
集成套件尚未提供。

## 开始使用

安装 [MoonBit 工具链](https://www.moonbitlang.com/download/) 后，在仓库根目录运行：

```sh
moon run examples/consumer --target native
moon check --target all --deny-warn
moon test --target all
```

`examples/consumer` 是独立 MoonBit 模块，借助 `moon.work` 从本地源码依赖
`shunge/arrow`，只调用公开 API。0.1.0 已发布能力可以通过
`moon add shunge/arrow@0.1.0` 安装；开发版扩展尚未发布到 Mooncakes。

真实 `.arrow` 文件的两个小型端到端工作流：

```sh
python -m pip install -r tools/requirements-interop.txt
python tools/workflow.py --target native --output-dir outputs/workflows
python tools/workflow.py --target js --output-dir outputs/workflows-js
```

第一个工作流跨两个批次筛选非空 ID、投影字段；第二个处理
Dictionary、List、Struct、Map。PyArrow 创建输入文件并验证 MoonBit 输出文件。
示例的命令行适配器使用十六进制参数传输小文件，不适合大文件或性能测量。

## 验证与基准

```sh
python tools/interop.py --target native
python tools/interop.py --target js
python tools/count_core.py --min-effective 4001
python -m pip install -r tools/requirements-bench.txt
python tools/bench.py --target native --output bench/native-local.json
```

本地 2026-09-24 验证记录、原始 Native/JS 基准和测量限制见
[验证记录](docs/VALIDATION.md)。核心代码按仓库内可复现脚本统计；
行数是实施规模指标，功能和正确性仍以测试及独立互操作为准。

## 文档

- [MoonBit API 使用指南](README.mbt.md)
- [格式契约与兼容边界](docs/FORMAT.md)
- [架构与 API 所有权](docs/ARCHITECTURE.md)
- [从 0.1.0 迁移](docs/MIGRATION.md)
- [实施状态与剩余工作](docs/IMPLEMENTATION_STATUS.zh-CN.md)
- [验证与性能记录](docs/VALIDATION.md)
- [最初的项目完善计划](PROJECT_PLAN.zh-CN.md)
- [开发与贡献](CONTRIBUTING.md)
- [变更记录](CHANGELOG.md)

本项目采用 [MIT License](LICENSE)，是 Apache Arrow 格式的独立实现，
不属于 Apache 软件基金会项目，也不代表其官方实现。
