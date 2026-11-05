#!/system/bin/sh
# 卸载时把本模块写入的 dtbo 还原为原版（v8.6.4）
#  - 两个数据目录都找（/data/adb/mi_charge_boost/dtbo 和备用目录 /data/adb/.mcb_dtbo）
#  - 备份按槽位：stock_a.img 只还 dtbo_a，stock_b.img 只还 dtbo_b；旧版单份 stock.img 只在只有一个槽是修改状态时才用
#  - 只在分区内容仍是本模块写入的那份时才还原（按 written 记录确认；记录缺失/损坏、OTA 或手动刷过 dtbo 都不碰）
#  - 写入后回读校验，失败重试 3 次
#  - 没还原的都把备份连同 conf/tpl/写入记录和 README 说明保留到 /data/adb/mcb_dtbo_keep/<目录>，不随卸载删除
LOG=/data/adb/mcb_uninstall.log
K=/data/adb/mcb_dtbo_keep
lg(){ echo "$(date '+%m-%d %H:%M:%S' 2>/dev/null) $*" >> $LOG; }
sha(){ dd if="$1" bs=4096 count=$2 2>/dev/null | sha256sum | cut -d' ' -f1; }
blk(){ for b in /dev/block/by-name/dtbo$1 /dev/block/bootdevice/by-name/dtbo$1; do [ -e $b ] && { echo $b; return; }; done; }
S=$(getprop ro.boot.slot_suffix)
keep(){ # $1=数据目录 $2=原因：备份连同 conf/tpl/state/written 和说明一起保留，按目录区分不互相覆盖
  t=$K/$(echo ${1#/data/adb/} | tr '/.' '__'); mkdir -p $t || return
  for f in $1/stock*.img $1/stock_src* $1/conf* $1/tpl* $1/*.unclaimed $1/state* $1/written*; do [ -f $f ] && cp -f $f $t/; done
  { echo "原因: $2"; echo "时间: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
    echo "机型: $(getprop ro.product.marketname) ($(getprop ro.product.device))  当前槽位: ${S:-无}"
    echo "系统: $(getprop ro.build.display.id)  底包: $(getprop ro.vendor.build.version.incremental)"
    echo "来源目录: $1"
    echo "stock_a.img / stock_b.img 是本模块首次修改对应槽位前备份的 dtbo（无槽位机型或旧版为 stock.img）"
    echo "确认机型和底包一致后，按文件名里的槽位刷回，例如 fastboot flash dtbo_a stock_a.img"; } > $t/README.txt
  lg "备份已保留：$t（$2）"; }
restore_dir(){ # $1=数据目录
  X=$1; [ -d $X ] || return 0; R=; NM=0
  for s in "" _a _b; do [ "$(cat $X/state$s 2>/dev/null)" = mod ] && NM=$((NM+1)); done
  for s in "" _a _b; do
    [ "$(cat $X/state$s 2>/dev/null)" = mod ] || continue
    I=$X/stock$s.img
    if [ ! -f $I ]; then
      if [ -n "$s" ] && [ -f $X/stock.img ] && [ $NM = 1 ]; then I=$X/stock.img
      else R="${R}dtbo$s 没有本槽位的原版备份，未还原；"; continue; fi
    fi
    n=$(( $(stat -c %s $I 2>/dev/null || echo 0) / 4096 ))
    [ $n -gt 0 ] || { R="${R}${I##*/} 为空或不足 4K，dtbo$s 未还原；"; continue; }
    want=$(sha $I $n)
    B=$(blk $s); [ -n "$B" ] || { R="${R}找不到 dtbo$s 分区；"; continue; }
    [ "$(sha $B $n)" = "$want" ] && { lg "dtbo$s 已是原版"; continue; }
    W=; N=; [ -f $X/written$s ] && read W N < $X/written$s
    case "$N" in ""|*[!0-9]*) N=;; esac
    if [ -z "$W" ] || [ -z "$N" ]; then R="${R}dtbo$s 缺少有效写入记录，无法确认分区归属，未还原；"; continue; fi
    [ "$(sha $B $N)" = "$W" ] || { R="${R}dtbo$s 已被系统或其它工具改过，未还原；"; continue; }
    ok=0; i=0
    while [ $i -lt 3 ]; do i=$((i+1))
      blockdev --setrw $B 2>/dev/null
      dd if=$I of=$B bs=1048576 conv=fsync 2>/dev/null; sync
      [ "$(sha $B $n)" = "$want" ] && { ok=1; break; }
      sleep 1
    done
    if [ $ok = 1 ]; then lg "dtbo$s 已用 ${I##*/} 还原原版（第 $i 次）"
    else R="${R}dtbo$s 还原失败（3 次回读校验不通过）；"; fi
  done
  for f in $X/stock.unclaimed.img $X/stock*.old.img; do [ -f $f ] && R="${R}${f##*/} 是无法确认归属/被系统替换前的旧备份，仅保留；"; done
  [ -n "$R" ] && { lg "$R"; keep $X "$R"; }
  return 0
}
restore_dir /data/adb/mi_charge_boost/dtbo
restore_dir /data/adb/.mcb_dtbo
# 高刷切换：解除锁定交还系统（只有小米15 用过高刷切换；其它机型不动刷新率设置）
if [ "$(cat ${0%/*}/model 2>/dev/null || echo dada)" = dada ]; then
cmd display clear-user-preferred-display-mode >/dev/null 2>&1
service call SurfaceFlinger 1035 i32 -1 >/dev/null 2>&1
settings put system peak_refresh_rate 120.0
settings delete system min_refresh_rate >/dev/null 2>&1
settings delete system user_refresh_rate >/dev/null 2>&1
settings delete secure miui_refresh_rate >/dev/null 2>&1
fi
# 软断充温度：撤销伪装、恢复充电
for n in /sys/class/xm_power/fuelgauge/strategy_fg/fake_temp; do [ -f $n ] && echo -999 > $n; done
[ -f /data/adb/mi_charge_boost/soft_stop ] && echo 0 > /sys/class/xm_power/charger/charge_interface/input_suspend 2>/dev/null
[ -f /data/adb/mi_charge_boost/cc_stop ] && echo 0 > /sys/class/xm_power/charger/charge_interface/input_suspend 2>/dev/null
# 实时充电电流：写回最大值交还系统温控
N=/sys/class/xm_power/charger/charger_thermal/wired_chg_curr; [ -f $N ] && echo 22000000 > $N 2>/dev/null
# 低电量延迟关机：还原小米 30 秒关机倒计时开关
[ -f /data/adb/mi_charge_boost/sde.list ] && while IFS='|' read -r f v; do [ -f "$f" ] && [ -n "$v" ] && echo "$v" > "$f" 2>/dev/null; done < /data/adb/mi_charge_boost/sde.list
rm -rf /data/adb/mi_charge_boost /data/adb/.mcb_dtbo
