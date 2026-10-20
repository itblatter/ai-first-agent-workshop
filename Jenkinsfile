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
                        secretNames.each { env[it] = params[it].toString() }
                    } else if (fileExists(secretsFile)) {
                        def resolved = [:]
                        readFile(secretsFile).eachLine { line ->
                            def idx = line.indexOf('=')
                            if (idx > 0) { resolved[line.substring(0, idx)] = line.substring(idx + 1) }
                        }
                        secretNames.each {
                            if (resolved[it] != null && !resolved[it].trim().isEmpty()) { env[it] = resolved[it] }
                        }
                    }
                    def missing = secretNames.findAll {
                        env[it] == null || env[it].toString().trim().isEmpty()
                    }
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
                sh(label: 'Install portable pwsh and pinned Allure 2.46.1 into workspace',
                   script: 'bash scripts/setup-agent-tools.sh')
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
                    sh(label: 'Generate Allure report with pinned CLI 2.46.1', script: '''
                        set -eu
                        if [ -d build/allure-results ] && ls build/allure-results/*-result.json >/dev/null 2>&1; then
                            "$PWD/.tools/allure-2.46.1/bin/allure" generate build/allure-results \
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
                                "$PWD/.tools/powershell-7.6.7/pwsh" -NoLogo -NoProfile -NonInteractive \
                                    -File scripts/jenkins-telegram.ps1
                            ''')
                    } catch (Throwable telegramError) {
                        echo "Telegram step failed: ${telegramError.getMessage()}"
                    }
                }
            }
        }
    }
}
