#!/usr/bin/env bash
# Colab VM 上の setup.sh / Strata のログを表示し続ける。Ctrl+C で終了する。
source "$(dirname "$0")/lib/common.sh"

rssh "tail -n 50 -F $(printf '%q' "$REMOTE_LOG")"
