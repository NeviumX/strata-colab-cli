#!/usr/bin/env bash
# 各スクリプト共通の設定読み込みと関数。source して使う。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$ROOT/.state"
TUNNEL_PID_FILE="$STATE_DIR/tunnel.pid"
mkdir -p "$STATE_DIR"

# shellcheck source=../config.env
source "$ROOT/config.env"
if [[ -f "$ROOT/config.local.env" ]]; then
    # shellcheck disable=SC1091
    source "$ROOT/config.local.env"
fi
# shellcheck source=messages.sh
source "$ROOT/lib/messages.sh"

# ssh_config が $COLAB_SESSION を参照する
export COLAB_SESSION
command -v colab >/dev/null 2>&1 || export PATH="$HOME/.local/bin:$PATH"

SSH_HOST="${SSH_HOST:-colab-strata}"
SSH_OPTS=(-F "$ROOT/ssh_config")
# 共有 SSH 接続のソケットの置き場所
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"

log()  { printf '\033[36m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '\033[33m[%s] %s\033[0m\n' "$(date +%H:%M:%S)" "$*" >&2; }
die()  { printf '\033[31m[%s] %s\033[0m\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

require_cmds() {
    local c
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || die "$(msg cmd_missing "$c")"
    done
}

# ランタイムがあるかを colab status の出力で判定する
session_exists() {
    local out
    out="$(colab status -s "$COLAB_SESSION" 2>&1)" || return 1
    ! grep -qi "not found" <<<"$out"
}

# ssh_config の ControlMaster で作った共有 SSH 接続への操作。新しい接続は作らない
ctl() { ssh "${SSH_OPTS[@]}" -O "$1" "${@:2}" "$SSH_HOST"; }

# 共有 SSH 接続を用意する。Colab のランタイムには同時に 1 本しか SSH をつなげないため、
# すべての ssh はこの 1 本に相乗りする。
ensure_master() {
    ctl check >/dev/null 2>&1 && return 0
    (
        flock 9
        ctl check >/dev/null 2>&1 && exit 0
        setsid -w ssh "${SSH_OPTS[@]}" -o ControlMaster=yes -N -f "$SSH_HOST"
    ) 9>"$HOME/.ssh/colab-cm-$COLAB_SESSION.lock"
}

# Colab VM 上でコマンドを実行する。
# colab ssh はランタイムが無いと新しく作るので、先に存在を確かめる。
rssh() {
    if ! session_exists; then
        warn "$(msg no_runtime_skip_ssh "$COLAB_SESSION")"
        return 255
    fi
    ensure_master || return 255
    ssh "${SSH_OPTS[@]}" "$SSH_HOST" "$@"
}

# 指定した変数を「NAME=値 ...」の形にして、リモートのコマンドの前に付けられるようにする
remote_env() {
    local v out=""
    for v in "$@"; do out+="$v=$(printf '%q' "${!v}") "; done
    printf '%s' "$out"
}

remote_healthy() {
    rssh "curl -sf -m 5 http://127.0.0.1:$REMOTE_PORT/health >/dev/null" 2>/dev/null
}

# remote-setup.sh と同じ値にしておくこと
EXIT_MARK='[strata-colab-cli] setup.sh exited'
PORT_ERR_RE='already in use|address in use|eaddrinuse'

# Colab VM で Strata を起動する。起動済み・起動中なら何もしない。引数 1 なら止めてからやり直す。
remote_start() {
    local FORCE_RESTART="${1:-0}"
    # 表示する文章も一緒に送り、言語は手元で決めたものを使わせる
    cat "$ROOT/lib/messages.sh" "$ROOT/lib/remote-setup.sh" |
        rssh "$(remote_env STRATA_REPO REMOTE_DIR DATA_DIR MODEL CONTEXT REMOTE_PORT API_KEY STRATA_EXTRA_ARGS REMOTE_LOG FORCE_RESTART MSG_LANG) bash -s"
}

# Colab 側の状態を 1 回の SSH で調べる: HEALTHY / PORT_IN_USE / EXITED / ログの最終行
remote_poll() {
    local q_log
    q_log="$(printf '%q' "$REMOTE_LOG")"
    rssh "if curl -sf -m 5 http://127.0.0.1:$REMOTE_PORT/health >/dev/null 2>&1; then echo HEALTHY;
          elif tail -n 40 $q_log 2>/dev/null | grep -qiE '$PORT_ERR_RE'; then echo PORT_IN_USE;
          elif tail -n 5 $q_log 2>/dev/null | grep -qF '$EXIT_MARK'; then echo EXITED;
          elif ! tmux has-session -t strata 2>/dev/null; then echo NOT_RUNNING;
          else tail -c 400 $q_log 2>/dev/null | tr '\r' '\n' | grep -v '^[[:space:]]*\$' | tail -n 1; fi" \
        2>/dev/null || msg ssh_no_response
}

# 起動完了を待つ。ポート使用中などで setup.sh が落ちたら SETUP_RETRIES 回までやり直す。
wait_healthy() {
    local deadline=$((SECONDS + HEALTH_TIMEOUT_MIN * 60)) status why retries=0
    while true; do
        status="$(remote_poll)"
        case "$status" in
            HEALTHY) return 0 ;;
            PORT_IN_USE|EXITED|NOT_RUNNING)
                case "$status" in
                    PORT_IN_USE) why="$(msg why_port_in_use "$REMOTE_PORT")" ;;
                    EXITED)      why="$(msg why_setup_exited)" ;;
                    *)           why="$(msg why_not_running)" ;;
                esac
                (( retries < SETUP_RETRIES )) ||
                    die "$(msg retry_exhausted "$why" "$SETUP_RETRIES")"
                retries=$((retries + 1))
                warn "$(msg retry_setup "$why" "$retries" "$SETUP_RETRIES")"
                remote_start 1
                deadline=$((SECONDS + HEALTH_TIMEOUT_MIN * 60))
                ;;
            *) if [[ -n "${status//[[:space:]]/}" ]]; then printf '    %s\n' "${status:0:160}"; fi ;;
        esac
        (( SECONDS < deadline )) || die "$(msg start_timeout "$HEALTH_TIMEOUT_MIN")"
        sleep "$POLL_SEC"
    done
}

local_healthy() { curl -sf -m 5 "http://127.0.0.1:$LOCAL_PORT/health" >/dev/null 2>&1; }

local_port_in_use() { ss -ltnH "sport = :$LOCAL_PORT" 2>/dev/null | grep -q .; }

# SSH が通るまで待つ。VM の起動直後は少し時間がかかる
wait_ssh() {
    local i err
    for i in 1 2 3 4 5 6; do
        err="$(rssh true 2>&1 >/dev/null)" && return 0
        if grep -q "429" <<<"$err"; then
            warn "$(msg ssh_busy_429 "$i")"
        else
            warn "$(msg ssh_waiting "$i")"
        fi
        sleep 10
    done
    die "$(msg ssh_failed)"
}

# ---- 共有 SSH 接続のトンネル ----
stop_master() { ctl exit >/dev/null 2>&1 || true; }

FWD_SPEC="127.0.0.1:$LOCAL_PORT:127.0.0.1:$REMOTE_PORT"
KEEPALIVE_PID=""

# 共有 SSH 接続にポート転送を足す。
# ウィンドウを開いている間は、接続を保つための何もしないセッションを 1 本つないでおく。
open_link() {
    rssh true || return 1
    if [[ -z "$KEEPALIVE_PID" ]] || ! kill -0 "$KEEPALIVE_PID" 2>/dev/null; then
        # shellcheck disable=SC2016
        ssh "${SSH_OPTS[@]}" "$SSH_HOST" 'while kill -0 $PPID 2>/dev/null; do sleep 30; done' \
            </dev/null >/dev/null 2>&1 &
        KEEPALIVE_PID=$!
    fi
    ctl forward -L "$FWD_SPEC" >/dev/null 2>&1
}

close_link() {
    if [[ -n "$KEEPALIVE_PID" ]]; then
        kill "$KEEPALIVE_PID" 2>/dev/null || true
        KEEPALIVE_PID=""
    fi
    ctl cancel -L "$FWD_SPEC" >/dev/null 2>&1 || true
}

open_browser() {
    local url="http://localhost:$LOCAL_PORT"
    if command -v cmd.exe >/dev/null 2>&1; then
        (cd /mnt/c 2>/dev/null || true; cmd.exe /c start "" "$url" >/dev/null 2>&1) || true
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$url" >/dev/null 2>&1 || true
    fi
}

print_endpoints() {
    local base="http://localhost:$LOCAL_PORT"
    echo
    echo "  $(msg ep_webui "$base")"
    echo "  $(msg ep_openai "$base/v1")"
    echo "  $(msg ep_anthropic "$base/v1/messages")"
    echo "  $(msg ep_apikey "${API_KEY:-$(msg ep_apikey_unset)}")"
    echo
}

# 別のウィンドウでトンネルを保っている up.sh / tunnel.sh を止める。トンネルはその終了処理が閉じる
stop_tunnel() {
    local pid
    pid="$(cat "$TUNNEL_PID_FILE" 2>/dev/null)" || return 0
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        local i
        for i in 1 2 3 4 5; do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
    fi
    rm -f "$TUNNEL_PID_FILE"
}

# トンネルをこのプロセスで保持する。ウィンドウを閉じるか Ctrl+C でトンネルだけ切れる。
run_tunnel_foreground() {
    local other
    other="$(cat "$TUNNEL_PID_FILE" 2>/dev/null || true)"
    if [[ -n "$other" && "$other" != "$$" ]] && kill -0 "$other" 2>/dev/null && local_healthy; then
        log "$(msg tunnel_already)"
        [[ "$OPEN_BROWSER" == 1 ]] && open_browser
        print_endpoints
        return 0
    fi
    # 前回のウィンドウが残した転送があれば外してから、ポートが空いているか確かめる
    close_link
    if local_port_in_use; then
        die "$(msg local_port_busy "$LOCAL_PORT")"
    fi

    echo "$$" > "$TUNNEL_PID_FILE"
    trap 'close_link; rm -f "$TUNNEL_PID_FILE"; echo; warn "$(msg tunnel_closed)"' EXIT
    trap 'exit 130' INT TERM

    open_link || die "$(msg tunnel_failed)"
    local i
    for i in $(seq 1 30); do
        local_healthy && break
        sleep 2
    done
    local_healthy || die "$(msg tunnel_unreachable)"

    log "$(msg ready)"
    [[ "$OPEN_BROWSER" == 1 ]] && open_browser
    print_endpoints
    log "$(msg tunnel_hold)"
    watch_strata
}

# トンネルを保っている間、Strata が応答するか見張る。
# Colab 側で落ちていたらセットアップをやり直し、トンネルだけが切れていたら張り直す。
watch_strata() {
    local fails=0
    while true; do
        sleep "$WATCH_SEC"
        if local_healthy; then
            fails=0
            continue
        fi
        fails=$((fails + 1))
        (( fails >= 2 )) || continue    # 一度だけの失敗は様子を見る
        fails=0

        session_exists || { warn "$(msg runtime_stopped "$COLAB_SESSION")"; break; }
        if remote_healthy; then
            warn "$(msg tunnel_stuck)"
            open_link || warn "$(msg relink_retry_later)"
            continue
        fi
        warn "$(msg strata_down_recovering)"
        remote_start 0
        wait_healthy
        open_link || warn "$(msg relink_retry_later)"
        log "$(msg recovered)"
    done
}
