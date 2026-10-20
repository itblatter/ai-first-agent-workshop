# Thin Jenkins entry point for the phase-6 Telegram sender.
# Reads only environment variables; never prints them. Always exits 0 so the
# notification step can never change the UI test result.
$ErrorActionPreference = 'Continue'
Set-StrictMode -Version Latest

try {
    . (Join-Path $PSScriptRoot 'ci-telegram.ps1')

    $evidence = 'invalid'
    try {
        $evidence = Get-UiTestEvidence -ResultsDirectory 'build/test-results/test'
    }
    catch {
        Write-Warning 'JUnit evidence could not be inspected; the test result is unverified.'
    }

    $delivery = Send-CiTelegramNotification `
        -BotToken $env:TELEGRAM_BOT_TOKEN `
        -ChatId $env:TELEGRAM_CHAT_ID `
        -Project $env:UI_PROJECT `
        -Branch $env:UI_BRANCH `
        -JobResult $env:UI_JOB_RESULT `
        -TestOutcome $env:UI_TEST_OUTCOME `
        -TestEvidence $evidence `
        -RunUrl $env:UI_RUN_URL
    Write-Output "Telegram notification: $delivery"
}
catch {
    Write-Warning 'Telegram notification could not run; the UI job result is unchanged.'
}
exit 0
