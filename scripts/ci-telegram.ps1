Set-StrictMode -Version Latest

function Get-UiTestEvidence {
    param([string]$ResultsDirectory)

    try {
        if (-not (Test-Path -LiteralPath $ResultsDirectory -PathType Container -ErrorAction Stop)) { return 'missing' }
        $files = @(Get-ChildItem -LiteralPath $ResultsDirectory -Filter 'TEST-*.xml' -File -ErrorAction Stop)
        if ($files.Count -eq 0) { return 'missing' }

        $total = 0L
        $failed = $false
        foreach ($file in $files) {
            $settings = New-Object System.Xml.XmlReaderSettings
            $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
            $settings.XmlResolver = $null
            $settings.MaxCharactersInDocument = 5MB
            $reader = $null
            try {
                $reader = [System.Xml.XmlReader]::Create($file.FullName, $settings)
                $document = New-Object System.Xml.XmlDocument
                $document.XmlResolver = $null
                $document.Load($reader)
            }
            finally {
                if ($null -ne $reader) { $reader.Dispose() }
            }

            $suite = $document.get_DocumentElement()
            # PowerShell's XML adapter maps .Name to a "name" attribute, if present.
            if ($suite.get_Name() -cne 'testsuite' -or $suite.get_NamespaceURI() -ne '') { return 'invalid' }
            $counts = @{}
            foreach ($name in @('tests', 'failures', 'errors', 'skipped')) {
                $value = $suite.GetAttribute($name)
                $number = 0
                if ($value -cnotmatch '\A[0-9]+\z' -or -not [int]::TryParse($value, [ref]$number)) {
                    return 'invalid'
                }
                $counts[$name] = $number
            }

            # Check Gradle's counters against actual cases, not arbitrary XML text.
            $cases = @($suite.SelectNodes('testcase'))
            $actual = @{ failures = 0; errors = 0; skipped = 0 }
            foreach ($case in $cases) {
                $states = 0
                foreach ($state in @('failure', 'error', 'skipped')) {
                    if ($case.SelectNodes($state).Count -gt 0) {
                        $key = @{ failure = 'failures'; error = 'errors'; skipped = 'skipped' }[$state]
                        $actual[$key]++
                        $states++
                    }
                }
                if ($states -gt 1) { return 'invalid' }
            }
            if ($counts.tests -ne $cases.Count) { return 'invalid' }
            foreach ($name in @('failures', 'errors', 'skipped')) {
                if ($counts[$name] -ne $actual[$name]) { return 'invalid' }
            }
            $total += $counts.tests
            if ($counts.failures -gt 0 -or $counts.errors -gt 0) { $failed = $true }
        }
        if ($failed) { return 'failed' }
        if ($total -eq 0) { return 'empty' }
        return 'no-failures'
    }
    catch {
        # XML and paths may contain sensitive content; never print parser errors.
        return 'invalid'
    }
}

function New-CiTelegramMessage {
    param(
        [string]$Project,
        [string]$Branch,
        [string]$JobResult,
        [string]$TestOutcome,
        [string]$TestEvidence,
        [string]$RunUrl
    )

    if ($JobResult -eq 'success') {
        switch ($TestEvidence) {
            'no-failures' { $reason = 'Test step succeeded; JUnit reports no failures.' }
            'empty' { $reason = 'Test step succeeded; JUnit contains zero test cases.' }
            'failed' { $reason = 'JUnit reports test failures despite a successful job.' }
            default { $reason = 'Test job succeeded; test results are unverified.' }
        }
    }
    elseif ($JobResult -eq 'failure') {
        if ($TestOutcome -eq 'skipped') {
            $reason = 'Environment preparation failed; tests were not started.'
        }
        elseif ($TestOutcome -eq 'success') {
            $reason = 'Post-test CI processing failed.'
        }
        elseif ($TestOutcome -eq 'failure') {
            switch ($TestEvidence) {
                'failed' { $reason = 'Test failures confirmed by JUnit XML.' }
                'empty' { $reason = 'Build/test execution failed; JUnit contains zero test cases.' }
                'no-failures' { $reason = 'Build/test execution failed; JUnit does not confirm failing tests.' }
                'missing' { $reason = 'Build/test execution failed; test results are missing.' }
                default { $reason = 'Build/test execution failed; test results are unverified.' }
            }
        }
        else {
            $reason = 'CI failed; the test phase result is unavailable.'
        }
    }
    elseif ($JobResult -eq 'cancelled') {
        $reason = 'Run cancelled; the final test result is unconfirmed.'
    }
    else {
        $reason = 'Test job did not complete with a supported result.'
    }

    # Keep metadata on one line; JSON serialization handles quotes and Unicode.
    $projectLine = [regex]::Replace($Project, '[\x00-\x1f\x7f]', ' ')
    $branchLine = [regex]::Replace($Branch, '[\x00-\x1f\x7f]', ' ')
    $urlLine = [regex]::Replace($RunUrl, '[\x00-\x1f\x7f]', ' ')
    $status = switch ($JobResult) {
        'success' { 'SUCCESS' }
        'failure' { 'FAILURE' }
        'cancelled' { 'CANCELLED' }
        default { 'UNKNOWN' }
    }
    return "Project: $projectLine`nBranch: $branchLine`nCI status: $status`nReason: $reason`nRun: $urlLine"
}

function Invoke-TelegramPinnedRequest {
    param([string]$BotToken, [string]$Json, [string]$EndpointIp)

    $tcp = $null
    $ssl = $null
    try {
        $tcp = [System.Net.Sockets.TcpClient]::new()
        $connect = $tcp.ConnectAsync($EndpointIp, 443)
        if (-not $connect.Wait([TimeSpan]::FromSeconds(8))) {
            throw 'Pinned Telegram endpoint connect timed out.'
        }
        $null = $connect.GetAwaiter().GetResult()
        $ssl = [System.Net.Security.SslStream]::new($tcp.GetStream(), $false)
        $ssl.WriteTimeout = 10000
        $auth = $ssl.AuthenticateAsClientAsync('api.telegram.org')
        if (-not $auth.Wait([TimeSpan]::FromSeconds(12))) {
            throw 'Pinned Telegram endpoint TLS handshake timed out.'
        }
        $null = $auth.GetAwaiter().GetResult()

        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($Json)
        $requestHead = "POST /bot$BotToken/sendMessage HTTP/1.1`r`n" +
            "Host: api.telegram.org`r`n" +
            "Content-Type: application/json`r`n" +
            "Content-Length: $($bodyBytes.Length)`r`n" +
            "Connection: close`r`n`r`n"
        $headBytes = [System.Text.Encoding]::ASCII.GetBytes($requestHead)
        $ssl.Write($headBytes, 0, $headBytes.Length)
        $ssl.Write($bodyBytes, 0, $bodyBytes.Length)
        $ssl.Flush()

        $buffer = [System.IO.MemoryStream]::new()
        $chunk = New-Object byte[] 16384
        $deadline = [DateTime]::UtcNow.AddSeconds(15)
        while ($true) {
            $readTask = $ssl.ReadAsync($chunk, 0, $chunk.Length)
            $remaining = [int]($deadline - [DateTime]::UtcNow).TotalMilliseconds
            if ($remaining -le 0 -or -not $readTask.Wait($remaining)) {
                throw 'Pinned Telegram endpoint response timed out.'
            }
            $count = $readTask.Result
            if ($count -le 0) { break }
            $buffer.Write($chunk, 0, $count)
        }

        $rawBytes = $buffer.ToArray()
        $headerEnd = -1
        for ($i = 0; $i -le $rawBytes.Length - 4; $i++) {
            if ($rawBytes[$i] -eq 13 -and $rawBytes[$i + 1] -eq 10 `
                    -and $rawBytes[$i + 2] -eq 13 -and $rawBytes[$i + 3] -eq 10) {
                $headerEnd = $i
                break
            }
        }
        if ($headerEnd -lt 0) { throw 'Pinned endpoint returned a malformed HTTP response.' }
        $head = [System.Text.Encoding]::ASCII.GetString($rawBytes, 0, $headerEnd)
        if ($head -notmatch '\AHTTP/\d+(?:\.\d+)?\s+(\d{3})') {
            throw 'Pinned endpoint returned a malformed HTTP status line.'
        }
        $statusCode = [int]$Matches[1]

        $bodyStart = $headerEnd + 4
        if ($head -match '(?im)^Transfer-Encoding:\s*chunked') {
            $decoded = [System.IO.MemoryStream]::new()
            $pos = $bodyStart
            while ($true) {
                $eol = -1
                for ($i = $pos; $i -le $rawBytes.Length - 2; $i++) {
                    if ($rawBytes[$i] -eq 13 -and $rawBytes[$i + 1] -eq 10) { $eol = $i; break }
                }
                if ($eol -lt 0) { throw 'Pinned endpoint returned a truncated chunk header.' }
                $sizeText = [System.Text.Encoding]::ASCII.GetString($rawBytes, $pos, $eol - $pos).Trim()
                $size = 0
                if (-not [int]::TryParse($sizeText, [System.Globalization.NumberStyles]::HexNumber, $null, [ref]$size)) {
                    throw 'Pinned endpoint returned a malformed chunk header.'
                }
                $pos = $eol + 2
                if ($size -eq 0) { break }
                if ($pos + $size -gt $rawBytes.Length) { throw 'Pinned endpoint returned a truncated chunk.' }
                $decoded.Write($rawBytes, $pos, $size)
                $pos += $size + 2
            }
            $content = [System.Text.Encoding]::UTF8.GetString($decoded.ToArray())
        }
        else {
            $content = [System.Text.Encoding]::UTF8.GetString($rawBytes, $bodyStart, $rawBytes.Length - $bodyStart)
        }
        return [pscustomobject]@{ StatusCode = $statusCode; Content = $content }
    }
    finally {
        if ($null -ne $ssl) { $ssl.Dispose() }
        if ($null -ne $tcp) { $tcp.Dispose() }
    }
}

function Invoke-TelegramRequest {
    param([string]$BotToken, [string]$Json)

    $pinnedIp = [string]$env:CI_TELEGRAM_ENDPOINT_IP
    if (-not [string]::IsNullOrWhiteSpace($pinnedIp)) {
        if ($pinnedIp.Trim() -notmatch '\A\d{1,3}(?:\.\d{1,3}){3}\z') {
            throw 'CI_TELEGRAM_ENDPOINT_IP is not a valid IPv4 address.'
        }
        return Invoke-TelegramPinnedRequest -BotToken $BotToken -Json $Json -EndpointIp $pinnedIp.Trim()
    }

    Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
    $handler = $null
    $client = $null
    $content = $null
    $response = $null
    try {
        $handler = New-Object System.Net.Http.HttpClientHandler
        $handler.AllowAutoRedirect = $false
        $client = [System.Net.Http.HttpClient]::new($handler)
        $client.Timeout = [TimeSpan]::FromSeconds(20)
        $content = [System.Net.Http.StringContent]::new($Json, [System.Text.Encoding]::UTF8, 'application/json')
        $response = $client.PostAsync("https://api.telegram.org/bot$BotToken/sendMessage", $content).GetAwaiter().GetResult()
        return [pscustomobject]@{
            StatusCode = [int]$response.StatusCode
            Content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        }
    }
    finally {
        if ($null -ne $response) { $response.Dispose() }
        if ($null -ne $content) { $content.Dispose() }
        if ($null -ne $client) { $client.Dispose() }
        elseif ($null -ne $handler) { $handler.Dispose() }
    }
}

function Send-CiTelegramNotification {
    param(
        [string]$BotToken,
        [string]$ChatId,
        [string]$Project,
        [string]$Branch,
        [string]$JobResult,
        [string]$TestOutcome,
        [string]$TestEvidence,
        [string]$RunUrl
    )

    if ($JobResult -notin @('success', 'failure')) { return 'skipped' }
    if ([string]::IsNullOrWhiteSpace($BotToken) -or [string]::IsNullOrWhiteSpace($ChatId)) {
        Write-Warning 'Telegram notification skipped: required Actions secrets are not configured.'
        return 'skipped'
    }

    try {
        $text = New-CiTelegramMessage -Project $Project -Branch $Branch -JobResult $JobResult `
            -TestOutcome $TestOutcome -TestEvidence $TestEvidence -RunUrl $RunUrl
        if ($text.Length -gt 4096) { throw 'Notification text exceeds the API limit.' }
        $json = @{
            chat_id = $ChatId
            text = $text
            link_preview_options = @{ is_disabled = $true }
        } | ConvertTo-Json -Depth 3 -Compress -ErrorAction Stop
        $response = Invoke-TelegramRequest -BotToken $BotToken -Json $json
        if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
            throw 'Telegram HTTP response was not successful.'
        }
        if (-not $response.Content.TrimStart().StartsWith('{')) {
            throw 'Telegram response was not a JSON object.'
        }
        $reply = $response.Content | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $reply -or $reply.ok -isnot [bool] -or $reply.ok -ne $true) {
            throw 'Telegram did not confirm delivery.'
        }
        return 'sent'
    }
    catch {
        # Exception messages may include the token-bearing URL or the API
        # response body; report only the type name for diagnosis.
        Write-Warning "Telegram delivery is unconfirmed ($($_.Exception.GetType().Name)); no retry was attempted. The UI job result is unchanged."
        return 'failed'
    }
}
