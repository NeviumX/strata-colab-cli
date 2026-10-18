# strata-colab-cli

Google Colab の GPU で [Strata](https://github.com/Niko1221/Strata) を動かし、
Windows から WebUI と OpenAI 互換 API として使うためのスクリプトです。
WSL 上の [Colab CLI](https://github.com/googlecolab/google-colab-cli) と SSH ポート転送を使います。

## 必要なもの

- Windows 10/11 と WSL2 の Ubuntu
- A100 などを使える Colab のプラン。コンピューティングユニットを消費します

## 準備

WSL でこのフォルダに移動して実行します。初回の `colab usage` で Google アカウントの認証を行います。

```bash
bash ./setup-wsl.sh
colab usage
```

GPU、モデル、ポートなどは `config.env` で、SSH の接続方法は `ssh_config` で変更できます。

公式のセットアップが落とすもの以外の GGUF を使うときは、`config.env` の `MODEL_REPO` に Hugging Face のリポジトリを書き、`MODEL` をそのファイルのサイズ名にします。Strata が動かせる形式かどうかは、ダウンロードの前に確かめます。非公開のリポジトリなら、`config.local.env` に `HF_TOKEN` を書いてください。

## 使い方

| 操作 | Windows | WSL |
|---|---|---|
| 起動して WebUI を開く | `start.bat` | `./up.sh` |
| 停止する | `stop.bat` | `./down.sh` |
| 状態を見る | `status.bat` | `./status.sh` |
| ログを見る | | `./logs.sh` |
| VM に入る | | `./ssh.sh` |

起動後の接続先:

- WebUI: `http://localhost:8080`
- OpenAI 互換 API: `http://localhost:8080/v1`

## 注意

- `start.bat` のウィンドウを閉じてもランタイムは動き続け、課金されます。使い終わったら `stop.bat` で停止してください。
- 停止するとダウンロードしたモデルも消え、次回はダウンロードからやり直しになります。
- Colab のランタイムには同時に 1 本しか SSH をつなげません。VM に手で入るときは `colab ssh` ではなく `./ssh.sh` を使ってください。
- 表示は、日本語の環境なら日本語、それ以外なら英語になります。`config.env` の `STRATA_LANG` を `ja` か `en` にすると固定できます。WSL で言語が設定されていないときは、Windows の表示言語に合わせます。
