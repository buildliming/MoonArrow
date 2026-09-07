# 首批代码交付：10 个提交

在仓库已有初始化提交之上追加以下 10 个提交，按实现依赖和审阅主题组织。
这些提交用于呈现本次代码交付，不代表十次独立发布日期。

| 序号 | 提交标题 | 内容 |
| --- | --- | --- |
| 1 | `chore: initialize MoonBit module and development conventions` | 模块配置、忽略规则、贡献代理指引和本地 hook；保留仓库 MIT 许可 |
| 2 | `feat: model Arrow schemas and nullable record batches` | 类型、字段、schema、可空列、批次验证、读取限制与错误类型 |
| 3 | `feat: add checked binary and FlatBuffer primitives` | 小端读写、边界检查、Arrow 元数据所需 FlatBuffer 原语 |
| 4 | `feat: encode and decode Arrow IPC metadata` | schema、field 元数据、消息帧与批次描述 |
| 5 | `feat: encode and validate nullable column buffers` | 位图、数值和变长列布局，偏移校验与分配预算 |
| 6 | `feat: support IPC streams and indexed Arrow files` | stream/file API、逐批读取、footer 索引与公开接口 |
| 7 | `test: cover IPC roundtrips and malformed input` | 公共 API、数据边界、错误输入及逐字节变异测试 |
| 8 | `test: verify interoperability with PyArrow` | 外部样本、Native/JS 测试驱动与 PyArrow 双向校验 |
| 9 | `docs: introduce MoonArrow and document the IPC subset` | 名称、简介、使用示例、格式契约、验证记录、路线图和变更说明 |
| 10 | `ci: validate all backends and PyArrow compatibility` | Linux/Windows CI、四后端测试和双向互操作检查 |

项目指南中列出的验证结果针对完整首版。早期提交按依赖逐步引入内部实现，
完整公开 API 在第 6 个提交形成，示例与完整文档在第 9 个提交形成。

仓库地址：<https://github.com/buildliming/MoonArrow>。目标默认分支：`default`。
推送源代码不等同于发布 Mooncakes 包或提交比赛。
