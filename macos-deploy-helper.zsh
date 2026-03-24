#!/bin/zsh

#
# macos-deploy-helper.zsh
# v1.0
#
# Commonly used macOS system configuration commands
# Grant run permissions with "chmod +x '/path/to/macos-deploy-helper.zsh'"
#
# - Brandon Thomas (me@brandonthomas.net), January 2026
#

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_NAME="$(basename "$0")"
MIN_MACOS_VERSION="26.0"

autoload -Uz colors && colors

COLOR_RED="%{$fg[red]%}"
COLOR_GREEN="%{$fg[green]%}"
COLOR_YELLOW="%{$fg[yellow]%}"
COLOR_BLUE="%{$fg[blue]%}"
COLOR_BOLD="%{$fg_bold[white]%}"
COLOR_RESET="%{$reset_color%}"

typeset -ga SETTINGS_KEYS
typeset -gA SETTINGS_CATEGORY=()
typeset -gA SETTINGS_TITLE=()
typeset -gA SETTINGS_RECOMMENDED_VALUE=()
typeset -gA SETTINGS_STATUS_TYPE=()
typeset -gA SETTINGS_STATUS_COMMAND=()
typeset -gA SETTINGS_APPLY_COMMAND=()
typeset -gA SETTINGS_REQUIRES_SUDO=()
typeset -gA SETTINGS_MIN_MACOS_VERSION=()
typeset -gA SETTINGS_OPEN_COMMAND=()
typeset -gA SETTINGS_RESTART_TARGET=()

typeset -ga RESTART_TARGETS
SUDO_REQUIRED="false"
SUDO_STARTED="false"

add_restart_target() {
    local restart_target="$1"
    local existing_target

    for existing_target in "${RESTART_TARGETS[@]}"; do
        if [[ "$existing_target" == "$restart_target" ]]; then
            return 0
        fi
    done

    RESTART_TARGETS+=("$restart_target")
}

add_setting() {
    local setting_id="$1"
    local setting_category="$2"
    local setting_title="$3"
    local setting_recommended_value="$4"
    local setting_status_type="$5"
    local setting_status_command="$6"
    local setting_apply_command="$7"
    local setting_requires_sudo="$8"
    local setting_min_macos_version="$9"
    local setting_open_command="${10}"
    local setting_restart_target="${11}"

    SETTINGS_KEYS+=("$setting_id")
    SETTINGS_CATEGORY+=("$setting_id" "$setting_category")
    SETTINGS_TITLE+=("$setting_id" "$setting_title")
    SETTINGS_RECOMMENDED_VALUE+=("$setting_id" "$setting_recommended_value")
    SETTINGS_STATUS_TYPE+=("$setting_id" "$setting_status_type")
    SETTINGS_STATUS_COMMAND+=("$setting_id" "$setting_status_command")
    SETTINGS_APPLY_COMMAND+=("$setting_id" "$setting_apply_command")
    SETTINGS_REQUIRES_SUDO+=("$setting_id" "$setting_requires_sudo")
    SETTINGS_MIN_MACOS_VERSION+=("$setting_id" "$setting_min_macos_version")
    SETTINGS_OPEN_COMMAND+=("$setting_id" "$setting_open_command")
    SETTINGS_RESTART_TARGET+=("$setting_id" "$setting_restart_target")
}

# ============================================================
# Centralized settings registry
# ============================================================

add_setting \
    "dock_autohide_delay" \
    "Dock" \
    "Remove delay before showing Dock" \
    "0" \
    "command" \
    'defaults read com.apple.dock autohide-delay 2>/dev/null || echo "__MISSING__"' \
    'defaults write com.apple.dock autohide-delay -float 0' \
    "false" \
    "26.0" \
    "" \
    "Dock"


add_setting \
    "dock_show_hidden" \
    "Dock" \
    "Show hidden apps" \
    "1" \
    "command" \
    'defaults read com.apple.dock showhidden 2>/dev/null || echo "__MISSING__"' \
    'defaults write com.apple.dock showhidden -bool true' \
    "false" \
    "26.0" \
    "" \
    "Dock"

add_setting \
    "dock_autohide" \
    "Dock" \
    "Automatically hide and show the Dock" \
    "1" \
    "command" \
    'defaults read com.apple.dock autohide 2>/dev/null || echo "__MISSING__"' \
    'defaults write com.apple.dock autohide -bool true' \
    "false" \
    "26.0" \
    "" \
    "Dock"


add_setting \
    "finder_show_hidden_files" \
    "Finder" \
    "Show hidden files" \
    "1" \
    "command" \
    'defaults read com.apple.finder AppleShowAllFiles 2>/dev/null || echo "__MISSING__"' \
    'defaults write com.apple.finder AppleShowAllFiles -bool true' \
    "false" \
    "26.0" \
    "" \
    "Finder"


add_setting \
    "desktopservices_dont_write_network_stores" \
    "Finder" \
    "Avoid .DS_Store files on network shares" \
    "1" \
    "command" \
    'defaults read com.apple.desktopservices DSDontWriteNetworkStores 2>/dev/null || echo "__MISSING__"' \
    'defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true' \
    "false" \
    "26.0" \
    "" \
    ""

add_setting \
    "finder_show_all_filename_extensions" \
    "Finder" \
    "Show all filename extensions" \
    "1" \
    "command" \
    'defaults read NSGlobalDomain AppleShowAllExtensions 2>/dev/null || echo "__MISSING__"' \
    'defaults write NSGlobalDomain AppleShowAllExtensions -bool true' \
    "false" \
    "26.0" \
    "" \
    "Finder"

add_setting \
    "finder_show_status_bar" \
    "Finder" \
    "Show status bar" \
    "1" \
    "command" \
    'defaults read com.apple.finder ShowStatusBar 2>/dev/null || echo "__MISSING__"' \
    'defaults write com.apple.finder ShowStatusBar -bool true' \
    "false" \
    "26.0" \
    "" \
    "Finder"

add_setting \
    "finder_show_path_bar" \
    "Finder" \
    "Show path bar" \
    "1" \
    "command" \
    'defaults read com.apple.finder ShowPathbar 2>/dev/null || echo "__MISSING__"' \
    'defaults write com.apple.finder ShowPathbar -bool true' \
    "false" \
    "26.0" \
    "" \
    "Finder"

add_setting \
    "finder_new_window_home_folder" \
    "Finder" \
    "New Finder windows show home folder" \
    "PfHm|file://${HOME}/" \
    "command" \
    'printf "%s|%s" "$(defaults read com.apple.finder NewWindowTarget 2>/dev/null || echo "__MISSING__")" "$(defaults read com.apple.finder NewWindowTargetPath 2>/dev/null || echo "__MISSING__")"' \
    'defaults write com.apple.finder NewWindowTarget -string "PfHm" && defaults write com.apple.finder NewWindowTargetPath -string "file://${HOME}/"' \
    "false" \
    "26.0" \
    "" \
    "Finder"

add_setting \
    "safari_include_develop_menu" \
    "Safari" \
    "Show Develop menu" \
    "1" \
    "command" \
    'defaults read com.apple.Safari IncludeDevelopMenu 2>/dev/null || echo "__MISSING__"' \
    'defaults write com.apple.Safari IncludeDevelopMenu -bool true' \
    "false" \
    "26.0" \
    "" \
    "Safari"


add_setting \
    "safari_show_overlay_status_bar" \
    "Safari" \
    "Show overlay status bar on link hover" \
    "1" \
    "command" \
    'defaults read com.apple.Safari ShowOverlayStatusBar 2>/dev/null || echo "__MISSING__"' \
    'defaults write com.apple.Safari ShowOverlayStatusBar -bool true' \
    "false" \
    "26.0" \
    "" \
    "Safari"

add_setting \
    "terminal_secure_keyboard_entry" \
    "Terminal" \
    "Secure Keyboard Entry" \
    "1" \
    "command" \
    'defaults read com.apple.Terminal SecureKeyboardEntry 2>/dev/null || echo "__MISSING__"' \
    'defaults write com.apple.Terminal SecureKeyboardEntry -bool true' \
    "false" \
    "26.0" \
    "" \
    "Terminal"

add_setting \
    "gatekeeper_master_status" \
    "Security" \
    "Allow apps from any source" \
    "assessments disabled" \
    "command" \
    'spctl --status 2>/dev/null | tr "[:upper:]" "[:lower:]" || echo "__ERROR__"' \
    'sudo spctl --master-disable' \
    "true" \
    "26.0" \
    "" \
    ""

add_setting \
    "system_computer_name" \
    "Network & Hostname" \
    "Friendly Name" \
    "NewName" \
    "info" \
    'scutil --get ComputerName 2>/dev/null || echo "__MISSING__"' \
    'sudo scutil --set ComputerName "NewName"' \
    "true" \
    "26.0" \
    "" \
    ""

add_setting \
    "system_host_name" \
    "Network & Hostname" \
    "Host Name" \
    "NewName" \
    "info" \
    'scutil --get HostName 2>/dev/null || echo "__MISSING__"' \
    'sudo scutil --set HostName "NewName"' \
    "true" \
    "26.0" \
    "" \
    ""

add_setting \
    "system_local_host_name" \
    "Network & Hostname" \
    "Local Host Name" \
    "NewName" \
    "info" \
    'scutil --get LocalHostName 2>/dev/null || echo "__MISSING__"' \
    'sudo scutil --set LocalHostName "NewName"' \
    "true" \
    "26.0" \
    "" \
    ""

add_setting \
    "developer_homebrew_installed" \
    "Homebrew & Dev Tools" \
    "Homebrew installed" \
    "installed" \
    "command" \
    'if command -v brew >/dev/null 2>&1; then echo "installed"; else echo "not installed"; fi' \
    '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' \
    "false" \
    "26.0" \
    "" \
    ""

add_setting \
    "developer_xcode_cli_installed" \
    "Homebrew & Dev Tools" \
    "Xcode Command Line Tools installed" \
    "installed" \
    "command" \
    'if xcode-select -p >/dev/null 2>&1; then echo "installed"; else echo "not installed"; fi' \
    'xcode-select --install' \
    "false" \
    "26.0" \
    "" \
    ""

add_setting \
    "textedit_open_blank_file" \
    "TextEdit" \
    "Open blank file on launch" \
    "0" \
    "command" \
    'defaults read com.apple.TextEdit NSShowAppCentricOpenPanelInsteadOfUntitledFile 2>/dev/null || echo "__MISSING__"' \
    'defaults write com.apple.TextEdit NSShowAppCentricOpenPanelInsteadOfUntitledFile -bool false' \
    "false" \
    "26.0" \
    "" \
    "TextEdit"

add_setting \
    "textedit_plain_text_default" \
    "TextEdit" \
    "Default to plain text" \
    "0" \
    "command" \
    'defaults read com.apple.TextEdit RichText 2>/dev/null || echo "__MISSING__"' \
    'defaults write com.apple.TextEdit RichText -int 0' \
    "false" \
    "26.0" \
    "" \
    "TextEdit"

add_setting \
    "system_prefer_tabs_always" \
    "System Settings" \
    "Prefer tabs: Always" \
    "manual" \
    "manual" \
    'echo "manual"' \
    'open "x-apple.systempreferences:com.apple.Desktop-Settings.extension"' \
    "false" \
    "26.0" \
    'open "x-apple.systempreferences:com.apple.Desktop-Settings.extension"' \
    ""

add_setting \
    "time_machine_configure" \
    "System Settings" \
    "Time Machine: Configure as needed" \
    "manual" \
    "manual" \
    'echo "manual"' \
    'open "x-apple.systempreferences:com.apple.TimeMachine-Settings.extension"' \
    "false" \
    "26.0" \
    'open "x-apple.systempreferences:com.apple.TimeMachine-Settings.extension"' \
    ""

add_setting \
    "keyboard_backlight_timeout" \
    "System Settings" \
    "Backlight off after inactivity: 30 seconds" \
    "manual" \
    "manual" \
    'echo "manual"' \
    'open "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"' \
    "false" \
    "26.0" \
    'open "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"' \
    ""

add_setting \
    "keyboard_key_repeat" \
    "System Settings" \
    "Key repeat & speed" \
    "manual" \
    "manual" \
    'echo "manual"' \
    'open "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"' \
    "false" \
    "26.0" \
    'open "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"' \
    ""

add_setting \
    "display_night_shift" \
    "System Settings" \
    "Night Shift: Sunrise to Sunset" \
    "manual" \
    "manual" \
    'echo "manual"' \
    'open "x-apple.systempreferences:com.apple.Displays-Settings.extension"' \
    "false" \
    "26.0" \
    'open "x-apple.systempreferences:com.apple.Displays-Settings.extension"' \
    ""

add_setting \
    "display_theme_auto" \
    "System Settings" \
    "Theme: Auto" \
    "manual" \
    "manual" \
    'echo "manual"' \
    'open "x-apple.systempreferences:com.apple.Appearance-Settings.extension"' \
    "false" \
    "26.0" \
    'open "x-apple.systempreferences:com.apple.Appearance-Settings.extension"' \
    ""

add_setting \
    "display_icons_dark_auto" \
    "System Settings" \
    "Icons: Dark (Auto)" \
    "manual" \
    "manual" \
    'echo "manual"' \
    'open "x-apple.systempreferences:com.apple.Appearance-Settings.extension"' \
    "false" \
    "26.0" \
    'open "x-apple.systempreferences:com.apple.Appearance-Settings.extension"' \
    ""

print_header() {
    echo
    print -P "${COLOR_BOLD}macOS Deployment Setup${COLOR_RESET}"
    echo "Minimum macOS version: ${MIN_MACOS_VERSION}"
    echo "Select an option:"
    echo "(1) Apply recommended settings"
    echo "(2) Apply individual settings"
    echo "(3) Get current status of all settings"
    echo "(4) Gatekeeper: disable (allow any source)"
    echo "(5) Gatekeeper: enable"
    echo "(6) Quit"
    echo
}

open_full_disk_access_settings() {
    open "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"
}

require_full_disk_access_confirmation() {
    echo
    print -P "${COLOR_YELLOW}Preflight Required${COLOR_RESET}"
    echo "Confirm this app has Full Disk Access before continuing:"
    echo "  - Terminal"
    echo
    echo "System Settings > Privacy & Security > Full Disk Access"
    echo

    while true; do
        printf "Open Full Disk Access settings now? [Y/N]: "
        read -r open_choice
        case "${open_choice:l}" in
            y|yes)
                open_full_disk_access_settings
                break
                ;;
            n|no)
                break
                ;;
            *)
                echo "Please enter Y or N."
                ;;
        esac
    done

    while true; do
        printf "Have you confirmed Terminal has Full Disk Access? [Y/N]: "
        read -r confirmed_choice
        case "${confirmed_choice:l}" in
            y|yes)
                return 0
                ;;
            n|no)
                echo "Exiting without changes."
                return 1
                ;;
            *)
                echo "Please enter Y or N."
                ;;
        esac
    done
}

get_current_macos_version() {
    sw_vers -productVersion | awk -F. '{print $1 "." $2}'
}

version_to_number() {
    local version_string="$1"
    local major_part minor_part

    major_part="${version_string%%.*}"
    minor_part="${version_string#*.}"

    if [[ "$minor_part" == "$version_string" ]]; then
        minor_part="0"
    fi

    printf '%d%03d\n' "$major_part" "$minor_part"
}

is_supported_macos_version() {
    local setting_id="$1"
    local current_macos_version
    local current_macos_number
    local minimum_macos_number

    current_macos_version="$(get_current_macos_version)"
    current_macos_number="$(version_to_number "$current_macos_version")"
    minimum_macos_number="$(version_to_number "${SETTINGS_MIN_MACOS_VERSION[$setting_id]-$MIN_MACOS_VERSION}")"

    [[ "$current_macos_number" -ge "$minimum_macos_number" ]]
}

normalize_value() {
    local current_value="$1"

    case "${current_value:l}" in
        yes|true) echo "1" ;;
        no|false) echo "0" ;;
        *) echo "$current_value" ;;
    esac
}

get_setting_status_value() {
    local setting_id="$1"
    local status_command="${SETTINGS_STATUS_COMMAND[$setting_id]-}"

    if [[ -z "$setting_id" || -z "$status_command" ]]; then
        echo "__ERROR__:missing status command"
        return 0
    fi

    if ! is_supported_macos_version "$setting_id"; then
        echo "__UNSUPPORTED__"
        return 0
    fi

    local current_value
    current_value="$(eval "$status_command" 2>&1)"
    local command_exit_code=$?

    if [[ "$command_exit_code" -ne 0 ]]; then
        echo "__ERROR__:${current_value}"
        return 0
    fi

    if [[ -z "$current_value" ]]; then
        echo "__ERROR__:empty result"
        return 0
    fi

    echo "$current_value"
}


is_setting_match() {
    local setting_id="$1"
    local current_value="$2"
    local recommended_value="${SETTINGS_RECOMMENDED_VALUE[$setting_id]-}"

    if [[ -z "$setting_id" || -z "$recommended_value" ]]; then
        return 1
    fi

    local normalized_current_value
    local normalized_recommended_value

    normalized_current_value="$(normalize_value "$current_value")"
    normalized_recommended_value="$(normalize_value "$recommended_value")"

    [[ "$normalized_current_value" == "$normalized_recommended_value" ]]
}

get_status_icon() {
    local setting_id="$1"
    local current_value="$2"

    if [[ "$current_value" == "manual" ]]; then
        print -P "${COLOR_YELLOW}[!]${COLOR_RESET}"
        return
    fi

    if [[ "${SETTINGS_STATUS_TYPE[$setting_id]-}" == "info" ]]; then
        print "   "
        return
    fi

    if [[ "$current_value" == "__UNSUPPORTED__" ]]; then
        print -P "${COLOR_YELLOW}[-]${COLOR_RESET}"
        return
    fi

    if [[ "$current_value" == "__MISSING__" || "$current_value" == __ERROR__* ]]; then
        print -P "${COLOR_RED}[X]${COLOR_RESET}"
        return
    fi

    if is_setting_match "$setting_id" "$current_value"; then
        print -P "${COLOR_GREEN}[√]${COLOR_RESET}"
    else
        print -P "${COLOR_RED}[X]${COLOR_RESET}"
    fi
}

get_choice_icon() {
    local setting_id="$1"
    local current_value="$2"

    if [[ "$current_value" == "manual" ]]; then
        print -P "${COLOR_YELLOW}[M]${COLOR_RESET}"
        return
    fi

    if [[ "${SETTINGS_STATUS_TYPE[$setting_id]-}" == "info" ]]; then
        print "   "
        return
    fi

    if [[ "$current_value" == "__UNSUPPORTED__" ]]; then
        print -P "${COLOR_YELLOW}[-]${COLOR_RESET}"
        return
    fi

    if [[ "$current_value" == "__MISSING__" || "$current_value" == __ERROR__* ]]; then
        print -P "${COLOR_RED}[N]${COLOR_RESET}"
        return
    fi

    if is_setting_match "$setting_id" "$current_value"; then
        print -P "${COLOR_GREEN}[Y]${COLOR_RESET}"
    else
        print -P "${COLOR_RED}[N]${COLOR_RESET}"
    fi
}

ensure_sudo_session() {
    if [[ "$SUDO_REQUIRED" != "true" ]]; then
        return 0
    fi

    if [[ "$SUDO_STARTED" == "true" ]]; then
        return 0
    fi

    sudo -v || return 1

    while true; do
        sudo -n true >/dev/null 2>&1
        sleep 30
        kill -0 "$$" >/dev/null 2>&1 || exit
    done 2>/dev/null &

    SUDO_STARTED="true"
    return 0
}

set_sudo_required_for_selection() {
    local setting_id
    SUDO_REQUIRED="false"

    for setting_id in "$@"; do
        if [[ -n "$setting_id" && "${SETTINGS_REQUIRES_SUDO[$setting_id]-}" == "true" ]]; then
            SUDO_REQUIRED="true"
            return 0
        fi
    done
}

queue_restart_target_for_setting() {
    local setting_id="$1"
    local restart_target="${SETTINGS_RESTART_TARGET[$setting_id]-}"

    if [[ -n "$restart_target" ]]; then
        add_restart_target "$restart_target"
    fi
}

restart_app_if_running() {
    local restart_target="$1"

    if pgrep -x "$restart_target" >/dev/null 2>&1; then
        killall "$restart_target" >/dev/null 2>&1 || true
        echo "Restarted: $restart_target"
    fi
}

restart_affected_apps() {
    local restart_target

    if [[ "${#RESTART_TARGETS[@]}" -eq 0 ]]; then
        return 0
    fi

    echo
    print -P "${COLOR_BLUE}Restarting affected apps${COLOR_RESET}"

    for restart_target in "${RESTART_TARGETS[@]}"; do
        restart_app_if_running "$restart_target"
    done

    RESTART_TARGETS=()
    echo
}

print_status_table() {
    echo
    print -P "${COLOR_BOLD}Current Status of All Settings${COLOR_RESET}"

    local setting_id
    local setting_title
    local current_value
    local status_icon
    local current_category=""
    local detail_text

    for setting_id in "${SETTINGS_KEYS[@]}"; do
        if [[ -z "$setting_id" ]]; then
            continue
        fi

        if [[ "$current_category" != "${SETTINGS_CATEGORY[$setting_id]-}" ]]; then
            current_category="${SETTINGS_CATEGORY[$setting_id]-}"
            echo
            print -P "${COLOR_BLUE}${current_category}${COLOR_RESET}"
        fi

        setting_title="${SETTINGS_TITLE[$setting_id]-$setting_id}"
        current_value="$(get_setting_status_value "$setting_id")"
        status_icon="$(get_status_icon "$setting_id" "$current_value")"
        detail_text=""

        if [[ "$current_value" == "manual" ]]; then
            detail_text="(manual)"
        elif [[ "$current_value" == "__UNSUPPORTED__" ]]; then
            detail_text="(requires macOS ${SETTINGS_MIN_MACOS_VERSION[$setting_id]-$MIN_MACOS_VERSION}+)"
        elif [[ "$current_value" == "__MISSING__" ]]; then
            detail_text="(not set)"
        elif [[ "$current_value" == __ERROR__:* ]]; then
            detail_text="(${current_value#__ERROR__:})"
        else
            if [[ "${SETTINGS_STATUS_TYPE[$setting_id]-}" == "info" ]]; then
                detail_text="$current_value"
            else
                detail_text="(current: $current_value)"
            fi
        fi

        if [[ "${SETTINGS_STATUS_TYPE[$setting_id]-}" == "info" ]]; then
            printf "• %-50s %s\n" "$setting_title" "$detail_text"
        else
            printf "• %-50s %b  %s\n" "$setting_title" "$status_icon" "$detail_text"
        fi
    done

    echo
}

apply_setting() {
    local setting_id="$1"
    local apply_command="${SETTINGS_APPLY_COMMAND[$setting_id]-}"
    local open_command="${SETTINGS_OPEN_COMMAND[$setting_id]-}"
    local setting_title="${SETTINGS_TITLE[$setting_id]-$setting_id}"
    local status_type="${SETTINGS_STATUS_TYPE[$setting_id]-}"
    local current_value

    if ! is_supported_macos_version "$setting_id"; then
        printf "Skipping: %s (requires macOS %s+)\n" "$setting_title" "${SETTINGS_MIN_MACOS_VERSION[$setting_id]-$MIN_MACOS_VERSION}"
        return 0
    fi

    current_value="$(get_setting_status_value "$setting_id")"

    if [[ -z "$setting_id" || -z "$setting_title" ]]; then
        echo "Skipping invalid setting entry."
        return 1
    fi

    if [[ "$status_type" == "manual" ]]; then
        printf "Opening: %s ... " "$setting_title"
        if eval "$open_command" >/dev/null 2>&1; then
            echo "Opened"
            return 0
        else
            echo "Failed"
            return 1
        fi
    fi

    if is_setting_match "$setting_id" "$current_value"; then
        printf "Skipping: %s (already set)\n" "$setting_title"
        return 0
    fi

    printf "Applying: %s ... " "$setting_title"

    local apply_output
    apply_output="$(eval "$apply_command" 2>&1)"
    local apply_exit_code=$?

    if [[ "$apply_exit_code" -eq 0 ]]; then
        echo "Done"
        queue_restart_target_for_setting "$setting_id"
        return 0
    else
        if [[ -n "$apply_output" ]]; then
            echo "Failed: $apply_output"
        else
            echo "Failed"
        fi
        return 1
    fi
}

apply_recommended_settings() {
    echo
    print -P "${COLOR_BOLD}Applying recommended settings${COLOR_RESET}"
    echo

    local setting_id
    local failed_count=0
    local selected_settings=()

    for setting_id in "${SETTINGS_KEYS[@]}"; do
        selected_settings+=("$setting_id")
    done

    set_sudo_required_for_selection "${selected_settings[@]}"
    if ! ensure_sudo_session; then
        echo "Unable to start sudo session."
        return 1
    fi

    for setting_id in "${selected_settings[@]}"; do
        if ! apply_setting "$setting_id"; then
            ((failed_count++))
        fi
    done

    restart_affected_apps

    echo
    if [[ "$failed_count" -eq 0 ]]; then
        print -P "${COLOR_GREEN}All applicable settings processed.${COLOR_RESET}"
    else
        print -P "${COLOR_RED}$failed_count setting(s) failed.${COLOR_RESET}"
    fi
    echo
}

apply_individual_settings() {
    echo
    print -P "${COLOR_BOLD}Apply Individual Settings${COLOR_RESET}"
    echo

    local setting_id
    local setting_title
    local current_value
    local choice_icon
    local user_choice
    local current_category=""
    local selected_settings=()

    for setting_id in "${SETTINGS_KEYS[@]}"; do
        if [[ -z "$setting_id" ]]; then
            continue
        fi

        if [[ "$current_category" != "${SETTINGS_CATEGORY[$setting_id]-}" ]]; then
            current_category="${SETTINGS_CATEGORY[$setting_id]-}"
            print -P "${COLOR_BLUE}${current_category}${COLOR_RESET}"
        fi

        setting_title="${SETTINGS_TITLE[$setting_id]-$setting_id}"
        current_value="$(get_setting_status_value "$setting_id")"
        choice_icon="$(get_choice_icon "$setting_id" "$current_value")"

        if [[ "${SETTINGS_STATUS_TYPE[$setting_id]-}" == "info" ]]; then
            printf "• %-50s (current: %s)  Apply? [Y/N]: " "$setting_title" "$current_value"
        else
            printf "• %-50s %b  Apply? [Y/N]: " "$setting_title" "$choice_icon"
        fi
        read -r user_choice

        case "${user_choice:l}" in
            y|yes)
                selected_settings+=("$setting_id")
                ;;
            n|no)
                ;;
            *)
                echo "Skipping invalid input."
                ;;
        esac
    done

    if [[ "${#selected_settings[@]}" -eq 0 ]]; then
        echo
        echo "No settings selected."
        echo
        return 0
    fi

    set_sudo_required_for_selection "${selected_settings[@]}"
    if ! ensure_sudo_session; then
        echo "Unable to start sudo session."
        return 1
    fi

    echo
    for setting_id in "${selected_settings[@]}"; do
        apply_setting "$setting_id"
    done

    restart_affected_apps
    echo
}

disable_gatekeeper_now() {
    SUDO_REQUIRED="true"
    if ! ensure_sudo_session; then
        echo "Unable to start sudo session."
        return 1
    fi

    echo
    printf "Disabling Gatekeeper ... "
    local gatekeeper_output
    gatekeeper_output="$(sudo spctl --master-disable 2>&1)"
    local gatekeeper_exit_code=$?
    if [[ "$gatekeeper_exit_code" -eq 0 ]]; then
        echo "Done"
    else
        if [[ -n "$gatekeeper_output" ]]; then
            echo "Failed: $gatekeeper_output"
        else
            echo "Failed"
        fi
    fi
    echo
}

enable_gatekeeper_now() {
    SUDO_REQUIRED="true"
    if ! ensure_sudo_session; then
        echo "Unable to start sudo session."
        return 1
    fi

    echo
    printf "Enabling Gatekeeper ... "
    local gatekeeper_output
    gatekeeper_output="$(sudo spctl --master-enable 2>&1)"
    local gatekeeper_exit_code=$?
    if [[ "$gatekeeper_exit_code" -eq 0 ]]; then
        echo "Done"
    else
        if [[ -n "$gatekeeper_output" ]]; then
            echo "Failed: $gatekeeper_output"
        else
            echo "Failed"
        fi
    fi
    echo
}

main() {
    if ! require_full_disk_access_confirmation; then
        exit 1
    fi

    while true; do
        print_header
        printf "Enter selection: "
        read -r menu_choice

        case "$menu_choice" in
            1)
                apply_recommended_settings
                ;;
            2)
                apply_individual_settings
                ;;
            3)
                print_status_table
                ;;
            4)
                disable_gatekeeper_now
                ;;
            5)
                enable_gatekeeper_now
                ;;
            6|q)
                exit 0
                ;;
            *)
                echo "Invalid selection."
                ;;
        esac
    done
}

main
