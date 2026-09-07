# MoonArrow · 月矢

**纯 MoonBit 实现的 Apache Arrow IPC 库，让列式数据在 MoonBit 与主流数据工具之间自由流动。**

MoonArrow 为 MoonBit 生态提供跨平台的列式数据交换能力。项目无需 C/C++
绑定，支持 Arrow IPC 流与文件读写、空值处理、元数据保留和多批次访问，
覆盖 Native、JavaScript、Wasm 与 Wasm-GC 后端，并通过 PyArrow 双向互操作
验证，为数据分析、数据库集成和浏览器端数据处理提供基础支持。

A pure MoonBit implementation of a focused Apache Arrow IPC subset, with no
Arrow C/C++ runtime or FFI dependency. PyArrow is used only as a test oracle.

> **状态：0.1.0 初始实现。** 当前覆盖下表中的类型和功能，尚未实现完整 Arrow
> 规范，也尚未发布到 Mooncakes。项目名称为 MoonArrow，模块名暂保留 `shunge/arrow`。

## 能力与边界

| 能力 | 当前支持 |
| --- | --- |
| 列类型 | Null、Boolean、Int32、Int64、Float64、Utf8、Binary |
| 数据完整性 | 空值位图、非空字段检查、Int64 完整精度、Float64 位模式 |
| IPC stream | V5 写入，V4/V5 读取，兼容 legacy 前缀 |
| IPC file | ARROW1 文件、footer 索引、多批次与随机批次读取 |
| 元数据 | schema/field UTF-8 key/value，保留顺序、重复键和缺省值 |
| 编译后端 | Native、JavaScript、Wasm、Wasm-GC |

目前未支持嵌套类型、字典编码、压缩、时间/日期、其他数值类型和零拷贝访问。
Reader 接收完整 `Bytes`，不执行文件或网络 I/O；逐批解码不等于网络增量解析。
详细限制见[格式契约](docs/FORMAT.md)。

## 快速运行

安装 [MoonBit 工具链](https://www.moonbitlang.com/download/) 后：

```sh
git clone https://github.com/buildliming/MoonArrow.git
cd MoonArrow
moon run cmd/main --target native
moon test --target all
```

示例写入并读取含可空字符串和 64 位整数的 Arrow 文件，输出：

```text
Arrow IPC file: 1066 bytes, 1 batch, 2 rows
Nulls in name column: 1
```

库的完整使用示例见[使用指南](README.mbt.md)，其中 MoonBit 示例由文档测试验证。

## 独立兼容性验证

需要 Python 和 Node.js（JS 后端）：

```sh
python -m pip install -r tools/requirements-interop.txt
python tools/interop.py --target native
python tools/interop.py --target js
```

测试由 PyArrow 生成输入，MoonBit 解码后重写，再由 PyArrow 读取并校验。
本地四后端各通过 18 项测试；Native 和 JS 各通过 80 项独立互操作断言。
测试环境、覆盖范围与局限见[验证记录](docs/VALIDATION.md)。

## 文档导航

- [使用指南与可运行示例](README.mbt.md)
- [格式契约与支持范围](docs/FORMAT.md)
- [开发与验证流程](CONTRIBUTING.md)
- [参赛定位与后续路线](docs/ROADMAP.zh-CN.md)
- [变更记录](CHANGELOG.md)
- [首批 10 个提交的划分说明](docs/INITIAL_COMMITS.zh-CN.md)

## 许可

沿用仓库的 [MIT License](LICENSE)。本项目是 Apache Arrow 格式的独立实现，
不属于 Apache 软件基金会项目，也不代表其官方实现。
