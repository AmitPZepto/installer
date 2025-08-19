#!/bin/bash

# ==============================================================================
#
# VS Code & Cursor Extension Installer for macOS (Verbose Debug Mode)
#
# Description:
# This script first ensures Trivy is installed by downloading it manually to a
# user-owned directory (no sudo required), then installs a VS Code extension
# for users of VS Code or Cursor. It includes extra logging for debugging.
#
# ==============================================================================

# --- Configuration ---
VSIX_URL="https://zepto-security-tooling-nonce-ndeekhbfsdhsnbasjkdmejdbs.s3.ap-south-1.amazonaws.com/shift-left-security-scanner.vsix"
VSIX_FILENAME="shift-left-security-scanner.vsix"

# --- Logging ---
# A simple logging function to provide feedback.
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] - $1"
}

# --- Manual Trivy Installer Function ---
install_trivy_manually() {
    log "Starting manual installation of Trivy..."

    # Use a user-specific directory to avoid needing sudo
    local INSTALL_DIR="$HOME/.local/bin"

    # 1. Determine OS and Architecture
    local os_name="darwin" # macOS's internal name
    local arch=$(uname -m)
    log "Detected OS: ${os_name}, Arch: ${arch}"

    # 2. Create a temporary directory for downloads
    local temp_dir=$(mktemp -d)
    log "Created temporary directory: ${temp_dir}"

    # 3. Construct Download URLs
    local trivy_archive="trivy.tar.gz"
    local download_url="https://get.trivy.dev/trivy?os=${os_name}&arch=${arch}&type=tar.gz"
    
    log "Trivy Download URL: ${download_url}"

    # 4. Download the Trivy binary archive
    log "Downloading Trivy archive..."
    if ! curl -L --silent --show-error -o "${temp_dir}/${trivy_archive}" "${download_url}"; then
        log "ERROR: Failed to download the Trivy archive."
        rm -rf "${temp_dir}"
        return 1
    fi
    log "Trivy archive downloaded successfully to ${temp_dir}/${trivy_archive}"

    # --- Checksum Verification (Optional but Recommended) ---
    log "Attempting to verify checksum for security..."
    # Get the latest release tag from GitHub API
    local latest_tag=$(curl -s "https://api.github.com/repos/aquasecurity/trivy/releases/latest" | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')

    if [ -n "$latest_tag" ]; then
        log "Latest Trivy release is: v${latest_tag}"
        local checksum_url="https://github.com/aquasecurity/trivy/releases/download/v${latest_tag}/trivy_${latest_tag}_checksums.txt"
        log "Checksum URL: ${checksum_url}"

        # Download checksums file
        if curl -L --silent --show-error -o "${temp_dir}/checksums.txt" "${checksum_url}"; then
            log "Checksum file downloaded."
            # Calculate checksum of the downloaded archive
            local downloaded_checksum=$(shasum -a 256 "${temp_dir}/${trivy_archive}" | awk '{print $1}')
            log "Calculated SHA256: ${downloaded_checksum}"

            # Check if the calculated checksum exists in the checksums file
            if grep -q "${downloaded_checksum}" "${temp_dir}/checksums.txt"; then
                log "SUCCESS: Checksum verification passed."
            else
                log "WARNING: Checksum verification FAILED. The binary's integrity cannot be verified. Aborting."
                rm -rf "${temp_dir}"
                return 1
            fi
        else
            log "WARNING: Could not download checksums file. Proceeding without verification."
        fi
    else
        log "WARNING: Could not determine latest release tag. Skipping checksum verification."
    fi
    # --- End Checksum Verification ---

    # 5. Extract the Trivy binary
    log "Extracting Trivy from archive..."
    if ! tar -xzf "${temp_dir}/${trivy_archive}" -C "${temp_dir}"; then
        log "ERROR: Failed to extract Trivy archive."
        rm -rf "${temp_dir}"
        return 1
    fi
    log "Extraction complete."

    # 6. Install the binary to the target directory
    log "Ensuring installation directory exists: ${INSTALL_DIR}"
    mkdir -p "${INSTALL_DIR}"

    local trivy_binary_path="${temp_dir}/trivy"
    local target_path="${INSTALL_DIR}/trivy"
    
    log "Moving 'trivy' to ${target_path}."
    if ! mv "${trivy_binary_path}" "${target_path}"; then
        log "ERROR: Failed to move Trivy to ${INSTALL_DIR}."
        rm -rf "${temp_dir}"
        return 1
    fi

    # 7. Set permissions
    log "Setting execute permissions on ${target_path}."
    if ! chmod +x "${target_path}"; then
        log "ERROR: Failed to set execute permissions."
        rm -rf "${temp_dir}"
        return 1
    fi

    # 8. Update shell PATH if necessary
    log "Updating shell PATH to include ${INSTALL_DIR}"
    local shell_config_file=""
    # Detect the user's shell and set the appropriate config file
    if [[ "$SHELL" == *"zsh"* ]]; then
        shell_config_file="$HOME/.zshrc"
    elif [[ "$SHELL" == *"bash"* ]]; then
        shell_config_file="$HOME/.bash_profile"
    else
        # Fallback for other shells, default to .zshrc for modern macOS
        shell_config_file="$HOME/.zshrc"
    fi

    log "Detected shell config file: ${shell_config_file}"
    
    # Add path to the shell config file if it's not already there
    if ! grep -q "export PATH=\"${INSTALL_DIR}:\$PATH\"" "${shell_config_file}" &>/dev/null; then
        log "Adding Trivy path to ${shell_config_file}"
        echo -e "\n# Add Trivy to PATH\nexport PATH=\"${INSTALL_DIR}:\$PATH\"" >> "${shell_config_file}"
        log "NOTE: You may need to restart your terminal for the 'trivy' command to be available everywhere."
    else
        log "Trivy path already exists in ${shell_config_file}."
    fi

    # Export for the current script session so the next check works
    export PATH="${INSTALL_DIR}:$PATH"

    # 9. Clean up
    log "Cleaning up temporary files..."
    rm -rf "${temp_dir}"
    log "SUCCESS: Trivy has been installed."
    return 0
}


# --- Main Logic ---

log "Starting VS Code/Cursor extension installation script."
echo "--------------------------------------------------"
echo "SCRIPT PARAMETERS:"
echo "  - VSIX URL: ${VSIX_URL}"
echo "  - Download Filename: ${VSIX_FILENAME}"
echo "--------------------------------------------------"

# --- Check for and Install Trivy ---

log "Checking for Trivy prerequisite..."
if ! command -v trivy &> /dev/null; then
    log "Trivy is not found. Starting manual installation process..."
    install_trivy_manually
    if [ $? -ne 0 ]; then
      log "Trivy installation failed. Aborting script."
      exit 1
    fi
else
    log "Trivy is already installed at: $(command -v trivy)"
fi
echo "--------------------------------------------------"

# --- Find the 'code' command ---

log "Searching for the 'code' command-line tool..."

CODE_CMD=""

# An array of the targeted application names.
declare -a target_app_names=(
    "Visual Studio Code.app"
    "Cursor.app"
)

# An array of standard paths where the applications might be installed.
declare -a standard_app_paths=(
    "/Applications"
    "$HOME/Applications"
)

echo "Will check for apps: ${target_app_names[*]}"
echo "In directories: ${standard_app_paths[*]}"
echo "--------------------------------------------------"

# Loop through possible paths and application names to find the 'code' executable.
for app_path in "${standard_app_paths[@]}"; do
    for app_name in "${target_app_names[@]}"; do
        potential_code_path="${app_path}/${app_name}/Contents/Resources/app/bin/code"
        echo "Checking for: ${potential_code_path}"
        if [ -f "$potential_code_path" ]; then
            log "SUCCESS: Found command-line tool for '${app_name}'"
            CODE_CMD="$potential_code_path"
            break 2 # Break out of both loops once found.
        fi
    done
done

echo "--------------------------------------------------"
# --- Check if 'code' command was found ---

if [ -z "$CODE_CMD" ]; then
    log "ERROR: Could not find the command-line tool for VS Code or Cursor in standard locations."
    log "Installation of the VSIX extension will be skipped."
    exit 1
else
    log "Final 'code' command path set to: '${CODE_CMD}'"
fi
echo "--------------------------------------------------"

# --- Download the Extension ---
VSIX_DOWNLOAD_DIR="/tmp"
VSIX_PATH="${VSIX_DOWNLOAD_DIR}/${VSIX_FILENAME}"
log "Preparing to download the extension."
echo "Executing: curl -L --silent --show-error -o \"$VSIX_PATH\" \"$VSIX_URL\""

if ! curl -L --silent --show-error -o "$VSIX_PATH" "$VSIX_URL"; then
    log "ERROR: Failed to download the VSIX extension."
    exit 1
fi

log "Successfully downloaded VSIX to: ${VSIX_PATH}"
echo "--------------------------------------------------"

# --- Install the Extension ---

log "Preparing to install the extension."
echo "Executing: \"$CODE_CMD\" --install-extension \"$VSIX_PATH\" --force"

if ! "$CODE_CMD" --install-extension "$VSIX_PATH" --force; then
    log "ERROR: Failed to install the extension."
    rm -f "$VSIX_PATH"
    exit 1
fi

log "Successfully installed the extension."
echo "--------------------------------------------------"

# --- Cleanup ---

log "Cleaning up downloaded VSIX file."
echo "Executing: rm -f \"$VSIX_PATH\""
rm -f "$VSIX_PATH"

log "Script finished successfully."
exit 0
