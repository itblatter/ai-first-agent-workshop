$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ci-telegram.ps1')

$script:assertions = 0
function Assert-True {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw "Assertion failed: $Name" }
    $script:assertions++
}

$build = Join-Path (Split-Path -Parent $PSScriptRoot) 'build'
Get-Item -LiteralPath $build -ErrorAction Stop | Out-Null
$fixtures = Join-Path $build ("phase6-tests-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtures | Out-Null
$pass = '<testsuite name="tests.SearchTests" tests="1" failures="0" errors="0" skipped="0"><testcase name="pass"/></testsuite>'
$failure = '<testsuite name="tests.SearchTests" tests="1" failures="1" errors="0" skipped="0"><testcase name="fail"><failure message="expected"/></testcase></testsuite>'
$cases = @(
    @{ Name = 'missing'; Xml = @(); Expected = 'missing' }
    @{ Name = 'pass'; Xml = @($pass); Expected = 'no-failures' }
    @{ Name = 'failure'; Xml = @($failure); Expected = 'failed' }
    @{ Name = 'error'; Xml = @('<testsuite tests="1" failures="0" errors="1" skipped="0"><testcase><error/></testcase></testsuite>'); Expected = 'failed' }
    @{ Name = 'skipped'; Xml = @('<testsuite tests="1" failures="0" errors="0" skipped="1"><testcase><skipped/></testcase></testsuite>'); Expected = 'no-failures' }
    @{ Name = 'zero'; Xml = @('<testsuite tests="0" failures="0" errors="0" skipped="0"/>'); Expected = 'empty' }
    @{ Name = 'malformed'; Xml = @('<testsuite'); Expected = 'invalid' }
    @{ Name = 'wrong-root'; Xml = @('<results/>'); Expected = 'invalid' }
    @{ Name = 'missing-counts'; Xml = @('<testsuite><testcase/></testsuite>'); Expected = 'invalid' }
    @{ Name = 'mismatch'; Xml = @('<testsuite tests="0" failures="0" errors="0" skipped="0"><testcase/></testsuite>'); Expected = 'invalid' }
    @{ Name = 'hidden-failure'; Xml = @($failure.Replace('failures="1"', 'failures="0"')); Expected = 'invalid' }
    @{ Name = 'negative'; Xml = @($pass.Replace('tests="1"', 'tests="-1"')); Expected = 'invalid' }
    @{ Name = 'overflow'; Xml = @($pass.Replace('tests="1"', 'tests="999999999999999999"')); Expected = 'invalid' }
    @{ Name = 'decimal'; Xml = @($pass.Replace('tests="1"', 'tests="1.0"')); Expected = 'invalid' }
    @{ Name = 'conflicting-state'; Xml = @('<testsuite tests="1" failures="1" errors="1" skipped="0"><testcase><failure/><error/></testcase></testsuite>'); Expected = 'invalid' }
    @{ Name = 'dtd'; Xml = @('<!DOCTYPE testsuite [<!ENTITY x SYSTEM "file:///should-not-be-read">]><testsuite tests="0" failures="0" errors="0" skipped="0">&x;</testsuite>'); Expected = 'invalid' }
    @{ Name = 'multiple'; Xml = @($pass, $failure); Expected = 'failed' }
    @{ Name = 'partial-invalid'; Xml = @($failure, '<broken'); Expected = 'invalid' }
    @{ Name = 'stdout-not-evidence'; Xml = @($pass.Replace('</testsuite>', '<system-out>failure error skipped</system-out></testsuite>')); Expected = 'no-failures' }
)
foreach ($case in $cases) {
    $directory = Join-Path $fixtures $case.Name
    New-Item -ItemType Directory -Path $directory | Out-Null
    for ($i = 0; $i -lt $case.Xml.Count; $i++) {
        [IO.File]::WriteAllText((Join-Path $directory "TEST-$i.xml"), $case.Xml[$i])
    }
    Assert-True ((Get-UiTestEvidence $directory) -ceq $case.Expected) "XML: $($case.Name)"
}
Assert-True ((Get-UiTestEvidence (Join-Path $fixtures 'not-created')) -ceq 'missing') 'Absent results directory'

$messageArgs = @{
    Project = 'itblatter/ai-first-agent-workshop'
    Branch = 'main'
    RunUrl = 'https://github.com/itblatter/ai-first-agent-workshop/actions/runs/123'
}
$messages = @(
    @{ Job = 'success'; Outcome = 'success'; Evidence = 'no-failures'; Reason = 'Test step succeeded; JUnit reports no failures.' }
    @{ Job = 'failure'; Outcome = 'failure'; Evidence = 'failed'; Reason = 'Test failures confirmed by JUnit XML.' }
    @{ Job = 'failure'; Outcome = 'skipped'; Evidence = ''; Reason = 'Environment preparation failed; tests were not started.' }
    @{ Job = 'failure'; Outcome = 'success'; Evidence = 'no-failures'; Reason = 'Post-test CI processing failed.' }
    @{ Job = 'failure'; Outcome = 'failure'; Evidence = 'missing'; Reason = 'Build/test execution failed; test results are missing.' }
    @{ Job = 'failure'; Outcome = 'failure'; Evidence = 'invalid'; Reason = 'Build/test execution failed; test results are unverified.' }
    @{ Job = 'failure'; Outcome = 'failure'; Evidence = 'empty'; Reason = 'Build/test execution failed; JUnit contains zero test cases.' }
    @{ Job = 'failure'; Outcome = 'failure'; Evidence = 'no-failures'; Reason = 'Build/test execution failed; JUnit does not confirm failing tests.' }
    @{ Job = 'success'; Outcome = 'success'; Evidence = 'missing'; Reason = 'Test job succeeded; test results are unverified.' }
    @{ Job = 'success'; Outcome = 'success'; Evidence = 'empty'; Reason = 'Test step succeeded; JUnit contains zero test cases.' }
    @{ Job = 'success'; Outcome = 'success'; Evidence = 'failed'; Reason = 'JUnit reports test failures despite a successful job.' }
    @{ Job = 'failure'; Outcome = ''; Evidence = ''; Reason = 'CI failed; the test phase result is unavailable.' }
    @{ Job = 'cancelled'; Outcome = 'cancelled'; Evidence = ''; Reason = 'Run cancelled; the final test result is unconfirmed.' }
)
foreach ($case in $messages) {
    $text = New-CiTelegramMessage @messageArgs -JobResult $case.Job -TestOutcome $case.Outcome -TestEvidence $case.Evidence
    Assert-True ($text.Contains("CI status: $($case.Job.ToUpperInvariant())")) 'Status comes from final job result'
    Assert-True ($text.Contains("Reason: $($case.Reason)")) 'Precise failure classification'
    Assert-True ($text.Contains("Run: $($messageArgs.RunUrl)")) 'Real run link'
    Assert-True ($text.Contains("Project: $($messageArgs.Project)") -and $text.Contains('Branch: main')) 'Project and branch'
    Assert-True (-not $text.Contains('passed:') -and -not $text.Contains('build/allure-report')) 'No counters or local report link'
}

# Replace the only network boundary before any send test. No real credentials are read.
$script:requests = New-Object 'System.Collections.Generic.List[object]'
$script:httpStatus = 200
$script:responseBody = '{"ok":true,"result":{"message_id":123}}'
$script:transportThrows = $false
function Invoke-TelegramRequest {
    param([string]$BotToken, [string]$Json)
    $script:requests.Add(@{ Token = $BotToken; Json = $Json })
    if ($script:transportThrows) {
        throw "Synthetic transport failure: https://api.telegram.org/bot$BotToken/sendMessage $Json"
    }
    return [pscustomobject]@{ StatusCode = $script:httpStatus; Content = $script:responseBody }
}

$sendArgs = @{
    BotToken = 'SYNTHETIC_TOKEN_CANARY_NOT_A_CREDENTIAL'
    ChatId = 'SYNTHETIC_CHAT_CANARY'
    Project = $messageArgs.Project
    Branch = $messageArgs.Branch
    JobResult = 'failure'
    TestOutcome = 'failure'
    TestEvidence = 'failed'
    RunUrl = $messageArgs.RunUrl
}
function Assert-SafeOutput {
    param([object[]]$Output)
    $rendered = $Output | Out-String
    Assert-True (-not $rendered.Contains($sendArgs.BotToken)) 'No token in output streams'
    Assert-True (-not $rendered.Contains($sendArgs.ChatId)) 'No chat ID in output streams'
    Assert-True (-not $rendered.Contains('api.telegram.org/bot')) 'No token-bearing URL in output streams'
}

$VerbosePreference = 'Continue'
$DebugPreference = 'Continue'
$output = @(Send-CiTelegramNotification @sendArgs *>&1)
Assert-True ($output[-1] -ceq 'sent') 'API success'
Assert-True ($script:requests.Count -eq 1) 'Exactly one request'
Assert-SafeOutput $output
$payload = $script:requests[0].Json | ConvertFrom-Json
Assert-True ($payload.chat_id -ceq $sendArgs.ChatId) 'Chat ID serialized'
Assert-True (-not $payload.text.Contains($sendArgs.BotToken) -and -not $payload.text.Contains($sendArgs.ChatId)) 'Message contains no credentials'
Assert-True ($null -eq $payload.PSObject.Properties['parse_mode']) 'No Markdown/HTML parse mode'
Assert-True ($payload.link_preview_options.is_disabled -eq $true) 'Link previews disabled'

$sendArgs.Branch = 'feature/"quotes"\path<&>*_`$()' + [char]0x416 + [char]0xD83D + [char]0xDE80 + "`nInjected: no`r`tend"
$output = @(Send-CiTelegramNotification @sendArgs *>&1)
$payload = $script:requests[1].Json | ConvertFrom-Json
$expectedBranch = [regex]::Replace($sendArgs.Branch, '[\x00-\x1f\x7f]', ' ')
Assert-True ($payload.text.Contains("Branch: $expectedBranch`nCI status: FAILURE")) 'Quotes, backslashes, Unicode and line breaks round-trip'
Assert-True (($payload.text.Split("`n")).Count -eq 5) 'Metadata cannot inject extra lines'
Assert-SafeOutput $output
$sendArgs.Branch = 'main'

$responses = @(
    @{ Status = 200; Body = '{"ok":false,"description":"SYNTHETIC_TOKEN_CANARY_NOT_A_CREDENTIAL"}' }
    @{ Status = 200; Body = '{"ok":"true"}' }
    @{ Status = 200; Body = '{}' }
    @{ Status = 200; Body = '[{"ok":true}]' }
    @{ Status = 200; Body = '{"ok":1}' }
    @{ Status = 200; Body = 'null' }
    @{ Status = 200; Body = '<not-json>SYNTHETIC_CHAT_CANARY</not-json>' }
    @{ Status = 400; Body = '{"ok":true}' }
    @{ Status = 401; Body = '{"ok":false}' }
    @{ Status = 429; Body = '{"ok":false,"parameters":{"retry_after":1}}' }
    @{ Status = 500; Body = '{"ok":false}' }
    @{ Status = 302; Body = '{"ok":true}' }
)
foreach ($response in $responses) {
    $script:httpStatus = $response.Status
    $script:responseBody = $response.Body
    $before = $script:requests.Count
    $output = @(Send-CiTelegramNotification @sendArgs *>&1)
    Assert-True ($output[-1] -ceq 'failed') 'HTTP and API failures detected'
    Assert-True ($script:requests.Count -eq $before + 1) 'No retry on rejected or ambiguous response'
    Assert-True ($sendArgs.JobResult -ceq 'failure') 'Notification failure does not mutate UI failure'
    Assert-SafeOutput $output
}
$script:transportThrows = $true
$before = $script:requests.Count
$output = @(Send-CiTelegramNotification @sendArgs *>&1)
Assert-True ($output[-1] -ceq 'failed') 'Transport exception handled'
Assert-True ($script:requests.Count -eq $before + 1) 'No retry after timeout or transport exception'
Assert-SafeOutput $output
$script:transportThrows = $false
$argsForCase = $sendArgs.Clone()
$argsForCase.JobResult = 'success'
$script:httpStatus = 503
$output = @(Send-CiTelegramNotification @argsForCase *>&1)
Assert-True ($output[-1] -ceq 'failed' -and $argsForCase.JobResult -ceq 'success') 'Notification failure does not mutate UI success'
Assert-SafeOutput $output

foreach ($jobResult in @('success', 'failure', 'cancelled', 'skipped')) {
    foreach ($configuration in @('complete', 'no-token', 'no-chat', 'empty')) {
        $argsForCase = $sendArgs.Clone()
        $argsForCase.JobResult = $jobResult
        if ($configuration -in @('no-token', 'empty')) { $argsForCase.BotToken = ' ' }
        if ($configuration -in @('no-chat', 'empty')) { $argsForCase.ChatId = '' }
        $script:httpStatus = 200
        $script:responseBody = '{"ok":true}'
        $before = $script:requests.Count
        $output = @(Send-CiTelegramNotification @argsForCase *>&1)
        $shouldSend = $jobResult -in @('success', 'failure') -and $configuration -eq 'complete'
        if ($shouldSend) {
            Assert-True ($output[-1] -ceq 'sent' -and $script:requests.Count -eq $before + 1) 'One send for configured success/failure'
        }
        else {
            Assert-True ($output[-1] -ceq 'skipped' -and $script:requests.Count -eq $before) 'No send for cancellation, skipped job or missing secrets'
        }
        Assert-SafeOutput $output
    }
}
$argsForCase = $sendArgs.Clone()
$argsForCase.Branch = 'x' * 4096
$before = $script:requests.Count
$output = @(Send-CiTelegramNotification @argsForCase *>&1)
Assert-True ($output[-1] -ceq 'failed' -and $script:requests.Count -eq $before) 'Oversized text rejected before sending'
Assert-SafeOutput $output

Write-Output "$script:assertions assertions passed. Transport mocked; no network requests or real credentials."
