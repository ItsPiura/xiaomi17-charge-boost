# 更新日志

## v8.7.0-pudding（2026-11-05）首个公开版本

基于原模块 v8.6.4，新增 **小米 17（`pudding` / SM8850 / HyperOS `OS4.0.5.0.XPCCNXM`）** 适配。

**新增**
- 机型表新增 `pudding`：`MI=18400`、`MX=20500`、`SC=20000`、`VQ=4580`、`V0=3030`、`PW0=100`、无私有协议可选档
- `sysinfo.sh` 机型显示为 `Xiaomi 17`；`stock.list` 收录本机原厂 dtbo 头部哈希
- `dtbo/pudding_os4.tpl`：37 条规则（原厂值全部取自真机 dtbo 并逐条校验）
- `dtbo/dtbopatch2`：支持多入口 DT table 的规则写入器（Go 静态编译，aarch64）
- `variants/pudding_os4-thermal.tpl`：可选模板，把温控降流表 `wired_thermal` 15 档电流全放开
- `tools/pack.py` + `build.sh`：一条命令出可刷 zip；`.github/workflows/release.yml`：打 tag 自动发 Release

**修复**
- `apply.sh` 在 `chmod 755` 之前判断 `dtbopatch2` 是否可执行 —— Magisk/KernelSU 解压后二进制为 0644，
  导致判断失败并退回原版 `dtbopatch`，在小米17 上必然 `appears 2 times, ambiguous` 中止（分区未改动，属安全失败）
- 写入失败原因现在记录到 `/data/adb/mi_charge_boost/dtbo_fail`，并在模块描述里以 `❌ 未写入：<原因>` 显示；
  写入成功后自动清除（此前失败原因会被开机后的 `apply.sh desc` 覆盖成含糊的「DTBO 未修改」）

**模板内容（相对原厂）**
- `normal_para_* / ffc_para_*`（≥23 °C 温区）电流 → 所选电流（拉平原厂的 18400→12400→8136→5424 衰减）
- 13–18 °C、18–23 °C 低温区电流保持原厂
- 断充温度 48 → 55 °C（`batt_para_atl` + `ffc_temp_high` + `jeita_para*`）
- 关机电压 `qcom,shutdown-voltage` / `vcutoff_*` / `cc_para0-4` / `dod_para0-4` 可选 2800 mV
- `drop_fv_cycle → 0`、`drop_fcc_para 门槛 → 65535`（关闭按循环次数降流/降压）
- 满充截止电压默认保持原厂（`dtbofv` 实测 4580 mV，WebUI 可调 4490–4650）

## 附：适配过程中的内部迭代（未单独发布）

| 标记 | 内容 | 结果 |
|---|---|---|
| `-pudding` | 首个适配版（机型 + 模板 + `dtbopatch2`） | ❌ 安装时因执行位判断顺序 bug 未能写入 dtbo |
| `-pudding2` | 修复执行位 bug、增加失败原因记录 | ✅ 写入成功（`patch=31 done=6 total=37`） |
| `-pudding3` | 新增 `wired_thermal`，仅放开 0–12 档 | ⚠️ 实测本机高温时落在 13/14 档，无明显改善 |
| `-pudding4` | `wired_thermal` 15 档全放开 + 前 4 列归一 | ✅ 有效，但发热明显；最终作为可选 `-thermal` 变体 |
