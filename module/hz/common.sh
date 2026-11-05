HD=/data/adb/mi_charge_boost
CONF=$HD/hz.conf
OFFF=$HD/hz.off     # 存在 = 高刷切换功能关闭，不锁档、不守护
LOCK=/dev/mi_charge_boost_hz.lock
LOCK_TTL=${LOCK_TTL:-90}      # 残留锁自动接管阈值（秒）
FAIL_TTL=${FAIL_TTL:-60}      # 失败冷却（秒）：一次失败不再永久放弃
OC="120 132 144 156 165"        # 超频档只能相邻逐级切换（若 SF 报 155 就把 156 改成 155）
STEP_DELAY=${STEP_DELAY:-0.28}  # 逐级切换间隔（同 HzSwitch 280ms）
LOGF=$HD/hz_switch.log
FAILF=/dev/mi_charge_boost_hz.fail
HISTF=$HD/hz.history   # 切换日志（重启保留，最多 100 条）
STATF=/dev/mi_charge_boost_hz.stat
AVAILF=/dev/mi_charge_boost_hz.avail   # 有 165Hz 模式=1   # 守护进程写入的状态缓存，WebUI 只读这个文件

sf(){ dumpsys SurfaceFlinger 2>/dev/null; }
# 档位表：每行 "Hz id 分辨率"；兼容 165.00 / 165.000000 / 字段顺序变化
modes(){
  sf | grep -oE "\{id=[0-9]+, hwcId=[0-9]+[^}]*vsyncRate=[0-9]+(\.[0-9]+)? ?Hz" \
     | sed -E 's/^\{id=([0-9]+).*resolution=([0-9]+x[0-9]+).*vsyncRate=([0-9]+).*/\3 \1 \2/'
}
get_id(){ modes | awk -v h="$1" '$1==h{print $2; exit}'; }
res(){    modes | awk -v h="$1" '$1==h{print $3; exit}'; }
hz_modes(){ modes | awk '{print $1}' | sort -n -u | tr '\n' ' '; }
raw_hz(){ sf | grep -m1 -oE "activeMode=\{id=[0-9]+[^}]*vsyncRate=[0-9]+" | sed 's/.*vsyncRate=//'; }

# 小米 DDIC 空闲模式（120@idle, ddic_mode=1）：静止画面时面板自动进入，有画面变化立即回到目标档。
# 这时以内核 dsi_display_set_mode 最近一次 ddic_mode=normal 的 fps 为准。
is_idle(){ sf | grep -m1 "activeMode=" | grep -q "ddic_mode=1"; }
kern_hz(){ dmesg 2>/dev/null | grep -o "fps=[0-9]*,ddic_mode=normal" | tail -n1 | sed 's/fps=\([0-9]*\),.*/\1/'; }
kern_n(){ dmesg 2>/dev/null | grep -c "ddic_mode=normal"; }
pol_hz(){ sf | grep -m1 -o "displayManagerPolicy={defaultModeId=[0-9]*" | sed 's/.*=//'; }
cur_hz(){
  if is_idle; then L=$(kern_hz); [ -n "$L" ] && { echo $L; return; }; fi
  raw_hz
}

# ---- 切换锁：进程被 WebUI 关掉 / 被系统回收时自动接管，不再永久卡“正在切换中” ----
now(){ date +%s 2>/dev/null || /system/bin/toybox date +%s; }
# 锁仍有效 = 目录在、持锁进程还活着、心跳没超时；进程被杀/回收后立刻视为残留锁
lock_busy(){
  [ -d $LOCK ] || return 1
  P=$(cat $LOCK/pid 2>/dev/null); T0=$(cat $LOCK/ts 2>/dev/null)
  [ -z "$T0" ] && T0=$(stat -c %Y $LOCK 2>/dev/null); [ -z "$T0" ] && T0=0
  [ -n "$P" ] && kill -0 $P 2>/dev/null && [ $(( $(now) - T0 )) -le $LOCK_TTL ] && return 0
  [ -z "$P" ] && [ $(( $(now) - T0 )) -le 5 ] && return 0   # 刚 mkdir 还没写 pid
  return 1
}
lock_take(){
  mkdir $LOCK 2>/dev/null || { lock_busy && return 1; echo "  清理残留锁"; rm -rf $LOCK; mkdir $LOCK 2>/dev/null || return 1; }
  now > $LOCK/ts; echo $$ > $LOCK/pid; return 0
}
lock_beat(){ now > $LOCK/ts 2>/dev/null; }
lock_free(){ rm -rf $LOCK 2>/dev/null; }

st(){ settings "$@" </dev/null >/dev/null 2>&1; }   # 输出必须给 /dev/null：输出到 /dev 下的文件时 system_server 无权用该 fd，会报 Failed transaction
lock_mode(){  # 同“屏幕刷新率”App：SF 后门 + 刷新率设置同时锁定
  service call SurfaceFlinger 1035 i32 $2 </dev/null >/dev/null 2>&1
  st put system peak_refresh_rate $1.0
  st put system min_refresh_rate $1.0
  st put system user_refresh_rate $1
  st put secure miui_refresh_rate $1
}
commit(){  # 到位后：设为系统“用户首选显示模式”，防止被空闲/系统调度打回
  [ -n "$MT" ] || MT=$(modes)
  RES=$(echo "$MT" | awk -v h="$1" '$1==h{print $3; exit}'); W=${RES%x*}; H=${RES#*x}
  [ -n "$W" ] && cmd display set-user-preferred-display-mode $W $H $1 </dev/null >/dev/null 2>&1
  lock_mode $1 $(mid $1)
}
release(){  # 解除后门锁定，交还系统调度
  cmd display clear-user-preferred-display-mode </dev/null >/dev/null 2>&1
  service call SurfaceFlinger 1035 i32 -1 </dev/null >/dev/null 2>&1
  st put system peak_refresh_rate 120.0
  st delete system min_refresh_rate
  st delete system user_refresh_rate
  st delete secure miui_refresh_rate
  sleep $STEP_DELAY
  echo "  已解除锁定，交还系统调度，当前 $(cur_hz)Hz"
}
[ -f $LOGF ] && [ $(wc -c < $LOGF) -gt 200000 ] && { tail -n 300 $LOGF > $LOGF.tmp; mv -f $LOGF.tmp $LOGF; }
diag(){  # 掉档诊断写入 switch.log
  { echo "=== $(date '+%m-%d %H:%M:%S' 2>/dev/null || /system/bin/toybox date '+%m-%d %H:%M:%S') 诊断 目标$1 可用档位: $(hz_modes)==="
    getprop | grep -iE "idle|fps|refresh|frame_rate|vrr" | head -n 30
    sf | grep -v "GL_" | grep -iE "activeMode|KernelIdleTimer|touchTimer|idleTimer|displayManagerPolicy" | head -n 8
    dmesg 2>/dev/null | grep -iE "early_trigger|thermal.*fps|fps.*limit" | tail -n 8
  } >> $LOGF 2>/dev/null
}
ladder(){  # 从 $1 到 $2 依次输出经过的档位（不含起点）
  echo "$OC" | tr ' ' '\n' | awk -v a=$1 -v b=$2 '{v[NR]=$1} END{
    if(a<b){for(i=1;i<=NR;i++) if(v[i]>a && v[i]<=b) print v[i]}
    else   {for(i=NR;i>=1;i--) if(v[i]<a && v[i]>=b) print v[i]}}'
}
# ---- 逐级爬档（照 HzSwitch 的回拉方式）----
# 华星 o3_42 超频档规律（HzSwitch 实测）：
#   只能相邻逐级往上，且必须在画面出帧时切，静止画面切了不生效；
#   每次亮屏面板都从 120 重新开始，但 SurfaceFlinger 还以为自己在原档位（SF 读数 165、面板实际 120），
#   这时再设同一个模式 SF 不会下发，所以“读数到位就跳过”的拉回永远拉不回来；
#   132 上下即时生效，从 144 及以上往下切要熄屏一次才生效。
# 做法同 HzSwitch 的阶梯：不信 SF 读数，每次都先切到 90（没有就 60）让 SF 真正下发一次，再 120→132→…逐级，
# 每级 0.28 秒，期间用 SF 1004 强制合成持续出帧；验证用面板 TE 计数（hw_vsync_info）而不是 SF 读数。
TE=/sys/devices/virtual/mi_display/disp_feature/disp-DSI-0/hw_vsync_info
MT=
mid(){ echo "$MT" | awk -v h="$1" '$1==h{print $2; exit}'; }
kick_on(){ kick_off; ( n=0; while [ $n -lt 600 ]; do service call SurfaceFlinger 1004 </dev/null >/dev/null 2>&1; n=$((n+1)); done ) & KP=$!; }
kick_off(){ [ -n "$KP" ] && { kill $KP 2>/dev/null; wait $KP 2>/dev/null; }; KP=; }
step(){ I=$(mid $1); [ -z "$I" ] && return 1
  service call SurfaceFlinger 1035 i32 $I </dev/null >/dev/null 2>&1; echo "  -> ${1}Hz(id=$I)"; sleep $STEP_DELAY; }
# 面板实测刷新率（有帧时才准）：先出帧 0.8 秒再读 TE；读不到返回空
te_hz(){ [ -r $TE ] || return; kick_on; sleep 0.8; V=$(awk '{v=$2+0; if(v>30) printf "%d", v+0.5}' $TE 2>/dev/null); kick_off; echo $V; }
# TE 实测与目标相差 6Hz 以内算到位（165 档实测 161–164）；没有 TE 节点就用 SF 读数
reached(){ R=$(te_hz); [ -z "$R" ] && R=$(cur_hz); echo "  实际 ${R}Hz"; [ -n "$R" ] && [ $((R - $1)) -le 6 ] && [ $(($1 - R)) -le 6 ]; }
ladder_full(){  # 重置档 → 120 → 逐级到 $1
  RST=90; [ -z "$(mid 90)" ] && RST=60; [ -z "$(mid $RST)" ] && RST=
  kick_on
  [ -n "$RST" ] && step $RST
  step 120
  for N in $(ladder 120 $1); do step $N || { kick_off; return 1; }; lock_beat; done
  sleep 0.3; kick_off
}
ladder_low(){  # 120 / 132：60 → 90 → 120 (→ 132)
  kick_on
  for N in 60 90 120 132; do [ $N -le $1 ] && step $N; done
  sleep 0.3; kick_off
}
apply_hz(){
  T=$1; [ "$T" -lt 120 ] && T=120
  lock_take || { echo "正在切换中，稍后再试"; return 1; }
  S0=$(now); MT=$(modes); F0=$(cur_hz); R=
  echo "目标 ${T}Hz，SF 读数 ${F0}Hz"
  RS=成功; STEP_DELAY=${STEP_DELAY:-0.28}
  if [ -z "$(mid $T)" ]; then echo "  当前 dtbo 无 ${T}Hz 模式（可用：$(hz_modes)）"; RS=未到位
  else
    r=0; ok=0
    while [ $r -lt 3 ]; do
      r=$((r+1)); lock_beat; [ $r -gt 1 ] && echo "  第${r}轮重爬"
      if [ "$T" -le 132 ]; then ladder_low $T; else ladder_full $T; fi
      if reached $T; then ok=1; break; fi
      { echo "$(date '+%H:%M:%S') want $T 第${r}轮 got $R"; dmesg 2>/dev/null | grep -iE "dsi_display_set_mode|early_trigger" | tail -n 4; } >> $LOGF
    done
    commit $T; [ $ok = 1 ] || RS=未到位
  fi
  N=${R:-$(cur_hz)}
  if [ "$RS" = 未到位 ]; then echo "未到位：实测 ${N}Hz，诊断已写入 switch.log"; echo "$(now) $T" > $FAILF; diag $T
  else echo "完成：实测 ${N}Hz"; rm -f $FAILF; fi
  hist "${F0:-?}→${T}Hz $RS 实测${N}Hz 用时$(( $(now) - S0 ))s"
  lock_free
}

write_stat(){  # 只调用一次 dumpsys，结果缓存给 WebUI；C=-1 表示 idle 且读不到内核记录（状态未知）
  D=$(timeout 4 dumpsys SurfaceFlinger 2>/dev/null | grep -m1 "activeMode=")
  W=$(echo "$D" | grep -o "vsyncRate=[0-9]*" | head -n1 | sed 's/.*=//'); [ -z "$W" ] && W=0
  I=0; C=$W
  if echo "$D" | grep -q "ddic_mode=1"; then
    I=1; K=$(kern_hz)
    if [ -n "$K" ]; then C=$K; else C=-1; fi
  fi
  echo "$C $W $I" > $STATF.tmp && mv -f $STATF.tmp $STATF
}

hist(){  # 写一条切换日志：时间 来源 内容
  echo "$(date '+%m-%d %H:%M:%S' 2>/dev/null || /system/bin/toybox date '+%m-%d %H:%M:%S') [${SRC:-手动}] $1" >> $HISTF
  [ $(wc -l < $HISTF) -gt 120 ] && { tail -n 100 $HISTF > $HISTF.tmp; mv -f $HISTF.tmp $HISTF; }
}
