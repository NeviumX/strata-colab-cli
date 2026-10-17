#!/usr/bin/env bash
# ランタイム・Strata・トンネルの状態をまとめて表示する。
source "$(dirname "$0")/lib/common.sh"

require_cmds colab ssh curl

msg st_runtime "$COLAB_SESSION"; echo
if session_exists; then
    colab status -s "$COLAB_SESSION" | sed 's/^/    /'

    msg st_vm; echo
    rssh "nvidia-smi --query-gpu=name,memory.used,memory.total --format=csv,noheader; free -g | sed -n 2p; df -h /content | tail -n 1" \
        2>/dev/null | sed 's/^/    /' || echo "    $(msg st_ssh_fail)"
    if remote_healthy; then
        echo "    $(msg st_strata_up)"
    else
        echo "    $(msg st_strata_down)"
    fi
else
    echo "    $(msg st_none)"
fi

msg st_tunnel "$LOCAL_PORT"; echo
if local_healthy; then echo "    $(msg st_connected)"; else echo "    $(msg st_disconnected)"; fi

msg st_units; echo
colab usage | sed 's/^/    /'
