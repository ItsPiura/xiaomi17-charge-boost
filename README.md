<div align="center">

# ⚡ Mi8Elite-charge-boost 充电加速 · 小米17 适配

**小米 / 红米 骁龙 8 至尊版系列充电增强模块 —— 新增小米 17 适配**

![version](https://img.shields.io/badge/version-v8.7.0--pudding-orange)
![device](https://img.shields.io/badge/device-Xiaomi%2017%20%28pudding%29-blue)
![root](https://img.shields.io/badge/root-KernelSU%20%7C%20Magisk-green)
![author](https://img.shields.io/badge/author-%E9%85%B7%E5%AE%89%40%E4%B8%8D%E4%BA%8BPiura-red)
![base](https://img.shields.io/badge/fork%20from-%E9%85%B7%E5%AE%89%40%E9%B1%BC%E6%A5%A0%20v8.6.4-lightgrey)

</div>

> 本项目 fork 自 [**酷安@鱼楠**](https://github.com/aichiyunan) 的
> [xiaomi-8Elite-charge-boost](https://github.com/aichiyunan/xiaomi-8Elite-charge-boost) v8.6.4，
> **只新增小米 17（`pudding` / SM8850）适配与若干缺陷修复**，原五款机型的参数与逻辑保持不变。
> 主要改动见 [本 fork 改了什么](#-本-fork-改了什么)，技术细节见 [docs/technical.md](docs/technical.md)。

---

## 📦 下载

| 文件 | 说明 |
| --- | --- |
| [`releases/Micharge-boost_v8.7.0-pudding_xiaomi17.zip`](releases/Micharge-boost_v8.7.0-pudding_xiaomi17.zip) | **默认版**：温控降流表保持原厂，温度上来后仍按原厂阶梯降流（保守，建议先刷这个） |
| [`releases/Micharge-boost_v8.7.0-pudding-thermal_xiaomi17.zip`](releases/Micharge-boost_v8.7.0-pudding-thermal_xiaomi17.zip) | **温控放开版**：`wired_thermal` 15 档电流全放开，高温也不降档（最快，发热明显） |
| [`CHANGELOG.md`](CHANGELOG.md) | 全部版本更新日志（含适配过程中的内部迭代记录） |
| [`docs/technical.md`](docs/technical.md) | 适配原理：2 入口 dtbo、`dtbopatch2`、温控表结构、验证手法 |

md5：默认版 `1ea50fbfcfbb1f43864b6374b9339e5d`，温控放开版 `428b7d8efcc95dd6f7653452514b5ba5`

> 两个 zip 同时放在 `releases/` 目录与 Release 页面；也可以自己打：`./build.sh all`

---

## ✨ 功能一览

### 🔋 DTBO 充电参数修改（重启生效）
| 选项 | 可选值 | 说明 |
| --- | --- | --- |
| 快充电流 | 原厂值 / 模块上限 / 不修改 | 小米17 为 **18.4A / 20.5A**；小米15 15.5A / 20.5A；K80 Pro 上限 22A |
| 满速/断充温度 | 55°C / 不修改 | 设定温度以下满速，超过才停充（小米17 原厂 48°C） |
| 内核关机电压 | 2800mV / 不修改 | 电池电压降到 2800mV 才关机（小米17 原厂 3030mV） |
| 满充截止电压 | 4490–4650mV / 不修改 | WebUI 可调，默认保持本机原厂（小米17 为 4580mV） |
| 屏幕超频 | 165Hz / 不超频 | 仅小米15：华星屏添加 132 / 144 / 155 / 165Hz 档位（小米17 不适用） |

- 关闭循环降压与降流：drop_fv_cycle 改 0，drop_fcc_para 循环门槛改 65535
- 刷入前自动备份当前 dtbo 为原厂镜像（按 A/B 槽位分开），卸载模块即还原
- 已收录原厂镜像按机型模板写入；未收录镜像（官改包、新底包）自动备份并逐项比对原厂值，只写吻合的项
- 保留原厂 AVB 尾部结构与 salt，写入后重新计算 dtbo 的 hash descriptor
- 低温温区保持原厂限流（小米17：13–18°C、18–23°C 不动），避免低温大电流

### 🌡️ 温控降流档位（小米17 双版本的区别）
小米17 的 `mca_charger_thermal/wired_thermal` 是 15 档 × 6 个电流上限：原厂最凉档 13500mA，最热档仅 500mA。

| 版本 | 处理方式 | 结果 |
| --- | --- | --- |
| 默认版 | 完全不动（原厂阶梯） | 电池 40°C 左右会被压到个位数瓦（实测 3.9W） |
| `-thermal` 版 | 15 档 6 个电流列 → 所选电流，每档前 4 个限值归一成最凉档 | 高温也不降档，速度最快、发热明显 |

### 🔌 公版 PPS 解锁
内置 FreePPS v1.7.0（Seyud / 酷安@瓦力喀，GPL-3.0），第三方 PPS 充电头放行高功率快充，小米原装头照常走私有协议。已启用 FreePPS 模块时内置版自动让出。

### 🌡️ 免重启调节
- **温控解除**：关闭有线充电温控降速（`wired_thermal_remove`）——判断"是不是温控在限"最快的办法
- **实时充电电流**：充电中直接改 `wired_chg_curr`，立即生效
- **私有协议功率**：小米15 / 15 Pro 可切 100W / 120W，K90 系列 120W，K80 Pro 原厂已 120W（**小米17 无对应节点，未开放该选项**）
- **原装头握手重试**（实验性，默认关）：插入 20 秒仍未进电荷泵快充时自动重走认证

### 🪫 低电量延迟关机
电量锁定 2%，屏蔽 0% 关机与 30 秒倒计时，电池电压降到设定值后才关机。

### 🖥️ 高刷切换
仅小米15：WebUI「高刷切换」页一键切换 120 / 132 / 144 / 156 / 165Hz。

### 📊 WebUI 与充电监测
- 实时功率、电流、电压、温度曲线与协议详情
- 充电记录、功率与温度极值统计（只在充电时记录）
- 内置 **充电监测 App**（含公版 PPS 控制中心磁贴）

---

## 🆕 本 fork 改了什么

| # | 内容 | 说明 |
| --- | --- | --- |
| 1 | **新增机型 `pudding`（小米17）** | `models.sh` 机型表、`sysinfo.sh` 识别、`stock.list` 收录原厂 dtbo 头部哈希 |
| 2 | **新增模板 `dtbo/pudding_os4.tpl`** | 37 条规则，原厂值全部取自真机 dtbo 并逐条校验 |
| 3 | **新增 `dtbo/dtbopatch2`（多入口写入器）** | 小米17 的 dtbo 是 **2 个 DT 入口**，原版 `dtbopatch` 会 `appears 2 times, ambiguous` 中止；且值变长时不重建 DT table，会把相邻属性写坏 |
| 4 | 修复安装期执行位判断顺序 | 原脚本在 `chmod 755` **之前**判断 `dtbopatch2` 是否可执行，Magisk/KernelSU 解压出的 0644 文件必然判断失败 → 静默退回原版工具 → 写入失败（现在会记录原因并在模块列表显示） |


> **关于 `module/` 的基准**：本仓库的模块源码以上游 **v8.6.4 发布包**（`releases/Micharge-boost_v8.6.4.zip`）为准。
> 上游 GitHub 仓库里的 `module/` 实际落后于发布包 —— 例如发布包的 `dtbo/apply.sh` 已包含 v8.6.4 的
> 「按 A/B 槽位分别备份」逻辑（`stock_a.img` / `written_a` / `state_a`），而仓库里仍是单份 `stock.img`；
> `uninstall.sh`、`hz/`、`cc/`、`pps/`、`tr/` 等也以发布包为准。因此与上游对比时看到的那约 20 个文件差异，
> 是**把仓库源码同步到发布包状态**，不是本 fork 多加的功能。

---

## 📱 适用范围

| 项目 | 支持 |
| --- | --- |
| 机型 | **小米17（pudding）**、小米15（dada）、小米15 Pro（haotian）、红米K80 Pro（miro）、红米K90（annibale）、红米K90至尊版（warsaw）已适配；其他机型按通用模式安装，dtbo 逐项比对原厂值，只写吻合的项 |
| 系统（小米17） | HyperOS `OS4.0.5.0.XPCCNXM`（Android 17，SM8850） |
| 系统（小米15） | HyperOS OS4.0.0.6 / 7 / 8 / 16 / 19，OS3.0.2 / 301 / 302 / 303 / 305 / 307 |
| 移植包 | ColorOS 16.1 移植包（自动识别官改 dtbo） |
| Root | KernelSU / Magisk |

> 小米17 原厂参数：快充电流峰值 18400mA、满充截止 4580mV、关机电压 3030mV、私有协议 100W。

---

## 🛠️ 安装

1. 在 KernelSU / Magisk 中选择刷入包安装
2. 按 **音量+** 切换选项，**音量-** 确认，15 秒不操作选默认
   - 小米17 建议：电流先选 **18.4A（原厂值）**、断充温度 55°C、关机电压按需、公版 PPS 不用第三方头就关
3. 确认结果后**重启生效**；不想重启可在 WebUI 设置里点「启动」
4. KernelSU 覆盖安装后模块目录只剩 `module.prop` + `update`（新版本暂存在 `/data/adb/modules_update/`），此时执行脚本会提示找不到文件，**重启后即恢复**

---

## 🧪 怎么确认生效

```sh
# ① 权威判断：分区内容是否等于模块写入记录
su -c "sh /data/adb/modules/mi_charge_boost/dtbo/apply.sh status"
# 期望输出： mod 18400 2800 55 - - -
#           状态  电流 关机电压 断充温度 超频 协议档 满充电压

# ② 不依赖模块文件的自检（安装后立刻可跑）
su -c "dd if=/dev/block/by-name/dtbo_a bs=4096 count=256 2>/dev/null | strings -n 4 | grep -cx 2800"   # 原厂≈20 → 写入后≈232
su -c "dd if=/dev/block/by-name/dtbo_a bs=4096 count=256 2>/dev/null | strings -n 4 | grep -cx 18400"  # 原厂≈42 → 写入后≈178
```

`status` 输出 `mod …` 表示已生效；`stock` 表示分区是原厂；`changed …` 表示被 OTA 或其它工具刷回，需要重新应用。

---

## ⚠️ 风险提示

修改 DTBO 与充电参数存在风险，大电流、高温充电会加速电池老化；写坏 dtbo 可能导致无法开机。
请确认机型与系统版本后再刷入，并保证：bootloader 已解锁、电量 >50%、手边有电脑与 fastboot。

回滚：`fastboot flash dtbo_a <原厂 dtbo.img>`，或使用模块自动备份的
`/data/adb/mi_charge_boost/dtbo/stock_a.img`。作者不对任何损坏负责。

---

## 🙏 致谢

- **酷安@鱼楠** —— 原模块「小米/红米充电加速模块」作者，本项目的全部基础设计与实现
- 酷安@低线阻狂魔
- 酷安@花橋桥（PPS 节点）
- [FreePPS](https://github.com/Seyud/FreePPS)（Seyud / 酷安@瓦力喀，GPL-3.0，已内置）
- 酷安@久保Sama / 刷新率 APP（高刷切换思路）
- 小米17 适配：酷安@不事Piura

详见 [CREDITS.md](CREDITS.md)；第三方组件与许可证见 [NOTICE.md](NOTICE.md)。

---

<details>
<summary>🛠️ 仓库结构与构建（点开）</summary>

```
.
├── module/                   # 模块本体（打包进 zip 的就是这个目录）
│   ├── META-INF/             # 安装入口
│   ├── customize.sh          # 安装脚本（音量键菜单 + 机型识别 + 写 dtbo）
│   ├── service.sh            # 开机启动守护脚本
│   ├── models.sh / model.sh  # 机型参数表 / WebUI 机型 JSON
│   ├── sysinfo.sh            # 机型与系统识别
│   ├── cc/ hs/ hz/ pps/ proto/ qr/ tr/   # 各功能守护脚本
│   ├── dtbo/
│   │   ├── apply.sh              # 写入主逻辑（按槽备份、回滚校验、状态机）
│   │   ├── dtbopatch             # 原版写入器（原样保留）
│   │   ├── dtbopatch2            # 本 fork 新增：多入口写入器（Go 静态编译 aarch64）
│   │   ├── dtbofv                # 满充截止电压探测/规则生成
│   │   ├── pudding_os4.tpl       # 小米17 模板（默认）
│   │   └── stock.list            # 原厂 dtbo 头部哈希 → 模板
│   └── webroot/index.html        # 模块 WebUI
├── variants/pudding_os4-thermal.tpl   # 可选：温控表全放开模板
├── releases/                 # 随仓库提供的两个 zip
├── tools/pack.py, build.sh   # 打包
├── docs/                     # technical.md / xiaomi17-adapt.md
└── .github/workflows/release.yml      # 打 tag 自动出 Release
```

```sh
./build.sh            # 默认版 → dist/
./build.sh thermal    # 温控放开版
./build.sh all        # 两个都打
git tag v8.7.0-pudding && git push --tags   # 触发 Actions 自动发 Release
```

</details>
