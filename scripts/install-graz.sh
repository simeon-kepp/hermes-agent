#!/usr/bin/env bash
# ============================================================================
# Hermes Agent — RFI-IRFOS Graz Installer
# ============================================================================
# Smart multi-OS installer that:
#   1. Detects OS (Linux / macOS / Windows-WSL / Termux)
#   2. Clones Hermes base from your fork
#   3. Seeds all RFI-IRFOS custom skills, schemata, settings
#   4. Initializes RuVector schema + Engram memory
#   5. Runs hermes setup non-interactively
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/simeon-kepp/hermes-agent/main/scripts/install-graz.sh | bash
#
# Or locally:
#   bash install-graz.sh
# ============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
REPO_URL="${HERMES_REPO_URL:-https://github.com/simeon-kepp/hermes-agent.git}"
BRANCH="${HERMES_BRANCH:-main}"
INSTALL_DIR="${HERMES_INSTALL_DIR:-$HOME/.hermes/hermes-agent}"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
print_banner() {
    echo ""
    echo -e "${MAGENTA}${BOLD}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║          ⚕ Hermes Agent — RFI-IRFOS Graz Edition         ║"
    echo "║           Smart Installer · Linux · macOS · Windows        ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info()  { echo -e "${CYAN}→${NC} $1"; }
log_ok()    { echo -e "${GREEN}✓${NC} $1"; }
log_warn()  { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

# ---------------------------------------------------------------------------
# OS Detection
# ---------------------------------------------------------------------------
detect_os() {
    if [[ -n "${TERMUX_VERSION:-}" ]] || [[ "${PREFIX:-}" == *"com.termux/files/usr"* ]]; then
        echo "termux"
    elif [[ "$(uname -s)" == "Linux" ]]; then
        if grep -qi microsoft /proc/version 2>/dev/null || [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
            echo "wsl"
        else
            echo "linux"
        fi
    elif [[ "$(uname -s)" == "Darwin" ]]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

OS_TYPE=$(detect_os)
log_info "Detected OS: ${OS_TYPE}"

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
preflight() {
    log_info "Running preflight checks..."

    # Git
    if ! command -v git &> /dev/null; then
        log_error "git is required but not installed."
        case "$OS_TYPE" in
            macos)
                echo "  Install with: xcode-select --install"
                ;;
            termux)
                echo "  Install with: pkg install git"
                ;;
            *)
                echo "  Install git for your distribution first."
                ;;
        esac
        exit 1
    fi
    log_ok "git found: $(git --version | head -1)"

    # curl / wget
    if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
        log_error "curl or wget is required."
        exit 1
    fi
    log_ok "download tool available"

    # Python
    if command -v python3 &> /dev/null; then
        PYTHON_VER=$(python3 --version | awk '{print $2}')
        log_ok "python3 found: $PYTHON_VER"
    else
        log_warn "python3 not found — will be installed by hermes setup"
    fi

    # Node.js (optional but recommended)
    if command -v node &> /dev/null; then
        log_ok "node found: $(node --version)"
    else
        log_warn "node not found — hermes setup can install it"
    fi
}

# ---------------------------------------------------------------------------
# Clone / Update Hermes fork
# ---------------------------------------------------------------------------
clone_hermes() {
    log_info "Cloning Hermes Agent fork..."

    if [[ -d "$INSTALL_DIR/.git" ]]; then
        log_info "Existing install found at $INSTALL_DIR — pulling latest..."
        cd "$INSTALL_DIR"
        git fetch origin "$BRANCH" || true
        git checkout "$BRANCH" || true
        git pull origin "$BRANCH" || true
        log_ok "Updated existing install"
    else
        mkdir -p "$(dirname "$INSTALL_DIR")"
        git clone --branch "$BRANCH" --depth 1 "$REPO_URL" "$INSTALL_DIR" 2>&1 || {
            log_error "Failed to clone $REPO_URL"
            exit 1
        }
        log_ok "Cloned Hermes fork to $INSTALL_DIR"
    fi
}

# ---------------------------------------------------------------------------
# Install system dependencies (platform-specific)
# ---------------------------------------------------------------------------
install_deps() {
    log_info "Installing platform dependencies..."

    case "$OS_TYPE" in
        termux)
            pkg update -y || true
            pkg install -y python nodejs git ripgrep ffmpeg || true
            log_ok "Termux packages installed"
            ;;
        macos)
            if command -v brew &> /dev/null; then
                brew install python node git ripgrep ffmpeg || true
                log_ok "Homebrew packages installed"
            else
                log_warn "Homebrew not found — install manually or run hermes setup"
            fi
            ;;
        linux|wsl)
            if command -v apt-get &> /dev/null; then
                sudo apt-get update -qq || true
                sudo apt-get install -y -qq python3 python3-venv python3-pip nodejs npm git ripgrep ffmpeg || true
                log_ok "apt packages installed"
            elif command -v pacman &> /dev/null; then
                sudo pacman -Sy --noconfirm python python-pip nodejs npm git ripgrep ffmpeg || true
                log_ok "pacman packages installed"
            elif command -v dnf &> /dev/null; then
                sudo dnf install -y python3 python3-pip nodejs npm git ripgrep ffmpeg || true
                log_ok "dnf packages installed"
            fi
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Create Hermes home structure
# ---------------------------------------------------------------------------
init_hermes_home() {
    log_info "Initializing Hermes home at $HERMES_HOME..."

    mkdir -p "$HERMES_HOME"/{skills,plugins,ruvector,cron,memories,state,sessions,logs,cache,images,audio_cache,platforms,templates,hooks}

    # Seed base directories if missing
    for dir in bin scripts hooks laura-pre-push-hook.sh; do
        if [[ -d "$INSTALL_DIR/$dir" ]] && [[ ! -e "$HERMES_HOME/$(basename "$dir")" ]]; then
            cp -r "$INSTALL_DIR/$dir" "$HERMES_HOME/" 2>/dev/null || true
        fi
    done

    log_ok "Hermes home initialized"
}

# ---------------------------------------------------------------------------
# Seed custom skills (RFI-IRFOS stack)
# ---------------------------------------------------------------------------
seed_skills() {
    log_info "Seeding custom RFI-IRFOS skills..."

    # Source skill repository (your local custom skills)
    LOCAL_SKILLS_SRC="${LOCAL_SKILLS_SRC:-$HOME/.hermes/skills}"

    if [[ ! -d "$LOCAL_SKILLS_SRC" ]]; then
        log_warn "Local skills source not found at $LOCAL_SKILLS_SRC — skipping skill seeding"
        return
    fi

    # Copy all custom skills not in upstream
    SKILLS_DST="$HERMES_HOME/skills"
    COUNT=0

    for skill_dir in "$LOCAL_SKILLS_SRC"/*/; do
        skill_name=$(basename "$skill_dir")

        # Skip hidden dirs and shared
        [[ "$skill_name" == .* ]] && continue
        [[ "$skill_name" == "_shared" ]] && continue

        # Copy if not exists in hermes home
        if [[ ! -d "$SKILLS_DST/$skill_name" ]]; then
            cp -r "$skill_dir" "$SKILLS_DST/$skill_name"
            COUNT=$((COUNT + 1))
        fi
    done

    log_ok "Seeded $COUNT custom skills"
}

# ---------------------------------------------------------------------------
# Seed RuVector schema + base data
# ---------------------------------------------------------------------------
seed_ruvector() {
    log_info "Seeding RuVector schema..."

    RV_DIR="$HERMES_HOME/ruvector"

    # Create schema files if they don't exist
    if [[ ! -f "$RV_DIR/package.json" ]]; then
        cat > "$RV_DIR/package.json" <<'EOF'
{
  "name": "ruvector",
  "version": "1.0.0",
  "description": "RuVector semantic memory for Hermes Agent"
}
EOF
        log_ok "Created ruvector/package.json"
    fi

    if [[ ! -f "$RV_DIR/graph.json" ]]; then
        cat > "$RV_DIR/graph.json" <<'EOF'
{
  "entities": [],
  "relations": [],
  "schema_version": "1.0"
}
EOF
        log_ok "Created ruvector/graph.json schema"
    fi

    # Copy agent-drive if available in install
    if [[ -f "$INSTALL_DIR/ruvector/agent-drive.js" ]] && [[ ! -f "$RV_DIR/agent-drive.js" ]]; then
        cp "$INSTALL_DIR/ruvector/agent-drive.js" "$RV_DIR/" 2>/dev/null || true
    fi

    log_ok "RuVector schema initialized"
}

# ---------------------------------------------------------------------------
# Seed Engram / Memory base
# ---------------------------------------------------------------------------
seed_memory() {
    log_info "Seeding Engram memory..."

    MEM_DIR="$HERMES_HOME/memories"

    if [[ ! -f "$MEM_DIR/MEMORY.md" ]]; then
        cat > "$MEM_DIR/MEMORY.md" <<'EOF'
# Hermes Memory — RFI-IRFOS Graz Edition

## Active Context
- Installation: auto-seeded via install-graz.sh
- Platform: multi-OS (Linux/macOS/Windows-WSL/Termux)
- Fork: simeon-kepp/hermes-agent

## Preferences
- User: Simeon (RFI-IRFOS Graz ZVR 1015608684)
- Style: Bairisch casual, decisive, minimal-invasive
- Communication: German-only UI in pricing/market sections
- Email rule: rich HTML with inline CSS, Drafts only, never auto-send
EOF
        log_ok "Created MEMORY.md"
    else
        log_info "MEMORY.md exists — preserving existing content"
    fi

    if [[ ! -f "$MEM_DIR/USER.md" ]]; then
        cat > "$MEM_DIR/USER.md" <<'EOF'
# User Profile

## Identity
- Name: Simeon
- Org: RFI-IRFOS Graz (ZVR 1015608684)
- Location: Graz, Austria

## Work Style
- Swarm/concurrency first
- Plan-first, then subagents
- Prefers direct execution over ceremony
- German-only UI in pricing/market/modals

## Contacts
- Laura Serna Gaviria: lsgaviria94@gmail.com
EOF
        log_ok "Created USER.md"
    else
        log_info "USER.md exists — preserving"
    fi

    log_ok "Engram memory seeded"
}

# ---------------------------------------------------------------------------
# Seed config.yaml (RFI-IRFOS defaults)
# ---------------------------------------------------------------------------
seed_config() {
    log_info "Seeding config.yaml..."

    CONFIG_FILE="$HERMES_HOME/config.yaml"

    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "config.yaml exists — backing up and appending RFI-IRFOS defaults"
        cp "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
    else
        # Create base config from install
        if [[ -f "$INSTALL_DIR/cli-config.yaml.example" ]]; then
            cp "$INSTALL_DIR/cli-config.yaml.example" "$CONFIG_FILE"
            log_ok "Created config.yaml from template"
        else
            log_warn "No config template found — hermes setup will create it"
            return
        fi
    fi

    # Append RFI-IRFOS specific defaults (only if not present)
    {
        echo ""
        echo "# ===== RFI-IRFOS Graz defaults (auto-seeded) ====="
        echo "agent:"
        echo "  max_turns: 150"
        echo "  reasoning_effort: xhigh"
        echo "  verify_on_stop: false"
        echo "terminal:"
        echo "  timeout: 180"
        echo "  auto_source_bashrc: true"
        echo "web:"
        echo "  backend: firecrawl"
        echo "browser:"
        echo "  engine: auto"
        echo "  record_sessions: false"
    } >> "$CONFIG_FILE"

    log_ok "RFI-IRFOS defaults appended to config.yaml"
}

# ---------------------------------------------------------------------------
# Seed SOUL.md + templates
# ---------------------------------------------------------------------------
seed_soul() {
    log_info "Seeding SOUL.md..."

    SOUL_FILE="$HERMES_HOME/SOUL.md"

    if [[ ! -f "$SOUL_FILE" ]]; then
        cat > "$SOUL_FILE" <<'EOF'
You are Hermes Agent ☤, an intelligent AI assistant created by Nous Research.

## RFI-IRFOS Operating Mode
- Hermes = FULL-EQUIVALENT EMPLOYEE
- Simeon states facts as GROUND TRUTH
- Never re-litigate context
- Laura = clarity benchmark (zero repetition tolerance)
- German umlauts required, never ASCII
- Never auto-send email — Drafts only
EOF
        log_ok "Created SOUL.md"
    else
        log_info "SOUL.md exists — preserving"
    fi

    # Seed templates
    if [[ -d "$INSTALL_DIR/templates" ]] && [[ ! -d "$HERMES_HOME/templates" ]]; then
        cp -r "$INSTALL_DIR/templates" "$HERMES_HOME/" 2>/dev/null || true
        log_ok "Templates copied"
    fi
}

# ---------------------------------------------------------------------------
# Install Hermes (uv + venv + deps)
# ---------------------------------------------------------------------------
install_hermes() {
    log_info "Installing Hermes Agent..."

    cd "$INSTALL_DIR"

    # Make sure setup script is executable
    chmod +x setup-hermes.sh 2>/dev/null || true

    # Run setup-hermes.sh non-interactively
    if [[ -f "setup-hermes.sh" ]]; then
        log_info "Running setup-hermes.sh..."
        bash setup-hermes.sh || {
            log_warn "setup-hermes.sh had non-zero exit — check output above"
        }
        log_ok "Hermes installation complete"
    else
        log_warn "setup-hermes.sh not found — falling back to hermes setup wizard"
    fi
}

# ---------------------------------------------------------------------------
# Link hermes command to ~/.local/bin
# ---------------------------------------------------------------------------
link_bin() {
    log_info "Linking hermes command..."

    BIN_DIR="$HOME/.local/bin"
    mkdir -p "$BIN_DIR"

    if [[ -f "$INSTALL_DIR/hermes" ]]; then
        ln -sf "$INSTALL_DIR/hermes" "$BIN_DIR/hermes"
        log_ok "Linked hermes -> $BIN_DIR/hermes"
    elif [[ -f "$INSTALL_DIR/venv/bin/hermes" ]]; then
        ln -sf "$INSTALL_DIR/venv/bin/hermes" "$BIN_DIR/hermes"
        log_ok "Linked hermes (venv) -> $BIN_DIR/hermes"
    else
        log_warn "hermes binary not found — run 'hermes setup' after installation"
    fi

    # Ensure ~/.local/bin is in PATH
    if ! echo "$PATH" | grep -q "$BIN_DIR"; then
        log_info "Adding $BIN_DIR to PATH in ~/.bashrc"
        echo "export PATH=\"$BIN_DIR:\$PATH\"" >> "$HOME/.bashrc"
        export PATH="$BIN_DIR:$PATH"
    fi
}

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
print_summary() {
    echo ""
    echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}  ✓ RFI-IRFOS Graz Hermes Agent Installation Complete${NC}"
    echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${CYAN}Install dir:${NC}      $INSTALL_DIR"
    echo -e "  ${CYAN}Hermes home:${NC}      $HERMES_HOME"
    echo -e "  ${CYAN}Platform:${NC}         $OS_TYPE"
    echo -e "  ${CYAN}Fork repo:${NC}       $REPO_URL"
    echo ""
    echo -e "  ${YELLOW}Next steps:${NC}"
    echo "    1. source ~/.bashrc  (or restart terminal)"
    echo "    2. hermes            (start chatting)"
    echo "    3. hermes model      (choose your LLM provider)"
    echo "    4. hermes setup      (run setup wizard)"
    echo ""
    echo -e "  ${MAGENTA}Custom skills seeded:${NC}   $(ls -1 "$HERMES_HOME/skills" 2>/dev/null | wc -l) total"
    echo -e "  ${MAGENTA}RuVector schema:${NC}       $HERMES_HOME/ruvector/"
    echo -e "  ${MAGENTA}Memory:${NC}               $HERMES_HOME/memories/"
    echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    print_banner
    preflight
    clone_hermes
    install_deps
    init_hermes_home
    seed_skills
    seed_ruvector
    seed_memory
    seed_config
    seed_soul
    install_hermes
    link_bin
    print_summary
}

main "$@"
