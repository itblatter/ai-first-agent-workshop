#!/bin/bash
# Workspace-only tool bootstrap for the Jenkins agent.
# Installs portable PowerShell 7.6.7 and pinned Allure Report 2 CLI 2.46.1
# under .tools/ in the job workspace. Idempotent: existing tools are reused.
# No system packages, no user changes, no global Jenkins configuration.
set +x
set -eu
umask 022
ulimit -c 0

printf '%s\n' 'AGENT_TOOLS_START: workspace-only tools, no system changes.'
printf 'Kernel: '; uname -srm

if [ "$(uname -s)" != Linux ] || [ "$(uname -m)" != x86_64 ]; then
    printf '%s\n' 'BLOCKED: pinned archives require Linux x86_64.'
    exit 20
fi
for tool in curl tar sha256sum git unzip; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'BLOCKED: prerequisite command unavailable: %s\n' "$tool"
        exit 21
    fi
done

tools_dir="$PWD/.tools"
mkdir -p "$tools_dir"
tool_home="$PWD/.tool-home"
mkdir -p "$tool_home"
export HOME="$tool_home"
export XDG_CACHE_HOME="$tool_home/cache"
export XDG_CONFIG_HOME="$tool_home/config"
export DOTNET_CLI_HOME="$tool_home"
# The agent image has no libicu; run portable PowerShell in invariant mode.
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
export POWERSHELL_TELEMETRY_OPTOUT=1
export POWERSHELL_UPDATECHECK=Off

pwsh_version=7.6.7
pwsh_sha256=6896f9e3a6b0a354bf470835a96da76d2f801cd50dcf047ad7c4563bf93bf431
pwsh_dir="$tools_dir/powershell-$pwsh_version"
pwsh_bin="$pwsh_dir/pwsh"
pwsh_archive="$tools_dir/powershell-$pwsh_version-linux-x64.tar.gz"

if [ ! -x "$pwsh_bin" ]; then
    if [ ! -f "$pwsh_archive" ]; then
        printf 'DOWNLOAD powershell-%s\n' "$pwsh_version"
        if ! curl --disable --fail --location --silent --proto '=https' --proto-redir '=https' \
            --connect-timeout 10 --max-time 300 \
            --output "$pwsh_archive" \
            "https://github.com/PowerShell/PowerShell/releases/download/v$pwsh_version/powershell-$pwsh_version-linux-x64.tar.gz"; then
            printf 'BLOCKED: PowerShell download failed; no retry.\n'
            exit 22
        fi
    fi
    printf '%s  %s\n' "$pwsh_sha256" "$pwsh_archive" | sha256sum --check -
    mkdir -p "$pwsh_dir"
    tar --extract --gzip --file "$pwsh_archive" \
        --directory "$pwsh_dir" --no-same-owner --no-same-permissions
    chmod a+x "$pwsh_bin"
fi

"$pwsh_bin" -NoLogo -NoProfile -NonInteractive -Command \
    'if ($PSVersionTable.PSVersion.ToString() -ne "7.6.7") { throw "Unexpected PowerShell version." }; "PowerShell " + $PSVersionTable.PSVersion.ToString()'
printf '%s\n' 'PWSH_READY'

"$pwsh_bin" -NoLogo -NoProfile -NonInteractive -File "$PWD/scripts/setup-allure.ps1"

allure_bin="$tools_dir/allure-2.46.1/bin/allure"
if [ ! -x "$allure_bin" ]; then
    printf '%s\n' 'BLOCKED: Allure launcher missing after installer.'
    exit 30
fi
printf '%s\n' 'AGENT_TOOLS_READY: portable pwsh + pinned Allure 2.46.1.'
