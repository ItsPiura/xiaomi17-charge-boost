#!/system/bin/sh
# WebUI 入口：sh hz.sh status | set <Hz> | poll | hist | clear | log | unlock
# 命令全部瞬间返回（只读缓存文件），不在管理器的 root shell 里跑 dumpsys
MODDIR=/data/adb/modules/mi_charge_boost
. $MODDIR/hz/common.sh
OUT=/dev/mi_charge_boost_hz.out
case "$1" in
  status)
    T=$(cat $CONF 2>/dev/null); [ -z "$T" ] && T=120
    S=$(cat $STATF 2>/dev/null); set -- $S
    C=${1:-0}; W=${2:-0}; I=${3:-0}; [ "$C" = -1 ] && C=0   # idle 读不到内核记录 = 未知
    B=0; lock_busy && B=1
    F=0; [ -f $FAILF ] && F=1
    A=$(cat $AVAILF 2>/dev/null); [ -z "$A" ] && A=-1
    O=1; [ -f $OFFF ] && O=0
    echo "{\"on\":$O,\"target\":$T,\"cur\":$C,\"raw\":$W,\"idle\":$I,\"busy\":$B,\"fail\":$F,\"avail\":$A}"
    ;;
  avail)  # 有 165Hz 模式才显示 WebUI 的高刷切换入口（只有小米15；K90至尊版原生 165Hz 不走这里）
    [ "$(cat $MODDIR/model 2>/dev/null || echo dada)" = dada ] || { echo 0; exit 0; }
    A=$(cat $AVAILF 2>/dev/null)
    if [ -z "$A" ]; then [ -n "$(get_id 165)" ] && A=1 || A=0; echo $A > $AVAILF; fi
    echo $A ;;
  poll) cat $OUT 2>/dev/null; lock_busy && echo "@@1" || echo "@@0" ;;
  on)  # 打开功能：恢复上次档位
    rm -f $OFFF; T=$(cat $CONF 2>/dev/null); [ -z "$T" ] && T=120
    if [ "$T" -gt 120 ] && ! lock_busy && [ "$(cat $AVAILF 2>/dev/null)" != 0 ]; then rm -f $FAILF; : > $OUT
      SRC=开启 setsid sh -c ". $MODDIR/hz/common.sh; apply_hz $T; write_stat" > $OUT 2>&1 </dev/null &
      echo "高刷切换已开启，恢复 ${T}Hz"; else echo "高刷切换已开启"; fi ;;
  off)  # 关闭功能：解除锁定交还系统，守护不再拉回
    touch $OFFF; rm -f $FAILF; : > $OUT
    setsid sh -c ". $MODDIR/hz/common.sh; lock_take; echo '关闭高刷切换'; release; lock_free; hist '关闭高刷切换，交还系统调度'; write_stat" > $OUT 2>&1 </dev/null &
    echo "高刷切换已关闭，交还系统调度" ;;
  set)
    [ -f $OFFF ] && { echo "高刷切换已关闭，请先打开开关"; exit 1; }
    case " $OC " in *" $2 "*) ;; *) echo "不支持的档位 $2"; exit 1;; esac
    lock_busy && { echo "正在切换中，稍后再试"; exit 1; }
    [ "$2" -gt 120 ] && [ "$(cat $AVAILF 2>/dev/null)" = 0 ] && { echo "当前 dtbo 没有 ${2}Hz 档位，请先在充电配置里写入屏幕超频并重启"; exit 1; }
    rm -f $FAILF; echo $2 > $CONF; : > $OUT
    SRC=WebUI setsid sh -c ". $MODDIR/hz/common.sh; apply_hz $2; write_stat" > $OUT 2>&1 </dev/null &
    echo "开始切换到 ${2}Hz"
    ;;
  hist) [ -s $HISTF ] && tail -n 50 $HISTF | sed -n '1!G;h;$p' || echo "暂无记录" ;;
  clear) : > $HISTF; echo "已清空" ;;
  unlock) rm -rf $LOCK; rm -f $FAILF; echo "已清除切换锁和失败标记" ;;
  log) cat $OUT 2>/dev/null; echo "--- 诊断日志 ---"; tail -n 20 $LOGF 2>/dev/null ;;
  *) echo "用法: hz.sh status|on|off|set <Hz>|poll|hist|clear|log|unlock" ;;
esac
exit 0
