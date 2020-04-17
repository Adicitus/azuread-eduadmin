param($Credential = $null)

Import-Module AzureAD -ErrorAction Stop

if (!$Credential) {
    $Credential = Get-Credential -Message "Please enter your Office 365 credentials." -ErrorAction Stop
}
$d = Connect-AzureAD -Credential $Credential -ErrorAction Stop
$tid = $d.TenantId.ToString()
Write-Host ("Logged on to '{0}' ({1}) as '{2}' [{3}]" -f $d.TenantDomain, $d.Environment, $d.Account, $d.TenantId) -ForegroundColor Magenta

$studentsFile = "$PSScriptRoot\students.csv"

$oldErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Stop"

try {
    $students = Get-Content "$PSScriptRoot\students.csv" | ConvertFrom-CSV
    $tennantStudents = $students | ? { $_.TennantID -eq $tid }
    $expiredStudents = $tennantStudents | ? { $_.Ends -lt ([datetime]::Now.Ticks) }

    #$expiredStudents | ConvertTo-Json | Write-Host

    $missingStudents = @()
    $removedStudents = @()
    $removedGroups = @()

    "Checking for expired locally listed users..." | Write-Host

    @($expiredStudents) | % {
        $f = "UserPrincipalName eq '{0}'" -f $_.UserPrincipalName
        #$_ | Out-string | Write-Host
        #Write-Host $f
        $account = Get-AzureADUser -Filter $f -ErrorAction Continue

        if ($account) {
            $removedStudents += $_
        } else {
            $missingStudents += $_
        }
    }

    if ($missingStudents.Count -gt 0) {
        Write-Host "The following accounts are missing!" -ForegroundColor Yellow
        $missingStudents | % {
            Write-Host $_.UserPrincipalName
            $upn = $_.UserPrincipalName
            $students = $students | ? { !(($_.UserPrincipalName -eq $upn) -and ($_.TennantID -eq $tid)) }
        }
        Write-Host "They were removed from the records." -ForegroundColor Cyan
    }

    "Checking for expired classes..." | Write-Host

    $existingClassGroups = Get-AzureADGroup -Filter "startswith(DisplayName,'students.class')"

    foreach ($eClassGroup in $existingClassGroups) {
        $s = $eClassGroup.Description | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($s -and ($s.ValidTo -lt [Datetime]::Now)) {
            $removedGroups += $eClassGroup
            $ms = $eClassGroup | Get-AzureAdGroupMember
            $ms | ForEach-Object {
                $removedStudents += @{
                    UserPrincipalName = $_.UserPrincipalName
                    Ends = $s.ValidTo.Ticks
                }
            }
        }
    }

    if ($removedStudents.Count -gt 0) {
        Write-Host "The following accounts will be removed from the tenant:" -ForegroundColor Yellow
        Write-Host ("{0,-50}{1}" -f "UPN","|Ended")
        Write-Host ("-" * 80)
        $removedStudents | % {
            Write-Host ("{0,-50}{1: yyyy/MM/dd - HH:mm:ss}" -f $_.UserPrincipalName,([datetime]::new($_.Ends)))
        }

        $r = Read-Host "Proceed? Y/N"
        if ($r -like "Y*") {
            $removedStudents | % {
                $upn = $_.UserPrincipalName
                Write-Host "Removing '$upn'... " -NoNewline
                $f = "UserPrincipalName eq '{0}'" -f $upn
                Get-AzureADUser -Filter $f | Remove-AzureADUser

                $students = $students | ? { !(($_.UserPrincipalName -eq $upn) -and ($_.TennantID -eq $tid)) }

                Write-Host "Done!" -ForegroundColor Green
            }
            

            if ($removedGroups.Count -gt 0) {
                $removedGroups | % {
                    "Removing group '{0}'..." -f $_.DisplayName | Write-Host -NoNewline
                    $_ | Remove-AzureADGroup
                    "Done." |  Write-Host -ForegroundColor Green
                }
            }
        } else {
            Write-Host "Aborting without making any changes to the tennant!" -ForegroundColor Yellow
        }
    }

    
    Write-Host "Writing updated record to '$studentsFile'... " -NoNewline
    $csvOut = if ( @($students).Count -eq 0 ) {
        '"UserPrincipalName","Ends","TennantId"'
    } else {
        $students | ConvertTo-Csv -NoTypeInformation
    }
    
    [System.IO.File]::WriteAllLines($studentsFile, $csvOut)
    Write-Host "Done!" -ForegroundColor Green

} catch {
    Write-Host "An exception occured!"
    $_ | Out-String | Write-Host -ForegroundColor Red
} finally {
    Disconnect-AzureAD
}

$ErrorActionPreference = $oldErrorActionPreference