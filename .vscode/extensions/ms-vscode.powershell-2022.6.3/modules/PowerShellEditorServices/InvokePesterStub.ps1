#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Stub around Invoke-Pester command used by VSCode PowerShell extension.
.DESCRIPTION
    The stub checks the version of Pester and if >= 4.6.0, invokes Pester
    using the LineNumber parameter (if specified). Otherwise, it invokes
    using the TestName parameter (if specified). If the All parameter
    is specified, then all the tests are invoked in the specifed file.
    Finally, if none of these three parameters are specified, all tests
    are invoked and a warning is issued indicating what the user can do
    to allow invocation of individual Describe blocks.
.EXAMPLE
    PS C:\> .\InvokePesterStub.ps1 ~\project\test\foo.tests.ps1 -LineNumber 14
    Invokes a specific test by line number in the specified file.
.EXAMPLE
    PS C:\> .\InvokePesterStub.ps1 ~\project\test\foo.tests.ps1 -TestName 'Foo Tests'
    Invokes a specific test by test name in the specified file.
.EXAMPLE
    PS C:\> .\InvokePesterStub.ps1 ~\project\test\foo.tests.ps1 -All
    Invokes all tests in the specified file.
.INPUTS
    None
.OUTPUTS
    None
#>
param(
    # Specifies the path to the test script.
    [Parameter(Position=0, Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $ScriptPath,

    # Specifies the name of the test taken from the Describe block's name.
    [Parameter()]
    [string]
    $TestName,

    # Specifies the starting line number of the DescribeBlock.  This feature requires
    # Pester 4.6.0 or higher.
    [Parameter()]
    [ValidatePattern('\d*')]
    [string]
    $LineNumber,

    # If specified, executes all the tests in the specified test script.
    [Parameter()]
    [switch]
    $All,

    [Parameter()]
    [switch] $MinimumVersion5,

    [Parameter(Mandatory)]
    [string] $Output,

    [Parameter()]
    [string] $OutputPath
)

$pesterModule = Microsoft.PowerShell.Core\Get-Module Pester
# add one line, so the subsequent output is not shifted to the side
Write-Output ''

if (!$pesterModule) {
    Write-Output "Importing Pester module..."
    if ($MinimumVersion5) {
        $pesterModule = Microsoft.PowerShell.Core\Import-Module Pester -ErrorAction Ignore -PassThru -MinimumVersion 5.0.0
    }

    if (!$pesterModule) {
        $pesterModule = Microsoft.PowerShell.Core\Import-Module Pester -ErrorAction Ignore -PassThru
    }

    if (!$pesterModule) {
        Write-Warning "Failed to import Pester. You must install Pester module to run or debug Pester tests."
        Write-Warning "$(if ($MinimumVersion5) {"Recommended version to install is Pester 5.0.0 or newer. "})You can install Pester by executing: Install-Module Pester$(if ($MinimumVersion5) {" -MinimumVersion 5.0.0" }) -Scope CurrentUser -Force"
        return
    }
}

$pester4Output = switch ($Output) {
    "None" { "None" }
    "Minimal" { "Fails" }
    default { "All" }
}

if ($MinimumVersion5 -and $pesterModule.Version -lt "5.0.0") {
    Write-Warning "Pester 5.0.0 or newer is required because setting PowerShell > Pester: Use Legacy Code Lens is disabled, but Pester $($pesterModule.Version) is loaded. Some of the code lens features might not work as expected."
}


function Get-InvokePesterParams {
    $invokePesterParams = @{
        Script = $ScriptPath
    }

    if ($pesterModule.Version -ge '3.4.0') {
        # -PesterOption was introduced before 3.4.0, and VSCodeMarker in 4.0.3-rc,
        # but because no-one checks the integrity of this hashtable we can call
        # all of the versions down to 3.4.0 like this
        $invokePesterParams.Add("PesterOption", @{ IncludeVSCodeMarker = $true })
    }

    if ($pesterModule.Version -ge '3.4.5') {
        # -Show was introduced in 3.4.5
        $invokePesterParams.Add("Show", $pester4Output)
    }

    return $invokePesterParams
}

if ($All) {
    if ($pesterModule.Version -ge '5.0.0') {
        $configuration = @{
            Run = @{
                Path = $ScriptPath
            }
        }
        # only override this if user asks us to do it, to allow Pester to pick up
        # $PesterPreference from caller context and merge it with the configuration
        # we provide below, this way user can specify his output (and other) settings
        # using the standard [PesterConfiguration] object, and we can avoid providing
        # settings for everything
        if ("FromPreference" -ne $Output) {
            $configuration.Add('Output', @{ Verbosity = $Output })
        }

        if ($OutputPath) {
            $configuration.Add('TestResult', @{
                Enabled = $true
                OutputPath = $OutputPath
            })
        }
        Pester\Invoke-Pester -Configuration $configuration | Out-Null
    }
    else {
        $invokePesterParams = Get-InvokePesterParams
        Pester\Invoke-Pester @invokePesterParams
    }
}
elseif (($LineNumber -match '\d+') -and ($pesterModule.Version -ge '4.6.0')) {
    if ($pesterModule.Version -ge '5.0.0') {
        $configuration = @{
            Run = @{
                Path = $ScriptPath
            }
            Filter = @{
                Line = "${ScriptPath}:$LineNumber"
            }
        }
        if ("FromPreference" -ne $Output) {
            $configuration.Add('Output', @{ Verbosity = $Output })
        }

        if ($OutputPath) {
            $configuration.Add('TestResult', @{
                Enabled = $true
                OutputPath = $OutputPath
            })
        }

        Pester\Invoke-Pester -Configuration $configuration | Out-Null
    }
    else {
        Pester\Invoke-Pester -Script $ScriptPath -PesterOption (New-PesterOption -ScriptBlockFilter @{
            IncludeVSCodeMarker=$true; Line=$LineNumber; Path=$ScriptPath}) -Show $pester4Output
    }
}
elseif ($TestName) {
    if ($pesterModule.Version -ge '5.0.0') {
       throw "Running tests by test name is unsafe. This should not trigger for Pester 5."
    }
    else {
        $invokePesterParams = Get-InvokePesterParams
        Pester\Invoke-Pester @invokePesterParams
    }
}
else {
    if ($pesterModule.Version -ge '5.0.0') {
       throw "Running tests by expandable string is unsafe. This should not trigger for Pester 5."
    }

    # We get here when the TestName expression is of type ExpandableStringExpressionAst.
    # PSES will not attempt to "evaluate" the expression so it returns null for the TestName.
    Write-Warning "The Describe block's TestName cannot be evaluated. EXECUTING ALL TESTS instead."
    Write-Warning "To avoid this, install Pester >= 4.6.0 or remove any expressions in the TestName."

    $invokePesterParams = Get-InvokePesterParams
    Pester\Invoke-Pester @invokePesterParams
}

# SIG # Begin signature block
# MIInrgYJKoZIhvcNAQcCoIInnzCCJ5sCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBEveY8BCv+6+1G
# 6Rri2oA0s3PUTsVHmkiczeFU4+rcVqCCDYUwggYDMIID66ADAgECAhMzAAACU+OD
# 3pbexW7MAAAAAAJTMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjEwOTAyMTgzMzAwWhcNMjIwOTAxMTgzMzAwWjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDLhxHwq3OhH+4J+SX4qS/VQG8HybccH7tnG+BUqrXubfGuDFYPZ29uCuHfQlO1
# lygLgMpJ4Geh6/6poQ5VkDKfVssn6aA1PCzIh8iOPMQ9Mju3sLF9Sn+Pzuaie4BN
# rp0MuZLDEXgVYx2WNjmzqcxC7dY9SC3znOh5qUy2vnmWygC7b9kj0d3JrGtjc5q5
# 0WfV3WLXAQHkeRROsJFBZfXFGoSvRljFFUAjU/zdhP92P+1JiRRRikVy/sqIhMDY
# +7tVdzlE2fwnKOv9LShgKeyEevgMl0B1Fq7E2YeBZKF6KlhmYi9CE1350cnTUoU4
# YpQSnZo0YAnaenREDLfFGKTdAgMBAAGjggGCMIIBfjAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUlZpLWIccXoxessA/DRbe26glhEMw
# VAYDVR0RBE0wS6RJMEcxLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJh
# dGlvbnMgTGltaXRlZDEWMBQGA1UEBRMNMjMwMDEyKzQ2NzU5ODAfBgNVHSMEGDAW
# gBRIbmTlUAXTgqoXNzcitW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIw
# MTEtMDctMDguY3JsMGEGCCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDEx
# XzIwMTEtMDctMDguY3J0MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIB
# AKVY+yKcJVVxf9W2vNkL5ufjOpqcvVOOOdVyjy1dmsO4O8khWhqrecdVZp09adOZ
# 8kcMtQ0U+oKx484Jg11cc4Ck0FyOBnp+YIFbOxYCqzaqMcaRAgy48n1tbz/EFYiF
# zJmMiGnlgWFCStONPvQOBD2y/Ej3qBRnGy9EZS1EDlRN/8l5Rs3HX2lZhd9WuukR
# bUk83U99TPJyo12cU0Mb3n1HJv/JZpwSyqb3O0o4HExVJSkwN1m42fSVIVtXVVSa
# YZiVpv32GoD/dyAS/gyplfR6FI3RnCOomzlycSqoz0zBCPFiCMhVhQ6qn+J0GhgR
# BJvGKizw+5lTfnBFoqKZJDROz+uGDl9tw6JvnVqAZKGrWv/CsYaegaPePFrAVSxA
# yUwOFTkAqtNC8uAee+rv2V5xLw8FfpKJ5yKiMKnCKrIaFQDr5AZ7f2ejGGDf+8Tz
# OiK1AgBvOW3iTEEa/at8Z4+s1CmnEAkAi0cLjB72CJedU1LAswdOCWM2MDIZVo9j
# 0T74OkJLTjPd3WNEyw0rBXTyhlbYQsYt7ElT2l2TTlF5EmpVixGtj4ChNjWoKr9y
# TAqtadd2Ym5FNB792GzwNwa631BPCgBJmcRpFKXt0VEQq7UXVNYBiBRd+x4yvjqq
# 5aF7XC5nXCgjbCk7IXwmOphNuNDNiRq83Ejjnc7mxrJGMIIHejCCBWKgAwIBAgIK
# YQ6Q0gAAAAAAAzANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlm
# aWNhdGUgQXV0aG9yaXR5IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEw
# OTA5WjB+MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYD
# VQQDEx9NaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG
# 9w0BAQEFAAOCAg8AMIICCgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+la
# UKq4BjgaBEm6f8MMHt03a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc
# 6Whe0t+bU7IKLMOv2akrrnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4D
# dato88tt8zpcoRb0RrrgOGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+
# lD3v++MrWhAfTVYoonpy4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nk
# kDstrjNYxbc+/jLTswM9sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6
# A4aN91/w0FK/jJSHvMAhdCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmd
# X4jiJV3TIUs+UsS1Vz8kA/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL
# 5zmhD+kjSbwYuER8ReTBw3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zd
# sGbiwZeBe+3W7UvnSSmnEyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3
# T8HhhUSJxAlMxdSlQy90lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS
# 4NaIjAsCAwEAAaOCAe0wggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRI
# bmTlUAXTgqoXNzcitW2oynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTAL
# BgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBD
# uRQFTuHqp8cx0SOJNDBaBgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jv
# c29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFf
# MDNfMjIuY3JsMF4GCCsGAQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFf
# MDNfMjIuY3J0MIGfBgNVHSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEF
# BQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1h
# cnljcHMuaHRtMEAGCCsGAQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkA
# YwB5AF8AcwB0AGEAdABlAG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn
# 8oalmOBUeRou09h0ZyKbC5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7
# v0epo/Np22O/IjWll11lhJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0b
# pdS1HXeUOeLpZMlEPXh6I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/
# KmtYSWMfCWluWpiW5IP0wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvy
# CInWH8MyGOLwxS3OW560STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBp
# mLJZiWhub6e3dMNABQamASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJi
# hsMdYzaXht/a8/jyFqGaJ+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYb
# BL7fQccOKO7eZS/sl/ahXJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbS
# oqKfenoi+kiVH6v7RyOA9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sL
# gOppO6/8MO0ETI7f33VtY5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtX
# cVZOSEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCGX8wghl7AgEBMIGVMH4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01p
# Y3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAAJT44Pelt7FbswAAAAA
# AlMwDQYJYIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# HAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIFmJ
# Vr9EfYW/0TTdMxwC+ucLfCjl5b2JZWIu0Vnhah5fMEIGCisGAQQBgjcCAQwxNDAy
# oBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20wDQYJKoZIhvcNAQEBBQAEggEAoPP9/cjxqWjjglE0Xyrp8P1MobgW8UnAqu3m
# 6k3yqZmyCvOo4nw/2nkG9KiiLt3zI3qE+Q5ttQ7h6ELY7uMZqms6bLulHquBnfcQ
# kB7eZvdR2Izi3kd/GkzIjxXVeYYT+rnjkp18YYR9Cyu1MN+LB5HT93C7qhnJFeDi
# XQOHNycDnpQWr6AQ38bBeukPIVKnGrM1lfcs3QfOtlVaiHqJRlUgJ5A0RVsQZTkH
# j9gtgE00qzXMyvA1uoMvCHuw1o/n3n3K5l5r8HN9/OSPtpvh6J2wisq1AU/wJeMy
# JBcC+TFpe7Ny9WYeREItU4sWrDpZVcWysgDqNYZZFXMDOi22MaGCFwkwghcFBgor
# BgEEAYI3AwMBMYIW9TCCFvEGCSqGSIb3DQEHAqCCFuIwghbeAgEDMQ8wDQYJYIZI
# AWUDBAIBBQAwggFVBgsqhkiG9w0BCRABBKCCAUQEggFAMIIBPAIBAQYKKwYBBAGE
# WQoDATAxMA0GCWCGSAFlAwQCAQUABCB4k4W8Rqa5GSGwbOZS83ebvYkMpCX/ILhR
# CSYNg7oYjAIGYrIKV51sGBMyMDIyMDYyOTIwNTIxMC45MzZaMASAAgH0oIHUpIHR
# MIHOMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSkwJwYDVQQL
# EyBNaWNyb3NvZnQgT3BlcmF0aW9ucyBQdWVydG8gUmljbzEmMCQGA1UECxMdVGhh
# bGVzIFRTUyBFU046ODk3QS1FMzU2LTE3MDExJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2WgghFcMIIHEDCCBPigAwIBAgITMwAAAasJCe+rY9To
# qQABAAABqzANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDAeFw0yMjAzMDIxODUxMjhaFw0yMzA1MTExODUxMjhaMIHOMQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSkwJwYDVQQLEyBNaWNyb3NvZnQg
# T3BlcmF0aW9ucyBQdWVydG8gUmljbzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046
# ODk3QS1FMzU2LTE3MDExJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNl
# cnZpY2UwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDJnUtaOXXoQElL
# LHC6ssdsJv1oqzVH6pBgcpgyLWMxJ6CrZIa3e8DbCbOIPgbjN7gV/NVpztu9JZKw
# tHtZpg6kLeNtE5m/JcLI0CjOphGjUCH1w66J61Td2sNZcfWwH+1WRAN5BxapemAD
# t5I0Oj37QOIlR19yVb/fJ7Y5G7asyniTGjVnfHQWgA90QpYjKGo0wxm8mDSk78QY
# ViC8ifFmHSfzQQ6aj80JfqcZumWVUngUACDrm2Y1NL36RAsRwubyNRK66mqRvtKA
# YYTjfoJZVZJTwFmb9or9JoIwk4+2DSl+8i9sdk767x1auRjzWuXzW6ct/beXL4om
# KjH9UWVWXHHa/trwKZOYm+WuDvEogID0lMGBqDsG2RtaJx4o9AEzy5IClH4Gj8xX
# 3eSWUm0Zdl4N+O/y41kC0fiowMgAhW9Om6ls7x7UCUzQ/GNI+WNkgZ0gqldszR0l
# bbOPmlH5FIbCkvhgF0t4+V1IGAO0jDaIO+jZ7LOZdNZxF+7Bw3WMpGIc7kCha0+9
# F1U2Xl9ubUgX8t1WnM2HdSUiP/cDhqmxVOdjcq5bANaopsTobLnbOz8aPozt0Y1f
# 5AvgBDqFWlw3Zop7HNz7ZQQlYf7IGJ6PQFMpm5UkZnntYMJZ5WSdLohyiPathxYG
# VjNdMjxuYFbdKa15yRYtVsZpoPgR/wIDAQABo4IBNjCCATIwHQYDVR0OBBYEFBRb
# zvKNXjXEgiEGTL6hn3TS/qaqMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1
# GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
# a2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEp
# LmNybDBsBggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWlj
# cm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUy
# MFBDQSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYB
# BQUHAwgwDQYJKoZIhvcNAQELBQADggIBAMpLlIE3NSjLMzILB24YI4BBr/3QhxX9
# G8vfQuOUke+9P7nQjTXqpU+tdBIc9d8RhVOh3Ivky1D1J4b1J0rs+8ZIlka7uUY2
# WZkqJxFb/J6Wt89UL3lH54LcotCXeqpUspKBFSerQ7kdSsPcVPcr7YWVoULP8psj
# sIfpsbdAvcG3iyfdnq9r3PZctdqRcWwjQyfpkO7+dtIQL63lqmdNhjiYcNEeHNYj
# 9/YjQcxzqM/g7DtLGI8IWs/R672DBMzg9TCXSz1n1BbGf/4k3d48xMpJNNlo52Tc
# yHthDX5kPym5Rlx3knvCWKopkxcZeZHjHy1BC4wIdJoUNbywiWdtAcAuDuexIO8j
# v2LgZ6PuEa1dAg9oKeATtdChVtkkPzIb0Viux24Eugc7e9K5CHklLaO6UZBzKq54
# bmyE3F3XZMuhrWbJsDN4b6l7krTHlNVuTTdxwPMqYzy3f26Jnxsfeh7sPDq37XEL
# 5O7YXTbuCYQMilF1D+3SjAiX6znaZYNI9bRNGohPqQ00kFZj8xnswi+NrJcjyVV6
# buMcRNIaQAq9rmtCx7/ywekVeQuAjuDLP6X2pf/xdzvoSWXuYsXr8yjZF128Tzmt
# UfkiK1v6x2TOkSAy0ycUxhQzNYUA8mnxrvUv2u7ppL4pYARzcWX5NCGBO0UViXBu
# 6ImPhRncdXLNMIIHcTCCBVmgAwIBAgITMwAAABXF52ueAptJmQAAAAAAFTANBgkq
# hkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5
# IDIwMTAwHhcNMjEwOTMwMTgyMjI1WhcNMzAwOTMwMTgzMjI1WjB8MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQg
# VGltZS1TdGFtcCBQQ0EgMjAxMDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoC
# ggIBAOThpkzntHIhC3miy9ckeb0O1YLT/e6cBwfSqWxOdcjKNVf2AX9sSuDivbk+
# F2Az/1xPx2b3lVNxWuJ+Slr+uDZnhUYjDLWNE893MsAQGOhgfWpSg0S3po5GawcU
# 88V29YZQ3MFEyHFcUTE3oAo4bo3t1w/YJlN8OWECesSq/XJprx2rrPY2vjUmZNqY
# O7oaezOtgFt+jBAcnVL+tuhiJdxqD89d9P6OU8/W7IVWTe/dvI2k45GPsjksUZzp
# cGkNyjYtcI4xyDUoveO0hyTD4MmPfrVUj9z6BVWYbWg7mka97aSueik3rMvrg0Xn
# Rm7KMtXAhjBcTyziYrLNueKNiOSWrAFKu75xqRdbZ2De+JKRHh09/SDPc31BmkZ1
# zcRfNN0Sidb9pSB9fvzZnkXftnIv231fgLrbqn427DZM9ituqBJR6L8FA6PRc6ZN
# N3SUHDSCD/AQ8rdHGO2n6Jl8P0zbr17C89XYcz1DTsEzOUyOArxCaC4Q6oRRRuLR
# vWoYWmEBc8pnol7XKHYC4jMYctenIPDC+hIK12NvDMk2ZItboKaDIV1fMHSRlJTY
# uVD5C4lh8zYGNRiER9vcG9H9stQcxWv2XFJRXRLbJbqvUAV6bMURHXLvjflSxIUX
# k8A8FdsaN8cIFRg/eKtFtvUeh17aj54WcmnGrnu3tz5q4i6tAgMBAAGjggHdMIIB
# 2TASBgkrBgEEAYI3FQEEBQIDAQABMCMGCSsGAQQBgjcVAgQWBBQqp1L+ZMSavoKR
# PEY1Kc8Q/y8E7jAdBgNVHQ4EFgQUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXAYDVR0g
# BFUwUzBRBgwrBgEEAYI3TIN9AQEwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5t
# aWNyb3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMBMGA1UdJQQM
# MAoGCCsGAQUFBwMIMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQE
# AwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFNX2VsuP6KJcYmjRPZSQ
# W9fOmhjEMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNv
# bS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNybDBa
# BggrBgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2kvY2VydHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3J0MA0GCSqG
# SIb3DQEBCwUAA4ICAQCdVX38Kq3hLB9nATEkW+Geckv8qW/qXBS2Pk5HZHixBpOX
# PTEztTnXwnE2P9pkbHzQdTltuw8x5MKP+2zRoZQYIu7pZmc6U03dmLq2HnjYNi6c
# qYJWAAOwBb6J6Gngugnue99qb74py27YP0h1AdkY3m2CDPVtI1TkeFN1JFe53Z/z
# jj3G82jfZfakVqr3lbYoVSfQJL1AoL8ZthISEV09J+BAljis9/kpicO8F7BUhUKz
# /AyeixmJ5/ALaoHCgRlCGVJ1ijbCHcNhcy4sa3tuPywJeBTpkbKpW99Jo3QMvOyR
# gNI95ko+ZjtPu4b6MhrZlvSP9pEB9s7GdP32THJvEKt1MMU0sHrYUP4KWN1APMdU
# bZ1jdEgssU5HLcEUBHG/ZPkkvnNtyo4JvbMBV0lUZNlz138eW0QBjloZkWsNn6Qo
# 3GcZKCS6OEuabvshVGtqRRFHqfG3rsjoiV5PndLQTHa1V1QJsWkBRH58oWFsc/4K
# u+xBZj1p/cvBQUl+fpO+y/g75LcVv7TOPqUxUYS8vwLBgqJ7Fx0ViY1w/ue10Cga
# iQuPNtq6TPmb/wrpNPgkNWcr4A245oyZ1uEi6vAnQj0llOZ0dFtq0Z4+7X6gMTN9
# vMvpe784cETRkPHIqzqKOghif9lwY1NNje6CbaUFEMFxBmoQtB1VM1izoXBm8qGC
# As8wggI4AgEBMIH8oYHUpIHRMIHOMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSkwJwYDVQQLEyBNaWNyb3NvZnQgT3BlcmF0aW9ucyBQdWVydG8g
# UmljbzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046ODk3QS1FMzU2LTE3MDExJTAj
# BgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WiIwoBATAHBgUrDgMC
# GgMVAFuoev9uFgqO1mc+ghFQHi87XJg+oIGDMIGApH4wfDELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgUENBIDIwMTAwDQYJKoZIhvcNAQEFBQACBQDmZxRHMCIYDzIwMjIwNjI5
# MjIxMTE5WhgPMjAyMjA2MzAyMjExMTlaMHQwOgYKKwYBBAGEWQoEATEsMCowCgIF
# AOZnFEcCAQAwBwIBAAICCkAwBwIBAAICEfAwCgIFAOZoZccCAQAwNgYKKwYBBAGE
# WQoEAjEoMCYwDAYKKwYBBAGEWQoDAqAKMAgCAQACAwehIKEKMAgCAQACAwGGoDAN
# BgkqhkiG9w0BAQUFAAOBgQCCNIR05mzv+ekG4zqFSfQEweC/PctLkUSeUkKp1jDR
# JOtYaUTwAx/Wuso1GHP5or1Dq6skkH7rTsyPtZ5YG+gRAI8gt5+9u8txEbH2Yns3
# r872i+jA9x8hR5L0xx7hzDoCTPghN/AEZUYx2pIWh9d7tbSOs9vkPcMeXrltsl4M
# 8jGCBA0wggQJAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
# dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMz
# AAABqwkJ76tj1OipAAEAAAGrMA0GCWCGSAFlAwQCAQUAoIIBSjAaBgkqhkiG9w0B
# CQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEIAzJBGI3PBO78AyRZLCZ
# wr4embtho8XWq/ayIrIQPUiuMIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQg
# Dhyv+rCFYBFUlQ9wK75OjskCr0cRRysq2lM2zdfwClcwgZgwgYCkfjB8MQswCQYD
# VQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEe
# MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3Nv
# ZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAasJCe+rY9ToqQABAAABqzAiBCDF
# K16w83HIxqfjYJRX26bRRRpnIzPYhgLSWRDBjGHlkjANBgkqhkiG9w0BAQsFAASC
# AgAy0p8CrlQXPHrtvqD0PXLaNf7WVTky6YA91B6Ye0c0UxR9g0oBbr4Zkde2UGQj
# ubgDkp2pnj/qNrfXOATDU6AJgEbaHMyd+JJPT1vRl9jAKzOa+WjUNB0JKMRYH3Kq
# /VRuk7eweCXZfgbIWnpTgzLVo2EB6GZydGzqEHIEb6MoTS818eKsrTAod0sZ241g
# FOp00VipxGg5LsqM/roubsowwQBTYZa2y/dc+AtTd6afGtK8BSLX1TbJaXzigufr
# iVNUHsk2rCOVeuMesRVM/JWtftzbevMlOGBuC2zWrOJ+zlXHlbtjaxDx3Bgd7+XX
# CIcIVNSvigSBdozCfjJIVg763WaEFLt9Xj6tHh2uy8v0ohluk+MDzQmP4+3mE8EC
# HQ8Ru6oNcsWof9l2P5E6yToZk/yQaEqgAyixNXG7Evr9PbkFhpfZW2HlcIV9r+oO
# M57hNW0VKkRMPIMturPfGs56GGrBPR1l8Cv6Gm9YnF8Ir1QV5YmDVFe5J4YJDitZ
# wEWVibcqQj+nH5NWh2haaUb5yTmW+MVo9hrwdy1YNdRNhQp+MUCNVt3dLNfoaoA6
# 6VUoCt1KVvVlH9Q93y88vLZdQKkiSFneeE/3FeMIe2QlqTGm56H98t1UQv+Fpt21
# laot3aww6uOUlT+JNKaoDFiqGk8cZ/I0lJBkKxkME3wsig==
# SIG # End signature block
