<#=
.Synopsis
  Creates a branch, changes files, and submits a pull request
.DESCRIPTION
  Creates a specifically named branch for an application change, updates Chocolatey file contents with new information,
  and submits a pull request for approval. This assumes that the following environment variable exists:
  $env:GITHUB_TOKEN - Access token to be used for GitHub operations
.PARAMETER RootDir
  Working directory from the runner job, should contain our repository so we can import modules from it
.PARAMETER Package
  JSON string containing package information
.PARAMETER CollectionURI
  Collection URI for repo in GitHub
.PARAMETER RepoName
  Name of the GitHub repository
.PARAMETER FileHash
  SHA256 checksum of the file
.PARAMETER FileName
  Name of the file that was uploaded to blob storage in previous steps
.PARAMETER TemplateURI
  Templating URI to use for chocolateyinstall.ps1 line replacement
.PARAMETER FileVersion
  Version of the file to use for PR and line replacement
.PARAMETER FileName64
  (Optional) Name of the x64 file that was uploaded to blob storage in previous steps
.PARAMETER FileHash64
  (Optional) SHA256 checksum of the x64 file
.PARAMETER TemplateURI64
  (Optional) x64 templating URI to use for chocolateyinstall.ps1 line replacement

.INPUTS
System.String

.OUTPUTS
System.String
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification='No other way to use this access token from pipeline')]
param(
  [Parameter(Mandatory = $true)][String]$WorkingDirectory,
  [Parameter(Mandatory = $true)][String]$Package,
  [Parameter(Mandatory = $true)][String]$SourceBranchName,
  [Parameter(Mandatory = $true)][String]$ChocoPackagePath,
  [Parameter(Mandatory = $true)][String]$CollectionURI,
  [Parameter(Mandatory = $true)][String]$RepoName,
  [Parameter(Mandatory = $true)][String]$FileName,
  [Parameter(Mandatory = $true)][String]$FileHash,
  [Parameter(Mandatory = $true)][String]$TemplateURI,
  [Parameter(Mandatory = $true)][String]$FileVersion,
  [Parameter(Mandatory = $false)][String]$FileName64 = '',
  [Parameter(Mandatory = $false)][String]$FileHash64 = '',
  [Parameter(Mandatory = $false)][String]$TemplateURI64 = ''
)
If ($PSBoundParameters['Debug']) {
  $DebugPreference = 'Continue'
}
try {
  $PackageInfo = $Package | ConvertFrom-JSON
} catch {
  Write-Output "##vso[task.logissue type=error]Unable to convert Package parameter from JSON: $($_ | Out-String)"
  Write-Output "##vso[task.complete result=Failed;]"
}
try {
  Import-Module 'choco-auto-packaging' -Force
} catch {
  Write-Output "##vso[task.logissue type=Error]Unable to import modules: $($_ | Out-String)"
  Write-Output "##vso[task.complete result=Failed;]"
  return
}
$branchName = "EVERGREEN-$($PackageInfo.PackageName)-$FileVersion"
$PrTitle = "EVERGREEN: Update $($PackageInfo.PackageName) to $FileVersion"
$PrDescription = "Auto generated pull request to update $($PackageInfo.PackageName)"
git fetch
(git branch -r) -like "*origin/$($branchName)"
if ((git branch -r) -like "*origin/$($branchName)" -and $branchName){
  write-output "Deleting $branchname since it already exists, likely from a failed previous run."
  try {
    git push origin --delete "$branchName"
    git branch -D "$branchName"
  } catch {
    Write-Output "##vso[task.logissue type=error]Issue deleting branches: $_"
    Write-Output "##vso[task.complete result=Failed;]"
    return
  }
}
git switch origin/main
git reset --hard origin/main
git pull
git checkout -B $branchName
Update-ChocoParam -ChocoPackagePath $ChocoPackagePath -ChocoPackageName $PackageInfo.PackageName `
  -FileVersion $FileVersion -FileHash $FileHash -FileName $FileName `
  -TemplateURI $TemplateURI -FileHash64 $FileHash64 -FileName64 $FileName64 `
  -TemplateURI64 $TemplateURI64
git add "$($ChocoPackagePath)\*"
git commit -m "$PrTitle" -m "$PrDescription"
git push --set-upstream origin "+$($branchName)"
Write-Output "Attempting to create pull request for $($RepoName) at orguri $($CollectionURI)"
$prData = New-GitHubPullRequest -OrgURI "$($CollectionURI)" -RepoName $RepoName `
  -SourceBranch $branchName -TargetBranch 'main' -PrTitle $PrTitle `
  -PrDescription $PrDescription -GitHubToken $env:GITHUB_TOKEN
if (!$prData) {
  Write-Output "##vso[task.logissue type=error]Pull request not created by API query"
  Write-Output "##vso[task.complete result=Failed;]"
  return
}
# Update pull request to enable auto complete
$requestBody = @{
  autoCompleteSetBy = @{
    id = "$($prData.createdBy.id)"
  }
  completionOptions = @{
    deleteSourceBranch = $TRUE
    transitionWorkItems = $TRUE
    mergeStrategy = 'squash'
  }
}
$requestBody = $requestBody | ConvertTo-JSON
Write-Output "Pull Request Data:"
$prData | select *

Write-Output "Attempting to enable auto merge for $($prData.node_id) at orguri $($CollectionURI)"
Enable-GitHubAutoMerge -PullRequestID $prData.node_id `
  -GitHubToken $env:GITHUB_TOKEN
Write-Output "##vso[task.setvariable variable=PullRequestID]$($prData.number)"
Write-Output "##vso[task.setvariable variable=PullRequestURL]$($prData.html_url)"
Write-Output "##vso[task.setvariable variable=PullRequestBranchName]$($branchName)"
git switch $SourceBranchName
git reset --hard origin/$SourceBranchName