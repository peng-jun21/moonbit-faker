# 可复现关联测试数据与断点生成工具

**本项目仓库：[https://github.com/peng-jun21/moonbit-faker](https://github.com/peng-jun21/moonbit-faker)**

模块 `peng-jun21/faker`，本地版本 **0.4.0**，MIT。当前评审状态：**保留候选**。本文件是当前入口，旧轮次说明与详细用法保存在 [历史/完整使用说明](README-BEFORE-VALUE-REWORK.md)。

## 解决什么任务

为客户—订单等关联表生成可重复的测试数据；批次或进程中断后继续生成时保持序列、外键关系和唯一性状态。

需要同版本可重放、关联字段与可保存生成会话时选择；词库数量本身不是独立贡献。

## 直接复现

安装 MoonBit 和 Node.js 24，在本仓库根目录运行：

```sh
moon build --target js
node -e "require('node:fs').copyFileSync('_build/js/debug/build/cmd/web/web.js','web/engine.mjs')"
node examples/run-use-case.mjs
```

流程：**关联客户和订单数据集**。运行器创建新的系统临时目录，保留每一步的 stdout/stderr、产物及 `report.json`，打印实际目录；重复运行不会覆盖之前产物。它只执行仓库内的本地样例，不连接公网或发送消息。`report.json` 的 `expected` 是应观察的结果，实际结果在各步输出中；成功退出不替代内容核对。

输入性质：原创合成 schema，词库来源仍为 Faker；不称真实数据脱敏。

应观察：新文件包含 100 个 customers 与 1000 个 orders；客户引用来自先生成的数据集。

具体命令和输入路径见 [使用任务](USE-CASE.md) 与 [机器可读流程](examples/use-case.json)。只把这个脚本当复现入口，不把通用运行器计作核心技术贡献。

## 实现与已有项目的关系

MoonBit 实现种子源、provider、schema、行内/外表引用与会话状态；Node 负责流式文件、背压和检查点 I/O。

本轮未找到同范围 MoonBit 数据生成库。价值在关联 schema、可保存状态和可复現数据工作流，不是发明随机数或姓名数据；词库及 Faker 来源版本必须披露。

同类项目和检索边界见 [DUPLICATION](DUPLICATION.md)。查重用于避免错误的首创表述；关键词零结果不能证明生态空白，Node 宿主能力也不计为 MoonBit 原生 I/O。

库使用从 [公共 API](pkg.generated.mbti) 和根包源码开始；可在本 checkout 的消费包中导入 `"peng-jun21/faker"`。源码中的网络/文件宿主入口及完整参数仍见 [完整使用说明](README-BEFORE-VALUE-REWORK.md)。是否已发布到 Mooncakes 需另核实，本文不把 `moon add` 的下载成功作为已完成事项。

## 验证与边界

前一轮工程验证真实流式、关联表、检查点续跑和十万行任务测试通过；examples/related-shop.json 是合成业务样例，不能称为客户数据。

[上一轮工程验证](evidence/innovation-review-20260922/results.json) 与 [本轮最小任务回执](evidence/value-rework-20260922/use-case.json) 分开。历史参考版本、golden 重放、本机 peer、真实第三方服务端和本次样例是不同证据，不能合并成“全部生产验证”。

常规核心检查可运行 `moon check --target js`、`moon test --target js`、`moon test --target wasm-gc`。专项命令：

```sh
node tools/test-stream.mjs
```

专项所需的参考环境和历史版本见原使用说明及 TESTING 文档；本轮回执只记录实际执行项，不声称上面所有参考服务在任意环境即装即跑。

合成数据不是脱敏后的真实数据，不具备密码学随机性或跨进程全局唯一性保证；唯一值重试有上限。

## 复审材料状态

没有客户数据或脱敏承诺；断点仅支持文档声明的单数据集路径。

2026-09-22 匿名新克隆成功；默认分支 `main`，核验公开提交 `fcb34dbe41602a281529e64771f177f23891537c`。本轮源码修订仅在本地，尚未推送；此记录不证明当时报名表中的地址正确，也不证明新修订已上线。

[申报草稿](PROPOSAL.md) 已压缩为 30 行以内，并单独标明本项目仓库；[复核说明](REVIEW-RESPONSE.md) 区分材料错误、功能变化及尚未解决的问题。没有编造用户、设备接入、生产部署或评审认可。
