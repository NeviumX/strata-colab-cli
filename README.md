# strata-colab-cli

[日本語](README_JP.md)

Scripts for running [Strata](https://github.com/Niko1221/Strata) on a Google Colab GPU
and using it from Windows as a WebUI and an OpenAI-compatible API.
They use the [Colab CLI](https://github.com/googlecolab/google-colab-cli) on WSL and SSH port forwarding.

## Requirements

- Windows 10/11 with Ubuntu on WSL2
- A Colab plan that gives access to GPUs such as the A100. Running it consumes compute units

## Setup

In WSL, move to this folder and run the following. The first `colab usage` signs you in to your Google account.

```bash
bash ./setup-wsl.sh
colab usage
```

Change the GPU, model, ports and other settings in `config.env`, and the SSH connection in `ssh_config`.

To use a GGUF that the official setup does not download, set `MODEL_REPO` in `config.env` to its Hugging Face repository and `MODEL` to the file's size name. The scripts check that Strata can run the file before downloading it. For a private repository, put `HF_TOKEN` in `config.local.env`.

## Usage

| Action | Windows | WSL |
|---|---|---|
| Start and open the WebUI | `start.bat` | `./up.sh` |
| Stop | `stop.bat` | `./down.sh` |
| Show status | `status.bat` | `./status.sh` |
| Show logs | | `./logs.sh` |
| Open a shell on the VM | | `./ssh.sh` |

Endpoints after startup:

- WebUI: `http://localhost:8080`
- OpenAI-compatible API: `http://localhost:8080/v1`

## Notes

- Closing the `start.bat` window does not stop the runtime, and it keeps being billed. Run `stop.bat` when you are done.
- Stopping also deletes the downloaded model, so the next start downloads it again.
- A Colab runtime accepts only one SSH connection at a time. To open a shell on the VM, use `./ssh.sh` instead of `colab ssh`.
- Messages are shown in Japanese on a Japanese system and in English otherwise. Set `STRATA_LANG` to `ja` or `en` in `config.env` to choose one. On WSL without a language set, the Windows display language is used.
