# 技术说明：小米17 适配是怎么做的

写给后续维护者。内容基于真机（小米17 `pudding`，SM8850，HyperOS `OS4.0.5.0.XPCCNXM`）实测数据。

## 1. 模块的工作方式（原设计）

每个已适配机型对应一个模板文件 `dtbo/<代号>_<布局>.tpl`，每行一条规则：

```
节点名<TAB>属性名<TAB>原厂值(hex)<TAB>类型(w|s)<TAB>写入值
```

- 第三列是**本机原厂值**，写入工具用它做"原厂比对"：只有分区里的值与原厂值一致时才写，否则记 `mismatch` 跳过；
- 第五列里的占位符由 shell（`prep()`）与写入工具（`DTBO_SET` 环境变量）替换：
  `{I}` 所选电流、`{S}` 单泵上限、`{V}` 关机电压、`{T}` 断充温度、`{L}` 回差温度（`T-3`，最小 48）；
- `w` 类型 = 若干个 32 位大端整数（逗号分隔）；`s` 类型 = qcom 参数串（`|` 分隔，每段写成 ASCII + NUL）；
- 机型模板由 `stock.list` 里的「原厂 dtbo 头部哈希」映射得到，头部哈希 = dt_table 头部 `total_size` 长度内的 sha256。

## 2. 小米17 的特殊之处

### 2.1 dtbo 是 2 个 DT 入口

```
dt_table header: magic=d7b7ab1e total=1004941 entries=2
entry0: offset=96      size=142142
entry1: offset=142238  size=862703
```

两个入口都含完整的 `fragment@40`（充电相关节点），且 `id/rev/custom` 全是 0。
原版 `dtbopatch` 按"属性名"全局查找，同一个属性出现两次就报
`ERROR: ... appears 2 times, ambiguous` 直接退出——**一条规则都写不进去**。

### 2.2 原版写入器在值变长时会写坏数据

原版按"就地覆盖 + 固定总长"处理。本模板里有 `5424 → 20500`、`9000 → 20500` 这类**变长**替换
（`s` 类型是 ASCII，多一位就多一个字节）。实测让原版工具写一遍后：

| 属性 | 应有值 | 实际写入 |
|---|---|---|
| `qcom,shutdown-voltage` | `00000af0`(2800) | `00000000` |
| `mca_strategy_buckchg_class/ffc_temp_high` | `0x37`(55) | `0x18`(24) |
| `div_max_curr` | `5000,12000,20500` | 4 字节乱码 |

原因就是没有重建 DT table，长值把后面的属性挤乱了。所以**必须**用能重建结构的写入器。

### 2.3 `dtbopatch2`

本 fork 新增的 Go 程序（静态链接 aarch64，约 1.8 MB），规则格式与原版完全一致，行为差异：

- 遍历**所有** DT 入口，对每条规则在每个入口里各写一次（汇总成一条状态输出）；
- 值变长时重建 FDT（保留原 memory-reservation 块与 strings 块），并重建 dt_table 的入口表与偏移；
- 重新计算 AVB：vbmeta 里 dtbo 的 hash descriptor（`digest = sha256(salt || data[0:image_size])`）与
  `image_size`、footer 的 `original_image_size`；
- 镜像总长度与输入保持一致（尾部补零），布局与出厂镜像相同。

在 `apply.sh` 里自动选择：

```sh
EC=$(dd if=$BLK bs=1 skip=16 count=4 | od -An -tx1 | tr -d ' \n'); EC=$((0x$EC))   # dt_entry_count
[ "$EC" -gt 1 ] && [ -x $H/dtbopatch2 ] && PATCHER=$H/dtbopatch2
```

> 注意 Changelog 里那个坑：**必须先 `chmod 755` 再判断 `-x`**，否则 Magisk/KernelSU 解压出的 0644 文件会让
> 判断失败并静默退回原版工具。

## 3. 小米17 的充电参数结构（与原模块已有模板都不同）

`mca_strategy_quick_charge` 用的是"按温区命名的参数表"：

```
batt_para_atl = -65535|13|0|2|0|null… |13|18|0|2|4068|normal_para_13_18|…
                    温度区间: 13-18, 18-23, 23-25, 25-35, 35-40, 40-48
normal_para_23_25 = 4285|18400|5424|4505|5424|800      # 电压门槛/电流/电流/电压门槛/电流/时长
ffc_para_23_25    = 4285|18400|12400|4345|12400|8136|4395|8136|5424|4555|5424|1085
```

- 原厂逻辑：23 °C 以上以 18400 mA 起，随电压升高逐段衰减（12400 → 8136 → 5424）；
- 模板逻辑：把**电流位**都写成 `{I}`，即"所选电流满速跑到截止电压"——这与原模块对其它机型的做法一致；
- 13–18 °C（4068 mA）、18–23 °C（10170 mA）保持原厂，避免低温大电流析锂。

`mca_quick_charge_batt_para_gbl` 是同一套表的"全局/非 ATL 电池"版本，需要同步写，否则两条路径不一致。

### 3.1 温控降流表 `mca_charger_thermal/wired_thermal`

150 个 32 位整数 = 15 档 × 10：

```
第0档(最凉)  1900 1500 1900 3000 | 13500 13500 13500 13500 13500 13500
…                              （前 4 个与后 6 个都随档位递减）
第13档       1100 650 1000 1000 | 1000 1000 1000 1000 1000 1000
第14档(最热) 1100 600  500  500 |  500  500  500  500  500  500
```

实测（v2 保守版、18.4 A、49 % 电量）充电中读数：电池 `3.965 V / 0.994 A ≈ 3.9 W`，USB 输入 `8.87 V`，
电池 40.4 °C、NTC 44.9 °C、充电芯片 45.2 °C。把 0.994 A 折算回输入侧约 0.5 A（电荷泵 2:1），
**正好等于第 14 档的 500 mA** —— 说明温控已把充电压到阶梯最底层，这就是"峰值 46.5 W → 4 W"的原因。

因此：

- 默认版模板**不动**这张表（保守，温度上来就按原厂降流）；
- `variants/pudding_os4-thermal.tpl` 把 15 档的 6 个电流列都写成 `{I}`，并把每档前 4 个限值归一成最凉档，
  与原模块对小米15/K90 的写法一致；保护仍由 `jeita` 分段、55 °C 断充、`vbat_ovp`、内核 `die/adp` 温度上限承担。

## 4. 验证手法（不用反编译、不用装工具）

`dd` 出 dtbo 前 1 MB，用 `strings -n 4` 取 ASCII 参数串再做计数，就能判断模板是否写进去了：

```sh
su -c "dd if=/dev/block/by-name/dtbo_a bs=4096 count=256 2>/dev/null | strings -n 4 | grep -cx 2800"
```

| 计数 | 原厂 | 写入后 | 原因 |
|---|---|---|---|
| `2800` | ≈ 20 | ≈ 232 | 关机电压 2800 铺进 `cc_para0-4`/`dod_para0-4` |
| `18400` | ≈ 42 | ≈ 178 | 快充电流被拉平，重复出现次数大幅增加 |

另外 `dtbo/apply.sh status` 会输出分区状态（`mod/stock/changed/none` + 各参数），
它是把分区内容与写入记录的 sha256 相比，属权威判断。

## 5. 系统 OTA 之后怎么重新适配

1. 先在 WebUI 重新应用一次（模板会逐项比对，只写与原厂值吻合的项，不会乱写）；
2. 若大版本改了表结构（例如 `normal_para_*` 改名或分段变化），逐项比对会一项都不匹配而安全中止。
   此时需要重新生成模板：

```sh
# 手机上导出原厂 dtbo（也可从线刷包的 images/dtbo.img 取）
su -c "dd if=/dev/block/by-name/dtbo_a of=/sdcard/dtbo_a.img bs=1M"
```

把 `dtbo_a.img` 交给维护者，按本文第 1、3 节的规则重新生成 `pudding_os4.tpl`，
并把新的「头部哈希」写进 `stock.list`（哈希算法：dt_table 头部 `total_size` 长度内的 sha256）。

## 6. 已核对过的关键字段（供复查）

| 节点 | 属性 | 原厂值 |
|---|---|---|
| `mca_qcom_subpmic_proxy` | `qcom,shutdown-voltage` | `0x0d16` = 3350 |
| `strategy-fg` | `vcutoff_shutdown_delay` / `vcutoff_sw` / `vcutoff_fw` | 3030 / 2930 / 3030 |
| `mca_strategy_quick_charge` | `div_max_curr` | 5000, 12000, 18400 |
| `mca_strategy_quick_charge` | `div_single_curr` | 4500, 11000, 18400 |
| `mca_strategy_quick_charge` | `non_mi_pps_max_curr` | 4500, 11000, 18400 |
| `mca_strategy_quick_charge` | `real_curr_max` / `curr_monitor_current` | 17500 / 17600 |
| `mca_strategy_buckchg_class` | `ffc_temp_high` / `in_pd` | 48 / 1600 mA |
| `mca_vbat_ovp_mon` | `vbat_ovp_threshold_ffc` | 4580 |
| `mca_protocol_pd_class` | `max_power` | 100 W |
| `strategy-fg` | `drop_fv_cycle` / `drop_fcc_para` | 300 / `300\|0\|800\|500\|65535\|1000` |
