#!/usr/bin/env bash
#
# 把源码工程打包成独立可编译的目录，并改写 control 里的包名/描述，
# 让 RootHide 与 rootless 两个包能同时安装、互相区分。
#
# 用法：./scripts/make_dist.sh <roothide|rootless> <输出目录>
#
set -euo pipefail

SCHEME="${1:?用法: make_dist.sh <roothide|rootless> <outdir>}"
OUT="${2:?用法: make_dist.sh <roothide|rootless> <outdir>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

rm -rf "$OUT"
mkdir -p "$OUT"

# 复制构建所需文件（不含 .git / preview / packages）
cd "$ROOT"
for item in Makefile control LockScreenDefine.plist Tweak Prefs Shared layout scripts; do
    cp -R "$item" "$OUT/"
done

cd "$OUT"

case "$SCHEME" in
  roothide)
    PKG_ID="com.lockdefine.lockscreendefine.roothide"
    DISPLAY="锁屏定义 (RootHide)"
    DESC="自定义锁屏通知宽度（隐根 / RootHide 专用版，Dopamine 2 roothide）。开关 + 滑块，实时调整锁屏通知卡片宽度并保持居中。"
    ;;
  rootless)
    PKG_ID="com.lockdefine.lockscreendefine.rootless"
    DISPLAY="锁屏定义 (Rootless)"
    DESC="自定义锁屏通知宽度（rootless / var-jb 版，Dopamine rootless、palera1n rootless）。开关 + 滑块，实时调整锁屏通知卡片宽度并保持居中。"
    ;;
  *)
    echo "未知方案: $SCHEME" >&2
    exit 1
    ;;
esac

# 改写 control
python3 - "$SCHEME" "$PKG_ID" "$DISPLAY" "$DESC" <<'PY'
import sys, re, io
scheme, pkg_id, display, desc = sys.argv[1:5]
s = open('control', encoding='utf-8').read()
s = re.sub(r'^Package:.*$', f'Package: {pkg_id}', s, flags=re.M)
s = re.sub(r'^Name:.*$', f'Name: {display}', s, flags=re.M)
s = re.sub(r'^Description:.*$', f'Description: {desc}', s, flags=re.M)
# 维护者/作者加方案后缀，避免两个包冲突感
s = re.sub(r'^Maintainer:.*$', f'Maintainer: LockScreenDefine ({scheme})', s, flags=re.M)
s = re.sub(r'^Author:.*$', f'Author: LockScreenDefine ({scheme})', s, flags=re.M)
open('control', 'w', encoding='utf-8').write(s)
PY

echo "==> 已生成 $SCHEME 源码目录: $OUT"
grep -E '^(Package|Name):' control
