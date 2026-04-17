#!/bin/bash

# ==============================================================================
# Path Configuration
# ==============================================================================
SIGMA_TOOL_DIR="/home/rtk/Documents/sigma_tool"
WFA_DIR="/tmp/wfa"
WFA_SCRIPT="./wfa_test.sh"
LINUX_STABLE_DIR="/home/rtk/Documents/linux-stable"
HOSTAP_DIR="/home/rtk/Documents/hostap-wfa26/hostap"
RELOAD_SCRIPT="./reload_all.sh"

# Monitoring Constants
DRIVER_NAME="rtw89"

# ==============================================================================
# Global Configuration & Visual Styles
# ==============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

BG_WHITE_FG_GREEN='\033[100;32;1m' # White BG (47) + Green FG (32) + Bold (1)
BG_WHITE_FG_RED='\033[100;31;1m'   # White BG (47) + Red FG (31) + Bold (1)

ICON_INFO="${BLUE}ℹ${NC}"
ICON_SUCCESS="${GREEN}✔${NC}"
ICON_WARN="${YELLOW}⚠${NC}"
ICON_ERROR="${RED}✖${NC}"

# ==============================================================================
# Helper Functions (Logging & UI)
# ==============================================================================
log_info()    { echo -e "${CYAN}[ INFO    ]${NC} ${CYAN}$1${NC}"; }
log_success() { echo -e "${GREEN}[ SUCCESS ]${NC} ${GREEN}$1${NC}"; }
log_warn()    { echo -e "${YELLOW}[ WARNING ]${NC} ${YELLOW}$1${NC}"; }
log_error()   { echo -e "${RED}[ ERROR   ]${NC} ${RED}$1${NC}"; }

print_banner() {
    echo -e "${PURPLE}┌────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${PURPLE}│${NC}  ${BOLD}${WHITE}SIGMA TOOL - 2026 FR Edition${NC}                                      ${PURPLE}│${NC}"
    echo -e "${PURPLE}└────────────────────────────────────────────────────────────────────┘${NC}"
}

# ==============================================================================
# Privilege Management
# ==============================================================================
init_sudo() {
    log_warn "This script requires administrative privileges."
    sudo -v
    # Keep-alive: update existing sudo time stamp until script has finished
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
    log_success "Sudo privilege authenticated."
}

# ==============================================================================
# Core Action Functions
# ==============================================================================

do_status() {
    local SYSTEM_HEALTH=1 # 1 means OK, 0 means Error

    # 1. Kernel Module Check
    echo -e "\n${BOLD}${WHITE}1. Kernel Module ($DRIVER_NAME):${NC}"
    if lsmod | grep -q "$DRIVER_NAME"; then
        echo -e "   Status: ${GREEN}✔ Loaded${NC}"
        lsmod | grep "$DRIVER_NAME" | sed 's/^/   /'
    else
        echo -e "   Status: ${RED}✖ Not Found${NC}"
        SYSTEM_HEALTH=0
    fi

    # 2. Core WFA Processes Check
    echo -e "\n${BOLD}${WHITE}2. WFA Components Status:${NC}"
    DUT_PID=$(pgrep "wfa_dut" | xargs)
    if [ -n "$DUT_PID" ]; then echo -e "   [ ${GREEN}OK${NC} ] wfa_dut is running (PID: $DUT_PID)"; else echo -e "   [ ${RED}!!${NC} ] wfa_dut is ${RED}MISSING${NC}"; SYSTEM_HEALTH=0; fi

    CA_PID=$(pgrep "wfa_ca" | xargs)
    if [ -n "$CA_PID" ]; then echo -e "   [ ${GREEN}OK${NC} ] wfa_ca  is running (PID: $CA_PID)"; else echo -e "   [ ${RED}!!${NC} ] wfa_ca  is ${RED}MISSING${NC}"; SYSTEM_HEALTH=0; fi

    WPAS_PID=$(pgrep "wpa_supplicant" | xargs)
    if [ -n "$WPAS_PID" ]; then echo -e "   [ ${GREEN}OK${NC} ] wpa_supplicant is running (PID: $WPAS_PID)"; else echo -e "   [ ${RED}!!${NC} ] wpa_supplicant is ${RED}MISSING${NC}"; SYSTEM_HEALTH=0; fi

    # 3. Network Ports Check
    echo -e "\n${BOLD}${WHITE}3. Port Listening:${NC}"
    if command -v ss >/dev/null; then
        DUT_PORT=$(ss -tunlp | grep :8000)
        CA_PORT=$(ss -tunlp | grep :9000)
    else
        DUT_PORT=$(netstat -tunlp | grep :8000)
        CA_PORT=$(netstat -tunlp | grep :9000)
    fi
    if [ -n "$DUT_PORT" ]; then echo -e "   Port 8000 (DUT): ${GREEN}LISTEN${NC}"; else echo -e "   Port 8000 (DUT): ${RED}CLOSED${NC}"; SYSTEM_HEALTH=0; fi
    if [ -n "$CA_PORT" ]; then echo -e "   Port 9000 (CA) : ${GREEN}LISTEN${NC}"; else echo -e "   Port 9000 (CA) : ${RED}CLOSED${NC}"; SYSTEM_HEALTH=0; fi

    # 4. WFA CA Device Info Validation
    echo -e "\n${BOLD}${WHITE}4. WFA CA Device Info Validation:${NC}"
    if [ -n "$CA_PORT" ]; then
        DEVICE_INFO=$(echo -e "device_get_info\r\n" | nc -w 2 localhost 9000 2>/dev/null)
        if echo "$DEVICE_INFO" | grep -q "status,COMPLETE"; then
            INFO_LINE=$(echo "$DEVICE_INFO" | grep "status,COMPLETE" | tr -d '\r')
            echo -e "   [ ${GREEN}OK${NC} ] Device: ${CYAN}$INFO_LINE${NC}"
        else
            echo -e "   [ ${RED}!!${NC} ] Failed or incomplete response from CA."
            SYSTEM_HEALTH=0
        fi
    else
        echo -e "   [ ${RED}!!${NC} ] Cannot fetch info (Port 9000 is closed)."
        SYSTEM_HEALTH=0
    fi

    # 5. Git Repository Status
    echo -e "\n${BOLD}${WHITE}5. Git Repository Status:${NC}"
    for dir in "$LINUX_STABLE_DIR" "$HOSTAP_DIR"; do
        # Check if directory exists
        if [ ! -d "$dir" ]; then
            echo -e "   [ ${RED}!!${NC} ] Directory not found: $dir"
            SYSTEM_HEALTH=0
            continue
        fi

        # Find the absolute root path of the git repository for this directory
        # This gracefully handles subdirectories (like wpa_supplicant) inside submodules (like hostap)
        REPO_ROOT=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)

        if [ -n "$REPO_ROOT" ]; then
            # Query branch and commit using the discovered root path
            local BRANCH=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)
            local COMMIT=$(git -C "$REPO_ROOT" log -1 --format="%h - %s (%cr)" 2>/dev/null)
            local REPO_NAME=$(basename "$REPO_ROOT")
            local TARGET_DIR=$(basename "$dir")
            
            # Format UI display name (e.g., hostap -> wpa_supplicant)
            local DISPLAY_NAME="$REPO_NAME"
            if [ "$REPO_NAME" != "$TARGET_DIR" ]; then
                DISPLAY_NAME="${REPO_NAME} -> ${TARGET_DIR}"
            fi
            
            echo -e "   [ ${BLUE}${DISPLAY_NAME}${NC} ]"
            echo -e "     Branch: ${GREEN}${BRANCH}${NC}"
            echo -e "     Latest: ${WHITE}${COMMIT}${NC}"
        else
            echo -e "   [ ${RED}!!${NC} ] Git metadata not found for path: $dir"
            SYSTEM_HEALTH=0
        fi
    done

    # 6. Debug Snippet
    echo -e "\n${BOLD}${WHITE}6. Latest Kernel Debug Messages:${NC}"
    sudo dmesg | grep -E "$DRIVER_NAME" | tail -n 5 | sed 's/^/   /'
    echo ""

    # Return status code based on health
    if [ "$SYSTEM_HEALTH" -eq 1 ]; then
        return 0
    else
        return 1
    fi
}

do_info() {
    log_info "Fetching device info from WFA CA (Port 9000)..."

    if command -v ss >/dev/null; then
        CA_PORT_STATUS=$(ss -tunl | grep :9000)
    else
        CA_PORT_STATUS=$(netstat -tunl | grep :9000)
    fi

    if [ -z "$CA_PORT_STATUS" ]; then
        log_error "WFA CA (Port 9000) is not listening."
        log_warn "Please ensure the WFA service is running (use 'start' or 'boot')."
        return 1
    fi

    DEVICE_INFO=$(echo -e "device_get_info\r\n" | nc -w 2 localhost 9000 2>/dev/null)

    if [ -n "$DEVICE_INFO" ]; then
        log_success "Device Info Received:"
        echo -e "${CYAN}${DEVICE_INFO}${NC}"
    else
        log_warn "No response received. The CA might be unresponsive."
        return 1
    fi
}

do_boot() {
    log_info "Executing boot sequence (Driver Reload)..."
    if cd "$LINUX_STABLE_DIR"; then
        log_info "Running reload script: $RELOAD_SCRIPT"
        sudo $RELOAD_SCRIPT
        log_success "Driver modules reloaded."
    else
        log_error "Failed to access directory: $LINUX_STABLE_DIR"
        return 1
    fi
    do_start
}

do_stop() {
    log_info "Initiating shutdown of services..."
    if cd "$WFA_DIR"; then
        sudo $WFA_SCRIPT stop
        log_success "Service stop signal sent to $WFA_SCRIPT."
    else
        log_error "Could not access WFA directory: $WFA_DIR"
        return 1
    fi
}

do_start() {
    log_info "Step 1: Switching to project directory..."
    if cd "$SIGMA_TOOL_DIR"; then
        echo -e "          ${WHITE}→ Path:${NC} ${BLUE}$(pwd)${NC}"
    else
        log_error "Failed to access directory: $SIGMA_TOOL_DIR"
        return 1
    fi

    log_info "Step 2: Running 'make install'..."
    if sudo make install; then
        log_success "Build and installation completed successfully."
    else
        log_error "Make install failed. Execution aborted."
        return 1
    fi

    log_info "Step 3: Triggering WFA test script..."
    if cd "$WFA_DIR"; then
        if sudo $WFA_SCRIPT start-sta; then
            log_success "WFA service is now UP and RUNNING."
        else
            log_error "WFA script execution failed."
            return 1
        fi
    else
        log_error "Could not find WFA directory: $WFA_DIR"
        return 1
    fi

    # Perform Self-Environment Check
    log_info "Step 4: Performing Self-Environment Check..."
    sleep 2 # Give WFA CA 2 seconds to bind port 9000 and become fully responsive
    do_status
    # The return value of do_status will be implicitly returned by do_start
}

do_restart() {
    log_warn "Restarting the services (Stop -> Boot -> Start)..."
    do_stop
    sleep 1
    do_boot
}

# ==============================================================================
# Main Entry Point
# ==============================================================================
main() {
    if [ -z "$1" ]; then
        echo -e "${RED}Usage:${NC} $0 {boot|start|stop|restart|status|info}"
        exit 1
    fi

    init_sudo
    print_banner

    START_TIME=$(date +%s)
    CMD_EXIT=0

    case "$1" in
        "boot")    do_boot; CMD_EXIT=$? ;;
        "start")   do_start; CMD_EXIT=$? ;;
        "stop")    do_stop; CMD_EXIT=$? ;;
        "restart") do_restart; CMD_EXIT=$? ;;
        "status")  
            log_info "Checking Sigma Tool Environment Status..."
            do_status; CMD_EXIT=$? 
            ;;
        "info")    do_info; CMD_EXIT=$? ;;
        *)
            log_error "Invalid parameter: $1"
            echo "Usage: $0 {boot|start|stop|restart|status|info}"
            exit 1
            ;;
    esac

    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    echo -e "\n"
    # Dynamic footer color based on execution success/failure
    if [ "$CMD_EXIT" -eq 0 ]; then
        echo -e "${GREEN}${ICON_SUCCESS}${NC}  ${BG_WHITE_FG_GREEN}Execution Finished Successfully / ALL SYSTEMS GO${NC}"
        echo -e "${GREEN}│${NC}"
        echo -e "${GREEN}├─${NC} Command  : ${CYAN}$1${NC}"
        echo -e "${GREEN}├─${NC} Duration : ${DURATION}s"
        echo -e "${GREEN}└────────────────────────────────────────────────────────────────────${NC}"
    else
        echo -e "${RED}${ICON_ERROR}${NC}  ${BG_WHITE_FG_RED}Execution Finished With Errors / ENVIRONMENT NOT READY${NC}"
        echo -e "${RED}│${NC}"
        echo -e "${RED}├─${NC} Command  : ${CYAN}$1${NC}"
        echo -e "${RED}├─${NC} Duration : ${DURATION}s"
        echo -e "${RED}└────────────────────────────────────────────────────────────────────${NC}"
    fi
    exit $CMD_EXIT
}

main "$@"