#!/usr/bin/env python3
# 打包工具：把仓库根目录（= 模块目录）打成可刷入的 zip
# 用法：python3 tools/pack.py [normal|thermal|all]
import os, sys, zipfile, stat, shutil, re

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.join(REPO, 'module')   # 模块本体在 module/ 子目录
DIST = os.path.join(REPO, 'dist')

# 模块本体文件/目录白名单（仓库里其余东西都是 GitHub 用的，不进 zip）
MODULE_ENTRIES = [
    'META-INF', 'apk', 'cc', 'dtbo', 'hs', 'hz', 'pps', 'proto', 'qr', 'tr', 'webroot',
    'common.sh', 'customize.sh', 'detect.sh', 'logger.sh', 'logs.sh', 'lowbat.sh',
    'model.sh', 'models.sh', 'module.prop', 'read.sh', 'service.sh', 'sysinfo.sh',
    'uninstall.sh',
]


def module_files():
    out = []
    for e in MODULE_ENTRIES:
        p = os.path.join(ROOT, e)
        if os.path.isfile(p):
            out.append(e)
        elif os.path.isdir(p):
            for dp, dn, fn in os.walk(p):
                for f in fn:
                    full = os.path.join(dp, f)
                    out.append(os.path.relpath(full, ROOT))
    return sorted(out)


def version():
    for line in open(os.path.join(ROOT, 'module.prop'), encoding='utf-8'):
        if line.startswith('version='):
            return line.strip().split('=', 1)[1]
    return 'unknown'


def build(mode):
    ver = version()
    name = 'Micharge-boost_%s_xiaomi17.zip' % ver
    if mode == 'thermal':
        name = 'Micharge-boost_%s-thermal_xiaomi17.zip' % ver
    os.makedirs(DIST, exist_ok=True)
    out = os.path.join(DIST, name)
    thermal = None
    if mode == 'thermal':
        thermal = os.path.join(REPO, 'variants', 'pudding_os4-thermal.tpl')

    files = module_files()
    files.sort(key=lambda r: (0 if r.startswith('META-INF') else
                              (1 if r in ('module.prop', 'customize.sh', 'service.sh') else 2), r))
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for rel in files:
            full = os.path.join(ROOT, rel)
            data = open(full, 'rb').read()
            if thermal and rel == 'dtbo/pudding_os4.tpl':
                data = open(thermal, 'rb').read()
            st = os.stat(full)
            zi = zipfile.ZipInfo(rel, date_time=(2026, 11, 5, 12, 0, 0))
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.external_attr = (stat.S_IFREG | (0o755 if st.st_mode & 0o111 else 0o644)) << 16
            z.writestr(zi, data)
    print('✓ %s  (%d files, %.2f MB)' % (out, len(files), os.path.getsize(out) / 1048576))
    return out


if __name__ == '__main__':
    mode = sys.argv[1] if len(sys.argv) > 1 else 'normal'
    if mode == 'all':
        build('normal'); build('thermal')
    elif mode in ('normal', 'thermal'):
        build(mode)
    else:
        sys.exit('usage: pack.py [normal|thermal|all]')
