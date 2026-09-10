#!/usr/bin/env bash
# Install pre-requisites for open-lakehouse.
#
# Usage:
#   bash scripts/tools/install-prereqs.sh         # check only
#   bash scripts/tools/install-prereqs.sh --auto  # attempt to install missing tools
#
# Supports macOS (homebrew), Debian/Ubuntu (apt), Fedora/RHEL (dnf/yum), Arch
# (pacman), and Windows Git Bash / MSYS2 (winget or chocolatey if available).
# The script never installs anything unless called with --auto.

set -euo pipefail

AUTO_INSTALL=false

for arg in "$@"; do
    case "$arg" in
        --auto) AUTO_INSTALL=true ;;
        -h|--help)
            echo "Usage: $(basename "$0") [--auto]"
            echo "  --auto  Attempt to install missing tools"
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            exit 1
            ;;
    esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

missing=()
installers=()

# -----------------------------------------------------------------------------
# Platform detection
# -----------------------------------------------------------------------------

OS="unknown"
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "win32" ]]; then
    OS="windows"
fi

if [[ "$OS" == "linux" ]]; then
    if command -v apt-get >/dev/null 2>&1; then
        DISTRO="debian"
    elif command -v dnf >/dev/null 2>&1; then
        DISTRO="fedora"
    elif command -v yum >/dev/null 2>&1; then
        DISTRO="rhel"
    elif command -v pacman >/dev/null 2>&1; then
        DISTRO="arch"
    else
        DISTRO="unknown"
    fi
fi

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

check_cmd() {
    command -v "$1" >/dev/null 2>&1
}

note_missing() {
    local tool="$1"
    local install_note="$2"
    missing+=("$tool")
    installers+=("$install_note")
}

print_summary() {
    if [ ${#missing[@]} -eq 0 ]; then
        echo -e "${GREEN}All pre-requisites are installed.${NC}"
        return 0
    fi

    echo -e "${YELLOW}Missing tools:${NC}"
    for i in "${!missing[@]}"; do
        echo -e "  ${RED}✗${NC} ${missing[$i]}"
        echo -e "      ${BLUE}→${NC} ${installers[$i]}"
    done

    if [ "$AUTO_INSTALL" != true ]; then
        echo ""
        echo "Run with --auto to let this script attempt the installs."
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Install helpers per platform
# -----------------------------------------------------------------------------

install_brew() {
    local pkg="$1"
    if check_cmd brew; then
        brew install "$pkg"
    else
        echo -e "${RED}Homebrew not found. Install it first: https://brew.sh${NC}" >&2
        return 1
    fi
}

install_apt() {
    local pkg="$1"
    echo -e "${YELLOW}Installing $pkg via apt...${NC}"
    sudo apt-get update
    sudo apt-get install -y "$pkg"
}

install_dnf() {
    local pkg="$1"
    echo -e "${YELLOW}Installing $pkg via dnf...${NC}"
    sudo dnf install -y "$pkg"
}

install_yum() {
    local pkg="$1"
    echo -e "${YELLOW}Installing $pkg via yum...${NC}"
    sudo yum install -y "$pkg"
}

install_pacman() {
    local pkg="$1"
    echo -e "${YELLOW}Installing $pkg via pacman...${NC}"
    sudo pacman -S --noconfirm "$pkg"
}

install_winget() {
    local id="$1"
    if check_cmd winget; then
        winget install --id "$id" --source winget --accept-package-agreements --accept-source-agreements
    else
        return 1
    fi
}

install_choco() {
    local pkg="$1"
    if check_cmd choco; then
        choco install "$pkg" -y
    else
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Tool checks and installers
# -----------------------------------------------------------------------------

check_docker() {
    if check_cmd docker && docker compose version >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} docker + compose"
        return 0
    fi

    if check_cmd docker && docker-compose version >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} docker + docker-compose"
        return 0
    fi

    note_missing "docker / docker compose" "https://docs.docker.com/get-docker/"
    if [ "$AUTO_INSTALL" != true ]; then
        return 0
    fi

    case "$OS" in
        macos) install_brew docker ;;
        linux)
            case "$DISTRO" in
                debian)
                    echo -e "${YELLOW}Installing Docker via the official convenience script...${NC}"
                    curl -fsSL https://get.docker.com | sh
                    sudo usermod -aG docker "${USER}" || true
                    ;;
                fedora) sudo dnf install -y docker-compose docker ;;
                rhel) sudo yum install -y docker-compose docker ;;
                arch) sudo pacman -S --noconfirm docker docker-compose ;;
            esac
            ;;
        windows)
            install_winget "Docker.DockerDesktop" || install_choco "docker-desktop" || {
                echo -e "${RED}Please install Docker Desktop manually.${NC}" >&2
                return 1
            }
            ;;
    esac
}

check_poetry() {
    if check_cmd poetry; then
        echo -e "  ${GREEN}✓${NC} poetry"
        return 0
    fi
    note_missing "poetry" "pip install poetry  ->  https://python-poetry.org/docs/#installation"
    if [ "$AUTO_INSTALL" != true ]; then return 0; fi

    curl -sSL https://install.python-poetry.org | python3 -
}

check_just() {
    if check_cmd just; then
        echo -e "  ${GREEN}✓${NC} just"
        return 0
    fi
    note_missing "just" "https://github.com/casey/just"
    if [ "$AUTO_INSTALL" != true ]; then return 0; fi

    case "$OS" in
        macos) install_brew just ;;
        linux)
            case "$DISTRO" in
                debian)
                    curl -q 'https://proget.makedeb.org/debian-feeds/prebuilt-mpr.pub' | gpg --dearmor | sudo tee /usr/share/keyrings/prebuilt-mpr-archive-keyring.gpg >/dev/null
                    echo "deb [signed-by=/usr/share/keyrings/prebuilt-mpr-archive-keyring.gpg] https://proget.makedeb.org prebuilt-mpr $(lsb_release -cs)" | sudo tee /etc/apt/sources.list.d/prebuilt-mpr.list
                    sudo apt-get update
                    sudo apt-get install -y just
                    ;;
                fedora) sudo dnf install -y just ;;
                rhel) sudo yum install -y just ;;
                arch) sudo pacman -S --noconfirm just ;;
            esac
            ;;
        windows)
            install_winget "Casey.Just" || install_choco "just" || {
                echo -e "${RED}Please install just manually.${NC}" >&2
                return 1
            }
            ;;
    esac
}

check_terraform() {
    if check_cmd terraform; then
        echo -e "  ${GREEN}✓${NC} terraform"
        return 0
    fi
    note_missing "terraform" "https://developer.hashicorp.com/terraform/install"
    if [ "$AUTO_INSTALL" != true ]; then return 0; fi

    case "$OS" in
        macos) install_brew terraform ;;
        linux)
            local tf_version="1.9.8"
            local tf_zip="terraform_${tf_version}_linux_amd64.zip"
            curl -fsSLO "https://releases.hashicorp.com/terraform/${tf_version}/${tf_zip}"
            unzip -o "$tf_zip" -d /tmp
            sudo mv /tmp/terraform /usr/local/bin/terraform
            rm -f "$tf_zip"
            ;;
        windows)
            install_winget "HashiCorp.Terraform" || install_choco "terraform" || {
                echo -e "${RED}Please install Terraform manually.${NC}" >&2
                return 1
            }
            ;;
    esac
}

check_az() {
    if check_cmd az; then
        echo -e "  ${GREEN}✓${NC} azure-cli"
        return 0
    fi
    note_missing "azure-cli" "https://learn.microsoft.com/en-us/cli/azure/install-azure-cli"
    if [ "$AUTO_INSTALL" != true ]; then return 0; fi

    case "$OS" in
        macos) install_brew azure-cli ;;
        linux)
            case "$DISTRO" in
                debian)
                    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
                    ;;
                fedora)
                    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
                    sudo dnf install -y https://packages.microsoft.com/config/rhel/9/packages-microsoft-prod.rpm
                    sudo dnf install -y azure-cli
                    ;;
                rhel)
                    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
                    sudo yum install -y https://packages.microsoft.com/config/rhel/9/packages-microsoft-prod.rpm
                    sudo yum install -y azure-cli
                    ;;
                arch)
                    echo -e "${YELLOW}Installing azure-cli from AUR helper (yay) if available...${NC}"
                    if check_cmd yay; then yay -S --noconfirm azure-cli; else echo -e "${RED}Install azure-cli manually.${NC}" >&2; return 1; fi
                    ;;
            esac
            ;;
        windows)
            install_winget "Microsoft.AzureCLI" || install_choco "azure-cli" || {
                echo -e "${RED}Please install Azure CLI manually.${NC}" >&2
                return 1
            }
            ;;
    esac
}

check_java() {
    if check_cmd java && [ "$(java -version 2>&1 | awk -F'"' '/version/ {print $2}' | cut -d'.' -f1)" -ge 17 ] 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} java 17+"
        return 0
    fi
    note_missing "java 17+" "Install a JDK (Temurin/Adoptium recommended)"
    if [ "$AUTO_INSTALL" != true ]; then return 0; fi

    case "$OS" in
        macos) install_brew temurin || install_brew openjdk ;;
        linux)
            case "$DISTRO" in
                debian) sudo apt-get install -y default-jdk ;;
                fedora) sudo dnf install -y java-21-openjdk ;;
                rhel) sudo yum install -y java-21-openjdk ;;
                arch) sudo pacman -S --noconfirm jre21-openjdk ;;
            esac
            ;;
        windows)
            install_winget "EclipseAdoptium.Temurin.21.JDK" || install_choco "temurin21jre" || {
                echo -e "${RED}Please install a JDK manually.${NC}" >&2
                return 1
            }
            ;;
    esac
}

check_psql() {
    if check_cmd psql; then
        echo -e "  ${GREEN}✓${NC} psql"
        return 0
    fi
    note_missing "psql (postgresql-client)" "Needed for local DB setup and health checks"
    if [ "$AUTO_INSTALL" != true ]; then return 0; fi

    case "$OS" in
        macos) install_brew libpq ;;
        linux)
            case "$DISTRO" in
                debian) sudo apt-get install -y postgresql-client ;;
                fedora) sudo dnf install -y postgresql ;;
                rhel) sudo yum install -y postgresql ;;
                arch) sudo pacman -S --noconfirm postgresql-libs ;;
            esac
            ;;
        windows)
            install_winget "PostgreSQL.pgAdmin" || install_choco "postgresql" || {
                echo -e "${RED}Please install psql manually.${NC}" >&2
                return 1
            }
            ;;
    esac
}

check_shellcheck() {
    if check_cmd shellcheck; then
        echo -e "  ${GREEN}✓${NC} shellcheck"
        return 0
    fi
    note_missing "shellcheck" "Optional linter for shell scripts"
    if [ "$AUTO_INSTALL" != true ]; then return 0; fi

    case "$OS" in
        macos) install_brew shellcheck ;;
        linux)
            case "$DISTRO" in
                debian) sudo apt-get install -y shellcheck ;;
                fedora) sudo dnf install -y ShellCheck ;;
                rhel) sudo yum install -y epel-release && sudo yum install -y ShellCheck ;;
                arch) sudo pacman -S --noconfirm shellcheck ;;
            esac
            ;;
        windows)
            install_winget "koalaman.shellcheck" || install_choco "shellcheck" || {
                echo -e "${RED}Please install shellcheck manually.${NC}" >&2
                return 1
            }
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

echo -e "${BLUE}Checking open-lakehouse pre-requisites (${OS})${NC}"
echo ""

check_docker
check_poetry
check_just
check_terraform
check_az
check_java
check_psql
check_shellcheck

echo ""
print_summary
