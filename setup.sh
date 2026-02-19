#!/usr/bin/env bash
# =============================================================================
# Dev Environment Setup Script for Ubuntu 24.04
# =============================================================================
# This script installs and configures a complete development environment.
# Run with: chmod +x setup.sh && ./setup.sh
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
#   - Cursor IDE (.deb) + Cursor CLI
#   - HTTPie
#   - DBeaver Community Edition
#   - RedisInsight (via Snap)
#   - GitHub CLI (gh)
#   - jq
#   - Terminator (terminal emulator, configured with ZSH + Powerlevel10k)
#   - git (identity, GPG signing key, aliases & settings)
#   - Postman (via Snap)
# =============================================================================

set -uo pipefail

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

# --- Step runner: executes a named function and continues on failure ----------
FAILED_STEPS=()
run_step() {
    local name="$1"
    local fn="$2"
    step_header "$name"
    if ( set -eo pipefail; "$fn" ); then
        :
    else
        warn "Step '$name' failed — continuing. Check output above for details."
        FAILED_STEPS+=("$name")
    fi
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

# =============================================================================
# System update
# =============================================================================
update_system() {
    sudo apt-get update -y
    sudo apt-get upgrade -y
    success "System packages updated"
}
run_step "Updating system packages" update_system

# =============================================================================
# 0. curl (required by many subsequent install steps)
# =============================================================================
install_curl() {
    if command -v curl &>/dev/null; then
        success "curl is already installed"
    else
        sudo apt-get install -y curl
        success "curl installed"
    fi
}
run_step "0. curl" install_curl

# =============================================================================
# 1. zsh
# =============================================================================
install_zsh() {
    if command -v zsh &>/dev/null; then
        success "zsh is already installed ($(zsh --version))"
    else
        sudo apt-get install -y zsh
        success "zsh installed"
    fi
}
run_step "1. zsh" install_zsh

# =============================================================================
# 2. Oh My Zsh
# =============================================================================
install_ohmyzsh() {
    if [[ -f "$ORIGINAL_HOME/.oh-my-zsh/oh-my-zsh.sh" ]]; then
        success "Oh My Zsh is already installed"
    else
        # A directory may exist from a partial install — preserve custom content and clear it
        if [[ -d "$ORIGINAL_HOME/.oh-my-zsh" ]]; then
            warn "Incomplete Oh My Zsh directory found — clearing it before reinstalling..."
            if [[ -d "$ORIGINAL_HOME/.oh-my-zsh/custom" ]]; then
                mv "$ORIGINAL_HOME/.oh-my-zsh/custom" /tmp/ohmyzsh-custom-backup
            fi
            rm -rf "$ORIGINAL_HOME/.oh-my-zsh"
        fi
        # Unattended install, don't switch shell yet
        RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
        # Restore any custom content (e.g. themes) that existed before
        if [[ -d /tmp/ohmyzsh-custom-backup ]]; then
            cp -r /tmp/ohmyzsh-custom-backup/. "$ORIGINAL_HOME/.oh-my-zsh/custom/"
            rm -rf /tmp/ohmyzsh-custom-backup
        fi
        success "Oh My Zsh installed"
    fi
}
run_step "2. Oh My Zsh" install_ohmyzsh

# =============================================================================
# 3. Powerlevel10k
# =============================================================================
install_p10k() {
    local p10k_dir="${ZSH_CUSTOM:-$ORIGINAL_HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    if [[ -d "$p10k_dir" ]]; then
        success "Powerlevel10k is already installed"
    else
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_dir"
        success "Powerlevel10k installed"
    fi
    info "Tip: Install a Nerd Font (e.g., MesloLGS NF) for proper Powerlevel10k rendering."
    info "  Download from: https://github.com/romkatv/powerlevel10k#fonts"
}
run_step "3. Powerlevel10k" install_p10k

# =============================================================================
# 3.5. Configure ZSH (.zshrc)
# =============================================================================
configure_zsh() {
    local zshrc="$ORIGINAL_HOME/.zshrc"

    if [[ ! -f "$zshrc" ]]; then
        warn ".zshrc not found — Oh My Zsh may not have been installed. Skipping ZSH configuration."
        return 1
    fi

    # Set Powerlevel10k theme
    if grep -q '^ZSH_THEME=' "$zshrc"; then
        sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$zshrc"
        success "ZSH_THEME set to powerlevel10k/powerlevel10k"
    fi

    # Set default plugins
    if grep -q '^plugins=' "$zshrc"; then
        sed -i 's|^plugins=.*|plugins=(git docker)|' "$zshrc"
        success "ZSH plugins configured: git docker"
    fi

    # Add nvm sourcing if not already present
    if ! grep -q 'NVM_DIR' "$zshrc"; then
        cat >> "$zshrc" << 'ZSHEOF'

# nvm (Node Version Manager)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
ZSHEOF
        success "nvm configuration added to .zshrc"
    else
        success "nvm configuration already present in .zshrc"
    fi

    # Add ~/.local/bin to PATH if not already present
    if ! grep -q '\.local/bin' "$zshrc"; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$zshrc"
        success "~/.local/bin added to PATH in .zshrc"
    fi

    # Add p10k config sourcing if not already present
    if ! grep -q 'p10k.zsh' "$zshrc"; then
        cat >> "$zshrc" << 'ZSHEOF'

# To customize the prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
ZSHEOF
        success "p10k sourcing added to .zshrc"
    fi

    success "ZSH configured"
}
run_step "3.5. Configure ZSH (.zshrc)" configure_zsh

# =============================================================================
# 4. nvm (Node Version Manager)
# =============================================================================
install_nvm() {
    if [[ -d "$ORIGINAL_HOME/.nvm" ]]; then
        success "nvm is already installed"
    else
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
        success "nvm installed"
    fi
}
run_step "4. nvm" install_nvm

# Load nvm in the current shell session (must run in main shell, not subshell)
export NVM_DIR="$ORIGINAL_HOME/.nvm"
set +u
# shellcheck disable=SC1091
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

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
set -u

# =============================================================================
# 5. Docker (Docker Engine + Compose plugin)
# =============================================================================
install_docker() {
    if ! command -v docker &>/dev/null; then
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

        success "Docker installed ($(docker --version))"
    else
        success "Docker is already installed ($(docker --version))"
    fi

    # Always ensure the current user is in the docker group
    if ! groups "$ORIGINAL_USER" | grep -qw docker; then
        sudo usermod -aG docker "$ORIGINAL_USER"
        warn "User '$ORIGINAL_USER' added to docker group. Log out and back in (or run 'newgrp docker') for this to take effect."
    else
        success "User '$ORIGINAL_USER' is already in the docker group"
    fi
}
run_step "5. Docker" install_docker

# =============================================================================
# 6. vim
# =============================================================================
install_vim() {
    if command -v vim &>/dev/null; then
        success "vim is already installed"
    else
        sudo apt-get install -y vim
        success "vim installed"
    fi
}
run_step "6. vim" install_vim

# =============================================================================
# 7. build-essential
# =============================================================================
install_build_essential() {
    if dpkg -s build-essential &>/dev/null 2>&1; then
        success "build-essential is already installed"
    else
        sudo apt-get install -y build-essential
        success "build-essential installed"
    fi
}
run_step "7. build-essential" install_build_essential

# =============================================================================
# 8. delta (beautiful git diffs)
# =============================================================================
install_delta() {
    if ! command -v delta &>/dev/null; then
        sudo apt-get install -y git-delta 2>/dev/null || {
            # Fallback: download .deb from GitHub releases
            info "git-delta not in apt, downloading from GitHub releases..."
            local delta_version="0.18.2"
            local delta_deb="git-delta_${delta_version}_amd64.deb"
            curl -fsSL -o "/tmp/${delta_deb}" \
                "https://github.com/dandavison/delta/releases/download/${delta_version}/${delta_deb}"
            sudo dpkg -i "/tmp/${delta_deb}" || sudo apt-get install -f -y
            rm -f "/tmp/${delta_deb}"
        }
        success "delta installed"
    else
        success "delta is already installed ($(delta --version))"
    fi

    info "Configuring git to use delta..."
    git config --global core.pager delta
    git config --global interactive.diffFilter "delta --color-only"
    git config --global delta.navigate true
    git config --global delta.side-by-side true
    git config --global delta.line-numbers true
    git config --global delta.syntax-theme "Dracula"
    git config --global merge.conflictstyle diff3
    git config --global diff.colorMoved default
    success "git configured to use delta with side-by-side diffs"
}
run_step "8. delta (git diffs)" install_delta

# =============================================================================
# 9. Claude Code CLI (native installer)
# =============================================================================
install_claude_code() {
    if command -v claude &>/dev/null; then
        success "Claude Code is already installed ($(claude --version 2>/dev/null || echo 'installed'))"
    else
        info "Installing via native installer (recommended by Anthropic)..."
        curl -fsSL https://claude.ai/install.sh | bash
        success "Claude Code CLI installed"
        info "Run 'claude' to authenticate and get started."
    fi
}
run_step "9. Claude Code CLI" install_claude_code

# =============================================================================
# 10. Claude Desktop (unofficial community build for Linux)
# =============================================================================
install_claude_desktop() {
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
}
run_step "10. Claude Desktop" install_claude_desktop

# =============================================================================
# 11. Cursor IDE (.deb) + Cursor CLI
# =============================================================================
install_cursor() {
    # Install Cursor IDE via .deb
    if command -v cursor &>/dev/null || dpkg -l 'cursor' 2>/dev/null | grep -q '^ii'; then
        success "Cursor IDE is already installed"
    else
        info "Downloading Cursor IDE .deb package..."
        local cursor_deb="/tmp/cursor.deb"
        curl -fsSL -o "$cursor_deb" "https://api2.cursor.sh/updates/download/golden/linux-x64-deb/cursor/2.5"
        sudo dpkg -i "$cursor_deb" || sudo apt-get install -f -y
        rm -f "$cursor_deb"
        success "Cursor IDE installed"
    fi

    # Install Cursor CLI
    info "Installing Cursor CLI..."
    curl https://cursor.com/install -fsS | bash
    success "Cursor CLI installed"
}
run_step "11. Cursor IDE + CLI" install_cursor

# Ensure ~/.local/bin is in the current session's PATH
if ! echo "$PATH" | grep -q "$ORIGINAL_HOME/.local/bin"; then
    export PATH="$ORIGINAL_HOME/.local/bin:$PATH"
fi

# =============================================================================
# 12. HTTPie
# =============================================================================
install_httpie() {
    if command -v http &>/dev/null; then
        success "HTTPie is already installed ($(http --version 2>/dev/null | head -1))"
    else
        sudo apt-get install -y httpie
        success "HTTPie installed"
    fi
}
run_step "12. HTTPie" install_httpie

# =============================================================================
# 13. DBeaver Community Edition
# =============================================================================
install_dbeaver() {
    if command -v dbeaver &>/dev/null || dpkg -s dbeaver-ce &>/dev/null 2>&1; then
        success "DBeaver is already installed"
    else
        info "Adding DBeaver PPA repository..."
        sudo add-apt-repository -y ppa:serge-rider/dbeaver-ce
        sudo apt-get update -y
        sudo apt-get install -y dbeaver-ce
        success "DBeaver Community Edition installed"
    fi
}
run_step "13. DBeaver" install_dbeaver

# =============================================================================
# 14. RedisInsight (via Snap)
# =============================================================================
install_redisinsight() {
    if snap list redisinsight &>/dev/null 2>&1; then
        success "RedisInsight is already installed"
    else
        info "Installing RedisInsight via Snap..."
        sudo snap install redisinsight
        success "RedisInsight installed"
        info "Optional: run 'snap connect redisinsight:password-manager-service' for encrypted credential storage."
    fi
}
run_step "14. RedisInsight" install_redisinsight

# =============================================================================
# 15. GitHub CLI (gh)
# =============================================================================
install_gh() {
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
}
run_step "15. GitHub CLI (gh)" install_gh

# =============================================================================
# 16. jq
# =============================================================================
install_jq() {
    if command -v jq &>/dev/null; then
        success "jq is already installed ($(jq --version))"
    else
        sudo apt-get install -y jq
        success "jq installed"
    fi
}
run_step "16. jq" install_jq

# =============================================================================
# 17. Terminator (terminal emulator)
# =============================================================================
install_terminator() {
    if ! command -v terminator &>/dev/null; then
        sudo apt-get install -y terminator
        success "Terminator installed"
    else
        success "Terminator is already installed"
    fi

    # Write config (Dracula theme + ZSH + MesloLGS NF for Powerlevel10k)
    local config_dir="$ORIGINAL_HOME/.config/terminator"
    mkdir -p "$config_dir"

    local zsh_path
    zsh_path="$(command -v zsh 2>/dev/null || echo '/usr/bin/zsh')"

    cat > "$config_dir/config" << EOF
[global_config]
  title_font = MesloLGS NF 11

[keybindings]

[profiles]
  [[default]]
    background_color = "#282a36"
    cursor_color = "#f8f8f2"
    font = MesloLGS NF 12
    foreground_color = "#f8f8f2"
    show_titlebar = False
    scrollback_lines = 5000
    custom_command = $zsh_path
    use_custom_command = True
    use_system_font = False
    palette = "#21222c:#ff5555:#50fa7b:#f1fa8c:#bd93f9:#ff79c6:#8be9fd:#f8f8f2:#6272a4:#ff6e6e:#69ff94:#ffffa5:#d6acff:#ff92df:#a4ffff:#ffffff"

[layouts]
  [[default]]
    [[[child1]]]
      parent = window0
      type = Terminal
    [[[window0]]]
      parent = ""
      type = Window

[plugins]
EOF

    success "Terminator configured with ZSH + Dracula theme + MesloLGS NF font"

    # Set Terminator as the default terminal emulator
    if update-alternatives --list x-terminal-emulator 2>/dev/null | grep -q terminator; then
        sudo update-alternatives --set x-terminal-emulator /usr/bin/terminator
        success "Terminator set as default terminal emulator"
    else
        warn "Could not set Terminator as default via update-alternatives — set it manually in System Settings."
    fi
}
run_step "17. Terminator" install_terminator

# =============================================================================
# 18. Configure git (identity, GPG signing key, aliases & settings)
# =============================================================================
configure_git() {
    # Ensure gnupg is available
    if ! command -v gpg &>/dev/null; then
        sudo apt-get install -y gnupg
    fi

    # --- Identity ---
    local GIT_EMAIL GIT_NAME
    GIT_EMAIL=$(git config --global user.email 2>/dev/null || true)
    GIT_NAME=$(git config --global user.name  2>/dev/null || true)

    if [[ -n "$GIT_EMAIL" ]]; then
        success "Git email already configured: $GIT_EMAIL"
    else
        echo ""
        read -rp "$(echo -e "${CYAN}[INPUT]${NC} Enter your git email: ")" GIT_EMAIL
        if [[ -z "$GIT_EMAIL" ]]; then
            fail "Git email is required."
            return 1
        fi
        git config --global user.email "$GIT_EMAIL"
        success "Git email set: $GIT_EMAIL"
    fi

    if [[ -n "$GIT_NAME" ]]; then
        success "Git name already configured: $GIT_NAME"
    else
        read -rp "$(echo -e "${CYAN}[INPUT]${NC} Enter your git name:  ")" GIT_NAME
        if [[ -z "$GIT_NAME" ]]; then
            fail "Git name is required."
            return 1
        fi
        git config --global user.name "$GIT_NAME"
        success "Git name set: $GIT_NAME"
    fi

    # --- GPG signing key ---
    local GPG_KEY_ID=""
    local EXISTING_KEY
    EXISTING_KEY=$(git config --global user.signingkey 2>/dev/null || true)

    if [[ -n "$EXISTING_KEY" ]] && gpg --list-secret-keys "$EXISTING_KEY" &>/dev/null 2>&1; then
        success "GPG signing key already configured: $EXISTING_KEY"
        GPG_KEY_ID="$EXISTING_KEY"
    elif gpg --list-secret-keys --keyid-format=long "$GIT_EMAIL" 2>/dev/null | grep -q 'sec'; then
        success "GPG key already exists for $GIT_EMAIL"
        GPG_KEY_ID=$(gpg --list-secret-keys --keyid-format=long "$GIT_EMAIL" 2>/dev/null \
            | grep 'sec' | head -1 | awk '{print $2}' | cut -d'/' -f2)
        git config --global user.signingkey "$GPG_KEY_ID"
        success "Git signing key set: $GPG_KEY_ID"
    else
        info "Generating RSA 4096 GPG key for $GIT_NAME <$GIT_EMAIL> (no passphrase)..."
        gpg --batch --gen-key <<GPGEOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: $GIT_NAME
Name-Email: $GIT_EMAIL
Expire-Date: 0
%commit
GPGEOF
        success "GPG key generated"
        GPG_KEY_ID=$(gpg --list-secret-keys --keyid-format=long "$GIT_EMAIL" 2>/dev/null \
            | grep 'sec' | head -1 | awk '{print $2}' | cut -d'/' -f2)
        git config --global user.signingkey "$GPG_KEY_ID"
        success "Git signing key set: $GPG_KEY_ID"
        echo ""
        info "Copy this GPG public key and add it to GitHub / GitLab (Settings → SSH and GPG keys):"
        echo ""
        gpg --armor --export "$GPG_KEY_ID"
        echo ""
    fi

    if [[ -z "$GPG_KEY_ID" ]]; then
        warn "Could not determine GPG key ID. Set it manually: git config --global user.signingkey <KEY_ID>"
    fi

    # --- Aliases ---
    git config --global alias.logpretty "log --graph --decorate --pretty=oneline --abbrev-commit"
    git config --global alias.ci        "commit"
    git config --global alias.br        "branch"
    git config --global alias.co        "checkout"
    git config --global alias.d         "difftool"
    git config --global alias.df        "diff"
    git config --global alias.lg        "log --all --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative"
    git config --global alias.st        "status"
    git config --global alias.who       "shortlog -s -n --"
    git config --global alias.up        "!git fetch origin && git pull --rebase origin main"
    git config --global alias.ir        "!git pull --rebase origin main"
    git config --global alias.cm        "!git checkout main"
    git config --global alias.dlb       "!git checkout main && git branch | grep - --sort=committerdate refs/heads/ --format='%(HEAD) %(color:yellow)%(refname:short)%(color:reset) - %(color:red)%(objectname:short)%(color:reset) - %(contents:subject) - %(authorname) (%(color:green)%(committerdate:relative)%(color:reset))'"
    git config --global alias.upush     "!git fetch origin && git pull --rebase origin main && git push"

    # --- Color ---
    git config --global color.branch      auto
    git config --global color.diff        auto
    git config --global color.interactive auto
    git config --global color.status      auto
    git config --global color.ui          true

    # --- Core ---
    git config --global core.editor       vim
    git config --global core.excludesfile "$HOME/.gitignore_global"

    # --- Commit ---
    git config --global commit.gpgsign true

    # --- Diff / DiffTool ---
    git config --global diff.tool       vimdiff
    git config --global difftool.prompt false

    # --- Merge ---
    git config --global merge.tool vimdiff

    # --- Push ---
    git config --global push.default current

    # --- Git LFS ---
    git config --global filter.lfs.clean    "git-lfs clean %f"
    git config --global filter.lfs.smudge   "git-lfs smudge %f"
    git config --global filter.lfs.required true

    success "Git aliases and configuration applied"
}
run_step "18. Configure git" configure_git

# =============================================================================
# 19. Postman (via Snap)
# =============================================================================
install_postman() {
    if snap list postman &>/dev/null 2>&1; then
        success "Postman is already installed"
    else
        sudo snap install postman
        success "Postman installed"
    fi
}
run_step "19. Postman" install_postman

# =============================================================================
# Change default shell to zsh
# =============================================================================
set_default_shell() {
    if [[ "$SHELL" == *"zsh"* ]]; then
        success "zsh is already the default shell"
    else
        chsh -s "$(which zsh)"
        success "Default shell changed to zsh (takes effect on next login)"
    fi
}
run_step "Set zsh as default shell" set_default_shell

# =============================================================================
# Summary
# =============================================================================
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Setup complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [[ ${#FAILED_STEPS[@]} -gt 0 ]]; then
    warn "The following steps encountered errors and were skipped:"
    for s in "${FAILED_STEPS[@]}"; do
        warn "  - $s"
    done
    echo ""
fi

echo "Post-install actions:"
echo "  1. Log out and back in for shell and Docker group changes."
echo "  2. Install a Nerd Font for Powerlevel10k (MesloLGS NF recommended)."
echo "  3. Run 'p10k configure' to set up Powerlevel10k."
echo "  4. Run 'claude' to authenticate Claude Code CLI."
echo "  5. Run 'gh auth login' to authenticate GitHub CLI."
echo "  6. Run 'nvm install --lts' if Node.js was not installed during this session."
echo "  7. Add your GPG public key (printed above) to GitHub / GitLab."
echo "     Re-print it anytime: gpg --armor --export <KEY_ID>"
echo ""
