#!/usr/bin/env bash
# トンネルを切り、Colab のランタイムを停止する。ダウンロード済みのモデルも消える。
source "$(dirname "$0")/lib/common.sh"

require_cmds colab

if [[ -f "$TUNNEL_PID_FILE" ]]; then
    log "$(msg closing_tunnel)"
    stop_tunnel
fi
# 共有 SSH 接続を閉じる。相乗りしている ./ssh.sh なども切れる
close_link
stop_master

if session_exists; then
    log "$(msg stopping_runtime "$COLAB_SESSION")"
    colab stop -s "$COLAB_SESSION"
else
    log "$(msg runtime_already_gone "$COLAB_SESSION")"
fi

log "$(msg usage_after_stop)"
colab usage | sed 's/^/    /'
