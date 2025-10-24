#!/usr/bin/env bash
#
# Full-stack cross-platform audio-science setup script.
#
# This script detects the host operating system and package manager,
# installs a base development and audio stack, bootstraps a Conda
# environment, installs common scientific libraries, and optionally
# configures the GitHub Copilot CLI. It strives to remain portable
# across Debian/Ubuntu (APT), Fedora (DNF), Arch (Pacman), and macOS
# (Homebrew) while being conservative about external dependencies.

set -euo pipefail

# Determine the invoking user (useful when running with sudo).  Fall
# back to the current user if SUDO_USER is unset.
ME="${SUDO_USER:-$USER}"

# Provide a dummy sudo implementation in environments where sudo is
# unavailable or cannot elevate privileges.  It executes the given
# command as the current user and ignores any failure to avoid
# aborting the script under `set -e`.
if ! command -v sudo >/dev/null 2>&1; then
  sudo() {
    "$@" || true
  }
fi

# Pretty logger: emit bold green headings for better readability.
log() {
  printf '\e[1;32m==> %s\e[0m\n' "$1"
}

# Detect the system's package manager.  Supports apt, dnf, pacman and
# Homebrew.  Returns "unknown" if none are found.
detect_pkg_mgr() {
  if command -v apt-get >/dev/null 2>&1; then
    echo apt
  elif command -v dnf >/dev/null 2>&1; then
    echo dnf
  elif command -v pacman >/dev/null 2>&1; then
    echo pacman
  elif command -v brew >/dev/null 2>&1; then
    echo brew
  else
    echo "unknown"
  fi
}

# Install one or more packages with the detected package manager.  On
# unsupported systems this function returns 1.  Each backend ensures
# package databases are refreshed appropriately.  Homebrew support
# includes a best-effort `brew update` prior to installation.
install_packages() {
  local mgr=$1
  shift
  case "$mgr" in
    apt)
      sudo apt-get update -y
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
      ;;
    dnf)
      sudo dnf install -y "$@"
      ;;
    pacman)
      # pacman doesn't like combined operations; sync first
      sudo pacman -Sy --noconfirm "$@"
      ;;
    brew)
      # On macOS update formulae and install packages one by one.
      brew update || true
      brew install "$@" || true
      ;;
    *)
      echo "Unsupported package manager: $mgr" >&2
      return 1
      ;;
  esac
}

main() {
  local pkg_mgr
  pkg_mgr=$(detect_pkg_mgr)
  if [ "$pkg_mgr" = "unknown" ]; then
    echo "No supported package manager found. Supported: apt, dnf, pacman, brew."
    exit 1
  fi

  # Base toolchain
  log "Installing base toolchain packages"
  install_packages "$pkg_mgr" \
    build-essential git cmake ninja-build pkgconf clang llvm make gdb \
    curl wget unzip p7zip-full neovim tmux htop ripgrep \
    fd-find bat exa

  # Audio stack (PipeWire + JACK) – names vary between distributions
  log "Installing audio packages (PipeWire, JACK and utilities)"
  case "$pkg_mgr" in
    apt)
      install_packages "$pkg_mgr" pipewire pipewire-audio-client-libraries wireplumber \
        jackd2 qjackctl alsa-utils sox ffmpeg
      ;;
    dnf)
      install_packages "$pkg_mgr" pipewire pipewire-alsa pipewire-jack \
        wireplumber jack-audio-connection-kit qjackctl alsa-utils sox ffmpeg
      ;;
    pacman)
      install_packages "$pkg_mgr" pipewire pipewire-pulse wireplumber pipewire-jack \
        qjackctl alsa-utils sox ffmpeg realtime-privileges
      # Add realtime privileges for current user
      sudo usermod -aG realtime "$ME" || true
      sudo install -Dm644 /dev/stdin /etc/security/limits.d/99-realtime.conf <<'EOF'
@realtime   -   rtprio     95
@realtime   -   memlock    unlimited
EOF
      ;;
    brew)
      # On macOS, install JACK and FFmpeg equivalents. PipeWire may not be
      # available via brew; these packages are optional.
      install_packages "$pkg_mgr" jack ffmpeg sox
      ;;
  esac

  # System tuning: TRIM and kernel parameters.  Only applicable on
  # Linux; skip gracefully on systems without systemd or sysctl.
  log "Configuring system tuning"
  if [ "$pkg_mgr" = "pacman" ]; then
    install_packages "$pkg_mgr" util-linux
  fi
  # Enable fstrim timer on Linux if systemctl is available.
  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl enable --now fstrim.timer || true
  fi
  # Write sysctl tuning file on Linux (safe to skip on macOS)
  if [ -d /etc/sysctl.d ] && command -v sysctl >/dev/null 2>&1; then
    sudo install -Dm644 /dev/stdin /etc/sysctl.d/99-audio.conf <<'EOF'
vm.swappiness = 10
fs.inotify.max_user_watches = 524288
EOF
    sudo sysctl --system > /dev/null || true
  fi

  # CPU governor: install cpufrequtils or cpupower if available.  On
  # macOS or systems without these utilities, this step is skipped.
  if install_packages "$pkg_mgr" cpufrequtils; then
    log "Setting CPU governor to performance"
    if command -v cpufreq-set >/dev/null 2>&1; then
      sudo cpufreq-set -g performance || true
    elif command -v cpupower >/dev/null 2>&1; then
      sudo cpupower frequency-set -g performance || true
    fi
  fi

  # Install Miniforge (Conda) if not present.  Use wget with a fallback
  # to curl if wget is unavailable.  Choose the installer based on the
  # host OS and architecture.  Skip download if network is unreachable
  # by testing the URL with --spider (no-download mode).
  log "Setting up Miniforge"
  if [ ! -d "$HOME/miniforge3" ]; then
    tmpdir=$(mktemp -d)
    pushd "$tmpdir" >/dev/null
    # Derive OS and architecture for Miniforge download.  Use uname
    # values and normalize to expected names.  See:
    # https://github.com/conda-forge/miniforge#miniforge3
    local os_name
    local arch_name
    case "$(uname -s)" in
      Linux*)   os_name="Linux" ;;
      Darwin*)  os_name="MacOSX" ;;
      *)        os_name="$(uname -s)" ;;
    esac
    case "$(uname -m)" in
      x86_64|amd64)  arch_name="x86_64" ;;
      arm64|aarch64) arch_name="arm64" ;;
      *)             arch_name="$(uname -m)" ;;
    esac
    local url="https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-${os_name}-${arch_name}.sh"
    # Check network availability with wget or curl before downloading.
    if command -v wget >/dev/null 2>&1 && wget --spider -q "$url"; then
      wget -q "$url" -O Miniforge3.sh
    elif command -v curl >/dev/null 2>&1 && curl -sSfI "$url" >/dev/null; then
      curl -sSL "$url" -o Miniforge3.sh
    else
      log "Network unavailable or download utilities missing; skipping Miniforge installation."
    fi
    if [ -f Miniforge3.sh ]; then
      bash Miniforge3.sh -b -p "$HOME/miniforge3"
    fi
    popd >/dev/null
    rm -rf "$tmpdir"
  fi

  # Activate conda and ensure mamba is available.
  if [ -d "$HOME/miniforge3" ]; then
    # shellcheck source=/dev/null
    source "$HOME/miniforge3/etc/profile.d/conda.sh"
    conda config --set auto_activate_base false
    conda update -n base -c conda-forge conda -y
    conda install -n base -c conda-forge mamba -y || true

    # Create qecstack env if missing
    if ! conda env list | grep -q '^qecstack'; then
      mamba create -y -n qecstack python=3.11
    fi
    mamba activate qecstack

    # Install core scientific stack
    log "Installing Python scientific packages"
    mamba install -y -c conda-forge numpy scipy pandas numba sympy h5py tqdm requests \
      jupyterlab matplotlib seaborn

    # Quantum and graph libraries
    log "Installing quantum and graph libraries"
    mamba install -y -c conda-forge qutip qiskit qiskit-aer cirq rustworkx networkx

    # Audio / DSP / Vision
    log "Installing audio/DSP/vision libraries"
    mamba install -y -c conda-forge librosa soundfile pyaudio opencv plotly

    # PyTorch GPU/CPU depending on NVIDIA presence.  Only attempt
    # detection on hosts with lspci; inside containers detection may fail.
    local has_nvidia=0
    if command -v lspci >/dev/null 2>&1 && lspci | grep -qi nvidia; then
      has_nvidia=1
    fi
    log "Installing PyTorch (HAS_NVIDIA=$has_nvidia)"
    if [ "$has_nvidia" -eq 1 ]; then
      mamba install -y pytorch torchvision torchaudio pytorch-cuda=12.4 -c pytorch -c nvidia
    else
      mamba install -y pytorch torchvision torchaudio cpuonly -c pytorch
    fi
    # Parallelism tuning
    # Determine the number of CPU cores without spawning external
    # processes unnecessarily.  Prefer nproc, fall back to getconf, then default.
    local nproc
    if command -v nproc >/dev/null 2>&1; then
      nproc=$(nproc)
    elif command -v getconf >/dev/null 2>&1; then
      nproc=$(getconf _NPROCESSORS_ONLN)
    else
      nproc=8
    fi
    if ! grep -q 'OMP_NUM_THREADS' "$HOME/.bashrc"; then
      cat >> "$HOME/.bashrc" <<EOF

# QEC/QDSP parallel tuning
export OMP_NUM_THREADS=$nproc
export MKL_NUM_THREADS=$nproc
EOF
    fi
    # Save environment lockfile for reproducibility
    local os_name
    os_name="$(uname -s)"
    # Lower-case conversion using Bash's parameter expansion; falls back to
    # external tr if not supported (POSIX shells would need tr).
    if [[ "$os_name" =~ [A-Z] ]]; then
      os_name="${os_name,,}"
    fi
    conda env export | sed '/^prefix:/d' > "$HOME/qec_env_${os_name}.yaml"
  else
    log "Conda not available; skipping environment creation."
  fi

  # GitHub Copilot CLI setup.  Install the CLI if missing (via npm or
  # Homebrew) and run login interactively.  Skip if copilot is already
  # present or network/tools are unavailable.
  log "Configuring GitHub Copilot CLI"
  # Ensure a dev folder exists
  mkdir -p "$HOME/dev"
  # Detect and install Copilot CLI only if absent
  if ! command -v copilot >/dev/null 2>&1; then
    if command -v npm >/dev/null 2>&1; then
      sudo npm install -g @githubnext/github-copilot-cli || true
    elif [ "$pkg_mgr" = "brew" ]; then
      brew install github-copilot-cli || true
    else
      log "Neither npm nor brew available; unable to install GitHub Copilot CLI."
    fi
  fi
  # Initialize Copilot CLI login
  if command -v copilot >/dev/null 2>&1; then
    # Use a subshell to ensure we run in the ~/dev directory
    (
      cd "$HOME/dev"
      # Print directory listing for sanity
      ls >/dev/null || true
      copilot <<'EOF'
/login
EOF
    )
    echo "GitHub Copilot CLI initialized in ~/dev. Please complete browser login if required."
  fi

  log "Setup complete"
  echo "Notes:"
  echo " • Re-login or restart your shell to pick up realtime group changes (if applicable)."
  echo " • Conda environment 'qecstack' contains all scientific libraries. Activate it with 'conda activate qecstack'."
  echo " • On unsupported systems some packages may not be installed; review the logs above for any skips."
  echo " • GitHub Copilot CLI installed and logged in if possible; manual sign-in may be required."
}

main "$@"
