<#
.Synopsis
  Sets PS repository to desired configuration and ensures modules are installed/updated
.DESCRIPTION
  Takes arguments to configure PS Repository and install a set of required modules. Most pipelines
  invoking this script assume it is in a folder called 'pipescripts'
.PARAMETER PSRepositoryName
Name of the PS Repository being configured
.PARAMETER PSRepositoryURI
URI for the PS Repository being configured
.PARAMETER PSRepositoryURILocal
Local URI (usually for publishing) for the PS Repository being configured
.PARAMETER RemoveDefaultPSRepository
Switch, when specified, removes the default PS Gallery
.PARAMETER PSModuleList
Comma separated list of modules:versions to be installed, ex: Evergreen:latest,Nevergreen:1.2.3
.EXAMPLE
For use in ADO Pipeline:
variables:
- name: PSRepositoryName
  value: '<name-of-chocolatey-feed>'
- name: PSRepositoryURI
  value: 'https://<artifactory-cloud-uri-here>/artifactory/api/nuget/v3/<name-of-chocolatey-feed>'
- name: PSRepositoryURILocal
  value: 'https://<artifactory-cloud-uri-here>/artifactory/api/nuget/v3/<name-of-chocolatey-feed>-local'
- name: PSModuleList
  value: 'Evergreen:latest,Nevergreen:latest,choco-auto-packaging:latest'
- name: RemoveDefaultPSRepository
  value: true

- task: PowerShell@2
  displayName: Configure PS repositories and install modules
  inputs:
    filePath: pipescripts/configure-poshEnv.ps1
    workingDirectory: $(System.DefaultWorkingDirectory)
    arguments: >-
      -PSRepositoryName ${{ variables.PSRepositoryName }} -PSRepositoryURI ${{ variables.PSRepositoryURI }}
      -PSRepositoryURILocal ${{ variables.PSRepositoryURILocal }} -RemoveDefaultPSRepository:$${{ variables.RemoveDefaultPSRepository }}
      -PSModuleList '${{ variables.PSModuleList }}'
#>
param(
    [Parameter(Mandatory = $true)][String]$PSRepositoryName,
    [Parameter(Mandatory = $true)][String]$PSRepositoryURI,
    [Parameter(Mandatory = $true)][String]$PSRepositoryURILocal,
    [Parameter(Mandatory = $true)][switch]$RemoveDefaultPSRepository,
    [Parameter(Mandatory = $true)][String[]]$PSModuleList
)
### Set PS Repository if required ###
$addRepo = $FALSE
$removeRepo = $FALSE
$repoCheck = Get-PSRepository | Where-Object {$_.Name -eq $PSRepositoryName}
if (!$repoCheck) {
  $addRepo = $TRUE
} elseif ($repoCheck.SourceLocation -ne $PSRepositoryURI) {
  $removeRepo = $TRUE
  $addRepo = $TRUE
}
# Perform necessary operations to remove/add internal repo based on pipeline variables
if ($addRepo) {
  if ($removeRepo) {
    try {
      Write-Output "Removing repo due to value mismatch:`n$($repoCheck | Out-String)"
      Unregister-PSRepository -Name $repoCheck.Name
    } catch {
      Write-Output @("##vso[task.logissue type=error]Unable to remove existing PS Repository.",
        "`nError info:`n$($_ | Select-Object * | Out-String)")
      Write-Output "##vso[task.complete result=Failed;]"
    }
  }
  $sourceSplat = @{
    Name               = $PSRepositoryName
    SourceLocation     = $PSRepositoryURI
    PublishLocation    = $PSRepositoryURILocal
    InstallationPolicy = 'Trusted'
  }
  try {
    Register-PSRepository @sourceSplat
  } catch {
    Write-Output @("##vso[task.logissue type=error]Unable to register PS Repository.",
        "`nError info:`n$($_ | Select-Object * | Out-String)")
    Write-Output "##vso[task.complete result=Failed;]"
  }
}
if ($RemoveDefaultPSRepository) {
  $psGalleryCheck = Get-PSRepository -Name 'PSGallery' -ErrorAction 'SilentlyContinue'
  if ($psGalleryCheck) {
    $psGalleryCheck | Unregister-PSRepository
  }
}
### Install required modules ###
foreach ($module in $PSModuleList.split(',')) {
  $moduleName = $NULL
  $moduleVersion = $NULL
  $moduleName,$moduleVersion = $module.split(':')
  $installSplat = @{
    Name = $moduleName
    Scope = 'CurrentUser'
    Force = $true
    Repository = $PSRepositoryName
    AllowClobber = $true
    SkipPublisherCheck = $true
  }
  $updateSplat = @{
    Name = $moduleName
    Force = $true
  }
  if ($moduleVersion -and $moduleVersion -ne 'latest') {
    $installSplat.Add('RequiredVersion',$moduleVersion)
    $updateSplat.Add('RequiredVersion',$moduleVersion)
  } elseif ($moduleVersion -eq 'latest') {
    $moduleVersion = $NULL
  }
  try {
    $localModule = $NULL
    $installedVersions = $NULL
    $currentModule = $NULL
    Write-Output "Checking $moduleName"
    $currentModule = Find-Module -Name $moduleName -Repository $PSRepositoryName
    $installedVersions = (Get-Module -Name $moduleName -ListAvailable)
    if ($installedVersions) {
      Write-Output "Versions currently installed for $($moduleName): $($installedVersions.Version.ToString())"
      $localModule = $installedVersions | Where-Object {$_.Version.ToString() -eq $currentModule.Version}
    } else {
      Write-Output "No module versions currently installed for $($moduleName)"
    }
    Write-Output "Current version available to download: $($currentModule.Version)"
    if (!$localModule){
      Write-Output "Installing module for $moduleName."
      Write-Output "Remote Version: $($currentModule.Version)"
      Install-Module @installSplat
    } elseif (($moduleVersion -and $localModule.Version.ToString() -notcontains $moduleVersion) -or
              (!$moduleVersion -and $localModule.Version.ToString() -notcontains $currentModule.Version)) {
      Write-Output "Updating module for $moduleName."
      Write-Output "Remote Version: $($currentModule.Version)"
      Update-Module @updateSplat
    } else {
      Write-Output "Current version already installed, nothing to do!"
    }
  } catch {
    Write-Output "##vso[task.logissue type=error]Unable to install/import modules modules: $($_ | select-object * | Out-String)"
    Write-Output "##vso[task.complete result=Failed;]"
    return
  }
}
Write-Output "Modules Currently Installed:"
Get-Module -ListAvailable -Refresh