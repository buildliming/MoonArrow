# MoonArrow · 月矢

`shunge/arrow` 是纯 MoonBit 实现的 Apache Arrow IPC 读写库，让 MoonBit
程序通过标准列式数据格式与 Python 等数据工具交换数据。
本仓库为 0.1.0 之后的未发布开发版本，模块名为 `shunge/arrow`。
Mooncakes 的 0.1.0 仍只有初始功能；以下新能力需从仓库源码使用。

生产代码只依赖 MoonBit 标准库，不依赖 PyArrow、Arrow C++ 或 FFI。
PyArrow 仅用于开发时的独立互操作测试。

## 已实现的范围

| 能力 | 当前状态 |
| --- | --- |
| 列类型 | Null、Boolean、各宽度有/无符号整数、Float32/64、Date32/64、Timestamp、Duration、Utf8/Binary、LargeUtf8/LargeBinary、FixedSizeBinary |
| 复合类型 | List、LargeList、FixedSizeList、Struct、Map、顶层 Int32 索引的 Utf8/Binary Dictionary |
| 空值 | 有效位图、null count、非空字段检查 |
| IPC stream | V5 写入；V4/V5 读取；兼容 legacy 前缀 |
| IPC file | ARROW1 文件、footer 索引、多批次与随机批次读取 |
| 元数据 | schema 与 field 的 UTF-8 key/value，保留顺序、重复键与缺省值 |
| 读取方式 | 整体读入、在已有 Bytes 上逐批解码，或增量推入 stream 字节块 |
| 数据处理 | BatchBuilder、RecordBatch/Table 的投影、筛选、拼接、重分块、摘要 |
| 后端 | Native、JS、Wasm、Wasm-GC 均有测试 |

## 快速示例

以下代码块会由 MoonBit 文档测试执行。在本仓库中运行不需要先发布包。
在其他 MoonBit 项目中安装已发布的 **0.1.0 子集**：

```sh
moon add shunge/arrow@0.1.0
```

然后在调用方的 `moon.pkg` 中导入 `shunge/arrow`：

```text
import {
  "shunge/arrow",
}
```

[Mooncakes 模块页面](https://mooncakes.io/docs/shunge/arrow) ·
[GitHub 源码](https://github.com/buildliming/MoonArrow)

本仓库的 `examples/consumer` 是一个独立模块，`moon.work` 将它的
`shunge/arrow@0.1.0` 依赖解析到本地源码，因此可验证开发版公开 API。
运行 `moon run examples/consumer --target native`。

```mbt check
///|
test "nullable Arrow file roundtrip" {
  let schema = @arrow.Schema::new([
    @arrow.Field::new("id", Int64, nullable=false),
    @arrow.Field::new("name", Utf8),
  ])
  let batch = @arrow.RecordBatch::new(schema, [
    Int64s([Some(1L), Some(9007199254740993L)]),
    Strings([Some("月兔"), None]),
  ])
  let bytes = @arrow.write_file(schema, [batch])
  let reader = @arrow.FileReader::new(bytes)
  assert_eq(reader.num_batches(), 1)
  let restored = reader.get_batch(0)
  assert_true(
    restored.columns[0] is Int64s([Some(1L), Some(9007199254740993L)]),
  )
  assert_true(restored.columns[1] is Strings([Some("月兔"), None]))
}
```

命令行演示：

```sh
moon run cmd/main --target native
```

`write_stream` / `read_stream` 对应 IPC stream；`write_file` / `read_file`
对应 IPC file。`StreamReader::next()` 每次解码一个批次，结束时返回 `None`，
解析报错后也进入结束状态。`FileReader::get_batch(index)` 按 footer 索引读取指定批次。
`StreamReader` 和 `FileReader` 保留完整输入 Bytes。
`IncrementalReader::push` 则可接受任意切分的 stream 数据块，返回已完成的批次；
最后调用 `finish()` 检查截断。`IncrementalWriter` 与 `FileWriter` 分段返回
`Bytes`。这几个 API 都不执行文件或网络 I/O，传输与落盘由调用方负责。

`BatchBuilder::append_row` 接受按 schema 顺序排列的 `Value?`；
`Table::filter_where` 使用类型化 `Predicate`，空值在 `Eq/Ne` 中均不匹配。
`Table::to_file` 和 `Table::from_file` 可衔接 IPC。典型外部消费代码见
[独立消费模块](examples/consumer/main.mbt)；两个 PyArrow 文件工作流见
[`tools/workflow.py`](tools/workflow.py)。

## 输入检查与限制

API 抛出 `ArrowError::Invalid`、`Unsupported` 或 `LimitExceeded`。
读入时检查长度、偏移、位图与空值数量、UTF-8、schema 和批次布局。
写入前会重新检查数组长度、类型、schema 一致性和非空约束。
公开数组可变；调用方应避免在 reader 使用期间修改其 schema。

可通过 `ReadLimits` 设置每批行数、每批值数、字段数、批次数、元数据字节数、
body 字节数、递归深度、字典值数和字典消息数上限。默认每批最多 100 万行、
800 万个值、1024 字段，最多 10000 批次，元数据 16 MiB、body 256 MiB、
递归深度 64、字典值 800 万、字典消息 10000。
这些是格式解析预算，并非精确的进程内存上限；整体读入多个批次会累积内存。

## 兼容性验证

```sh
moon check --target all --deny-warn
moon test --target all
python -m pip install -r tools/requirements-interop.txt
python tools/interop.py --target native
python tools/interop.py --target js
python tools/workflow.py --target native
python tools/count_core.py --min-effective 4001
```

当前工具链的 `moon test` 已包含文档测试，不需要已弃用的 `--doc` 参数。
互操作测试会让 PyArrow 生成输入、让 MoonBit 解码并重写，再由 PyArrow
读取和完整校验。另有一个 PyArrow 生成的固定样本，直接由四个后端运行。
测试覆盖空批次、位图字节边界、Unicode/BOM/NUL、切片、数值极值、
时间单位、嵌套布局、字典和浮点位模式。测试驱动用十六进制命令行参数
传输小样本，不是大文件工具。

## 尚未支持

Decimal、Union、RunEndEncoded、View 类型、压缩 body、big-endian schema、
非 Int32 索引或嵌套的 Dictionary、message/footer 自定义元数据尚未支持。
schema/field 的 extension metadata 会原样保留，但不解释扩展类型语义。

目前解码生成拥有数据的数组，不提供零拷贝视图、Arrow C Data Interface
或并行计算。仅支持类型范围内的未压缩 Feather V2；不能读取所有
`.feather` 文件。文件布局方面，当前 reader 要求批次连续排列。

详细约束见 [格式契约](docs/FORMAT.md)，后续工作见 [路线图](docs/ROADMAP.zh-CN.md)。

## 格式依据与许可

实现依据 [Apache Arrow Columnar Format](https://arrow.apache.org/docs/format/Columnar.html)
及其 [format schemas](https://github.com/apache/arrow/tree/main/format)。
元数据编码器仅覆盖本项目使用的 Arrow 表结构，不是通用 FlatBuffers 库。
代码采用 MIT 许可；本项目为独立实现，不代表 Apache 软件基金会。
