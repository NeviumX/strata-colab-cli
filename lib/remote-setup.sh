#!/usr/bin/env bash
# Colab VM 上で実行される。手元の lib/common.sh が lib/messages.sh と一緒に ssh 経由で標準入力から流し込む。
# 受け取る変数: STRATA_REPO REMOTE_DIR DATA_DIR MODEL CONTEXT REMOTE_PORT API_KEY STRATA_EXTRA_ARGS REMOTE_LOG
#               FORCE_RESTART: 1 なら進行中でも止めてやり直す
#               MSG_LANG: 表示する言語。ja か en
set -euo pipefail

TMUX_SESSION=strata
EXIT_MARK='[strata-colab-cli] setup.sh exited'
PORT_ERR_RE='already in use|address in use|eaddrinuse'
FORCE_RESTART="${FORCE_RESTART:-0}"

rmsg() { echo "[remote] $(msg "$@")"; }

if curl -sf -m 5 "http://127.0.0.1:$REMOTE_PORT/health" >/dev/null 2>&1; then
    rmsg r_already_running
    exit 0
fi

if command -v tmux >/dev/null 2>&1 && tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    if [[ "$FORCE_RESTART" == 1 ]]; then
        rmsg r_redo
    elif tail -n 5 "$REMOTE_LOG" 2>/dev/null | grep -qF "$EXIT_MARK"; then
        rmsg r_prev_exited
    elif tail -n 40 "$REMOTE_LOG" 2>/dev/null | grep -qiE "$PORT_ERR_RE"; then
        rmsg r_port_fail_restart "$REMOTE_PORT"
    else
        rmsg r_in_progress
        exit 0
    fi
fi

need_pkg() {
    command -v "$1" >/dev/null 2>&1 && return 0
    rmsg r_installing "$2"
    apt-get -qq update >/dev/null
    apt-get -qq install -y "$2" >/dev/null
}
need_pkg tmux tmux
need_pkg ss iproute2

# ---- 前回の Strata を片付けて、ポートを空ける ----
# 止めるのは、作業フォルダか実行ファイルが Strata のフォルダの中にあるプロセスだけ。
under_strata() {
    [[ -n "$1" ]] || return 1
    [[ "$1" == "$REMOTE_DIR" || "$1" == "$REMOTE_DIR"/* || "$1" == "$DATA_DIR" || "$1" == "$DATA_DIR"/* ]]
}
is_strata_pid() {
    local cwd exe
    cwd="$(readlink "/proc/$1/cwd" 2>/dev/null)" || return 1
    exe="$(readlink "/proc/$1/exe" 2>/dev/null)" || true
    under_strata "$cwd" || under_strata "$exe"
}
strata_pids() {
    local d p
    for d in /proc/[0-9]*; do
        p="${d#/proc/}"
        [[ "$p" == "$$" || "$p" == "$PPID" ]] && continue
        is_strata_pid "$p" && echo "$p"
    done
    return 0
}
port_pids() {
    ss -ltnpH "sport = :$REMOTE_PORT" 2>/dev/null | grep -o 'pid=[0-9]*' | cut -d= -f2 | sort -u
}
kill_and_wait() {
    local p alive i
    kill "$@" 2>/dev/null || true
    for i in $(seq 1 10); do
        alive=""
        for p in "$@"; do kill -0 "$p" 2>/dev/null && alive+="$p "; done
        [[ -z "$alive" ]] && return 0
        sleep 1
    done
    # shellcheck disable=SC2086
    kill -9 $alive 2>/dev/null || true
    sleep 1
}

tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
mapfile -t old < <(strata_pids)
if (( ${#old[@]} > 0 )); then
    rmsg r_stop_old "${old[*]}"
    kill_and_wait "${old[@]}"
fi

mapfile -t holders < <(port_pids)
if (( ${#holders[@]} > 0 )); then
    others=""
    for p in "${holders[@]}"; do
        if is_strata_pid "$p"; then
            kill_and_wait "$p"
        else
            others+="  pid $p: $(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | cut -c1-120)"$'\n'
        fi
    done
    if [[ -n "$others" ]]; then
        rmsg r_port_other "$REMOTE_PORT"
        printf '%s' "$others"
        rmsg r_port_other_hint
        exit 3
    fi
fi

# ---- Strata の取得 ----
if [[ ! -d "$REMOTE_DIR/.git" ]]; then
    rmsg r_cloning "$STRATA_REPO"
    git clone --depth 1 "$STRATA_REPO" "$REMOTE_DIR"
fi

# ---- Python ----
# Strata の setup.sh は PATH 上の python3 で venv を作る。venv が作れる Python を探して PATH の先頭に置く。
ok_py() { "$1" -c 'import sys, venv, ensurepip; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; }
find_py() {
    local c
    for c in $(type -ap python3 python3.12 python3.11 python3.10) \
             /usr/bin/python3 /usr/bin/python3.12 /usr/bin/python3.11 /usr/bin/python3.10; do
        if [[ -x "$c" ]] && ok_py "$c"; then
            echo "$c"
            return 0
        fi
    done
    return 1
}
if ! PY="$(find_py)"; then
    rmsg r_py_install
    apt-get -qq update >/dev/null
    apt-get -qq install -y python3 python3-venv python3-pip >/dev/null
    PY="$(find_py)" || { rmsg r_py_missing; exit 1; }
fi
PY_SHIM_DIR="$(dirname "$REMOTE_DIR")/.strata-python"
mkdir -p "$PY_SHIM_DIR"
ln -sf "$PY" "$PY_SHIM_DIR/python3"
ln -sf "$PY" "$PY_SHIM_DIR/python"
rmsg r_py "$PY" "$("$PY" --version 2>&1)"

# ---- 保存済み設定のポート ----
# Strata は保存済みの設定 strata-<model>.json のポートで起動するので、REMOTE_PORT に合わせる。
for f in "$REMOTE_DIR"/strata-*.json; do
    [[ -f "$f" ]] || continue
    old_ports="$("$PY" - "$f" "$REMOTE_PORT" <<'PYEOF'
import json, sys
path, port = sys.argv[1], int(sys.argv[2])
with open(path, encoding="utf-8") as fh:
    cfg = json.load(fh)
if not isinstance(cfg, dict):
    sys.exit(0)
changed = []
if "port" in cfg and str(cfg["port"]) != str(port):
    changed.append(str(cfg["port"]))
    cfg["port"] = port
args = cfg.get("args")
if isinstance(args, list):
    for i, a in enumerate(args[:-1]):
        if a == "--port" and str(args[i + 1]) != str(port):
            changed.append(str(args[i + 1]))
            args[i + 1] = str(port)
if changed:
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(cfg, fh, indent=2, ensure_ascii=False)
    print(", ".join(sorted(set(changed))))
PYEOF
)"
    [[ -z "$old_ports" ]] || rmsg r_port_fixed "$f" "$old_ports" "$REMOTE_PORT"
done

# ---- 起動 ----
args=(--model "$MODEL" --context "$CONTEXT" --port "$REMOTE_PORT"
      --data-dir "$DATA_DIR" --no-browser --yes)
[[ -n "$API_KEY" ]] && args+=(--api-key "$API_KEY")
# STRATA_EXTRA_ARGS は空白で区切って渡す
# shellcheck disable=SC2206
[[ -n "$STRATA_EXTRA_ARGS" ]] && args+=($STRATA_EXTRA_ARGS)

# 前回のログは .prev に残す
[[ -f "$REMOTE_LOG" ]] && mv -f "$REMOTE_LOG" "$REMOTE_LOG.prev"

cmd="export PATH=$(printf '%q' "$PY_SHIM_DIR"):\$PATH; cd $(printf '%q' "$REMOTE_DIR") && ./setup.sh $(printf '%q ' "${args[@]}") 2>&1 | tee -a $(printf '%q' "$REMOTE_LOG")"
cmd+="; echo $(printf '%q' "$EXIT_MARK") | tee -a $(printf '%q' "$REMOTE_LOG"); sleep infinity"

# tmux の中で動かすので、SSH が切れてもサーバーは止まらない
tmux new-session -d -s "$TMUX_SESSION" bash -c "$cmd"
rmsg r_started "$MODEL" "$CONTEXT" "$REMOTE_PORT"
