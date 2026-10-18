#!/usr/bin/env bash
# スクリプトが表示する文章を日本語と英語でまとめたファイル。
# `msg キー 引数...` で、選ばれた言語の文章を返す。文章は printf の書式で、%s に引数が入る。改行は付かない。
# 文章に % を書くときは %% にする。
#
# 言語は次の順で決める。
#   1. STRATA_LANG が ja か en ならそれに従う
#   2. LC_ALL / LC_MESSAGES / LANG が ja で始まれば日本語、ほかの言語が指定されていれば英語
#   3. C や POSIX のように言語の指定がなく、WSL 上で動いているときは Windows の表示言語に合わせる
#   4. どれにも当てはまらなければ英語
# MSG_LANG がすでに決まっているときは判定しない。Colab VM 側にはこの値を渡している。

_detect_msg_lang() {
    local v ui
    case "${STRATA_LANG:-}" in
        ja|en) echo "$STRATA_LANG"; return ;;
    esac
    for v in "${LC_ALL:-}" "${LC_MESSAGES:-}" "${LANG:-}"; do
        [[ -n "$v" ]] || continue
        case "$v" in
            ja*) echo ja; return ;;
            C|C.*|POSIX|POSIX.*) break ;;
            *) echo en; return ;;
        esac
    done
    if [[ -n "${WSL_DISTRO_NAME:-}" ]] && command -v powershell.exe >/dev/null 2>&1; then
        ui="$(cd /mnt/c 2>/dev/null; powershell.exe -NoProfile -NonInteractive -Command \
            '[Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName' 2>/dev/null | tr -d '\r\n ')"
        if [[ "$ui" == ja ]]; then echo ja; return; fi
    fi
    echo en
}
MSG_LANG="${MSG_LANG:-$(_detect_msg_lang)}"

declare -A _MSG_JA=() _MSG_EN=()
# 文章を登録する: _m キー 日本語 英語
_m() { _MSG_JA[$1]="$2"; _MSG_EN[$1]="$3"; }

msg() {
    local key="$1" fmt
    shift
    if [[ "$MSG_LANG" == ja ]]; then fmt="${_MSG_JA[$key]-}"; else fmt="${_MSG_EN[$key]-}"; fi
    [[ -n "$fmt" ]] || fmt="[$key]"
    # shellcheck disable=SC2059
    printf "$fmt" "$@"
}

# ===== 共通 =====
_m cmd_missing \
    "%s が見つかりません。先に ./setup-wsl.sh を実行してください。" \
    "%s not found. Run ./setup-wsl.sh first."
_m no_runtime_skip_ssh \
    "ランタイム %s がないので、SSH は行いません。" \
    "Runtime %s does not exist, so SSH is skipped."
_m runtime_missing_start \
    "ランタイム %s がありません。start.bat か ./up.sh で起動してください。" \
    "Runtime %s does not exist. Start it with start.bat or ./up.sh."
_m ssh_no_response \
    "SSH の応答がありません。" \
    "No response over SSH."
_m ssh_busy_429 \
    "別の colab ssh がこのランタイムに接続中です。手動の colab ssh を閉じてください。%s/6 回目" \
    "Another colab ssh is connected to this runtime. Close your manual colab ssh. Attempt %s/6"
_m ssh_waiting \
    "SSH 接続を待っています。%s/6 回目" \
    "Waiting for SSH. Attempt %s/6"
_m ssh_failed \
    "SSH で接続できません。ssh_config を見直し、./ssh.sh -v true で詳細を確認してください。" \
    "Cannot connect over SSH. Check ssh_config and run ./ssh.sh -v true for details."
_m ssh_failed_429 \
    "SSH で接続できません。別の colab ssh が接続中なら閉じてください。HTTP 429 はそれが原因です。" \
    "Cannot connect over SSH. If another colab ssh is connected, close it. HTTP 429 means exactly that."

# ===== 起動待ちと復旧 =====
_m why_port_in_use \
    "ポート %s が使用中で Strata が起動できませんでした" \
    "Strata could not start because port %s is in use"
_m why_setup_exited \
    "setup.sh が途中で終了しました" \
    "setup.sh exited before Strata was ready"
_m why_not_running \
    "Colab 側で Strata が動いていません" \
    "Strata is not running on Colab"
_m retry_setup \
    "%s。Colab 側のセットアップをやり直します。%s/%s 回目です。" \
    "%s. Redoing the setup on Colab. Attempt %s/%s."
_m retry_exhausted \
    "%s。%s 回やり直しても起動しませんでした。./logs.sh でログを確認してください。" \
    "%s. It did not start after %s retries. Check the log with ./logs.sh."
_m start_timeout \
    "%s 分待っても起動しませんでした。./logs.sh でログを確認してください。" \
    "Strata did not start within %s minutes. Check the log with ./logs.sh."
_m strata_unresponsive_redo \
    "Colab 上で Strata が応答しません。セットアップをやり直します。" \
    "Strata on Colab is not responding. Redoing the setup."

# ===== トンネルと監視 =====
_m tunnel_already \
    "トンネルは別のウィンドウですでに有効です。" \
    "The tunnel is already up in another window."
_m local_port_busy \
    "手元のポート %s は別のプログラムが使っています。config.env の LOCAL_PORT を変えてください。" \
    "Local port %s is used by another program. Change LOCAL_PORT in config.env."
_m tunnel_closed \
    "トンネルを閉じました。ランタイムを止めていなければ課金が続くので、stop.bat か ./down.sh で停止してください。" \
    "Tunnel closed. Unless you stopped the runtime, it is still being billed. Stop it with stop.bat or ./down.sh."
_m tunnel_failed \
    "トンネルを張れませんでした。" \
    "Could not open the tunnel."
_m tunnel_unreachable \
    "トンネル経由で Strata に接続できません。" \
    "Cannot reach Strata through the tunnel."
_m ready \
    "準備ができました。" \
    "Ready."
_m tunnel_hold \
    "このウィンドウを開いている間トンネルが保たれます。Ctrl+C で切断します。" \
    "The tunnel stays up while this window is open. Press Ctrl+C to disconnect."
_m runtime_stopped \
    "ランタイム %s が停止しました。" \
    "Runtime %s has stopped."
_m tunnel_stuck \
    "Colab 側の Strata は動いていますが、トンネルが応答しません。張り直します。" \
    "Strata is running on Colab, but the tunnel is not responding. Reopening it."
_m relink_retry_later \
    "トンネルを張り直せませんでした。次の確認でもう一度試します。" \
    "Could not reopen the tunnel. Will try again at the next check."
_m strata_down_recovering \
    "Colab 側の Strata が応答しません。復旧します。" \
    "Strata on Colab is not responding. Recovering."
_m recovered \
    "Strata が復旧しました。" \
    "Strata has recovered."

# ===== 接続先の表示 =====
_m ep_webui      "WebUI          : %s" "WebUI          : %s"
_m ep_openai     "OpenAI 互換 API : %s" "OpenAI API     : %s"
_m ep_anthropic  "Anthropic 形式  : %s" "Anthropic API  : %s"
_m ep_apikey     "API キー        : %s" "API key        : %s"
_m ep_apikey_unset \
    "未設定。任意の文字列で可" \
    "not set. Any string works"

# ===== up.sh =====
_m units_left \
    "コンピューティングユニットの残り:" \
    "Compute units left:"
_m runtime_exists \
    "ランタイム %s は作成済みです。" \
    "Runtime %s already exists."
_m runtime_creating \
    "ランタイムを作成します: %s" \
    "Creating the runtime: %s"
_m ssh_connecting \
    "SSH で接続します。" \
    "Connecting over SSH."
_m gpu_line \
    "GPU: %s" \
    "GPU: %s"
_m gpu_unknown \
    "取得できませんでした" \
    "unknown"
_m gpu_mismatch \
    "期待した GPU %s ではありません。" \
    "This is not the expected GPU, %s."
_m gpu_continue_prompt \
    "このまま続けますか？ [y/N] " \
    "Continue anyway? [y/N] "
_m stopping_to_save \
    "コンピューティングユニットを節約するため、ランタイムを停止します。" \
    "Stopping the runtime to save compute units."
_m gpu_aborted \
    "中止しました。時間をおいて再実行するか、config.env の GPU を変えてください。" \
    "Aborted. Try again later or change GPU in config.env."
_m preparing \
    "Strata を準備します。" \
    "Preparing Strata."
_m waiting_start \
    "起動完了を待ちます。初回はモデルのダウンロードで 20〜30 分かかります。" \
    "Waiting for Strata to start. The first run downloads the model and takes 20 to 30 minutes."
_m started \
    "Strata が起動しました。" \
    "Strata has started."

# ===== down.sh =====
_m closing_tunnel \
    "トンネルを閉じます。" \
    "Closing the tunnel."
_m stopping_runtime \
    "ランタイム %s を停止します。" \
    "Stopping runtime %s."
_m runtime_already_gone \
    "ランタイム %s は見つかりません。停止済みです。" \
    "Runtime %s was not found. It is already stopped."
_m usage_after_stop \
    "利用状況です。Active assignments: 0 なら停止済みです。" \
    "Usage. Active assignments: 0 means everything is stopped."

# ===== status.sh =====
_m st_runtime      "== ランタイム: %s ==" "== Runtime: %s =="
_m st_vm           "== Colab VM ==" "== Colab VM =="
_m st_ssh_fail     "SSH で接続できません" "Cannot connect over SSH"
_m st_strata_up    "Strata: 起動中" "Strata: running"
_m st_strata_down \
    "Strata: 停止中または起動途中。./logs.sh で確認できます" \
    "Strata: stopped or still starting. Check with ./logs.sh"
_m st_none         "ありません" "None"
_m st_tunnel       "== 手元のトンネル: localhost:%s ==" "== Local tunnel: localhost:%s =="
_m st_connected    "つながっています" "Connected"
_m st_disconnected "つながっていません" "Not connected"
_m st_units        "== コンピューティングユニット ==" "== Compute units =="

# ===== setup-wsl.sh =====
_m sw_apt          "== apt パッケージ: ssh, curl, iproute2 ==" "== apt packages: ssh, curl, iproute2 =="
_m sw_uv           "== uv ==" "== uv =="
_m sw_colab        "== Colab CLI ==" "== Colab CLI =="
_m sw_key          "== SSH 鍵: colab ssh がこの公開鍵を VM に送る ==" "== SSH key: colab ssh sends this public key to the VM =="
_m sw_key_exists   "既存の ~/.ssh/id_ed25519 を使います。" "Using the existing ~/.ssh/id_ed25519."
_m sw_done \
    "\n完了しました。次の手順:\n  1. colab usage を実行して Google アカウントの認証を済ませる。済んでいれば不要。\n     ブラウザが開かなければ、表示された URL を Windows のブラウザで開く。\n  2. 必要なら config.env を編集する。\n  3. start.bat をダブルクリックするか、./up.sh を実行する。\n" \
    "\nDone. Next steps:\n  1. Run colab usage to sign in to your Google account. Skip this if you already have.\n     If no browser opens, open the printed URL in a browser on Windows.\n  2. Edit config.env if needed.\n  3. Double-click start.bat or run ./up.sh.\n"

# ===== Colab VM 側: remote-setup.sh =====
_m r_already_running \
    "Strata は既に起動しています。" \
    "Strata is already running."
_m r_redo \
    "セットアップをやり直します。" \
    "Redoing the setup."
_m r_prev_exited \
    "前回の setup.sh は終了しています。起動し直します。" \
    "The previous setup.sh has exited. Starting again."
_m r_port_fail_restart \
    "ポート %s が使用中で起動に失敗しています。起動し直します。" \
    "Startup failed because port %s is in use. Starting again."
_m r_in_progress \
    "セットアップまたは起動が進行中です。完了を待ちます。" \
    "Setup or startup is in progress. Waiting for it to finish."
_m r_installing \
    "%s をインストールします。" \
    "Installing %s."
_m r_stop_old \
    "前回の Strata のプロセスを止めます: %s" \
    "Stopping processes left from the previous Strata: %s"
_m r_port_other \
    "ポート %s は Strata 以外のプロセスが使っています。そのプロセスは止めずに中止します:" \
    "Port %s is used by a process other than Strata. Aborting without stopping it:"
_m r_port_other_hint \
    "config.env の REMOTE_PORT を別の番号に変えてから、もう一度実行してください。" \
    "Change REMOTE_PORT in config.env to another number and run again."
_m r_cloning \
    "Strata を取得します: %s" \
    "Cloning Strata: %s"
_m r_py_install \
    "venv が使える Python が無いので、python3-venv をインストールします。" \
    "No Python with venv support was found. Installing python3-venv."
_m r_py_missing \
    "venv が使える Python 3.10 以上が見つかりません。" \
    "No Python 3.10 or newer with venv support was found."
_m r_py \
    "Strata 用の Python: %s %s" \
    "Python for Strata: %s %s"
_m r_port_fixed \
    "%s のポートを %s から %s に直します。" \
    "Changing the port in %s from %s to %s."
_m r_started \
    "setup.sh を起動しました。モデル %s / コンテキスト %s / ポート %s" \
    "Started setup.sh. Model %s / context %s / port %s"

# ===== Colab VM 側: 公式以外のモデル =====
_m r_hf_install \
    "Hugging Face のダウンロードツールを用意します。" \
    "Setting up the Hugging Face download tool."
_m r_custom_inspect \
    "%s の %s が Strata で動かせるかを確かめます。読むのはヘッダーだけで、まだダウンロードはしません。" \
    "Checking whether %s %s runs on Strata. Only the headers are read; nothing is downloaded yet."
_m r_custom_unsupported \
    "%s の %s は Strata で動かせないファイルです。config.env の MODEL_REPO / MODEL / MODEL_FILES を見直してください。" \
    "%s %s is not a file Strata can run. Check MODEL_REPO, MODEL and MODEL_FILES in config.env."
_m r_custom_inspect_unknown \
    "Strata での確認を終えられませんでした。終了コードは %s です。このまま続けます。" \
    "Strata could not finish the check, exit code %s. Continuing anyway."
_m r_custom_nofiles \
    "%s に、%s に合うファイルがありません。MODEL_FILES を見直してください。" \
    "%s has no files matching %s. Check MODEL_FILES."
_m r_custom_multidir \
    "%s に合うファイルが複数のフォルダに分かれています。MODEL_FILES で 1 つのフォルダに絞ってください。" \
    "Files matching %s are spread over several folders. Narrow MODEL_FILES to one folder."
_m r_custom_disk \
    "ディスクが足りません。ダウンロードに %s GB 必要ですが、空きは %s GB です。" \
    "Not enough disk space. The download needs %s GB, but only %s GB is free."
_m r_custom_lookup_failed \
    "%s の情報を取得できませんでした。リポジトリ名と MODEL_REVISION を確かめてください。非公開なら HF_TOKEN も必要です。" \
    "Could not read %s. Check the repository name and MODEL_REVISION. A private repository also needs HF_TOKEN."
_m r_custom_ready \
    "%s のファイルはすべてそろっています。" \
    "All files from %s are already here."
_m r_custom_plan \
    "%s から %s 個のファイルを %s にダウンロードします。残りは %s GB、ディスクの空きは %s GB です。" \
    "Downloading %s: %s files into %s. %s GB to go, %s GB of disk free."
