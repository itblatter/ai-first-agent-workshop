pipeline {
    agent { label 'java-jdk21-jenkins-agent-1' }

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(
            daysToKeepStr: '14', numToKeepStr: '30',
            artifactDaysToKeepStr: '14', artifactNumToKeepStr: '30'
        ))
    }

    // Parameters are defined in the job configuration, not here: a Jenkinsfile
    // parameters block would overwrite them on every run and wipe the saved
    // password defaults.

    environment {
        ALLURE_VERSION = '2.46.1'
        ALLURE_SHA256 = 'd25c519bbde940dc953cff8901130ce18b73013dc19a8f8b90b8b4b1c5eb252f'
        PWSH_VERSION = '7.6.7'
        PWSH_SHA256 = '6896f9e3a6b0a354bf470835a96da76d2f801cd50dcf047ad7c4563bf93bf431'
        DOTNET_SYSTEM_GLOBALIZATION_INVARIANT = '1'
        POWERSHELL_TELEMETRY_OPTOUT = '1'
        POWERSHELL_UPDATECHECK = 'Off'
    }

    stages {
        stage('Resolve secrets') {
            steps {
                script {
                    def secretNames = ['SELENOID_USER', 'SELENOID_PASSWORD',
                                       'TELEGRAM_BOT_TOKEN', 'TELEGRAM_CHAT_ID']
                    def secretsFile = '.ci-secrets.env'
                    def provided = secretNames.every {
                        params[it] != null && !params[it].toString().trim().isEmpty()
                    }
                    if (provided) {
                        // Keep secrets off command lines: write them into the
                        // agent-local file so later runs work without params.
                        writeFile file: secretsFile,
                                  text: secretNames.collect { "${it}=${params[it]}" }.join('\n') + '\n'
                        sh(label: 'Restrict secrets file permissions', script: "chmod 600 ${secretsFile}")
                    } else if (fileExists(secretsFile)) {
                        def resolved = [:]
                        readFile(secretsFile).split('\n').each { line ->
                            def idx = line.indexOf('=')
                            if (idx > 0) { resolved.put(line.substring(0, idx).trim(), line.substring(idx + 1).trim()) }
                        }
                        env.SELENOID_USER = resolved['SELENOID_USER'] ?: ''
                        env.SELENOID_PASSWORD = resolved['SELENOID_PASSWORD'] ?: ''
                        env.TELEGRAM_BOT_TOKEN = resolved['TELEGRAM_BOT_TOKEN'] ?: ''
                        env.TELEGRAM_CHAT_ID = resolved['TELEGRAM_CHAT_ID'] ?: ''
                    }
                    def effective = [
                        SELENOID_USER      : env.SELENOID_USER ?: params.SELENOID_USER,
                        SELENOID_PASSWORD  : env.SELENOID_PASSWORD ?: params.SELENOID_PASSWORD,
                        TELEGRAM_BOT_TOKEN : env.TELEGRAM_BOT_TOKEN ?: params.TELEGRAM_BOT_TOKEN,
                        TELEGRAM_CHAT_ID   : env.TELEGRAM_CHAT_ID ?: params.TELEGRAM_CHAT_ID
                    ]
                    def missing = effective.findAll {
                        it.value == null || it.value.toString().trim().isEmpty()
                    }.collect { it.key }
                    if (!missing.isEmpty()) {
                        error("Required secrets are missing as parameters and in ${secretsFile}: ${missing.join(', ')}")
                    }
                }
            }
        }

        stage('Validate parameters') {
            steps {
                script {
                    if (!(params.UI_BROWSER_SIZE ==~ /\d{3,4}x\d{3,4}/)) {
                        error('UI_BROWSER_SIZE must match WIDTHxHEIGHT with 3-4 digits per dimension.')
                    }
                }
            }
        }

        stage('Prepare agent tools') {
            steps {
                sh(label: 'Install portable pwsh and pinned Allure into workspace', script: '''#!/bin/bash
                    # Workspace-only tool bootstrap for the Jenkins agent.
                    # Installs portable PowerShell 7.6.7 and pinned Allure Report 2 CLI 2.46.1
                    # under .tools/ in the job workspace. Idempotent: existing tools are reused.
                    # No system packages, no user changes, no global Jenkins configuration.
                    set +x
                    set -eu
                    umask 022
                    ulimit -c 0

                    printf '%s\\n' 'AGENT_TOOLS_START: workspace-only tools, no system changes.'
                    printf 'Kernel: '; uname -srm
                    if [ "$(uname -s)" != Linux ] || [ "$(uname -m)" != x86_64 ]; then
                        printf '%s\\n' 'BLOCKED: pinned archives require Linux x86_64.'
                        exit 20
                    fi
                    for tool in curl tar sha256sum git unzip; do
                        if ! command -v "$tool" >/dev/null 2>&1; then
                            printf 'BLOCKED: prerequisite command unavailable: %s\\n' "$tool"
                            exit 21
                        fi
                    done

                    tools_dir="$PWD/.tools"
                    tool_home="$PWD/.tool-home"
                    mkdir -p "$tools_dir" "$tool_home"
                    export HOME="$tool_home"
                    export XDG_CACHE_HOME="$tool_home/cache"
                    export XDG_CONFIG_HOME="$tool_home/config"
                    export DOTNET_CLI_HOME="$tool_home"
                    pwsh_dir="$tools_dir/powershell-$PWSH_VERSION"
                    pwsh_bin="$pwsh_dir/pwsh"
                    pwsh_archive="$tools_dir/powershell-$PWSH_VERSION-linux-x64.tar.gz"
                    if [ ! -x "$pwsh_bin" ]; then
                        if [ ! -f "$pwsh_archive" ]; then
                            printf 'DOWNLOAD powershell-%s\\n' "$PWSH_VERSION"
                            if ! curl --disable --fail --location --silent --proto '=https' --proto-redir '=https' \
                                --connect-timeout 10 --max-time 300 \
                                --output "$pwsh_archive" \
                                "https://github.com/PowerShell/PowerShell/releases/download/v$PWSH_VERSION/powershell-$PWSH_VERSION-linux-x64.tar.gz"; then
                                printf 'BLOCKED: PowerShell download failed; no retry.\\n'
                                exit 22
                            fi
                        fi
                        printf '%s  %s\\n' "$PWSH_SHA256" "$pwsh_archive" | sha256sum --check -
                        mkdir -p "$pwsh_dir"
                        tar --extract --gzip --file "$pwsh_archive" \
                            --directory "$pwsh_dir" --no-same-owner --no-same-permissions
                        chmod a+x "$pwsh_bin"
                    fi
                    # The agent image has no libicu; run portable PowerShell in invariant mode.
                    "$pwsh_bin" -NoLogo -NoProfile -NonInteractive -Command \
                        'if ($PSVersionTable.PSVersion.ToString() -ne $env:PWSH_VERSION) { throw "Unexpected PowerShell version." }; "PowerShell " + $PSVersionTable.PSVersion.ToString()'
                    printf '%s\\n' 'PWSH_READY'

                    if [ -z "${JAVA_HOME:-}" ] || [ ! -f "$JAVA_HOME/bin/java" ]; then
                        printf '%s\\n' 'Set JAVA_HOME to an installed JDK before installing Allure.'
                        exit 1
                    fi
                    allure_archive="$tools_dir/allure-commandline-$ALLURE_VERSION.zip"
                    allure_bin="$tools_dir/allure-$ALLURE_VERSION/bin/allure"
                    if [ ! -f "$allure_archive" ]; then
                        curl --disable --fail --location --silent --proto '=https' --proto-redir '=https' \
                            --connect-timeout 10 --max-time 300 --output "$allure_archive" \
                            "https://repo.maven.apache.org/maven2/io/qameta/allure/allure-commandline/$ALLURE_VERSION/allure-commandline-$ALLURE_VERSION.zip"
                    fi
                    printf '%s  %s\\n' "$ALLURE_SHA256" "$allure_archive" | sha256sum --check -
                    if [ ! -f "$allure_bin" ]; then
                        unzip -q "$allure_archive" -d "$tools_dir"
                    fi
                    chmod a+x "$allure_bin"
                    actual_version="$("$allure_bin" --version)"
                    if [ "$actual_version" != "$ALLURE_VERSION" ]; then
                        printf 'Expected Allure Report %s, got: %s\\n' "$ALLURE_VERSION" "$actual_version"
                        exit 1
                    fi
                    if [ ! -x "$allure_bin" ]; then
                        printf '%s\\n' 'BLOCKED: Allure launcher missing after installer.'
                        exit 30
                    fi
                    printf 'AGENT_TOOLS_READY: portable pwsh + pinned Allure %s.\\n' "$ALLURE_VERSION"
                ''')
            }
        }

        stage('UI tests') {
            steps {
                script {
                    env.UI_TEST_OUTCOME = 'skipped'
                    try {
                        sh(label: 'Gradle UI tests against selenoid.qa.guru', script: '''
                                set +x
                                set -eu
                                export UI_REMOTE="https://${SELENOID_USER}:${SELENOID_PASSWORD}@selenoid.qa.guru/wd/hub"
                                ./gradlew test --no-daemon --console=plain \
                                    "-Dselenide.baseUrl=${UI_BASE_URL}" \
                                    "-Dselenide.browser=${UI_BROWSER}" \
                                    "-Dselenide.browserVersion=${UI_BROWSER_VERSION}" \
                                    "-Dselenide.browserSize=${UI_BROWSER_SIZE}" \
                                    "-Dselenide.headless=false"
                            ''')
                        env.UI_TEST_OUTCOME = 'success'
                    } catch (Throwable testError) {
                        env.UI_TEST_OUTCOME = 'failure'
                        throw testError
                    }
                }
            }
        }
    }

    post {
        always {
            script {
                // Raw evidence first: JUnit XML and Allure results are preserved
                // independently of test outcome and of report generation.
                try {
                    junit testResults: 'build/test-results/test/TEST-*.xml',
                          allowEmptyResults: true, skipMarkingBuildUnstable: true
                } catch (Throwable junitError) {
                    echo "JUnit publication failed: ${junitError.getMessage()}"
                }
                archiveArtifacts artifacts: 'build/test-results/test/**, build/reports/tests/test/**',
                                 allowEmptyArchive: true
                archiveArtifacts artifacts: 'build/allure-results/**', allowEmptyArchive: true

                // Pinned Allure Report 2 CLI generates the canonical report artifact
                // even when tests failed, as long as raw results exist.
                try {
                    sh(label: 'Generate Allure report with pinned CLI', script: '''
                        set -eu
                        if [ -d build/allure-results ] && ls build/allure-results/*-result.json >/dev/null 2>&1; then
                            "$PWD/.tools/allure-$ALLURE_VERSION/bin/allure" generate build/allure-results \
                                --clean -o build/allure-report
                        else
                            echo 'No Allure test results were produced; report was not generated.'
                        fi
                    ''')
                    archiveArtifacts artifacts: 'build/allure-report/**', allowEmptyArchive: true
                } catch (Throwable reportError) {
                    echo "Pinned Allure report generation failed: ${reportError.getMessage()}"
                }

                // Jenkins Allure plugin view; failure here must not change the build result.
                try {
                    allure includeProperties: false, jdk: '', reportBuildPolicy: 'ALWAYS',
                           results: [[path: 'build/allure-results']]
                } catch (Throwable allureError) {
                    echo "Allure plugin step failed: ${allureError.getMessage()}"
                }

                // One Telegram notification per run; delivery problems are warnings only.
                def jobResult
                switch (currentBuild.currentResult) {
                    case 'SUCCESS': jobResult = 'success'; break
                    case 'FAILURE': jobResult = 'failure'; break
                    case 'ABORTED': jobResult = 'cancelled'; break
                    default: jobResult = (currentBuild.currentResult ?: 'UNKNOWN').toLowerCase()
                }
                if (!params.SEND_TELEGRAM) {
                    echo 'Telegram notification skipped: SEND_TELEGRAM parameter is off.'
                } else if (env.TELEGRAM_BOT_TOKEN == null || env.TELEGRAM_BOT_TOKEN.toString().trim().isEmpty()
                           || env.TELEGRAM_CHAT_ID == null || env.TELEGRAM_CHAT_ID.toString().trim().isEmpty()) {
                    echo 'Telegram notification skipped: Telegram secrets were not resolved.'
                } else {
                    try {
                        env.UI_JOB_RESULT = jobResult
                        env.UI_RUN_URL = env.BUILD_URL
                        env.UI_PROJECT = env.JOB_NAME
                        env.UI_BRANCH = env.GIT_BRANCH ?: 'main'
                        sh(label: 'Send Telegram notification via existing sender', script: '''
                                set +x
                                "$PWD/.tools/powershell-$PWSH_VERSION/pwsh" -NoLogo -NoProfile -NonInteractive \
                                    -File ci/jenkins-telegram.ps1
                            ''')
                    } catch (Throwable telegramError) {
                        echo "Telegram step failed: ${telegramError.getMessage()}"
                    }
                }
            }
        }
    }
}
