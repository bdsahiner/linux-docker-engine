#!/bin/bash

get_distribution() {
    lsb_dist=""
    if [ -r /etc/os-release ]; then
        lsb_dist="$(. /etc/os-release && echo "$ID")"
    fi
    echo "$lsb_dist"
}

is_wsl() {
    case "$(uname -r)" in
    *microsoft* ) true ;;
    *Microsoft* ) true ;;
    * ) false;;
    esac
}

is_darwin() {
    case "$(uname -s)" in
    *darwin* ) true ;;
    *Darwin* ) true ;;
    * ) false;;
    esac
}

command_exists() {
  command -v "$@" > /dev/null 2>&1
}

lsb_dist=$( get_distribution )
lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"

if is_wsl; then
    echo "Operating System: Windows Subsystem for Linux (WSL)"
elif is_darwin; then
    echo "Operating System: macOS"
else
    dist_version=""
    case "$lsb_dist" in
        ubuntu|debian|raspbian)
            if command_exists lsb_release; then
                dist_version="$(lsb_release --codename | cut -f2)"
            fi
            if [ -z "$dist_version" ] && [ -r /etc/lsb-release ]; then
                dist_version="$(. /etc/lsb-release && echo "$DISTRIB_CODENAME")"
            fi
            echo "Operating System: $lsb_dist"
            echo "Version: $dist_version"
        ;;
        centos|rhel)
            if [ -z "$dist_version" ] && [ -r /etc/os-release ]; then
                dist_version="$(. /etc/os-release && echo "$VERSION_ID")"
            fi
            echo "Operating System: $lsb_dist"
            echo "Version: $dist_version"
        ;;
        *)
            if command_exists lsb_release; then
                dist_version="$(lsb_release --release | cut -f2)"
            fi
            if [ -z "$dist_version" ] && [ -r /etc/os-release ]; then
                dist_version="$(. /etc/os-release && echo "$VERSION_ID")"
            fi
            if [ -z "$lsb_dist" ]; then
              echo "Operating System: Unknown Linux"
            else
              echo "Operating System: $lsb_dist"
            fi
            if [ -n "$dist_version" ]; then
              echo "Version: $dist_version"
            fi
        ;;
    esac
fi

if ! command_exists curl; then
    echo "curl is not installed. Downloading..."

    case "$lsb_dist" in
        ubuntu|debian|raspbian)
            if command_exists sudo; then
                sudo apt-get update
                sudo apt-get install -y curl
            else
                apt-get update
                apt-get install -y curl
            fi
            ;;
        centos|rhel|fedora)
            if command_exists sudo; then
                sudo dnf install -y curl
            else
                dnf install -y curl
            fi
            ;;
        *)
            echo "Cannot automatically install curl on this distribution."
            echo "Please install it manually."
            exit 1
            ;;
    esac

    if command_exists curl; then
        echo "curl has been successfully installed."
    else
        echo "curl installation failed."
        exit 1
    fi
else
    echo "curl is already installed."
fi
