<#=
.Synopsis
  Performs Azure file operations for Evergreen/Nevergreen workflow
.DESCRIPTION
  Uploads azure files to blob storage if necessary. This assumes that the following environment variables exist:
  $env:SHARE_USER - Username to be used for authenticating to file shares, formatted as fqdn.of.domain\username
  $env:SHARE_PASS - Password for the user above, can be a regular or secure string. Azure DevOps pipelines only supplies strings.
  $env:GITHUB_TOKEN - Access token to be used for GitHub operations
.PARAMETER RootDir
  Working directory from the runner job, should contain our repository so we can import modules from it
.PARAMETER Package
  JSON string containing package information
.PARAMETER TenantID
  Tenant ID for Azure storage account
.PARAMETER AppID
  Application ID for Azure storage account
.PARAMETER SubscriptionName
  Subscription name for Azure storage account
.PARAMETER StorageAcctName
  Storage Account Name for Azure storage account
.PARAMETER StorageContainer
  Container name for Azure storage account
.PARAMETER CollectionURI
  Collection URI for repo in GitHub
.PARAMETER RepoName
  Name of the GitHub repository
.PARAMETER FilePath
  Local path that the binary will be downloaded to if it doesnt already exist
.PARAMETER FileURI
  URI to download the file form
.PARAMETER FileVersion
  Version string to used for PR verification
.PARAMETER FilePath64
  (Optional) Local path that the x64 binary will be downloaded to if it doesnt already exist
.PARAMETER FileURI64
  (Optional) URI to download the x64 file from

.INPUTS
System.String

.OUTPUTS
System.String
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification='No other way to use this access token from pipeline')]
param(
  [Parameter(Mandatory = $true)][String]$WorkingDirectory,
  [Parameter(Mandatory = $true)][String]$Package,
  [Parameter(Mandatory = $true)][String]$TenantID,
  [Parameter(Mandatory = $true)][String]$AppID,
  [Parameter(Mandatory = $true)][String]$SubscriptionName,
  [Parameter(Mandatory = $true)][String]$StorageAcctName,
  [Parameter(Mandatory = $true)][String]$StorageContainer,
  [Parameter(Mandatory = $true)][String]$CollectionURI,
  [Parameter(Mandatory = $true)][String]$RepoName,
  [Parameter(Mandatory = $true)][String]$FilePath,
  [Parameter(Mandatory = $true)][String]$FileURI,
  [Parameter(Mandatory = $true)][String]$FileVersion,
  [Parameter(Mandatory = $false)][String]$FilePath64 = '',
  [Parameter(Mandatory = $false)][String]$FileURI64 = ''
)
If ($PSBoundParameters['Debug']) {
  $DebugPreference = 'Continue'
}
try {
  $PackageInfo = $Package | ConvertFrom-JSON
} catch {
  Write-Output "##vso[task.logissue type=Error]Unable to convert Package parameter from JSON: $($_ | Out-String)"
  Write-Output "##vso[task.complete result=Failed;]"
}
try {
  Import-Module 'choco-auto-packaging' -Force
} catch {
  Write-Output "##vso[task.logissue type=Error]Unable to import modules: $($_ | Out-String)"
  Write-Output "##vso[task.complete result=Failed;]"
  return
}
$branchName = "EVERGREEN-$($PackageInfo.PackageName)-$($FileVersion)"
# Remove existing pull requests for this package that arent for this specific version
Write-Output "Checking for old pull requests with the following arguments:"
$OldPrTest = Test-GitHubPullRequest -OrgURI "$($CollectionURI)" -RepoName $RepoName `
  -TargetBranch 'main' -RelativeMatch "*EVERGREEN-$($PackageInfo.PackageName)*" `
  -ExcludeBranch $branchName -GitHubToken $env:GITHUB_TOKEN
Write-Output "Old PR Test:`n$($OldPrTest)"
Write-Output "Old PR Test values:`n$($OldPrTest.Values)"
if ($OldPrTest.Result) {
  Write-Output "Detected existing pull requests below, commencing removal:"
  $OldPrTest.Values | out-string
  $requestBody = @{
    state = 'closed'
  }
  $requestBody = $requestBody | ConvertTo-JSON
  foreach ($oldPR in $OldPrTest.Values) {
    try {
      $deleteResult = Update-GitHubPullRequest -OrgURI "$($CollectionURI)" -RepoName $RepoName `
      -PullRequestID $oldPR.number -RequestBody $requestBody `
      -RESTMethod 'PATCH'
    } catch {
      Write-Output "##vso[task.logissue type=Error]Error closing existing pull request with id $($oldPR.pullRequestId): $($_ | Out-String)"
      Write-Output "##vso[task.complete result=Failed;]"
      continue
    }
    if ($deleteResult.state -ne 'closed') {
      Write-Output "##vso[task.logissue type=Error]Close method called for PR with ID $($oldPR.pullRequestId) but status is still $($deleteResult.status)"
      Write-Output "##vso[task.complete result=Failed;]"
      continue
    }
    Write-Output "Pull request with id $($oldPR.pullRequestId) successfully abandoned"
    try {
      git push origin --delete "$($oldPR.sourceRefName)"
      Write-Output "git branch with id $($oldPR.sourceRefName) successfully deleted"
    } catch {
      Write-Output "##vso[task.logissue type=Error]Unable to delete branch with name $($branchName): $($_ | Out-String)"
      Write-Output "##vso[task.complete result=Failed;]"
      continue
    }
  }
}

# If a pull request matching the same name as our branch already exists then we don't need to do this again
$prTest = Test-GitHubPullRequest -OrgURI "$($CollectionURI)" -RepoName $RepoName `
  -SourceBranch $branchName -TargetBranch 'main' -GitHubToken $env:GITHUB_TOKEN
if ($prTest.Result) {
  Write-Output "Pull request already exists:"
  $prTest.Values | out-string
  return
}
$destinationPath = $FilePath
$destinationPath64 = $FilePath64
if ($PackageInfo.CustomMethod -eq 'Share') {
  try {
    if ($env:SHARE_PASS.GetType().Name -ne 'SecureString') {
      $secpass = $env:SHARE_PASS | ConvertTo-SecureString -AsPlainText -Force
    } else {
      $secpass = $env:SHARE_PASS
    }
    $creds = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "$($env:SHARE_USER)", $secPass
    # Change destination path to be a zip file if we have a specific custom zip file name
    if ($PackageInfo.CustomZipName -ne '') {
      $destinationPath = "$FilePath".Replace($PackageInfo.CustomFileName,$PackageInfo.CustomZipName)
      Write-Output "Setting new destination path due to custom zip name: $destinationPath"
      Write-Output "##vso[task.setvariable variable=FilePath]$destinationPath"
      Write-Output "Setting new FileName due to custom zip name: $PackageInfo.CustomZipName"
      Write-Output "##vso[task.setvariable variable=FileName]$PackageInfo.CustomZipName"
    }
    Copy-AppFromShare -SharePath $PackageInfo.CustomSharePath -FileName $PackageInfo.CustomFileName `
      -DestinationPath $destinationPath -CustomZip $PackageInfo.CustomZip -Credential $creds
  } catch {
    Write-Output "##vso[task.logissue type=warning]Unable to retrieve file from share: $($_ | Out-String)"
    return
  }
}
if (!(Test-Path $destinationPath)){
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -Uri $FileURI -OutFile $destinationPath
}
Write-Output "Attempting to upload file to $StorageContainer in subscription $SubscriptionName using app id $AppID"
$blobOutput = Set-ChocoBlob -TenantID $TenantID -AppID $AppID `
  -SubscriptionName $SubscriptionName -StorageAcctName $StorageAcctName `
  -StorageContainer $StorageContainer -Vendor $PackageInfo.Vendor `
  -ProductName $PackageInfo.ProductName -FilePath $destinationPath -FileVersion $FileVersion
$blobOutput
Remove-Item $destinationPath
Write-Output "##vso[task.setvariable variable=TemplateURI]$($blobOutput.TemplateURL)"
if ($destinationPath64 -ne '') {
  if (!(Test-Path $destinationPath64)){
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $FileURI64 -OutFile $destinationPath64
  }
  $blobOutput64 = Set-ChocoBlob -TenantID $TenantID -AppID $AppID `
    -SubscriptionName $SubscriptionName -StorageAcctName $StorageAcctName `
    -StorageContainer $StorageContainer -Vendor $PackageInfo.Vendor `
    -ProductName $PackageInfo.ProductName -FilePath $destinationPath64 -FileVersion $FileVersion
  $blobOutput64
  Remove-Item $destinationPath64
  Write-Output "##vso[task.setvariable variable=TemplateURI64]$($blobOutput64.TemplateURL64)"
}