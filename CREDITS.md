# 致谢 / Credits

本项目是 **「小米/红米充电加速模块」** 的小米17 适配 fork。核心设计与绝大部分实现来自原作者，
本仓库的改动见 [CHANGELOG.md](CHANGELOG.md) 与 [docs/technical.md](docs/technical.md)。

## 原作者与贡献者

| 贡献者 | 贡献 |
|---|---|
| **酷安@鱼楠** | 「小米/红米充电加速模块」（`mi_charge_boost`）原作者：机型参数体系、dtbo 模板机制、`dtbopatch`/`dtbofv` 工具、WebUI、FreePPS 集成方案等。本项目 fork 自其 **v8.6.4** |
| 酷安@低线阻狂魔 | PPS 节点相关 |
| 酷安@花橋桥 | PPS 节点相关 |
| Seyud | [FreePPS](https://github.com/Seyud/FreePPS)（GPL-3.0） |
| 酷安@瓦力喀 | FreePPS 适配/集成 |
| 酷安@久保Sama / 刷新率APP | 高刷切换思路（小米15 165 Hz） |

## 小米17 适配

| 贡献者 | 贡献 |
|---|---|
| 酷安@不事Piura | 小米17（`pudding`）机型适配：`pudding_os4.tpl` 模板、`dtbopatch2` 多入口写入器、安装期执行位 bug 修复、真机验证 |

## 第三方组件

| 组件 | 说明 | 许可证 |
|---|---|---|
| `pps/FreePPS` | 公版 PPS 解锁守护进程 | GPL-3.0，见 `pps/README-FreePPS.txt`、`pps/FreePPS-LICENSE`、`pps/FreePPS-NOTICES` |
| `apk/charge_monitor.apk` | 配套充电监测 App（v5.9） | 由原作者提供，随模块分发 |
| `qr/mi_qc_retry.ko` | 快充断流秒恢复内核模块（默认关闭） | 由原作者提供 |
| `dtbo/dtbopatch`、`dtbo/dtbofv` | 原作者的 dtbo 规则写入/满充电压探测工具 | 由原作者提供，原样保留未改动 |
