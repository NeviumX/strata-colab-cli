#!/usr/bin/env bash
# Colab にランタイムを作り、Strata を起動して、手元に WebUI / API をつなぐ。
# 途中で失敗しても、もう一度実行すれば済んだ手順は飛ばして続きから進む。
source "$(dirname "$0")/lib/common.sh"

check_gpu() {
    local gpu
    gpu="$(rssh "nvidia-smi --query-gpu=name,memory.total --format=csv,noheader" 2>/dev/null | head -n 1 || true)"
    log "$(msg gpu_line "${gpu:-$(msg gpu_unknown)}")"
    [[ "$gpu" =~ $EXPECT_GPU_REGEX ]] && return 0

    warn "$(msg gpu_mismatch "$EXPECT_GPU_REGEX")"
    local ans
    case "$ON_GPU_MISMATCH" in
        continue) return 0 ;;
        stop) ans=n ;;
        *) read -r -p "$(msg gpu_continue_prompt)" ans || ans=n ;;
    esac
    [[ "$ans" =~ ^[yY] ]] && return 0

    log "$(msg stopping_to_save)"
    stop_master
    colab stop -s "$COLAB_SESSION" || true
    die "$(msg gpu_aborted)"
}

main() {
    require_cmds colab ssh curl ss

    log "$(msg units_left)"
    colab usage 2>/dev/null | sed 's/^/    /' || true

    # 1. ランタイム
    if session_exists; then
        log "$(msg runtime_exists "$COLAB_SESSION")"
    else
        local new_args=(-s "$COLAB_SESSION" --gpu "$GPU")
        [[ "$HIGH_MEM" == 1 ]] && new_args+=(--high-mem)
        # 前のランタイムへの共有 SSH 接続が残っていたら閉じる
        stop_master
        log "$(msg runtime_creating "colab new ${new_args[*]}")"
        colab new "${new_args[@]}"
    fi

    # 2. SSH と GPU
    log "$(msg ssh_connecting)"
    wait_ssh
    check_gpu

    # 3. Strata のセットアップと起動。VM 上の tmux で動かす
    log "$(msg preparing)"
    remote_start 0

    # 4. 起動完了を待つ。落ちたら Colab 側のセットアップを自動でやり直す
    log "$(msg waiting_start)"
    wait_healthy
    log "$(msg started)"

    # 5. トンネル → ブラウザ
    run_tunnel_foreground
}

main "$@"
