# `fullstack.sh` + `lint.yml`

> *The “It Works On My Machine” Industrial-Strength Starter Pack*
> Minimal yak-shaving. Maximal vibes. 💅🐍🎛️

<p align="center">
  <img alt="Bash" src="https://img.shields.io/badge/Bash-4%2B-222?logo=gnu-bash&logoColor=white">
  <img alt="Linux" src="https://img.shields.io/badge/Linux-supported-111?logo=linux&logoColor=white">
  <img alt="macOS" src="https://img.shields.io/badge/macOS-supported-000?logo=apple&logoColor=white">
  <img alt="PipeWire/JACK" src="https://img.shields.io/badge/Audio-PipeWire%2FJACK-700080">
  <img alt="Conda/Miniforge" src="https://img.shields.io/badge/Conda-Miniforge-43B02A?logo=anaconda&logoColor=white">
  <img alt="CI Lint" src="https://img.shields.io/badge/CI-ShellCheck%20%2B%20shfmt-0a0">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue">
</p>

---

## Table of Contents

* [✨ What You Get](#-what-you-get)
* [🚀 TL;DR Quickstart](#-tldr-quickstart)
* [🧠 Supported Platforms](#-supported-platforms)
* [🧩 Script Anatomy (fun tour)](#-script-anatomy-fun-tour)
* [🔧 Config You’ll Actually Touch](#-config-youll-actually-touch)
* [🛠️ CI: `lint.yml` (ShellCheck + shfmt)](#️-ci-lintyml-shellcheck--shfmt)
* [🆘 Troubleshooting (real talk)](#-troubleshooting-real-talk)
* [🙌 Pro Tips](#-pro-tips)
* [🧪 Local Dev Niceties](#-local-dev-niceties)
* [📝 Changelog Seeds](#-changelog-seeds)
* [🧾 License](#-license)

---

## ✨ What You Get

* **One command** to stand up a **full-stack audio-science/ML/quantum** dev machine.
* **PipeWire/JACK** + sensible low-latency sys tuning.
* **Miniforge (Conda)** env with scientific, audio/DSP, and quantum libs.
* **PyTorch** auto-picks CPU vs CUDA if it detects NVIDIA.
* Optional **GitHub Copilot CLI** bootstrapped in `~/dev` (terminal side-kick unlocked).
* **CI lint** that roasts bad shell and formats the rest — automatically.

> **Meme mode:**
> **Boss:** “Can you document the setup?”
> **You:** `./fullstack.sh && git push`
> **Boss:** “You’re getting a bigger monitor.”

---

## 🚀 TL;DR Quickstart

```bash
# 1) Make it executable
chmod +x ./fullstack.sh

# 2) Run it (Linux recommends sudo; macOS prompts as needed)
sudo ./fullstack.sh
# or
./fullstack.sh
```

<details>
<summary><b>What happens next?</b></summary>

* Detects your package manager (`apt`, `dnf`, `pacman`, or `brew`)
* Installs tooling + audio stack
* Tunes system (TRIM, sysctl, CPU governor where possible)
* Installs **Miniforge** → sets up **mamba**
* Creates **qecstack** env (numpy/scipy/pandas/numba/jupyterlab, librosa/pyaudio/opencv, qutip/qiskit/cirq, etc.)
* Picks **PyTorch** CPU/CUDA based on hardware
* Adds threads vars to your `~/.bashrc`
* Optionally installs **Copilot CLI** (`copilot /login`)

</details>

> [!NOTE]
> No network? It won’t throw a tantrum — it just skips downloads and keeps going.

---

## 🧠 Supported Platforms

* **Debian/Ubuntu** (`apt`)
* **Fedora/RHEL** (`dnf`)
* **Arch/Manjaro** (`pacman`)
* **macOS** (`brew`) — JACK/FFmpeg/Sox covered; PipeWire is “some assembly required.”

> [!TIP]
> Running in a container or a minimal VM? Missing `sudo` won’t kill the run — the script autostubs a no-op `sudo()` so non-privileged steps still pass under `set -euo pipefail`.

---

## 🧩 Script Anatomy (fun tour)

```text
fullstack.sh
├─ Shebang:  #!/usr/bin/env bash   (portable, not hard-coded)
├─ Safety:   set -euo pipefail     (fail fast, no unbound vars, pipe safety)
├─ User:     figures out $SUDO_USER → falls back to $USER
├─ sudo():   polyfill if absent; keeps strict mode happy
├─ log():    tasteful green/bold logs you can read on a Monday
├─ detect_pkg_mgr(): apt | dnf | pacman | brew | unknown
├─ install_packages(): wrapper over native PM (refresh + batch install)
├─ Base toolchain: compilers, cmake, ninja, git, ripgrep, fd, bat, exa…
├─ Audio stack: PipeWire/JACK (+ qjackctl/alsa-utils/sox/ffmpeg)
├─ Tuning:   fstrim.timer, sysctl(99-audio.conf), CPU governor (if possible)
├─ Miniforge: OS/arch-aware installer; network reachability checks
├─ Conda env: mamba + qecstack (sci/audio/quantum + PyTorch CPU/CUDA)
├─ Threads:  OMP_NUM_THREADS / MKL_NUM_THREADS → ~/.bashrc
└─ Copilot:  npm/brew install; `copilot /login` in ~/dev
```

> [!IMPORTANT]
> We use **built-ins** whenever possible (e.g., lowercase transforms, core counts via `nproc`/`getconf`) to avoid pointless subprocesses and keep this zippy.

---

## 🔧 Config You’ll Actually Touch

* **Base packages** — trim or add in the toolchain section. Keep it lean.
* **Audio** — swap JACK flavors, add/remove Pulse bridges, ditch `qjackctl` if you CLI all day.
* **Sys tuning** — comment TRIM/sysctl if it’s a laptop you care about; pick `powersave` governor if needed.
* **Conda env** — pin versions/channels, add/remove libs, then re-lock:

  ```bash
  conda env export | sed '/^prefix:/d' > ~/qec_env_<os>.yaml
  ```
* **Copilot CLI** — lock a specific version via npm/brew or remove entirely.

> **Meme mode:**
> “One does not simply… manually reinstall fifty packages for a new laptop.” — You, before this repo

---

## 🛠️ CI: `lint.yml` (ShellCheck + shfmt)

> Clean shell is fast shell. And future-you will actually understand it.

**What it does**

* Runs on every **push**/**PR** that touches `*.sh`
* **ShellCheck**: finds foot-guns (unquoted vars, unsafe globs, bashisms)
* **shfmt**: keeps spacing + `case` indentation ✨ consistent
* Comments on PRs so reviewers can roast the code and not the author

**Workflow file** → `.github/workflows/lint.yml`:

```yaml
name: Shell Lint

on:
  push:
    paths: ['**/*.sh']
  pull_request:
    paths: ['**/*.sh']

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run ShellCheck + shfmt
        uses: luizm/action-sh-checker@master
        with:
          sh_checker_comment: true
          # sh_checker_exclude: 'vendor/** tests/fixtures/**'
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          # SHELLCHECK_OPTS: "-e SC1091"
          # SHFMT_OPTS: "-i 2 -ci"
```

<details>
<summary><b>Customize it without crying</b></summary>

* **Only lint a folder**

  ```yaml
  with:
    path: "scripts,deploy.sh"
  ```
* **Exclude generated stuff**

  ```yaml
  with:
    sh_checker_exclude: "vendor/** build/**"
  ```
* **Make ShellCheck chill about sourcing**

  ```yaml
  env:
    SHELLCHECK_OPTS: "-e SC1091"
  ```
* **Formatting knobs**

  ```yaml
  env:
    SHFMT_OPTS: "-i 2 -ci"
  ```

</details>

> **Meme mode:**
> “CI failed.” — Good news. That’s cheaper than prod failing.

---

## 🆘 Troubleshooting (real talk)

* **“No package manager detected”** → Unsupported distro/base image. Add a new case in `detect_pkg_mgr()` + wiring in `install_packages()`.
* **Permission denied** → Use `sudo` (Linux) or ensure you can write `/etc` for tuning bits.
* **Network failures** → We only download when reachability checks pass. Fix the network or re-run later.
* **CUDA not found** → `lspci` isn’t always available in containers. Force GPU build:

  ```bash
  has_nvidia=1 ./fullstack.sh
  ```

---

## 🙌 Pro Tips

* **Idempotent runs**: Safe to re-run; it’ll skip what’s already set up.
* **Lock your env**: Commit `qec_env_<os>.yaml` to keep the team in sync.
* **Feature flags**: Wrap optional sections in simple `ENABLE_*` env checks if you want more toggles.
* **Secrets**: CI uses `GITHUB_TOKEN` for comments — no extra secrets needed.

---

## 🧪 Local Dev Niceties

**Pre-commit hook** (keeps CI green by default):

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/koalaman/shellcheck
    rev: v0.10.0
    hooks:
      - id: shellcheck
        args: [--severity=style]
  - repo: https://github.com/mvdan/sh
    rev: v3.7.0
    hooks:
      - id: shfmt
        args: [-i, "2", -ci]
```

```bash
pipx install pre-commit || pip install pre-commit
pre-commit install
```

---

## 📝 Changelog Seeds

* feat(script): add OS/arch-aware Miniforge installer
* feat(audio): PipeWire/JACK installs per-distro
* feat(ml): auto-detect NVIDIA → choose PyTorch CUDA/CPU
* chore(ci): add ShellCheck + shfmt action with PR comments
* perf(shell): prefer built-ins over external commands
* docs: meme-powered README that your PM will actually read

---

## 🧾 License

MIT. Because life’s too short for weird licenses.

---

> **Final meme:**
> *You run `./fullstack.sh` once.*
> Your future self from three laptops ahead appears:
> “I’m here to say thanks.”
