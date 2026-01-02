#!/bin/bash

# AppKeep System Installer
# POSIX-compliant shell script for installing/uninstalling AppKeep on Linux systems

set -e  # Exit on any error

#=============================================================================
# CONFIGURATION SECTION
#=============================================================================

# Application information
readonly APP_NAME="appkeep"
readonly APP_DISPLAY_NAME="AppKeep"
readonly APP_DESCRIPTION="Application management and process monitoring tool"
readonly APP_VERSION="1.0.0"

# Source paths (relative to script location)
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SOURCE_BINARY="${SCRIPT_DIR}/build/bin/appkeep"
readonly SOURCE_ICON="${SCRIPT_DIR}/appicon.png"

# Target installation paths (following XDG standards)
readonly TARGET_BIN_DIR="/usr/local/bin"
readonly TARGET_DESKTOP_DIR="/usr/share/applications"
readonly TARGET_ICON_DIR="/usr/share/pixmaps"

# Target file paths
readonly TARGET_BINARY="${TARGET_BIN_DIR}/${APP_NAME}"
readonly TARGET_DESKTOP="${TARGET_DESKTOP_DIR}/${APP_NAME}.desktop"
readonly TARGET_ICON="${TARGET_ICON_DIR}/${APP_NAME}.png"

# File permissions
readonly PERM_EXECUTABLE="755"
readonly PERM_DATA_FILE="644"
readonly PERM_DIRECTORY="755"

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1
readonly EXIT_PERMISSION_DENIED=2
readonly EXIT_FILE_NOT_FOUND=3
readonly EXIT_INVALID_ARGS=4

#=============================================================================
# LOGGING AND UTILITY FUNCTIONS
#=============================================================================

# Color codes for output
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_RESET='\033[0m'

# Logging functions
log_info() {
    printf "${COLOR_BLUE}[INFO]${COLOR_RESET} %s\n" "$1" >&2
}

log_success() {
    printf "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} %s\n" "$1" >&2
}

log_warning() {
    printf "${COLOR_YELLOW}[WARNING]${COLOR_RESET} %s\n" "$1" >&2
}

log_error() {
    printf "${COLOR_RED}[ERROR]${COLOR_RESET} %s\n" "$1" >&2
}

# Error handling function
die() {
    local exit_code="${2:-$EXIT_ERROR}"
    log_error "$1"
    exit "$exit_code"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if running as root or with sudo
is_root() {
    [ "$(id -u)" -eq 0 ]
}

# Print usage information
show_usage() {
    cat << EOF
AppKeep System Installer v${APP_VERSION}

USAGE:
    $0 <command> [options]

COMMANDS:
    install     Install AppKeep to system directories
    uninstall   Remove AppKeep from system directories
    --help      Show this help message

EXAMPLES:
    $0 install      # Install AppKeep
    $0 uninstall    # Uninstall AppKeep
    $0 --help       # Show help

REQUIREMENTS:
    - Linux system with standard XDG directories
    - Root privileges (run with sudo)
    - AppKeep binary at: ${SOURCE_BINARY}
    - AppKeep icon at: ${SOURCE_ICON}

EOF
}

#=============================================================================
# PERMISSION VALIDATION FUNCTIONS
#=============================================================================

validate_permissions() {
    log_info "Validating permissions..."
    
    # Check if running as root or with sudo
    if ! is_root; then
        die "This script requires root privileges. Please run with sudo." $EXIT_PERMISSION_DENIED
    fi
    
    # Validate write access to target directories
    validate_directory_access "$TARGET_BIN_DIR" "binary installation"
    validate_directory_access "$TARGET_DESKTOP_DIR" "desktop entry installation"
    validate_directory_access "$TARGET_ICON_DIR" "icon installation"
    
    log_success "Permission validation completed successfully"
}

validate_directory_access() {
    local dir="$1"
    local purpose="$2"
    
    # Check if directory exists, if not, check if we can create it
    if [ ! -d "$dir" ]; then
        local parent_dir
        parent_dir="$(dirname "$dir")"
        
        if [ ! -d "$parent_dir" ]; then
            die "Parent directory '$parent_dir' does not exist and cannot be created for $purpose" $EXIT_PERMISSION_DENIED
        fi
        
        if [ ! -w "$parent_dir" ]; then
            die "No write permission to parent directory '$parent_dir' for $purpose" $EXIT_PERMISSION_DENIED
        fi
        
        log_info "Directory '$dir' will be created for $purpose"
    else
        # Directory exists, check write permission
        if [ ! -w "$dir" ]; then
            die "No write permission to directory '$dir' for $purpose" $EXIT_PERMISSION_DENIED
        fi
        
        log_info "Write access to '$dir' confirmed for $purpose"
    fi
}

#=============================================================================
# SYSTEM COMPATIBILITY CHECKS
#=============================================================================

check_system_compatibility() {
    log_info "Checking system compatibility..."
    
    # Check if we're on a Linux system
    if [ "$(uname -s)" != "Linux" ]; then
        die "This installer only supports Linux systems. Detected: $(uname -s)" $EXIT_ERROR
    fi
    
    # Detect Linux distribution (for informational purposes)
    detect_linux_distribution
    
    # Check for standard XDG directories
    check_xdg_directories
    
    # Check system type (systemd vs non-systemd)
    detect_init_system
    
    log_success "System compatibility check completed successfully"
}

detect_linux_distribution() {
    local distro="Unknown"
    
    if [ -f /etc/os-release ]; then
        distro=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d'"' -f2)
    elif [ -f /etc/lsb-release ]; then
        distro=$(grep '^DISTRIB_DESCRIPTION=' /etc/lsb-release | cut -d'"' -f2)
    elif [ -f /etc/redhat-release ]; then
        distro=$(cat /etc/redhat-release)
    elif [ -f /etc/debian_version ]; then
        distro="Debian $(cat /etc/debian_version)"
    fi
    
    log_info "Detected Linux distribution: $distro"
}

check_xdg_directories() {
    local missing_dirs=""
    
    for dir in "$TARGET_BIN_DIR" "$TARGET_DESKTOP_DIR" "$TARGET_ICON_DIR"; do
        local parent_dir
        parent_dir="$(dirname "$dir")"
        
        if [ ! -d "$parent_dir" ]; then
            missing_dirs="$missing_dirs $parent_dir"
        fi
    done
    
    if [ -n "$missing_dirs" ]; then
        log_warning "Some standard directories are missing:$missing_dirs"
        log_info "These directories will be created during installation if needed"
    else
        log_info "All standard XDG directories are available"
    fi
}

detect_init_system() {
    local init_system="Unknown"
    
    if command_exists systemctl && [ -d /run/systemd/system ]; then
        init_system="systemd"
    elif [ -f /sbin/init ] && [ -L /sbin/init ]; then
        local init_target
        init_target="$(readlink /sbin/init)"
        case "$init_target" in
            *systemd*) init_system="systemd" ;;
            *upstart*) init_system="upstart" ;;
            *) init_system="sysvinit" ;;
        esac
    elif [ -f /etc/inittab ]; then
        init_system="sysvinit"
    fi
    
    log_info "Detected init system: $init_system"
}

#=============================================================================
# FILE OPERATION FUNCTIONS
#=============================================================================

safe_copy() {
    local source="$1"
    local destination="$2"
    local purpose="$3"
    
    log_info "Copying '$source' to '$destination' for $purpose"
    
    # Validate source file exists and is readable
    if [ ! -f "$source" ]; then
        die "Source file '$source' does not exist for $purpose" $EXIT_FILE_NOT_FOUND
    fi
    
    if [ ! -r "$source" ]; then
        die "Source file '$source' is not readable for $purpose" $EXIT_PERMISSION_DENIED
    fi
    
    # Validate destination directory exists or can be created
    local dest_dir
    dest_dir="$(dirname "$destination")"
    create_directory "$dest_dir" "$purpose directory"
    
    # Perform the copy operation
    if ! cp "$source" "$destination"; then
        die "Failed to copy '$source' to '$destination' for $purpose" $EXIT_ERROR
    fi
    
    log_success "Successfully copied '$source' to '$destination'"
}

safe_remove() {
    local file_path="$1"
    local purpose="$2"
    
    log_info "Removing '$file_path' for $purpose"
    
    # Check if file exists
    if [ ! -e "$file_path" ]; then
        log_warning "File '$file_path' does not exist, nothing to remove for $purpose"
        return 0
    fi
    
    # Check if we have permission to remove the file
    local parent_dir
    parent_dir="$(dirname "$file_path")"
    
    if [ ! -w "$parent_dir" ]; then
        die "No write permission to directory '$parent_dir' to remove file for $purpose" $EXIT_PERMISSION_DENIED
    fi
    
    # Perform the removal
    if ! rm -f "$file_path"; then
        die "Failed to remove '$file_path' for $purpose" $EXIT_ERROR
    fi
    
    log_success "Successfully removed '$file_path'"
}

create_directory() {
    local dir_path="$1"
    local purpose="$2"
    
    # If directory already exists, just verify permissions
    if [ -d "$dir_path" ]; then
        if [ ! -w "$dir_path" ]; then
            die "Directory '$dir_path' exists but is not writable for $purpose" $EXIT_PERMISSION_DENIED
        fi
        return 0
    fi
    
    log_info "Creating directory '$dir_path' for $purpose"
    
    # Create directory with parents if needed
    if ! mkdir -p "$dir_path"; then
        die "Failed to create directory '$dir_path' for $purpose" $EXIT_ERROR
    fi
    
    # Set appropriate permissions
    if ! chmod "$PERM_DIRECTORY" "$dir_path"; then
        die "Failed to set permissions on directory '$dir_path' for $purpose" $EXIT_ERROR
    fi
    
    log_success "Successfully created directory '$dir_path'"
}

set_file_permissions() {
    local file_path="$1"
    local permissions="$2"
    local purpose="$3"
    
    log_info "Setting permissions '$permissions' on '$file_path' for $purpose"
    
    # Verify file exists
    if [ ! -e "$file_path" ]; then
        die "File '$file_path' does not exist for $purpose" $EXIT_FILE_NOT_FOUND
    fi
    
    # Set permissions
    if ! chmod "$permissions" "$file_path"; then
        die "Failed to set permissions '$permissions' on '$file_path' for $purpose" $EXIT_ERROR
    fi
    
    log_success "Successfully set permissions '$permissions' on '$file_path'"
}

#=============================================================================
# INSTALLATION FUNCTIONS
#=============================================================================

install_binary() {
    log_info "Installing binary..."
    
    # Validate source binary exists
    if [ ! -f "$SOURCE_BINARY" ]; then
        die "Source binary not found at '$SOURCE_BINARY'. Please build the application first." $EXIT_FILE_NOT_FOUND
    fi
    
    # Validate source binary is executable
    if [ ! -x "$SOURCE_BINARY" ]; then
        die "Source binary '$SOURCE_BINARY' is not executable" $EXIT_ERROR
    fi
    
    # Copy binary to target location
    safe_copy "$SOURCE_BINARY" "$TARGET_BINARY" "binary installation"
    
    # Set executable permissions
    set_file_permissions "$TARGET_BINARY" "$PERM_EXECUTABLE" "binary installation"
    
    # Verify binary is accessible in PATH
    if ! command -v "$APP_NAME" >/dev/null 2>&1; then
        log_warning "Binary may not be immediately available in PATH. You may need to restart your shell or run 'hash -r'"
    fi
    
    log_success "Binary installation completed successfully"
}

install_desktop_entry() {
    log_info "Installing desktop entry..."
    
    # Create desktop entry content
    local desktop_content
    desktop_content="[Desktop Entry]
Name=$APP_DISPLAY_NAME
Comment=$APP_DESCRIPTION
Exec=$TARGET_BINARY
Icon=$TARGET_ICON
Type=Application
Categories=System;Monitor;Utility;
Terminal=false
StartupNotify=true
Keywords=process;monitor;application;management;
MimeType=
StartupWMClass=$APP_NAME"
    
    # Ensure target directory exists
    create_directory "$TARGET_DESKTOP_DIR" "desktop entry installation"
    
    # Write desktop entry file
    if ! printf "%s\n" "$desktop_content" > "$TARGET_DESKTOP" 2>/dev/null; then
        die "Failed to create desktop entry file '$TARGET_DESKTOP'" $EXIT_ERROR
    fi
    
    # Set appropriate permissions
    set_file_permissions "$TARGET_DESKTOP" "$PERM_DATA_FILE" "desktop entry installation"
    
    # Update desktop database if available
    if command_exists update-desktop-database; then
        log_info "Updating desktop database..."
        if ! update-desktop-database "$TARGET_DESKTOP_DIR" 2>/dev/null; then
            log_warning "Failed to update desktop database, but installation can continue"
        fi
    else
        log_info "update-desktop-database not available, skipping database update"
    fi
    
    log_success "Desktop entry installation completed successfully"
}

install_icon() {
    log_info "Installing icon..."
    
    # Validate source icon exists
    if [ ! -f "$SOURCE_ICON" ]; then
        die "Source icon not found at '$SOURCE_ICON'" $EXIT_FILE_NOT_FOUND
    fi
    
    # Ensure target directory exists
    create_directory "$TARGET_ICON_DIR" "icon installation"
    
    # Copy icon to target location
    safe_copy "$SOURCE_ICON" "$TARGET_ICON" "icon installation"
    
    # Set appropriate permissions
    set_file_permissions "$TARGET_ICON" "$PERM_DATA_FILE" "icon installation"
    
    log_success "Icon installation completed successfully"
}

verify_installation() {
    log_info "Verifying installation..."
    
    local verification_failed=0
    
    # Verify binary installation
    if ! verify_binary_installation; then
        verification_failed=1
    fi
    
    # Verify desktop entry installation
    if ! verify_desktop_entry_installation; then
        verification_failed=1
    fi
    
    # Verify icon installation
    if ! verify_icon_installation; then
        verification_failed=1
    fi
    
    # Overall verification result
    if [ $verification_failed -eq 1 ]; then
        die "Installation verification failed" $EXIT_ERROR
    fi
    
    log_success "Installation verification completed successfully"
    display_installation_summary
}

verify_binary_installation() {
    log_info "Verifying binary installation..."
    
    # Check if binary file exists
    if [ ! -f "$TARGET_BINARY" ]; then
        log_error "Binary file '$TARGET_BINARY' not found"
        return 1
    fi
    
    # Check binary permissions
    local actual_perms
    actual_perms="$(stat -c '%a' "$TARGET_BINARY" 2>/dev/null)"
    if [ "$actual_perms" != "$PERM_EXECUTABLE" ]; then
        log_error "Binary permissions incorrect. Expected: $PERM_EXECUTABLE, Actual: $actual_perms"
        return 1
    fi
    
    # Check if binary is executable
    if [ ! -x "$TARGET_BINARY" ]; then
        log_error "Binary '$TARGET_BINARY' is not executable"
        return 1
    fi
    
    log_success "Binary installation verified"
    return 0
}

verify_desktop_entry_installation() {
    log_info "Verifying desktop entry installation..."
    
    # Check if desktop entry file exists
    if [ ! -f "$TARGET_DESKTOP" ]; then
        log_error "Desktop entry file '$TARGET_DESKTOP' not found"
        return 1
    fi
    
    # Check desktop entry permissions
    local actual_perms
    actual_perms="$(stat -c '%a' "$TARGET_DESKTOP" 2>/dev/null)"
    if [ "$actual_perms" != "$PERM_DATA_FILE" ]; then
        log_error "Desktop entry permissions incorrect. Expected: $PERM_DATA_FILE, Actual: $actual_perms"
        return 1
    fi
    
    log_success "Desktop entry installation verified"
    return 0
}

verify_icon_installation() {
    log_info "Verifying icon installation..."
    
    # Check if icon file exists
    if [ ! -f "$TARGET_ICON" ]; then
        log_error "Icon file '$TARGET_ICON' not found"
        return 1
    fi
    
    # Check icon permissions
    local actual_perms
    actual_perms="$(stat -c '%a' "$TARGET_ICON" 2>/dev/null)"
    if [ "$actual_perms" != "$PERM_DATA_FILE" ]; then
        log_error "Icon permissions incorrect. Expected: $PERM_DATA_FILE, Actual: $actual_perms"
        return 1
    fi
    
    # Check icon file is not empty
    if [ ! -s "$TARGET_ICON" ]; then
        log_error "Icon file '$TARGET_ICON' is empty"
        return 1
    fi
    
    log_success "Icon installation verified"
    return 0
}

display_installation_summary() {
    log_success "=== AppKeep Installation Summary ==="
    log_success "Binary installed: $TARGET_BINARY"
    log_success "Desktop entry: $TARGET_DESKTOP"
    log_success "Icon: $TARGET_ICON"
    log_success ""
    log_success "AppKeep has been successfully installed!"
    log_success "You can now:"
    log_success "  - Run 'appkeep' from the command line"
    log_success "  - Find AppKeep in your application menu"
    log_success "  - Launch AppKeep from your desktop environment"
    log_success ""
    log_success "If the application doesn't appear in your menu immediately,"
    log_success "try logging out and back in, or restart your desktop session."
}

#=============================================================================
# UNINSTALLATION FUNCTIONS
#=============================================================================

uninstall_files() {
    log_info "Uninstalling files..."
    
    local files_removed=0
    local files_not_found=0
    
    # Remove binary
    if [ -f "$TARGET_BINARY" ]; then
        safe_remove "$TARGET_BINARY" "binary uninstallation"
        files_removed=$((files_removed + 1))
    else
        log_warning "Binary '$TARGET_BINARY' not found (already removed?)"
        files_not_found=$((files_not_found + 1))
    fi
    
    # Remove desktop entry
    if [ -f "$TARGET_DESKTOP" ]; then
        safe_remove "$TARGET_DESKTOP" "desktop entry uninstallation"
        files_removed=$((files_removed + 1))
        
        # Update desktop database after removal
        if command_exists update-desktop-database; then
            log_info "Updating desktop database after removal..."
            update-desktop-database "$TARGET_DESKTOP_DIR" 2>/dev/null || true
        fi
    else
        log_warning "Desktop entry '$TARGET_DESKTOP' not found (already removed?)"
        files_not_found=$((files_not_found + 1))
    fi
    
    # Remove icon
    if [ -f "$TARGET_ICON" ]; then
        safe_remove "$TARGET_ICON" "icon uninstallation"
        files_removed=$((files_removed + 1))
    else
        log_warning "Icon '$TARGET_ICON' not found (already removed?)"
        files_not_found=$((files_not_found + 1))
    fi
    
    # Summary
    if [ $files_removed -eq 0 ] && [ $files_not_found -gt 0 ]; then
        log_warning "No files were removed (AppKeep may not have been installed)"
    elif [ $files_removed -gt 0 ]; then
        log_success "Successfully removed $files_removed file(s)"
    fi
    
    log_success "File uninstallation completed"
}

verify_removal() {
    log_info "Verifying removal..."
    
    local files_still_present=0
    
    # Check if binary was removed
    if [ -f "$TARGET_BINARY" ]; then
        log_error "Binary '$TARGET_BINARY' still exists after uninstallation"
        files_still_present=$((files_still_present + 1))
    else
        log_info "Binary successfully removed"
    fi
    
    # Check if desktop entry was removed
    if [ -f "$TARGET_DESKTOP" ]; then
        log_error "Desktop entry '$TARGET_DESKTOP' still exists after uninstallation"
        files_still_present=$((files_still_present + 1))
    else
        log_info "Desktop entry successfully removed"
    fi
    
    # Check if icon was removed
    if [ -f "$TARGET_ICON" ]; then
        log_error "Icon '$TARGET_ICON' still exists after uninstallation"
        files_still_present=$((files_still_present + 1))
    else
        log_info "Icon successfully removed"
    fi
    
    # Check if binary is still in PATH
    if command -v "$APP_NAME" >/dev/null 2>&1; then
        log_warning "AppKeep binary still found in PATH. You may need to restart your shell or run 'hash -r'"
    fi
    
    # Overall verification result
    if [ $files_still_present -gt 0 ]; then
        die "Uninstallation verification failed: $files_still_present file(s) still present" $EXIT_ERROR
    fi
    
    log_success "Uninstallation verification completed successfully"
    display_uninstallation_summary
}

display_uninstallation_summary() {
    log_success "=== AppKeep Uninstallation Summary ==="
    log_success "All AppKeep files have been successfully removed:"
    log_success "  - Binary: $TARGET_BINARY"
    log_success "  - Desktop entry: $TARGET_DESKTOP"
    log_success "  - Icon: $TARGET_ICON"
    log_success ""
    log_success "AppKeep has been completely uninstalled from your system."
    log_success ""
    log_success "Note: If AppKeep still appears in your application menu,"
    log_success "try logging out and back in, or restart your desktop session."
}

#=============================================================================
# MAIN FUNCTIONS
#=============================================================================

do_install() {
    log_info "Starting AppKeep installation..."
    
    # Validate permissions first
    validate_permissions
    
    # Check system compatibility
    check_system_compatibility
    
    # Install components
    install_binary
    install_desktop_entry
    install_icon
    
    # Verify installation
    verify_installation
    
    log_success "AppKeep installation completed successfully!"
}

do_uninstall() {
    log_info "Starting AppKeep uninstallation..."
    
    # Validate permissions
    validate_permissions
    
    # Remove files
    uninstall_files
    
    # Verify removal
    verify_removal
    
    log_success "AppKeep uninstallation completed successfully!"
}

main() {
    # Parse command line arguments
    case "${1:-}" in
        "install")
            shift
            while [ $# -gt 0 ]; do
                case "$1" in
                    "--help"|"-h")
                        show_usage
                        exit $EXIT_SUCCESS
                        ;;
                    *)
                        log_error "Unknown install option: $1"
                        show_usage
                        exit $EXIT_INVALID_ARGS
                        ;;
                esac
                shift
            done
            do_install
            ;;
        "uninstall"|"remove")
            shift
            while [ $# -gt 0 ]; do
                case "$1" in
                    "--help"|"-h")
                        show_usage
                        exit $EXIT_SUCCESS
                        ;;
                    *)
                        log_error "Unknown uninstall option: $1"
                        show_usage
                        exit $EXIT_INVALID_ARGS
                        ;;
                esac
                shift
            done
            do_uninstall
            ;;
        "--help"|"-h"|"help")
            show_usage
            exit $EXIT_SUCCESS
            ;;
        "--version"|"-v"|"version")
            printf "AppKeep System Installer v%s\n" "$APP_VERSION"
            exit $EXIT_SUCCESS
            ;;
        "")
            log_error "No command specified"
            show_usage
            exit $EXIT_INVALID_ARGS
            ;;
        *)
            log_error "Unknown command: $1"
            show_usage
            exit $EXIT_INVALID_ARGS
            ;;
    esac
}

# Script entry point
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi