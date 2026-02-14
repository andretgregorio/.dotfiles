#!/usr/bin/env bash
# =============================================================================
# Dev Environment Setup Script for Ubuntu 24.04
# =============================================================================
# This script installs and configures a complete development environment.
# Run with: chmod +x setup-dev-env.sh && ./setup-dev-env.sh
#
# Tools installed:
#   - zsh + Oh My Zsh + Powerlevel10k
#   - nvm (Node Version Manager)
#   - Docker (Docker Engine + Docker Compose)
#   - vim
#   - build-essential
#   - delta (beautiful git diffs)
#   - Claude Code CLI (native installer)
#   - Claude Desktop (unofficial .deb via community repo)
#   - Cursor IDE + CLI (AppImage-based)
#   - HTTPie
#   - DBeaver Community Edition
#   - RedisInsight (via Snap)
#   - GitHub CLI (gh)
#   - jq
# =============================================================================

set -euo pipefail

# --- Colors & helpers --------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()    { echo -e "${RED}[FAIL]${NC} $*"; }

step_header() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  $*${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# --- Pre-flight checks -------------------------------------------------------
if [[ "$(lsb_release -rs 2>/dev/null || echo 'unknown')" != "24.04" ]]; then
    warn "This script is designed for Ubuntu 24.04. Detected: $(lsb_release -ds 2>/dev/null || echo 'unknown')."
    warn "Proceeding anyway, but some steps may not work as expected."
fi

if [[ "$EUID" -eq 0 ]]; then
    fail "Do NOT run this script as root or with sudo."
    fail "The script will ask for sudo when needed."
    exit 1
fi

ORIGINAL_USER="$USER"
ORIGINAL_HOME="$HOME"

step_header "Updating system packages"
sudo apt-get update -y
sudo apt-get upgrade -y
success "System packages updated"

# =============================================================================
# 1. zsh
# =============================================================================
step_header "Installing zsh"
if command -v zsh &>/dev/null; then
    success "zsh is already installed ($(zsh --version))"
else
    sudo apt-get install -y zsh
    success "zsh installed"
fi

# =============================================================================
# 2. Oh My Zsh
# =============================================================================
step_header "Installing Oh My Zsh"
if [[ -d "$ORIGINAL_HOME/.oh-my-zsh" ]]; then
    success "Oh My Zsh is already installed"
else
    # Unattended install, don't switch shell yet
    RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    success "Oh My Zsh installed"
fi

# =============================================================================
# 3. Powerlevel10k
# =============================================================================
step_header "Installing Powerlevel10k theme"
P10K_DIR="${ZSH_CUSTOM:-$ORIGINAL_HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
if [[ -d "$P10K_DIR" ]]; then
    success "Powerlevel10k is already installed"
else
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
    # Set theme in .zshrc
    if grep -q '^ZSH_THEME=' "$ORIGINAL_HOME/.zshrc" 2>/dev/null; then
        sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$ORIGINAL_HOME/.zshrc"
    fi
    success "Powerlevel10k installed and configured in .zshrc"
fi

info "Tip: Install a Nerd Font (e.g., MesloLGS NF) for proper Powerlevel10k rendering."
info "  Download from: https://github.com/romkatv/powerlevel10k#fonts"

# =============================================================================
# 4. nvm (Node Version Manager)
# =============================================================================
step_header "Installing nvm"
export NVM_DIR="$ORIGINAL_HOME/.nvm"
if [[ -d "$NVM_DIR" ]]; then
    success "nvm is already installed"
else
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    success "nvm installed"
fi

# Load nvm for this session
export NVM_DIR="$ORIGINAL_HOME/.nvm"
# shellcheck disable=SC1091
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Install latest LTS Node.js
if command -v nvm &>/dev/null; then
    info "Installing latest Node.js LTS via nvm..."
    nvm install --lts
    nvm use --lts
    nvm alias default 'lts/*'
    success "Node.js LTS installed: $(node --version)"
else
    warn "nvm loaded but 'nvm' command not available in this session."
    warn "After the script finishes, open a new terminal and run: nvm install --lts"
fi

# =============================================================================
# 5. Docker (Docker Engine + Compose plugin)
# =============================================================================
step_header "Installing Docker"
if command -v docker &>/dev/null; then
    success "Docker is already installed ($(docker --version))"
else
    # Remove any old/conflicting packages
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
        sudo apt-get remove -y "$pkg" 2>/dev/null || true
    done

    # Add Docker's official GPG key and repo
    sudo apt-get install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Add current user to docker group (avoids sudo for docker commands)
    sudo usermod -aG docker "$ORIGINAL_USER"

    success "Docker installed ($(docker --version))"
    warn "Log out and back in (or run 'newgrp docker') for group changes to take effect."
fi

# =============================================================================
# 6. vim
# =============================================================================
step_header "Installing vim"
if command -v vim &>/dev/null; then
    success "vim is already installed"
else
    sudo apt-get install -y vim
    success "vim installed"
fi

# =============================================================================
# 7. build-essential
# =============================================================================
step_header "Installing build-essential"
if dpkg -s build-essential &>/dev/null 2>&1; then
    success "build-essential is already installed"
else
    sudo apt-get install -y build-essential
    success "build-essential installed"
fi

# =============================================================================
# 8. delta (beautiful git diffs)
# =============================================================================
step_header "Installing git-delta (beautiful git diffs)"
if command -v delta &>/dev/null; then
    success "delta is already installed ($(delta --version))"
else
    sudo apt-get install -y git-delta 2>/dev/null || {
        # Fallback: download .deb from GitHub releases
        info "git-delta not in apt, downloading from GitHub releases..."
        DELTA_VERSION="0.18.2"
        DELTA_DEB="git-delta_${DELTA_VERSION}_amd64.deb"
        curl -fsSL -o "/tmp/${DELTA_DEB}" \
            "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/${DELTA_DEB}"
        sudo dpkg -i "/tmp/${DELTA_DEB}" || sudo apt-get install -f -y
        rm -f "/tmp/${DELTA_DEB}"
    }
    success "delta installed"
fi

# Configure git to use delta
info "Configuring git to use delta as the pager..."
git config --global core.pager delta
git config --global interactive.diffFilter "delta --color-only"
git config --global delta.navigate true
git config --global delta.side-by-side true
git config --global delta.line-numbers true
git config --global delta.syntax-theme "Dracula"
git config --global merge.conflictstyle diff3
git config --global diff.colorMoved default
success "git configured to use delta with side-by-side diffs"

# =============================================================================
# 9. Claude Code CLI (native installer)
# =============================================================================
step_header "Installing Claude Code CLI"
if command -v claude &>/dev/null; then
    success "Claude Code is already installed ($(claude --version 2>/dev/null || echo 'installed'))"
else
    info "Installing via native installer (recommended by Anthropic)..."
    curl -fsSL https://claude.ai/install.sh | bash
    success "Claude Code CLI installed"
    info "Run 'claude' to authenticate and get started."
fi

# =============================================================================
# 10. Claude Desktop (unofficial community build for Linux)
# =============================================================================
step_header "Installing Claude Desktop (community .deb package)"
if command -v claude-desktop &>/dev/null || dpkg -s claude-desktop &>/dev/null 2>&1; then
    success "Claude Desktop is already installed"
else
    info "Adding aaddrick/claude-desktop-debian community repository..."
    curl -fsSL https://aaddrick.github.io/claude-desktop-debian/KEY.gpg \
        | sudo gpg --dearmor -o /usr/share/keyrings/claude-desktop.gpg
    echo "deb [signed-by=/usr/share/keyrings/claude-desktop.gpg arch=amd64,arm64] https://aaddrick.github.io/claude-desktop-debian stable main" \
        | sudo tee /etc/apt/sources.list.d/claude-desktop.list > /dev/null
    sudo apt-get update -y
    sudo apt-get install -y claude-desktop
    success "Claude Desktop installed"
    warn "Note: This is an unofficial community build, not an official Anthropic product."
fi

# =============================================================================
# 11. Cursor IDE + CLI (AppImage)
# =============================================================================
step_header "Installing Cursor IDE"
CURSOR_DIR="$ORIGINAL_HOME/.local/bin/cursor"
CURSOR_APPIMAGE="$CURSOR_DIR/cursor.AppImage"

if [[ -f "$CURSOR_APPIMAGE" ]] || command -v cursor &>/dev/null; then
    success "Cursor IDE is already installed"
else
    info "Downloading Cursor AppImage..."
    mkdir -p "$CURSOR_DIR"
    curl -fsSL "https://downloader.cursor.sh/linux/appImage/x64" -o "$CURSOR_APPIMAGE"
    chmod +x "$CURSOR_APPIMAGE"

    # Extract AppImage for better desktop integration (avoids FUSE issues on 24.04)
    info "Extracting AppImage for native integration..."
    cd "$CURSOR_DIR"
    "$CURSOR_APPIMAGE" --appimage-extract 2>/dev/null || true
    if [[ -d "$CURSOR_DIR/squashfs-root" ]]; then
        # Move extracted content and clean up
        mv squashfs-root/* . 2>/dev/null || true
        rm -rf squashfs-root "$CURSOR_APPIMAGE"

        # Fix Chrome sandbox permissions
        if [[ -f "$CURSOR_DIR/chrome-sandbox" ]]; then
            sudo chown root:root "$CURSOR_DIR/chrome-sandbox"
            sudo chmod 4755 "$CURSOR_DIR/chrome-sandbox"
        fi
    fi
    cd - >/dev/null

    # Create desktop entry
    mkdir -p "$ORIGINAL_HOME/.local/share/applications"
    CURSOR_ICON="$CURSOR_DIR/resources/app/resources/linux/code.png"
    CURSOR_EXEC="$CURSOR_DIR/cursor"
    if [[ -f "$CURSOR_APPIMAGE" ]]; then
        CURSOR_EXEC="$CURSOR_APPIMAGE --no-sandbox"
    fi

    cat > "$ORIGINAL_HOME/.local/share/applications/cursor.desktop" << EOF
[Desktop Entry]
Name=Cursor AI IDE
Comment=AI-powered code editor
Exec=$CURSOR_EXEC %U
Icon=$CURSOR_ICON
Type=Application
Categories=Development;IDE;
Terminal=false
StartupWMClass=cursor
EOF

    # Create CLI symlink
    mkdir -p "$ORIGINAL_HOME/.local/bin"
    if [[ -f "$CURSOR_DIR/cursor" ]]; then
        ln -sf "$CURSOR_DIR/cursor" "$ORIGINAL_HOME/.local/bin/cursor"
    elif [[ -f "$CURSOR_APPIMAGE" ]]; then
        cat > "$ORIGINAL_HOME/.local/bin/cursor" << 'WRAPPER'
#!/usr/bin/env bash
exec "$HOME/.local/bin/cursor/cursor.AppImage" --no-sandbox "$@"
WRAPPER
        chmod +x "$ORIGINAL_HOME/.local/bin/cursor"
    fi

    success "Cursor IDE installed"
    info "Launch from app menu or run 'cursor' in the terminal."
fi

# Ensure ~/.local/bin is in PATH
if ! echo "$PATH" | grep -q "$ORIGINAL_HOME/.local/bin"; then
    for rc_file in "$ORIGINAL_HOME/.bashrc" "$ORIGINAL_HOME/.zshrc"; do
        if [[ -f "$rc_file" ]] && ! grep -q '\.local/bin' "$rc_file"; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc_file"
        fi
    done
    export PATH="$ORIGINAL_HOME/.local/bin:$PATH"
fi

# =============================================================================
# 12. HTTPie
# =============================================================================
step_header "Installing HTTPie"
if command -v http &>/dev/null; then
    success "HTTPie is already installed ($(http --version 2>/dev/null | head -1))"
else
    sudo apt-get install -y httpie
    success "HTTPie installed"
fi

# =============================================================================
# 13. DBeaver Community Edition
# =============================================================================
step_header "Installing DBeaver Community Edition"
if command -v dbeaver &>/dev/null || dpkg -s dbeaver-ce &>/dev/null 2>&1; then
    success "DBeaver is already installed"
else
    info "Adding DBeaver PPA repository..."
    sudo add-apt-repository -y ppa:serge-rider/dbeaver-ce
    sudo apt-get update -y
    sudo apt-get install -y dbeaver-ce
    success "DBeaver Community Edition installed"
fi

# =============================================================================
# 14. RedisInsight (via Snap)
# =============================================================================
step_header "Installing RedisInsight"
if snap list redisinsight &>/dev/null 2>&1; then
    success "RedisInsight is already installed"
else
    info "Installing RedisInsight via Snap..."
    sudo snap install redisinsight
    success "RedisInsight installed"
    info "Optional: run 'snap connect redisinsight:password-manager-service' for encrypted credential storage."
fi

# =============================================================================
# 15. GitHub CLI (gh)
# =============================================================================
step_header "Installing GitHub CLI (gh)"
if command -v gh &>/dev/null; then
    success "GitHub CLI is already installed ($(gh --version | head -1))"
else
    info "Adding GitHub CLI repository..."
    sudo mkdir -p -m 755 /etc/apt/keyrings
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
    sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli-stable.list > /dev/null
    sudo apt-get update -y
    sudo apt-get install -y gh
    success "GitHub CLI installed ($(gh --version | head -1))"
    info "Run 'gh auth login' to authenticate."
fi

# =============================================================================
# 16. jq
# =============================================================================
step_header "Installing jq"
if command -v jq &>/dev/null; then
    success "jq is already installed ($(jq --version))"
else
    sudo apt-get install -y jq
    success "jq installed"
fi

# =============================================================================
# Change default shell to zsh
# =============================================================================
step_header "Setting zsh as default shell"
if [[ "$SHELL" == *"zsh"* ]]; then
    success "zsh is already the default shell"
else
    chsh -s "$(which zsh)"
    success "Default shell changed to zsh (takes effect on next login)"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Setup complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Post-install actions:"
echo "  1. Log out and back in for shell and Docker group changes."
echo "  2. Install a Nerd Font for Powerlevel10k (MesloLGS NF recommended)."
echo "  3. Run 'p10k configure' to set up Powerlevel10k."
echo "  4. Run 'claude' to authenticate Claude Code CLI."
echo "  5. Run 'gh auth login' to authenticate GitHub CLI."
echo "  6. Run 'nvm install --lts' if Node.js was not installed during this session."
echo ""
