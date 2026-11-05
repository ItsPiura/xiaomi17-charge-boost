# 小米17 适配记录（面向使用者）

本文是适配过程的简明记录，技术细节见 [technical.md](technical.md)。

## 结论

- 机型：`pudding` / Xiaomi 17 / SM8850 / `OS4.0.5.0.XPCCNXM`
- 原厂参数：快充电流峰值 18400 mA、满充截止 4580 mV、关机电压 3030 mV、私有协议 100 W
- 适配后可选：电流 18.4 A（原厂值）/ 20.5 A（上限）、断充温度 55 °C、关机电压 2800 mV、
  满充截止电压 4490–4650 mV（默认保持原厂）

## 为什么原版模块在小米17 上写不进去

1. 小米17 的 dtbo 有 **2 个 DT 入口**，原版写入器会因"同一属性出现两次"直接中止；
2. 原版写入器不支持值变长，会写坏相邻属性；
3. 安装脚本在 `chmod` 之前判断可执行位，Magisk/KernelSU 解压出的 0644 文件必然判断失败。

三点均已修复（新增 `dtbopatch2` + 修正 `apply.sh`）。

## 实测数据

| 场景 | 结果 |
|---|---|
| 保守版（温控表原厂）、18.4 A、49 % 电量、亮屏 | 峰值 46.5 W，随后降至 33 W，40 °C 时降到 ~4 W |
| 同状态读数 | 电池 3.965 V / 0.994 A；USB 输入 8.87 V；电池 40.4 °C、NTC 44.9 °C、充电芯片 45.2 °C |
| 归因 | 0.994 A ≈ 温控降流表第 14 档 500 mA ×2（电荷泵），即温控已把充电压到最底层 |

因此提供一个可选模板 `variants/pudding_os4-thermal.tpl`（温控表全放开），适合"要速度、能接受发热"的场景。

## 验证（三条命令）

```sh
su -c "sh /data/adb/modules/mi_charge_boost/dtbo/apply.sh status"     # 期望 mod 18400 2800 55 - - -
su -c "dd if=/dev/block/by-name/dtbo_a bs=4096 count=256 2>/dev/null | strings -n 4 | grep -cx 2800"   # 期望 ≈232
su -c "dd if=/dev/block/by-name/dtbo_a bs=4096 count=256 2>/dev/null | strings -n 4 | grep -cx 18400"  # 期望 ≈178
```
