#require -Modules AzureAD
#TODO: Add options to generate Azure ResourceGroups for the students. Needs to specify which Subscription to use.

Param(
    [parameter(Mandatory=$true, HelpMessage="Number of users to generate. (0-2000)", ParameterSetName="series")]
    [ValidateRange(0, 2000)]
    [int]$Count,

    [parameter(Mandatory=$true, HelpMessage="ID used to identify these users. (At least 4 characters)", ParameterSetName="series")]
    [ValidateLength(4, 2147483647)]
    [string]$courseID,

    [parameter(Mandatory=$false, HelpMessage="Password to set for the users. (At least 8 characters)")]
    [ValidateLength(8, 2147483647)]
    [string]$Password,
    
    [parameter(Mandatory=$false, HelpMessage="The index to start generating users from. (Default '1')", ParameterSetName="series")]
    [ValidateRange(1, 2000)]
    [int]$StartIndex=1,

    [parameter(Mandatory=$false, HelpMessage="Groups that the users should be added to (a single string or an array of strings).")]
    $GroupNames=@("Students","Students.Licenses"),

    [parameter(Mandatory=$false, HelpMessage="Optional prefix for the username. (Default '')", ParameterSetName="series")]
    [ValidateLength(0, 2147483647)]
    [string]$NamePrefix="",

    [parameter(Mandatory=$false, HelpMessage="Date that the course will commence on.")]
    [datetime]$CourseStart = [datetime]::now,

    [parameter(Mandatory=$false, HelpMessage="How long the account should remain accessible after the start of the course (1-365, default 7)")]
    [ValidateRange(1, 365)]
    [int]$ValidityDays = 7,

    [parameter(Mandatory=$false, HelpMessage="Credential to use when connecting to the tennant")]
    [pscredential]$Credential,

    [parameter(Mandatory=$false, HelpMessage="Domain to use for the UserPrincipalname. Must be a domain registered to the tenant.")]
    [string]$Domain
)

$ValidTo = [datetime]::new($CourseStart.Year, $CourseStart.Month, $CourseStart.Day) + ([timespan]::FromDays($ValidityDays)) 

if ($ValidTo -lt [datetime]::Now) {
    Write-Host ("The end date for the accounts is set in the past! ({0:yyyy/MM/dd - hh:mm:ss})" -f $ValidTo) -ForegroundColor Red
    Write-Host "Stopping!"
    pause
    return
}

if (!$PSBoundParameters.ContainsKey("Credential")) {
    $Credential = Get-Credential -Message "Please enter your connection credentials." -ErrorAction Stop
}

$connectionDetailsAD = Connect-AzureAD -Credential $Credential -ErrorAction Stop

"Logged on to AzureAD '{0}' ({1}) as '{2}'" -f $connectionDetailsAD.TenantDomain, $connectionDetailsAD.Environment, $connectionDetailsAD.Account | Write-Host -ForegroundColor Magenta

$oldErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Stop"

$usersCreated = @()

try{
    Write-Host "Collecting Group information..." -NoNewline
    $groups = $GroupNames | ? { $_ -ne $null } | % {
        $gn = $_
        $o = Get-AzureADGroup -All $true | ? { $_.DisplayName -eq $gn }
        if (!$o) {
            throw "Invalid group name provided! The group '$gn' does not exist in this tennant!"
        }
        $o
    }
    Write-Host "Done!" -ForegroundColor Green

    Write-Host "Selecting domain..." -NoNewline
    $studentDomain = if ($PSBoundParameters.ContainsKey("Domain")) {
        Write-Host "Using given domain ('$Domain')" -ForegroundColor Green
        $Domain
    } else {
        Write-Host "Using tenant domain ($($connectionDetailsAD.tenantDomain))" -ForegroundColor Yellow
        $connectionDetailsAD.tenantDomain
    }


    if (!$PSBoundParameters.ContainsKey("Password")) {
        Write-Host "Generating a password... " -NoNewline
        $candidates = "abcdefghijklmnopqrstuvwxyz01234567890"
        $tPassword = ""

        $r = [System.Random]::new()
        for($i = 0; $i -lt 8; $i++) {
            $vi = $r.Next(0, $candidates.Length)
            $v = $candidates[$vi]
            if ($r.Next(0,2) -eq 0) {
                $v = "$v".ToUpper()
            }
            $tPassword += $v
        }
        Write-Host $tPassword
        $Password = $tPassword
    }
    Write-Host "Generating student details..." -NoNewline
    $studentDetails = for ($i = 0; $i -lt $Count; $i++ ) { # Hard-coded student details, these should probably be overridable/extendable with a parameter.
        $name = "{0}{1}{2}" -f $NamePrefix, $courseID, ("$($i + $startIndex)".PadLeft(2,"0"))
        $d = @{
            UserType="Member"
        }

        $d.DisplayName = $name
        $d.GivenName = $name
        
        $d.UserPrincipalName = ("{0}@{1}" -f $name,$studentDomain)
        $d.PasswordProfile = New-Object Microsoft.Open.AzureAD.Model.PasswordProfile($Password, $false, $false)
        $d.PasswordPolicies = "DisableStrongPassword"
        $d.ShowInAddressList = $true
        $d.AccountEnabled = $true
        $d.MailNickName = $name
        $d.UsageLocation= "SE"

        $d
    }
    Write-Host "Done!" -ForegroundColor Green

    $users = $studentDetails | % {
        Write-Host ("Creating '{0}'..." -f $_.UserPrincipalName) -NoNewline
        $user = New-AzureADUser @_
        $usersCreated += $user
        Write-Host "Done!" -ForegroundColor Green
        Write-Host ("Adding to groups ({0})..." -f @($groups).Length) -NoNewline
        if ($groups) {
            $groups | % { Add-AzureADGroupMember -ObjectId $_.ObjectId -RefObjectId $user.ObjectId }
        }
        Write-Host "Done!" -ForegroundColor Green
    }

    $studentDetails | % { "{0},{1},{2}" -f $_.UserPrincipalName,$ValidTo.Ticks,$connectionDetailsAD.TenantId } | Out-File "$PSScriptRoot\students.csv" -Encoding utf8 -Append

    Write-Host ("-"*80)
    $studentDetails | % UserPrincipalName | Write-Host -ForegroundColor White
    Write-host ""
    Write-Host "Password: $Password"
    Write-Host ("-"*80)


} catch {
    Write-Host "An error was encountered while generating users:" -ForegroundColor Red
    $_ | Out-String | Write-Host -ForegroundColor Gray
    Write-Host "Rolling back generated users..."
    $usersCreated | % {
        Write-Host ("Removing '{0}'..." -f $_.UserPrincipalName) -ForegroundColor White -NoNewline
        $_ | Remove-AzureADUser -ErrorAction Continue
        Write-Host "Done." -ForegroundColor DarkGray
    }
    Write-host "Finished rollback"
}

$ErrorActionPreference = $oldErrorActionPreference

Disconnect-AzureAD