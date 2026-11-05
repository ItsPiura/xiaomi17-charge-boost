#!/system/bin/sh
# 高刷守护：开机恢复上次档位；亮屏解锁后逐级重爬；掉档逐级拉回（失败 60 秒冷却后再试）
MODDIR=${0%/*}; MODDIR=${MODDIR%/hz}
. $MODDIR/hz/common.sh
# 高刷切换只适用于小米15（华星 o3_42 超频档）；其它机型不启动守护
[ "$(cat $MODDIR/model 2>/dev/null || echo dada)" = dada ] || { echo 0 > $AVAILF; exit 0; }
lock_free; rm -f $FAILF $AVAILF
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done
sleep 20
[ -n "$(get_id 165)" ] && echo 1 > $AVAILF || echo 0 > $AVAILF
HZ=$(cat $CONF 2>/dev/null); [ -z "$HZ" ] && HZ=120
if [ "$HZ" -gt 120 ] && [ "$(cat $AVAILF)" = 0 ]; then
  hist "当前 dtbo 无超频档位（可用：$(hz_modes)），${HZ}Hz 未恢复"; echo 120 > $CONF; HZ=120
fi
[ -f $CONF ] && [ ! -f $OFFF ] && SRC=开机 apply_hz $HZ >/dev/null 2>&1   # 没选过档位（无 hz.conf）就不动系统
write_stat
awake(){ timeout 4 dumpsys power 2>/dev/null | grep -q "mWakefulness=Awake"; }
# 锁屏界面还在（没解锁）
locked(){ timeout 4 dumpsys window 2>/dev/null | grep -qE "mDreamingLockscreen=true|isKeyguardShowing=true|mShowingLockscreen=true|KeyguardShowing=true"; }
LAST=1
while true; do
  sleep 2
  awake || { LAST=0; continue; }
  lock_busy && continue
  write_stat
  [ -f $MODDIR/disable ] && continue
  [ -f $OFFF ] && continue
  T=$(cat $CONF 2>/dev/null); [ -z "$T" ] && T=120
  [ -f $CONF ] || { LAST=1; continue; }
  [ "$T" -lt 120 ] && T=120
  # 亮屏边沿：每次亮屏面板都从 120 开始，直接设目标档不生效，要等解锁后（有画面在动）逐级重爬
  if [ $LAST = 0 ]; then
    LAST=1; n=0; while locked && [ $n -lt 40 ]; do sleep 0.5; n=$((n+1)); awake || break; done
    awake || { LAST=0; continue; }
    rm -f $FAILF; SRC=亮屏 apply_hz $T >/dev/null 2>&1
    # 解锁动画结束后再用面板 TE 实测核对一次，没到位再爬（锁屏识别不到时也能兜住）
    sleep 3; awake && ! lock_busy && { MT=$(modes); reached $T >/dev/null || { SRC=亮屏复核 apply_hz $T >/dev/null 2>&1; }; }
    write_stat; continue
  fi
  [ "$T" -le 120 ] && continue   # 120 只在亮屏时重新锁一次，不按读数拉回（idle 会报 60）
  # 失败冷却：失败后 60 秒内不重试，之后再试（不再永久放弃）
  if [ -f $FAILF ]; then
    F0=$(cut -d' ' -f1 $FAILF 2>/dev/null); case "$F0" in ''|*[!0-9]*) F0=0;; esac
    [ $(( $(now) - F0 )) -lt $FAIL_TTL ] && continue
    rm -f $FAILF; hist "失败冷却结束，重新尝试 ${T}Hz"
  fi
  read C W I < $STATF
  [ -z "$C" ] && continue
  [ "$C" = "$T" ] && continue
  [ "$C" = -1 ] && continue    # 面板 idle 且内核无切换记录：状态未知，不当掉档
  [ "$W" = 0 ] && continue     # dumpsys 超时
  [ "$C" -gt "$T" ] 2>/dev/null && continue   # 比目标高 = 降档等熄屏生效，不算掉档
  hist "检测到掉档 ${C}Hz，自动拉回"; SRC=守护 apply_hz $T >/dev/null 2>&1; write_stat
done
