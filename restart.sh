#!/usr/bin/env bash
# config.env や config.local.env を変えたあとに、ランタイムを残したまま Strata だけを起動し直す。
# ダウンロード済みのモデルはそのまま使う。MODEL を変えたときは、そのモデルだけを新しく落とす。
source "$(dirname "$0")/lib/common.sh"

require_cmds colab ssh curl ss
session_exists || die "$(msg runtime_missing_start "$COLAB_SESSION")"

# 別のウィンドウの見張りは起動したときの設定を持っているので、先に止める
if [[ -f "$TUNNEL_PID_FILE" ]]; then
    log "$(msg rs_closing_window)"
    stop_tunnel
fi

log "$(msg rs_restarting)"
remote_start 2
log "$(msg rs_waiting)"
wait_healthy
log "$(msg started)"

run_tunnel_foreground
