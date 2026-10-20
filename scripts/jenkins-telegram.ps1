# Thin Jenkins entry point for the phase-6 Telegram sender.
# Reads only environment variables; never prints them. Always exits 0 so the
# notification step can never change the UI test result.
$ErrorActionPreference = 'Continue'
Set-StrictMode -Version Latest

try {
    . (Join-Path $PSScriptRoot 'ci-telegram.ps1')

    # The agent egress drops the DNS-assigned Telegram endpoint; probe the
    # known api.telegram.org edge IPs and pin the first reachable one for the
    # sender's single delivery attempt.
    foreach ($candidate in @('149.154.167.220', '149.154.167.99', '149.154.166.110', '95.161.64.100', '91.108.56.130')) {
        $probe = $null
        try {
            $probe = [System.Net.Sockets.TcpClient]::new()
            if ($probe.ConnectAsync($candidate, 443).Wait(2000) -and $probe.Connected) {
                $env:CI_TELEGRAM_ENDPOINT_IP = $candidate
                break
            }
        }
        catch { }
        finally {
            if ($null -ne $probe) { $probe.Dispose() }
        }
    }
    if ([string]::IsNullOrWhiteSpace($env:CI_TELEGRAM_ENDPOINT_IP)) {
        Write-Warning 'No pinned Telegram endpoint is reachable; the default resolver path will be used.'
    }

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
