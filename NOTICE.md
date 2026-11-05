# 合规与第三方组件说明

## 1. 本项目与原项目

- 本项目是「小米/红米充电加速模块」（`mi_charge_boost`，作者 **酷安@鱼楠**）v8.6.4 的 fork，
  仅新增小米17（`pudding`）适配与若干缺陷修复，并保留原作者署名。
- 原项目未附开源许可证声明。如原作者对分发方式有异议，请提 issue / 联系维护者，会立即删除相关内容。

## 2. 第三方组件

| 组件 | 位置 | 许可证 |
|---|---|---|
| FreePPS | `pps/FreePPS`、`pps/freepps-paths.patch` | **GPL-3.0**（见 `pps/README-FreePPS.txt`、`pps/FreePPS-LICENSE`、`pps/FreePPS-NOTICES`） |
| 充电监测 App | `apk/charge_monitor.apk` | 由原作者提供，随模块分发 |
| `mi_qc_retry.ko` | `qr/` | 由原作者提供 |
| `dtbopatch`、`dtbofv` | `dtbo/` | 由原作者提供，原样保留（本 fork 未修改） |

## 3. 本 fork 新增代码

| 文件 | 说明 |
|---|---|
| `dtbo/dtbopatch2` | Go 编写的多入口 dtbo 规则写入器（含源码说明见 `docs/technical.md`） |
| `dtbo/pudding_os4.tpl` | 小米17 模板 |
| `variants/pudding_os4-thermal.tpl` | 可选：温控表全放开模板 |
| `tools/pack.py`、`build.sh` | 打包脚本 |
| `docs/`、`README.md`、`CHANGELOG.md`、`CREDITS.md` | 文档 |

## 4. 免责声明

修改 dtbo 属于高风险操作，可能导致无法开机、充电异常或硬件损伤。
本项目仅供个人学习与自用，使用风险自负；请务必先备份原厂 dtbo 并确认能通过 fastboot 回滚。
