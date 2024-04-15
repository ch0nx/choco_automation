function Compare-Version {
  param (
    [Parameter(Mandatory = $true)][System.Collections.IDictionary]$object1,
    [Parameter(Mandatory = $true)][System.Collections.IDictionary]$object2
  )
  <#
    .SYNOPSIS
    Compares two hash tables containing version information
    .DESCRIPTION
    Compares hash tables generated from the Convert-VersionToDict filter in order to determine if one is greater
    than the other. Returns true if object 1 is greater than object 2, or false if it is less than or equal to object 1.
    .PARAMETER Object1
    First hash table to be compared
    .PARAMETER Object2
    Second hash table to be compared

    .EXAMPLE
    $hash1 = '1.2.3.4' | Convert-VersionToDict
    $hash2 = '1.0.1-alpha+123' | Convert-VersionToDict
    Compare-Version $hash1 $hash2

    .INPUTS
    System.Collections.IDictionary

    .OUTPUTS
    Boolean
  #>
  if ($object1['Major'] -gt $object2['Major']){
    Write-Debug "Detected major version diff: $($object1['Major']) - $($object2['Major'])"
    return $TRUE
  } elseif (($object1['Major'] -eq $object2['Major']) -and
            ($object1['Minor'] -gt $object2['Minor'])
  ) {
    Write-Debug "Detected Minor version diff: $($object1['Minor']) - $($object2['Minor'])"
    return $TRUE
  } elseif (($object1['Major'] -eq $object2['Major']) -and
            ($object1['Minor'] -eq $object2['Minor']) -and
            ($object1['Patch'] -gt $object2['Patch'])
  ) {
    Write-Debug "Detected Patch version diff: $($object1['Patch']) - $($object2['Patch'])"
    return $TRUE
  } elseif (($object1['Major'] -eq $object2['Major']) -and
            ($object1['Minor'] -eq $object2['Minor']) -and
            ($object1['Patch'] -eq $object2['Patch']) -and
            ($object1['FourthSegment'] -or $object2['FourthSegment'])
  ) {
    # This is here for backwards compatibility with previous System.Version notation
    if ($object1['FourthSegment'] -and (!$object2['FourthSegment'] -and !$object2['PreRelease'])) {
      Write-Debug "No fourth segment for object2 while object1 does, which would result in object1 having higher precedence."
      return $TRUE
    } elseif ((!$object1['FourthSegment'] -and !$object1['PreRelease']) -and $object2['FourthSegment'] ) {
      Write-Debug "No fourth segment for object1 while object2 does, which would result in object2 having higher precedence."
      return $FALSE
    } elseif ($object1['FourthSegment'] -gt $object2['FourthSegment']) {
      Write-Debug "Detected fourth segment version diff: $($object1['Patch']) - $($object2['Patch'])"
      return $TRUE
    } else {
      Write-Debug "Versions either equal or less than for all: $($object1 | Out-String)`n$($object2 | Out-String)"
      return $FALSE
    }
  } elseif (($object1['Major'] -eq $object2['Major']) -and
            ($object1['Minor'] -eq $object2['Minor']) -and
            ($object1['Patch'] -eq $object2['Patch']) -and
            (!$object1['Prerelease'] -and $object2['Prerelease'])
  ) {
    Write-Debug "Source object has no prerelease version while object2 does, which means that object1 has higher precedence"
    return $TRUE
  } elseif (($object1['Major'] -eq $object2['Major']) -and
            ($object1['Minor'] -eq $object2['Minor']) -and
            ($object1['Patch'] -eq $object2['Patch']) -and
            ($object1['Prerelease'] -and !$object2['Prerelease'])
  ) {
  Write-Debug "Source object has a prerelease version while object2 does not, which means that object2 has higher precedence"
  return $FALSE
  } elseif (($object1['Major'] -eq $object2['Major']) -and
            ($object1['Minor'] -eq $object2['Minor']) -and
            ($object1['Patch'] -eq $object2['Patch']) -and
            ($object1['Prerelease'] -ne $object2['Prerelease'])
  ) {
    Write-Debug "Comparing prerelease versions"
    $prerelease1 = $object1['Prerelease'] -split '\.'
    $prerelease2 = $object2['Prerelease'] -split '\.'
    if ($prerelease1.count -gt $prerelease2.count){
      Write-Debug "Detected Prerelease version diff based on number of segments (true): $($object1['Prerelease']) - $($object2['Prerelease'])"
      return $TRUE
    } elseif ($prerelease1.count -lt $prerelease2.count) {
      Write-Debug "Detected Prerelease version diff based on number of segments (false): $($object1['Prerelease']) - $($object2['Prerelease'])"
      return $FALSE
    }
    Write-Debug "Comparing individual segments"
    $intPat = '^\d+$'
    for($i=0;$i -lt $prerelease1.count; $i++){
      if ($prerelease1[$i] -eq $prerelease2[$i]) {
        # If both are equal we just move on to the next segment
        continue
      } elseif ($prerelease1[$i] -match $intPat -and $prerelease2[$i] -match $intPat) {
        Write-Debug "$($prerelease1[$i]) and $($prerelease2[$i]) are both integers"
        # If both are integers we can compare them numerically
        if ([int]$prerelease1[$i] -gt [int]$prerelease2[$i]){
          Write-Debug "$($prerelease1[$i]) is greater than $($prerelease2[$i])"
          return $TRUE
        } else {
          Write-Debug "$($prerelease1[$i]) is less than $($prerelease2[$i])"
          return $FALSE
        }
      } elseif ($prerelease1[$i] -match $intPat -and $prerelease2[$i] -notmatch $intPat) {
        # If object1's segment is an integer and object2's is not, object1's segment is lower precedence
        Write-Debug "$($prerelease1[$i]) is an integer while $($prerelease2[$i]) is not, returning false"
        return $FALSE
      } elseif ($prerelease1[$i] -notmatch $intPat -and $prerelease2[$i] -match $intPat) {
        # If object1's segment is not an integer and object2's is, object1's segment is higher precedence
        Write-Debug "$($prerelease1[$i]) is not an integer while $($prerelease2[$i]) is, returning true"
        return $TRUE
      } else {
        # This would mean that both are not integers and should be compared lexically
        if ($prerelease1[$i] -gt $prerelease2[$i]){
          Write-Debug "$($prerelease1[$i]) is greater than $($prerelease2[$i]) returning true"
          return $TRUE
        } else {
          Write-Debug "$($prerelease1[$i]) is less than $($prerelease2[$i]) returning false"
          return $FALSE
        }
      }
    }
    Write-Debug "Detected Prerelease version diff: $($object1['Prerelease']) - $($object2['Prerelease'])"
    return $TRUE
  } else {
    Write-Debug "Versions either equal or less than for all: $($object1 | Out-String)`n$($object2 | Out-String)"
    return $FALSE
  }
}

filter Convert-VersionToDict {
  <#
    .SYNOPSIS
    Converts a version string into an ordered hash table
    .DESCRIPTION
    Takes a multi part or SemVer version string and converts it to an ordered hash table
    that can be used for accurate version comparisons.
    .PARAMETER <thing being piped to this filter>
    Multi part version or SemVer string (1.2.3.4 vs 1.2.3-4+567)
    .PARAMETER Object2
    Second hash table to be compared

    .EXAMPLE
    '1.2.3.4' | Convert-VersionToDict
    '1.0.1-alpha+123' | Convert-VersionToDict

    .INPUTS
    String

    .OUTPUTS
    OrderedDictionary
  #>
  $newVersion = [ordered]@{
    Major = 0
    Minor = 0
    Patch = 0
    Prerelease = $NULL
    Build = $NULL
    FourthSegment = $NULL
  }
  $prerelease = $NULL
  $build = $NULL
  $tmpArr = $NULL
  if (!$_){
    throw "Nothing supplied to convert"
  }
  $tmpArr = $_ -split '\.'
  if ($tmpArr[0] -and $tmpArr[0] -match '^\d+$') {
    Write-Debug "Detected digit notation in second segment"
    $newVersion['Major'] = [long]$tmpArr[0]
  } elseif ($tmpArr[0] -and $tmpArr[0] -notmatch '^\d+$') {
    throw "Invalid first segment: $($tmpArr[0])"
  }
  if ($tmpArr[1] -and $tmpArr[1] -match '^\d+$') {
    Write-Debug "Detected digit notation in second segment"
    $newVersion['Minor'] = [long]$tmpArr[1]
  } elseif ($tmpArr[1] -and $tmpArr[1] -notmatch '^\d+$') {
    throw "Invalid second segment: $($tmpArr[1])"
  }
  if ($tmpArr[2] -and $tmpArr[2] -match '^\d+$') {
    Write-Debug "Detected simple digit patch notation in third segment"
    $newVersion['Patch'] = [long]$tmpArr[2]
  } elseif ($tmpArr[2] -and $tmpArr[2] -match '^\d+(-[0-9A-Za-z.]+|)(\+[0-9A-Za-z-]+|)$') {
    # Pattern matched above is checking for Patch-Prerelease+Build formatting according to SemVer2.0
    Write-Debug "Detected semver patch notation in third segment"
    $patch = (($tmpArr[2] -split '-')[0] -split '\+')[0]
    Write-Debug "Patch value: $([long]$patch)"
    $newVersion['Patch'] = [long]$patch
    try {
      $prerelease = ($tmpArr[2] | Select-String -Pattern '-([a-zA-Z0-9]+)').Matches.Groups[1].Value
    } catch [System.Management.Automation.RuntimeException] {
      Write-Debug "Prerelease regex selection failed in an expected way: $($_ | Out-String)"
      $prerelease = $NULL
    } catch {
      throw "Unexpected error parsing prerelease regex: $($_ | Out-String)"
    }
    try {
      $build = ($tmpArr[2] | Select-String -Pattern '\+([a-zA-Z0-9]+)').Matches.Groups[1].Value
    } catch [System.Management.Automation.RuntimeException] {
      Write-Debug "Build regex selection failed in an expected way: $($_ | Out-String)"
      $build = $NULL
    } catch {
      throw "Unexpected error parsing build regex: $($_ | Out-String)"
    }
    Write-Debug "Prerelease value: $prerelease"
    Write-Debug "Build value: $build"
    if ($prerelease) {
      foreach ($segment in ($prerelease -split '\.')){
        if ($segment -notmatch '(^\d+$)|(^[A-Za-z]+$)') {
          throw "Invalid prerelease pattern for $prerelease segment $segment"
        }
      }
      $newVersion['Prerelease'] = $prerelease
    }
    if ($build) {
      $newVersion['Build'] = $build
    }
  } elseif ($tmpArr[2] -and $tmpArr[2] -notmatch '^\d+$' -and $tmpArr[2] -notmatch '^\d+(-[0-9A-Za-z.]+|)(\+[0-9A-Za-z-]+|)$') {
    throw "Invalid third segment: $($tmpArr[2])"
  }
  if (!$prerelease -and $tmpArr[3] -and $tmpArr[3] -match '^\d+$') {
    # This is for backwards compatibility with previous 4 segment version options, appending the 4th segment to the patch version
    # rather than using the Prerelease field (which has less precedence than versions of the same value without prerelease),
    # we can ensure that the previous version precedence remains intact while still supporting current semver requirements.
    Write-Debug "Detected fourth segment to be used, which makes this not a SemVer version: $($tmpArr[3])"
    $newVersion['FourthSegment'] = [long]$tmpArr[3]
    #$newVersion['Patch'] = [long]([string]$newVersion['Patch'] + [string]$tmpArr[3])
  } elseif (!$prerelease -and $tmpArr[3] -and $tmpArr[3] -notmatch '^\d+$') {
    throw "Invalid fourth segment: $($tmpArr[3])"
  }
  $newVersion
}


function Compare-EvergreenVersion {
  param(
    [Parameter(Mandatory = $true)][String]$PackagePath,
    [Parameter(Mandatory = $true)][String]$ChocoPackageName,
    [Parameter(Mandatory = $true)][String]$FileVersion,
    [Parameter(Mandatory = $true)][String]$FileHash,
    [Parameter(Mandatory = $false)][String]$CustomZip = ''
  )
  <#
    .SYNOPSIS
    Compares file data to choco package version

    .DESCRIPTION
    Finds the nuspec file for a chocolatey package given a base packages path,
    and then compares the major, minor, build, and revision data to determine
    if the file needs to be updated.

    .PARAMETER $PackagePath
    Path to the directory containing all Chocolatey package source code
    .PARAMETER $ChocoPackageName
    Name of the Chocolatey package to query
    .PARAMETER $FileVersion
    Version of the file to check
    .PARAMETER $FileHash
    Checksum/Hash of the file to check

    .EXAMPLE
    Compare-EvergreenVersion -PackagePath C:\azp\agent\_work\4\s\packages
      -ChocoPackageName citrix-workspace -FileVersion '22.3.4000.4080' `
      -FileHash 'efcc0838ba47e7ceca77daaad0a32e31695b3f7728cee3ad0b77d611265e95a8'

    .INPUTS
    System.String

    .OUTPUTS
    PSCustomObject
  #>
  if (!(test-path $PackagePath)) {
    throw "Package code repo path: $PackagePath is not accessible, aborting"
  }
  $packageDir = Get-ChildItem $PackagePath -Recurse -Directory -Filter $ChocoPackageName
  if (!$packageDir){
    throw "No package directory found for $ChocoPackageName in $PackagePath or its children"
  }
  $packageDir = $packageDir.FullName
  try {
    $xml = New-Object -TypeName XML
    $xml.Load("$($packageDir)\$($ChocoPackageName).nuspec")
  } catch {
    throw "Unable to load XML object $($packageDir)\$($ChocoPackageName).nuspec"
  }
  try {
    $chocoInstallPath = Get-ChildItem $packageDir -Recurse -File -Filter 'chocolateyinstall.ps1'
    $chocoInstallPath = $chocoInstallPath.FullName
    if (!$chocoInstallPath){
      throw 'This is probably an unnecessary check'
    }
  } catch {
    throw "Unable to get chocolateyinstall.ps1 file at $packageDir"
  }
  try {
    $varPattern = '^(?<!#)(\s+|)(\$(checksum)(\s+|)=(\s+|)).*$'
    # Get matches based on our dynamic regex and create a string output, in PS7 there is the -Raw argument for Select-String,
    # But not enough stuff is standardized onto PS7 yet so we've got this jank.
    $psVarList = Get-Content $chocoInstallPath | select-string -Pattern $varPattern | ForEach-Object {$_.toString().trim()}
    # Have to put non-strings into string format so this doesnt try to reference variables that dont exist outside of the choco
    # context
    $psVarList = foreach ($psvar in $psVarList) {
      $temp = $NULL
      $temp = $psvar.split('=') | ForEach-Object {$_.trim()}
      if ($temp[1][0] -notmatch "`"|'"){
        "$($temp[0].trim()) = '$($temp[1].trim())'"
      } else {
        "$($temp[0].trim()) = $($temp[1].trim())"
      }
    }
    # Convert the string to a script block, then dot source it to import the current variable values
    $psVarList = [Scriptblock]::Create($psvarlist -join ';')
    .$psVarList
  } catch {
    throw "Unable to load variables in $chocoInstallPath for checksum comparison"
  }
  $returnObject = [PSCustomObject]@{
    Result = $FALSE
    ChecksumTest = $FALSE
    VersionComp = $FALSE
    ChocoPackagePath = $packageDir
    NuspecVersion = $xml.package.metadata.version
    ConvertedVersion = $NULL
  }
  if ($filehash -ne $checksum){
    Write-Output "Checksum mismatch:`n$fileHash `n$checksum"
    $returnObject.ChecksumTest = $TRUE
  } else {
    Write-Output "Checksum match:`n$fileHash `n$checksum"
  }
  $tmpVer = $FileVersion | Convert-VersionToDict
  Write-Output "FileVersion: $($tmpVer | Out-String)"
  Write-Output "NuspecVersion: $($returnObject.NuspecVersion | Convert-VersionToDict | Out-String)"
  $returnObject.VersionComp = Compare-Version $tmpVer ($returnObject.NuspecVersion | Convert-VersionToDict)
  $returnObject.ConvertedVersion = "$($tmpVer['Major'])"
  if ($NULL -ne $tmpVer['Minor']){ $returnObject.ConvertedVersion +=  ".$($tmpVer['Minor'])"}
  if ($NULL -ne $tmpVer['Patch']){ $returnObject.ConvertedVersion +=  ".$($tmpVer['Patch'])"}
  if ($NULL -ne $tmpVer['Prerelease'] -or $NULL -ne $tmpVer['Build']){
    if ($NULL -ne $tmpVer['Prerelease']){ $returnObject.ConvertedVersion +=  "-$($tmpVer['Prerelease'])"}
    if ($NULL -ne $tmpVer['Build']){ $returnObject.ConvertedVersion +=  "+$($tmpVer['Build'])"}
  } elseif ($NULL -ne $tmpVer['FourthSegment']){ $returnObject.ConvertedVersion +=  ".$($tmpVer['FourthSegment'])"}
  # If the version is mismatched but the checksum is still the same, no action should be required.
  if ($returnObject.VersionComp -and !$returnObject.ChecksumTest){
    Write-Warning "File version does not match nuspec, but checksum does"
    $returnObject.Result = $FALSE
  } elseif ($returnObject.VersionComp -or ($returnObject.ChecksumTest -and $CustomZip -eq '')){
    # We have to ignore the checksum tests for zipped folders since we dont want to copy them down and zip them
    # at every execution for the sake of a checksum comparison.
    Write-Debug "Setting result to true, versionComp result: $($returnObject.VersionComp), checksum + customzip result: $($returnObject.ChecksumTest -and $CustomZip -eq '')"
    $returnObject.Result = $TRUE
  }
  return $returnObject
}

function Set-ChocoBlob {
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification='No other way to use this access token from pipeline')]
  param(
    [Parameter(Mandatory = $true)][String]$TenantID,
    [Parameter(Mandatory = $true)][String]$AppID,
    [Parameter(Mandatory = $true)][String]$SubscriptionName,
    [Parameter(Mandatory = $true)][String]$StorageAcctName,
    [Parameter(Mandatory = $true)][String]$StorageContainer,
    [Parameter(Mandatory = $true)][String]$Vendor,
    [Parameter(Mandatory = $true)][String]$ProductName,
    [Parameter(Mandatory = $true)][String]$FilePath,
    [Parameter(Mandatory = $true)][String]$FileVersion
  )
  <#
    .SYNOPSIS
    Uploads a file to Azure Blob Storage

    .DESCRIPTION
    A URL/Path including the Vendor, product, and application is automatically generated.
    If the supplied file does not exist in the generated URL, it is uploaded.
    .PARAMETER $TenantID
    Azure tenant ID
    .PARAMETER $AppID
    Azure Service Principal application ID
    .PARAMETER $SubscriptionName
    Azure subscription containing the storage account
    .PARAMETER $StorageAcctName
    Storage account to upload to
    .PARAMETER $StorageContainer
    Name of the container in the storage account to upload to
    .PARAMETER $Vendor
    Name of the Vendor for the software file being uploaded
    .PARAMETER $ProductName
    Chocolatey package name for the software
    .PARAMETER $FilePath
    Path to the file that is being uploaded
    .PARAMETER $FileVersion
    Version of the file that is being uploaded

    .EXAMPLE
    Set-ChocoBlob -TenantID 'some-long-string' -AppID 'some-other-long-string' `
      -SubscriptionName '<azure-subscription-name>' -StorageAcctName '<azure-storage-account-name>' `
      -StorageContainer '<container name in blob storage account here>' -Vendor 'citrix' `
      -ProductName 'Citrix-Workspace' -FilePath 'C:\azp\agent\_work\4\s\CitrixWorkspaceApp22.3.4000.4080.exe' -FileVersion '22.3.4000.4080'

    .INPUTS
    System.String

    .OUTPUTS
    NOTHING
  #>
  $securePassword = ConvertTo-SecureString -String $env:BLOB_ACCESSTOKEN -AsPlainText -Force
  $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $appId, $securePassword
  Connect-AzAccount -ServicePrincipal -TenantId $tenantId -Credential $credential -Subscription $SubscriptionName -SkipContextPopulation -confirm:$FALSE | Out-Null
  Set-AzContext -Subscription $SubscriptionName | Out-Null
  $storContext = New-AzStorageContext -StorageAccountName $StorageAcctName -UseConnectedAccount
  $fileHash = Get-FileHash -Path $FilePath
  $blobName = get-item $FilePath | Select-Object -expand Name
  $blobPath = "$($Vendor)/$($ProductName)/$($FileVersion)/$blobName"
  $splatArgs = @{
    Container = $StorageContainer
    Context = $storContext
    Blob = $blobPath
  }
  $blobTest = Get-AzStorageBlob @splatArgs -ErrorAction 'SilentlyContinue'
  if (!$blobTest){
    $splatArgs['File'] = $FilePath
    try {
      $blobInfo = Set-AzStorageBlobContent @splatArgs -Force
    } catch {
      throw "Unable to upload file, error: $($_)"
      return
    }
  } else {
    Write-Host "File already exists: $($blobTest.icloudBlob.uri.AbsoluteUri)"
    $blobInfo = $blobTest
  }
  # Formatting output object, same format as the AzureUploader
  $baseURL = $blobInfo.iCloudBlob.uri.Scheme + '://' + $blobInfo.iCloudBlob.uri.DnsSafeHost
  for ($i=0; $i -lt ($blobInfo.iCloudBlob.uri.segments.count - 1); $i++){
    $baseURL += $blobInfo.iCloudBlob.uri.segments[$i]
  }
  $outputObj = [PSCustomObject]@{
    BaseURL = $baseURL
    TemplateURL = $($BaseURL + '$filename')
    TemplateURL64 = $($BaseURL + '$filename64')
    FullURL = $blobInfo.ICloudBlob.uri.absoluteuri
    FileName = $blobInfo.iCloudBlob.name.split('/')[-1]
    Hash = $fileHash.Hash
    Algorithm = $fileHash.Algorithm.ToLower()
  }
  return $outputObj
}

function Remove-ChocoBlob {
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification='No other way to use this access token from pipeline')]
  param(
    [Parameter(Mandatory = $true)][String]$TenantID,
    [Parameter(Mandatory = $true)][String]$AppID,
    [Parameter(Mandatory = $true)][String]$SubscriptionName,
    [Parameter(Mandatory = $true)][String]$StorageAcctName,
    [Parameter(Mandatory = $true)][String]$StorageContainer,
    [Parameter(Mandatory = $true)][String]$BlobPath
  )
  <#
    .SYNOPSIS
    Deletes a file from Azure Blob Storage

    .DESCRIPTION
    A URL/Path including the Vendor, product, and application is automatically generated.
    If the supplied file does not exist in the generated URL, it is uploaded.
    .PARAMETER $TenantID
    Azure tenant ID
    .PARAMETER $AppID
    Azure Service Principal application ID
    .PARAMETER $SubscriptionName
    Azure subscription containing the storage account
    .PARAMETER $StorageAcctName
    Storage account to upload to
    .PARAMETER $StorageContainer
    Name of the container in the storage account to upload to
    .PARAMETER $BlobPath
    Path to the blob to be removed, ex: mozilla/firefox/115.3.1/Firefox%20Setup%20115.3.1esr.exe

    .EXAMPLE
    Remove-ChocoBlob -TenantID 'some-long-string' -AppID 'some-other-long-string' `
      -SubscriptionName '<azure-subscription-name>' -StorageAcctName '<blob storage account name here>' `
      -StorageContainer '<container name in blob storage account here>' BlobPath 'mozilla/firefox/115.3.1/Firefox%20Setup%20115.3.1esr.exe'

    .INPUTS
    System.String

    .OUTPUTS
    NOTHING
  #>
  $securePassword = ConvertTo-SecureString -String $env:BLOB_ACCESSTOKEN -AsPlainText -Force
  $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $appId, $securePassword
  Connect-AzAccount -ServicePrincipal -TenantId $tenantId -Credential $credential -Subscription $SubscriptionName -SkipContextPopulation -confirm:$FALSE | Out-Null
  Set-AzContext -Subscription $SubscriptionName | Out-Null
  $storContext = New-AzStorageContext -StorageAccountName $StorageAcctName -UseConnectedAccount
  $splatArgs = @{
    Container = $StorageContainer
    Context = $storContext
    Blob = $blobPath
  }
  $blobTest = Get-AzStorageBlob @splatArgs -ErrorAction 'SilentlyContinue'
  if ($blobTest){
    try {
      $blobTest | Remove-AzStorageBlob
      return "Blob at $BlobPath removed successfully"
    } catch {
      return "Unable to remove blob at $BlobPath, error: $($_)"
    }
  } else {
    return "Blob not found at $BlobPath"
  }
}

function Update-ChocoParam {
  param (
    [Parameter(Mandatory = $true)][String]$ChocoPackagePath,
    [Parameter(Mandatory = $true)][String]$ChocoPackageName,
    [Parameter(Mandatory = $true)][String]$FileVersion,
    [Parameter(Mandatory = $true)][String]$FileHash,
    [Parameter(Mandatory = $true)][String]$FileName,
    [Parameter(Mandatory = $true)][String]$TemplateURI,
    [Parameter(Mandatory = $false)][String]$FileHash64 = $NULL,
    [Parameter(Mandatory = $false)][String]$FileName64 = $NULL,
    [Parameter(Mandatory = $false)][String]$TemplateURI64 = $NULL
  )
  <#
    .SYNOPSIS
    Updates Chocolatey install parameters for file retrieval as well as the nuspec version

    .DESCRIPTION
    Selectively replaces file retrieval URL, name, and checksum in the chocolateyinstall.ps1 script, and
    updates the nuspec to use the new file version
    .PARAMETER ChocoPackagePath
    Path to the base folder for the package being modified
    .PARAMETER ChocoPackageName
    Name of the package itself, should match folder name and nuspec name
    .PARAMETER FileVersion
    Version of the new binary being targeted on blob storage
    .PARAMETER FileHash
    Checksum of the new binary
    .PARAMETER FileName
    Name of the new binary
    .PARAMETER TemplateURI
    The "Template URI" that is generated by Set-ChocoBlob

    .EXAMPLE
    Update-ChocoParams -ChocoPackagePath 'C:\azp\agent\_work\9\s\packages\cvad_packaging\Citrix-Workspace' -ChocoPackageName 'Citrix-Workspace' `
    -FileVersion '22.3.4000.4080' -FileHash 'efcc0838ba47e7ceca77daaad0a32e31695b3f7728cee3ad0b77d611265e95a8' `
    -FileName 'CitrixWorkspaceApp22.3.4000.4080.exe' -TemplateURI 'https://<blob storage account name here>.blob.core.windows.net/<container name in blob storage account here>/citrix/Citrix-Workspace/22.3.4000.4080/$filename'

    .INPUTS
    System.String

    .OUTPUTS
    NOTHING
  #>
  if (!(test-path $ChocoPackagePath)) {
    throw "Choco package path: $ChocoPackagePath is not accessible, aborting"
  }
  $chocoInstallPath = "$($ChocoPackagePath)\tools\chocolateyinstall.ps1"
  $nuspecPath = "$($ChocoPackagePath)\$($ChocoPackageName).nuspec"
  if (!(Test-Path $chocoInstallPath)){
    throw "Missing choco install at $chocoinstallpath"
  } elseif  (!(Test-Path $nuspecPath)){
    throw "Missing nuspec at $nuspecpath"
  }
  $newFile = '$file = ' + "`"$($TemplateURI)`""
  $newFileName = '$fileName = ' + "'$fileName'"
  $newSoftwareVersion = '$softwareVersion = ' + "'$FileVersion'"
  $newChecksum = '$checksum = ' + "'$fileHash'"
  # Replace the content of the choco install file with our new contents
  try {
    (Get-Content $chocoInstallPath) `
      -replace '\$file(\s+|)=(\s+|)\S+$', $newFile `
      -replace '\$fileName(\s+|)=(\s+|)\S+$', $newFileName `
      -replace '\$softwareVersion(\s+|)=(\s+|)\S+$', $newSoftwareVersion `
      -replace '\$checksum(\s+|)=(\s+|)\S+$', $newChecksum |
    Set-Content $chocoInstallPath
  } catch {
    throw "Error replacing content in $($chocoInstallPath): $_"
  }
  if ($TemplateURI64 -and $FileName64 -and $FileHash64) {
    $newFile64 = '$file64 = ' + "`"$($TemplateURI64)`""
    $newFileName64 = '$fileName64 = ' + "'$FileName64'"
    $newChecksum64 = '$checksum64 = ' + "'$FileHash64'"
    # Replace the content of the choco install file with our new contents
    try {
      (Get-Content $chocoInstallPath) `
        -replace '\$file64(\s+|)=(\s+|)\S+$', $newFile64 `
        -replace '\$fileName64(\s+|)=(\s+|)\S+$', $newFileName64 `
        -replace '\$checksum64(\s+|)=(\s+|)\S+$', $newChecksum64 |
      Set-Content $chocoInstallPath
    } catch {
      throw "Error replacing x64 content in $($chocoInstallPath): $_"
    }
  }
  try {
    $xml = New-Object -TypeName XML
    $xml.Load($nuspecPath)
    $xml.package.metadata.version = $FileVersion
    $xml.Save($nuspecPath)

  } catch {
    throw "Error replacing nuspec content in $($nuspecPath): $_"
  }
}
function New-ADOPullRequest {
  param (
    [Parameter(Mandatory = $true)][String]$OrgURI,
    [Parameter(Mandatory = $true)][String]$RepoName,
    [Parameter(Mandatory = $true)][String]$SourceRef,
    [Parameter(Mandatory = $true)][String]$TargetRef,
    [Parameter(Mandatory = $true)][String]$PrTitle,
    [Parameter(Mandatory = $true)][String]$PrDescription
  )
  <#
    .SYNOPSIS
    Creates a new Azure DevOps Pull Request
    .DESCRIPTION
    Uses the supplied parameters to create a new pull request for the desired branch
    using the pipeline's credentials

    .PARAMETER OrgURI
    Base URI of the organization in ADO, ex: https://dev.azure.com/<OrganizationID>/<TeamID>
    .PARAMETER RepoName
    Name of the repository in ADO
    .PARAMETER SourceRef
    ref for the branch that is to be merged
    .PARAMETER TargetRef
    ref for the main branch
    .PARAMETER PrTitle
    Title to use for the pull request
    .PARAMETER PrDescription
    Description to use for the pull request

    .EXAMPLE
    New-ADOPullRequest -OrgURI 'https://dev.azure.com/<OrganizationID>/<TeamID>' -RepoName 'Chocolatey'
      -SourceRef "refs/heads/EVERGREEN-Citrix-Workspace-22.3.4000.4080" -TargetRef 'refs/heads/main' `
      -PrTitle 'EVERGREEN: Update Citrix-Workspace to 22.3.4000.4080' `
      -PrDescription 'Auto generated pull request to update Citrix-Workspace'

    .INPUTS
    System.String

    .OUTPUTS
    PSCustomObject
  #>
  $newReqURI = "$OrgURI/_apis/git/repositories/$RepoName/pullrequests?supportsIterations=false&api-version=7.0"
  $requestBody = @{
    SourceRefName = $SourceRef
    TargetRefName = $TargetRef
    title         = $PrTitle
    description   = $PrDescription
  }
  $requestBody = $requestBody | ConvertTo-JSON
  Invoke-RestMethod -Uri $newReqURI -Method POST -ContentType "application/json" `
    -Headers @{Authorization = "Bearer $($env:SYSTEM_ACCESSTOKEN)"} -Body $requestBody
}

function New-GitHubPullRequest {
  param (
    [Parameter(Mandatory = $true)][String]$OrgURI,
    [Parameter(Mandatory = $true)][String]$RepoName,
    [Parameter(Mandatory = $true)][String]$SourceBranch,
    [Parameter(Mandatory = $true)][String]$TargetBranch,
    [Parameter(Mandatory = $true)][String]$PrTitle,
    [Parameter(Mandatory = $true)][String]$PrDescription,
    [Parameter(Mandatory = $true)][String]$GitHubToken
  )
  <#
    .SYNOPSIS
    Creates a new GitHub Pull Request
    .DESCRIPTION
    Uses the supplied parameters to create a new pull request for the desired branch
    using the pipeline's credentials

    .PARAMETER OrgURI
    Base URI of the organization in GitHub, ex: https://api.github.com/repos/<OrganizationID>
    .PARAMETER RepoName
    Name of the repository in GitHub
    .PARAMETER SourceBranch
    Name of the branch that is to be merged
    .PARAMETER TargetBranch
    Main branch name
    .PARAMETER PrTitle
    Title to use for the pull request
    .PARAMETER PrDescription
    Description to use for the pull request
    .PARAMETER GitHubToken
    Bearer token to be used for the API query

    .EXAMPLE
    New-GitHubPullRequest -OrgURI 'https://api.github.com/repos/<OrganizationID>' -RepoName 'Chocolatey'
      -SourceBranch "EVERGREEN-Citrix-Workspace-22.3.4000.4080" -TargetBranch 'main' `
      -PrTitle 'EVERGREEN: Update Citrix-Workspace to 22.3.4000.4080' `
      -PrDescription 'Auto generated pull request to update Citrix-Workspace'

    .INPUTS
    System.String

    .OUTPUTS
    PSCustomObject
  #>
  $newReqURI = "$OrgURI/$RepoName/pulls"
  $headers = @{
    Accept = 'application/vnd.github+json'
    Authorization = "Bearer $($GitHubToken)"
    'X-GitHub-Api-Version' = '2022-11-28'
  }
  $requestBody = @{
    head   = $SourceBranch
    base   = $TargetBranch
    title  = $PrTitle
    body   = $PrDescription
    maintainer_can_modify = $TRUE
  }
  $requestBody = $requestBody | ConvertTo-JSON
  Write-host "Creating pull request with using uri $newReqURI with body:`n$($requestBody | Out-String)"
  Invoke-RestMethod -Uri $newReqURI -Method POST -Headers $headers -Body $requestBody
}

function Test-ADOPullRequest {
  param (
    [Parameter(Mandatory = $true,ParameterSetName = 'Exact')]
    [Parameter(Mandatory = $true,ParameterSetName = 'Relative')]
    [String]$OrgURI,
    [Parameter(Mandatory = $true,ParameterSetName = 'Exact')]
    [Parameter(Mandatory = $true,ParameterSetName = 'Relative')]
    [String]$RepoName,
    [Parameter(Mandatory = $true,ParameterSetName = 'Exact')]
    [Parameter(Mandatory = $true,ParameterSetName = 'Relative')]
    [String]$TargetRef,
    [Parameter(Mandatory = $true,ParameterSetName = 'Exact')]
    [String]$SourceRef,
    [Parameter(Mandatory = $true,ParameterSetName = 'Relative')]
    [String]$RelativeMatch,
    [Parameter(Mandatory = $true,ParameterSetName = 'Relative')]
    [String]$ExcludeRef,
    [Parameter(Mandatory = $false,ParameterSetName = 'Relative')]
    [String]$RelativeDays = 6
  )
  <#
    .SYNOPSIS
    Checks Azure DevOps for matching pull request
    .DESCRIPTION
    Uses the supplied parameters to query Azure Devops' active pull requests for the
    desired branch using the pipeline's credentials

    .PARAMETER OrgURI
    Base URI of the organization in ADO, ex: https://dev.azure.com/<OrganizationID>/<TeamID>
    .PARAMETER RepoName
    Name of the repository in ADO
    .PARAMETER SourceRef
    ref for the branch that is to be merged
    .PARAMETER TargetRef
    ref for the main branch
    .PARAMETER RelativeMatch
    Should provide a wildcard search for the SourceRef, so that open pull requests can be filtered
    .PARAMETER RelativeDays
    How many days old a pull request can be before being eligible for deletion

    .EXAMPLE
    Test-ADOPullRequest -OrgURI 'https://dev.azure.com/<OrganizationID>/<TeamID>' -RepoName 'Chocolatey'
      -SourceRef "refs/heads/EVERGREEN-Citrix-Workspace-22.3.4000.4080" -TargetRef 'refs/heads/main'

    Test-ADOPullRequest -OrgURI 'https://dev.azure.com/<OrganizationID>/<TeamID>' -RepoName 'Chocolatey'
      RelativeMatch "*EVERGREEN-Citrix-Workspace*" -TargetRef 'refs/heads/main'

    .INPUTS
    System.String

    .OUTPUTS
    PSCustomObject
  #>
  switch ($PsCmdlet.ParameterSetName) {
    'Exact' {
      $uriCheckActivePR = "$($OrgURI)/_apis/git/repositories/$($RepoName)/pullrequests?searchCriteria.TargetRefName=$($TargetRef)&searchCriteria.SourceRefName=$($SourceRef)&api-version=7.0"
    }
    'Relative' {
      # Get all requests older than 8 days
      $beforeDate = get-date (get-date).AddDays(-$RelativeDays) -Format "o"
      $uriCheckActivePR = "$($OrgURI)/_apis/git/repositories/$($RepoName)/pullrequests?searchCriteria.TargetRefName=$($TargetRef)&searchCriteria.maxTime=$($beforeDate)&api-version=7.0"
    }
  }
  Write-Host "Using URI: $uriCheckActivePR"
  $returnObject = [PSCustomObject]@{
    Result = $FALSE
    Values = $NULL
  }
  $result = Invoke-RestMethod -Uri $uriCheckActivePR -Method Get -ContentType "application/json" -Headers @{Authorization = "Bearer $($env:SYSTEM_ACCESSTOKEN)"}
  Write-Debug "result: $($result | out-string)`nvalue: $($result.value | out-string)"
  if ($result.value -and $result.value.count -gt 0){
    if ($PsCmdlet.ParameterSetName -eq 'Relative') {
      Write-Debug "Filtering values"
      $returnObject.Values = $result.value | Where-Object {$_.sourcerefname -like "$RelativeMatch" -and $_.sourcerefname -ne $ExcludeRef}
      Write-Debug "Post filtering: $($returnObject.Values | out-string)"
    } else {
      Write-debug "Not filtering values"
      $returnObject.Values = $result.value
    }
  }
  if ($returnObject.Values) {
      Write-Debug "Existing PR(s) detected"
      Write-Debug "$($returnObject.Values | Out-String)"
      $returnObject.Result = $TRUE
  } else {
    Write-Debug "No PR exists"
    $returnObject.Result = $FALSE
  }
  return $returnObject
}

function Test-GitHubPullRequest {
  param (
    [Parameter(Mandatory = $true,ParameterSetName = 'Exact')]
    [Parameter(Mandatory = $true,ParameterSetName = 'Relative')]
    [String]$OrgURI,
    [Parameter(Mandatory = $true,ParameterSetName = 'Exact')]
    [Parameter(Mandatory = $true,ParameterSetName = 'Relative')]
    [String]$RepoName,
    [Parameter(Mandatory = $true,ParameterSetName = 'Exact')]
    [Parameter(Mandatory = $true,ParameterSetName = 'Relative')]
    [String]$TargetBranch,
    [Parameter(Mandatory = $true,ParameterSetName = 'Exact')]
    [String]$SourceBranch,
    [Parameter(Mandatory = $true,ParameterSetName = 'Relative')]
    [String]$RelativeMatch,
    [Parameter(Mandatory = $true,ParameterSetName = 'Relative')]
    [String]$ExcludeBranch,
    [Parameter(Mandatory = $false,ParameterSetName = 'Relative')]
    [String]$RelativeDays = 6,
    [Parameter(Mandatory = $true,ParameterSetName = 'Exact')]
    [Parameter(Mandatory = $true,ParameterSetName = 'Relative')]
    [String]$GitHubToken
  )
  <#
    .SYNOPSIS
    Checks GitHub for matching pull request
    .DESCRIPTION
    Uses the supplied parameters to query GitHub's active pull requests for the
    desired branch using the pipeline's credentials

    .PARAMETER OrgURI
    Base URI of the organization in GitHub, ex: https://api.github.com/repos/<OrganizationID>
    .PARAMETER RepoName
    Name of the repository in GitHub
    .PARAMETER SourceBranch
    Name of the branch that is to be merged
    .PARAMETER TargetBranch
    Main branch name
    .PARAMETER ExcludeBranch
    Branch name that should not be returned in a relative match list
    .PARAMETER RelativeMatch
    Should provide a wildcard search for the SourceRef, so that open pull requests can be filtered
    .PARAMETER RelativeDays
    How many days old a pull request can be before being eligible for deletion
    .PARAMETER GitHubToken
    Bearer token to be used for the API query

    .EXAMPLE
    Test-GitHubPullRequest -OrgURI 'https://api.github.com/repos/<OrganizationID>' -RepoName 'Chocolatey'
      -SourceBranch "EVERGREEN-Citrix-Workspace-22.3.4000.4080" -TargetBranch 'main' -GitHubToken "MyToken"

    Test-GitHubPullRequest -OrgURI 'https://api.github.com/repos/<OrganizationID>' -RepoName 'Chocolatey'
      -RelativeMatch "*EVERGREEN-Citrix-Workspace*" -TargetBranch 'main' -ExcludeBranch 'EVERGREEN-Citrix-Workspace-22.3.4000.4080' -GitHubToken "MyToken"

    .INPUTS
    System.String

    .OUTPUTS
    PSCustomObject
  #>
  # Because GitHub has way fewer REST API options, we have to do filtering after getting a bulk list of PRs
  $uriCheckActivePR = "$($OrgURI)/$($RepoName)/pulls"
  Write-Host "Org URI: $($OrgURI)"
  Write-Host "Repo Name: $($RepoName)"
  Write-Host "Using URI: $uriCheckActivePR"
  $returnObject = [PSCustomObject]@{
    Result = $FALSE
    Values = $NULL
  }
  $headers = @{
    Accept = 'application/vnd.github+json'
    Authorization = "Bearer $($GitHubToken)"
    'X-GitHub-Api-Version' = '2022-11-28'
  }
  $result = Invoke-RestMethod -Uri $uriCheckActivePR -Method Get -Headers $headers
  Write-Debug "result: $($result | out-string)"
  if ($result -and $result.count -gt 0){
    if ($PsCmdlet.ParameterSetName -eq 'Relative') {
      $beforeDate = (get-date).AddDays(-$RelativeDays)
      Write-Debug "Filtering values for relative match"
      $returnObject.Values = $result | Where-Object {
        $_.head.ref -like $RelativeMatch -and
        $_.base.ref -eq $TargetBranch -and
        $_.head.ref -ne $ExcludeBranch -and
        $_.created_at -lt $beforeDate}
      Write-Debug "Post filtering: $($returnObject.Values | out-string)"
    } else {
      Write-debug "Getting exact match"
      $returnObject.Values = $result | Where-Object {$_.head.ref -eq $SourceBranch -and $_.base.ref -eq $TargetBranch}
      Write-Debug "Post filtering: $($returnObject.Values | out-string)"
    }
  }
  if ($returnObject.Values) {
      Write-Debug "Existing PR(s) detected"
      Write-Debug "$($returnObject.Values | Out-String)"
      $returnObject.Result = $TRUE
  } else {
    Write-Debug "No PR exists"
    $returnObject.Result = $FALSE
  }
  return $returnObject
}

function Update-GitHubPullRequest {
  param (
    [Parameter(Mandatory = $true)][String]$OrgURI,
    [Parameter(Mandatory = $true)][String]$RepoName,
    [Parameter(Mandatory = $true)][String]$PullRequestID,
    [Parameter(Mandatory = $true)][String]$RequestBody,
    [Parameter(Mandatory = $true)][String]$RESTMethod,
    [Parameter(Mandatory = $true)][String]$GitHubToken
  )
  <#
    .SYNOPSIS
    Updates and existing GitHub Pull Request
    .DESCRIPTION
    Uses the supplied parameters to update an existing pull request for the desired branch
    using the pipeline's credentials

    .PARAMETER OrgURI
    Base URI for GitHub API, ex: https://api.github.com/repos
    .PARAMETER RepoName
    Name of the repository in GitHub
    .PARAMETER PullRequestID
    ID of the pull request to be modified
    .PARAMETER RequestBody
    JSON of the body to be passed to Invoke-WebRequest
    .PARAMETER RESTMethod
    What method to use, PATCH, POST, etc

    .EXAMPLE
    $requestBody = @{
      state = 'closed'
    }
    $requestBody = $requestBody | ConvertTo-JSON
    Update-PullRequest -OrgURI 'https://api.github.com/repos/<OrganizationID>' -RepoName 'Chocolatey' `
      -PullRequestID '12345' -RequestBody $RequestBody -RESTMethod 'PATCH'

    .INPUTS
    System.String

    .OUTPUTS
    PSCustomObject
  #>
  $updatePrById = "$($OrgURI)/$($RepoName)/pulls/$($PullRequestID)"
  $headers = @{
    Accept = 'application/vnd.github+json'
    Authorization = "Bearer $($GitHubToken)"
    'X-GitHub-Api-Version' = '2022-11-28'
  }
  Write-Host "Attempting to update pull request with url $updatePrByID using REST Method $RestMethod and body: `n$($requestBody)"
  Invoke-RestMethod -Uri $updatePrById -Method $RESTMethod -Headers $headers -Body $requestBody
}

function Update-ADOPullRequest {
  param (
    [Parameter(Mandatory = $true)][String]$OrgURI,
    [Parameter(Mandatory = $true)][String]$RepoName,
    [Parameter(Mandatory = $true)][String]$PullRequestID,
    [Parameter(Mandatory = $true)][String]$RequestBody,
    [Parameter(Mandatory = $true)][String]$RESTMethod
  )
  <#
    .SYNOPSIS
    Updates an existing Azure DevOps pull request
    .DESCRIPTION
    Uses the supplied parameters to update an existing pull request for the desired branch
    using the pipeline's credentials

    .PARAMETER OrgURI
    Base URI of the organization in ADO
    .PARAMETER RepoName
    Name of the repository in ADO
    .PARAMETER PullRequestID
    ID Number of the pull request to be modified
    .PARAMETER RequestBody
    JSON of the body to be passed to Invoke-WebRequest
    .PARAMETER RESTMethod
    What method to use, PATCH, POST, etc

    .EXAMPLE
    $requestBody = @{
      state = 'closed'
    }
    $requestBody = $requestBody | ConvertTo-JSON
    Update-ADOPullRequest -OrgURI 'https://dev.azure.com/<OrganizationID>/<TeamID>' -RepoName 'Chocolatey' `
      -PullRequestID '12345' -RequestBody $RequestBody -RESTMethod 'PATCH'

    $requestBody = @{
      allow_auto_merge = $true
    }
    $requestBody = $requestBody | ConvertTo-JSON
    Update-ADOPullRequest -OrgURI 'https://dev.azure.com/<OrganizationID>/<TeamID>' -RepoName 'Chocolatey' `
      -PullRequestID '12345' -RequestBody $RequestBody -RESTMethod 'PATCH'

    .INPUTS
    System.String

    .OUTPUTS
    PSCustomObject
  #>
  $updatePrById = "$($OrgURI)/_apis/git/repositories/$($RepoName)/pullrequests/$($PullRequestID)?api-version=7.0"
  Invoke-RestMethod -Uri $updatePrById -Method $RESTMethod -ContentType 'application/json' `
    -Headers @{Authorization = "Bearer $($env:SYSTEM_ACCESSTOKEN)"} -Body $requestBody
}

function Enable-GitHubAutoMerge {
  param (
    [Parameter(Mandatory = $true)][String]$PullRequestID,
    [Parameter(Mandatory = $true)][String]$GitHubToken
  )
  <#
    .SYNOPSIS
    Enables auto merge on a github pull request
    .DESCRIPTION
    Uses GitHub's GraphQL endpoint to enable auto merge on a pull request, because no REST API endpoint exists for it.

    .PARAMETER PullRequestID
    node_id number of the pull request to be modified. It cannot be just the numeric pull request value, but the
    node_id returned from a pull request query.
    .PARAMETER GitHubToken
    Bearer token to be used for the API query

    .EXAMPLE
    Enable-GitHubAutoMerge -PullRequestID 'PR_sOmerEalLylOnGsTrinG' -GitHubToken "MyToken"

    .INPUTS
    System.String

    .OUTPUTS
    PSCustomObject
  #>
  $endpoint = "https://api.github.com/graphql"
  # here-string needs to end as the first character on a line and cannot be indented, so we're doing this instead
  $query = @(
    'mutation EnableAutoMerge($pullRequestId: ID!, $mergeMethod: PullRequestMergeMethod!, $commitBody: String!) {',
    '  enablePullRequestAutoMerge(input: {',
    '    pullRequestId: $pullRequestId,',
    '    mergeMethod: $mergeMethod,',
    '    commitBody: $commitBody',
    '  }) {',
    '    clientMutationId',
    '  }',
    '}'
    ) | Out-String

  $variables = @{
    pullRequestId = "$PullRequestID"
    mergeMethod = "SQUASH"
    commitBody = "Automatically merging pull request upon approval"
  }

  # Convert the query and variables to JSON
  $requestBody = @{
    query = $query
    variables = $variables
  } | ConvertTo-Json

  # Send the GraphQL request
  $response = Invoke-RestMethod -Method POST -Uri $endpoint `
    -Headers @{ Authorization = "Bearer $($GitHubToken)" } `
    -Body $requestBody
  # Check for errors
  if ($response.errors) {
    throw "GraphQL query failed: $($response.errors[0].message)"
  }
  $response
}

function Remove-ArtifactoryPackage {
  param (
    [Parameter(Mandatory = $true)][String]$RemoveString,
    [Parameter(Mandatory = $true)][String]$ArtifactoryURIBase,
    [Parameter(Mandatory = $true)][String]$FeedName,
    [Parameter(Mandatory = $true)][DateTime]$DeletionDate,
    [Parameter(Mandatory = $true)][Hashtable]$Headers,
    [Parameter(Mandatory = $true)][String]$BlobURIBase,
    [Parameter(Mandatory = $true)][String]$TenantID,
    [Parameter(Mandatory = $true)][String]$AppID,
    [Parameter(Mandatory = $true)][String]$SubscriptionName,
    [Parameter(Mandatory = $true)][String]$StorageAcctName,
    [Parameter(Mandatory = $true)][String]$StorageContainer
  )
  <#
    .SYNOPSIS
    Removes a nupkg from Artifactory hosted NuGet feed based on specific statistics
    .DESCRIPTION
    If a package is old enough and has not been downloaded within the specified timeframe, delete it and its backing binary

    .PARAMETER RemoveString
    Name of the package in Artifactory, usually package-name.version. ex: package-name.1.2.3
    .PARAMETER ArtifactoryURIBase
    Base URI for Artifactory deployment
    .PARAMETER FeedName
    Name of the NuGet feed in Artifactory
    .PARAMETER DeletionDate
    If the package has not been downloaded since this date, delete it
    .PARAMETER Headers
    Headers to pass to the REST API, ex:
    $headers = @{
      'Authorization' = "Bearer $ArtifactoryToken"
      'Content-Type' = 'application/json'
    }
    .PARAMETER BlobURIBase
    Base URI for the Azure Blob storage, ex. https://<blob storage account name here>.blob.core.windows.net/<container name in blob storage account here>/
    .PARAMETER TenantID
    Azure tenant id that contains your blob storage
    .PARAMETER $AppID
    Azure Service Principal application ID, must have deletion rights to blob storage
    .PARAMETER $SubscriptionName
    Azure subscription containing the storage account
    .PARAMETER $StorageAcctName
    Storage account to upload to
    .PARAMETER $StorageContainer
    Name of the container in the storage account to upload to

    .EXAMPLE
      $headers = @{
        'Authorization' = "Bearer $ArtifactoryToken"
        'Content-Type' = 'application/json'
      }
      $dateCompare = (Get-Date).AddMonths(-3)
      $afRemoveSplat = @{
        RemoveString       = package-name.1.2.3
        ArtifactoryURIBase = 'https://<artifactory-cloud-uri-here>/artifactory'
        FeedName            = <name-of-chocolatey-feed>
        DeletionDate       = $dateCompare
        Headers            = $headers
        BlobURIBase        = 'https://<blob storage account name here>.blob.core.windows.net/<container name in blob storage account here>/'
        TenantID           = 'some long string'
        AppID              = 'some other long string'
        SubscriptionName   = '<azure-subscription-name>'
        StorageAcctName    = '<blob storage account name here>'
        StorageContainer   = '<container name in blob storage account here>'
      }
      $removalStatus = Remove-ArtifactoryPackage @afRemoveSplat

    .INPUTS
    System.String,DateTime,Hashtable

    .OUTPUTS
    Hashtable
  #>
  $feedURI = "$($ArtifactoryURIBase)/api/nuget/v3/$($FeedName)"
  $artifactoryString = $RemoveString
  $queryURI = "$($ArtifactoryURIBase)/api/storage/$($FeedName)/$($artifactoryString).nupkg?stats"
  $returnValue = @{
    ArtifactoryRemoved = $FALSE
    BlobRemoved        = $FALSE
    BlobURI            = ''
  }
  try {
    $artifactoryQuery = Invoke-RESTMethod -URI $queryURI -Method GET -Headers $headers -ErrorAction 'Stop'
  } catch {
    Write-Host $("##vso[task.logissue type=warning]Error querying artifactory for $($artifactoryString), manual "+
      "NuGet query required. Query URI:`n$queryURI")
    Write-Debug "Error Info: $($_ | Out-String)"
    $queryRequired = $TRUE
  }
  # Manual query to NuGet feed for version disparity, likely caused by leading zeroes or no third version segment
  if ($queryRequired) {
    try {
      $packageName = ($artifactoryString -split '\.',2)[0]
      $sourceVersion = ($artifactoryString -split '\.',2)[1] | Convert-VersionToDict
    } catch {
      Write-Host "##vso[task.logissue type=warning]Unable to split and convert $($artifactoryString): $($_ | Out-String)"
      Write-Host "##vso[task.complete result=SucceededWithIssues;]"
      return $returnValue
    }
    $sourceString = "$($sourceVersion.Major).$($sourceVersion.Minor).$($sourceVersion.Patch)"
    if ($NULL -ne $sourceVersion.FourthSegment) {
      $sourceString += ".$($sourceVersion.FourthSegment)"
    }
    $searchTerm = "PackageId:$($packageName)"
    # Build the NuGet search query URI
    $queryURI = '{0}/query?q={1}&prerelease=true&semVerLevel=2' -f $feedURI, [uri]::EscapeDataString($searchTerm)
    try {
      Write-Debug "Attempting to query NuGet with Query URI:`n$queryURI"
      # Download the search results in JSON format
      $resultsJson = Invoke-WebRequest -Uri $queryURI -UseBasicParsing | Select-Object -ExpandProperty Content
      # Parse the JSON results and extract the package IDs and versions, with the PackageId term it should be an exact
      # match, but some filters have been inconsistent in the past
      $results = ConvertFrom-Json $resultsJson | Where-Object {$_.data.id -eq $packageName}
      if (!$results) {
        Write-Host "##vso[task.logissue type=warning]Error querying NuGet for $($searchTerm): No object returned from feed"
        Write-Host "##vso[task.complete result=SucceededWithIssues;]"
        return $returnValue
      }
    } catch {
      Write-Host "##vso[task.logissue type=warning]Error querying NuGet for $($searchTerm): $($_ | Out-String)"
      Write-Host "##vso[task.complete result=SucceededWithIssues;]"
      return $returnValue
    }
    foreach ($version in $results.data.versions.version) {
      # Create the same version dict that we have in our package object, so that it can be compared
      # equally with the source version, and create a new Artifactory API query based on it if found
      $tmpCompare = $NULL
      $tmpCompare = $version | Convert-VersionToDict
      $compareString = "$($tmpCompare.Major).$($tmpCompare.Minor).$($tmpCompare.Patch)"
      if ($NULL -ne $tmpCompare.FourthSegment) {
        $compareString += ".$($tmpCompare.FourthSegment)"
      }
      # Edge case where one version reports a fourth segment of 0 and the other doesnt
      if (($sourceVersion.FourthSegment -eq 0 -and $NULL -eq $tmpCompare.FourthSegment) -or
          ($NULL -eq $sourceVersion.FourthSegment -and $tmpCompare.FourthSegment -eq 0)
      ) {
        $sourceString = "$($sourceVersion.Major).$($sourceVersion.Minor).$($sourceVersion.Patch)"
        $compareString = "$($tmpCompare.Major).$($tmpCompare.Minor).$($tmpCompare.Patch)"
      }
      Write-Debug "Comparing Strings: '$($sourceString)' and '$($compareString)'"
      if ($sourceString -eq $compareString) {
        $artifactoryString = "$($packageName).$($version)"
        $queryURI = "$($artifactoryURIBase)/api/storage/$($FeedName)/$($artifactoryString).nupkg?stats"
        Write-Debug $("$($packageName): NuGet query found match for source version '$($version)': '$($compareString)'."+
          " Querying Artifactory using $queryURI")
        try {
          $artifactoryQuery = Invoke-RESTMethod -URI $queryURI -Method GET -Headers $headers -ErrorAction 'Stop'
        } catch {
          Write-Host "##vso[task.logissue type=warning]Error querying Artifactory using version from NuGet for $($artifactoryString): $($_ | Out-String)"
          Write-Host "##vso[task.complete result=SucceededWithIssues;]"
          return $returnValue
        }
        break
      }
    }
  }
  if ($artifactoryQuery) {
    # Timestamp returned from Artifactory is ISO8601 milisconds from epoch, this conversion results in the correct date
    $dateConverted = [datetimeoffset]::FromUnixTimeMilliseconds($artifactoryQuery.lastDownloaded).datetime
    if (($dateConverted -le $dateCompare) -or ($artifactoryQuery.lastDownloaded -eq 0)) {
      if ($artifactoryQuery.lastDownloaded -eq 0) {
        Write-Host "$($artifactoryString): Artifact never downloaded, deletion required"
      } else {
        Write-Host "$($artifactoryString): $($dateConverted.DateTime) is before $($dateCompare.DateTime), deletion required"
      }
    } else {
      Write-Host $("$($artifactoryString): Artifact has been downloaded after $($dateCompare.DateTime), and will not be deleted. "+
        "Last Download Date: $($dateConverted.DateTime)")
      return $returnValue
    }
  } else {
    Write-Host "##vso[task.logissue type=warning]$($artifactoryString): Was not able to be found in Artifactory and did not hit existing error handlers."
    Write-Host "##vso[task.complete result=SucceededWithIssues;]"
    return $returnValue
  }
  ### Blob Deletion Block ###
  ### Import chocolateyInstall.ps1 script variables ###
  $varPattern = '^(?<!#)(\s+|)(\$(file|file64|fileName|fileName64)(\s+|)=(\s+|)).*$'
  $scriptContentsQuery = "$($ArtifactoryURIBase)/$($FeedName)/$($artifactoryString).nupkg!/tools/chocolateyinstall.ps1"
  try {
    Write-Host "Attempting to download script from $scriptContentsQuery"
    $webclient = new-object System.Net.WebClient
    $scriptContents = $webclient.DownloadString($scriptContentsQuery)
  } catch {
    Write-Host $("##vso[task.logissue type=error]Error querying artifactory for chocolateyinstall.ps1 file at $($scriptContentsQuery)"+
      "Error info:`n$($_ | Out-String)")
  }
  $scriptVarList = $scriptContents.Split([Environment]::NewLine) | select-string -Pattern $varPattern | ForEach-Object {$_.toString().trim()}
  # Have to put non-strings into string format so this doesnt try to reference variables that dont exist outside of the choco
  # context
  $scriptVarList = foreach ($scriptVar in $scriptVarList) {
    $temp = $NULL
    $temp = $scriptVar.split('=') | ForEach-Object {$_.trim()}
    if ($temp[1][0] -notmatch "`"|'"){
      "$($temp[0].trim()) = '$($temp[1].trim())'"
    } else {
      "$($temp[0].trim()) = $($temp[1].trim())"
    }
  }
  # Convert the string to a script block, then dot source it to import the current variable values
  $scriptVarList = [Scriptblock]::Create($scriptVarList -join ';')
  $file = $NULL
  $file64 = $NULL
  .$scriptVarList
  # Remove any blobs from storage
  $removeSplat = @{
    TenantID         = $TenantID
    AppID            = $AppID
    SubscriptionName = $SubscriptionName
    StorageAcctName  = $StorageAcctName
    StorageContainer = $StorageContainer
    BlobPath         = $NULL
  }
  @(
    $file,
    $file64
  ) | Foreach-Object {
    if (!$_) {
      continue
    }
    if ($returnValue.BlobURI) {
      $returnValue.BlobURI += ";$_"
    } else {
      $returnValue.BlobURI = $_
    }
    $removeSplat.BlobPath = $NULL
    $removeSplat.BlobPath = $_.trimstart($BlobURIBase)
    if (!$removeSplat.BlobPath) {
      Write-Host "##vso[task.logissue type=warning]Could not obtain blob path from $file with base $BlobURIBase"
      continue
    }
    $removalTest = Remove-ChocoBlob @removeSplat
    if ($removalTest -like '*removed successfully*') {
      Write-Host "$removalTest"
      $returnValue.BlobRemoved = $TRUE
    } elseif ($removalTest -like 'Unable to remove*') {
      Write-Host "##vso[task.logissue type=error]$removalTest"
      $returnValue.BlobRemoved = $FALSE
      continue
    } else {
      Write-Host "##vso[task.logissue type=warning]$removalTest"
      $returnValue.BlobRemoved = $TRUE
    }
  }
  ### Delete from Artifactory ###
  $deleteURI = "$($ArtifactoryURIBase)/$($FeedName)/$($artifactoryString).nupkg"
  Write-Debug "Calling $deleteURI"
  # Attempt deletion via REST API
  try {
    Invoke-RESTMethod -URI $deleteURI -Method DELETE -Headers $headers
    Write-Host "$($artifactoryString): Removed from Artifactory."
    $returnValue.ArtifactoryRemoved = $TRUE
  } catch {
    Write-Host "##vso[task.logissue type=warning]$($artifactoryString): Failed to delete from Artifactory.  Error: $($_ | Out-String)"
    Write-Host "##vso[task.complete result=SucceededWithIssues;]"
  }
  return $returnValue
}

function Get-AppFromShare {
  param (
    [Parameter(Mandatory = $true)][String]$SharePath,
    [Parameter(Mandatory = $true)][String]$FileName,
    [Parameter(Mandatory = $true)][System.Management.Automation.PSCredential]$Credential
  )
  <#
    .SYNOPSIS
    Gets app info from file hosted on a file share
    .DESCRIPTION
    Mounts a PS Drive and attempts to get information on a file that should be present at that exact spot

    .PARAMETER SharePath
    UNC path for the directory that contains the file being queried, ex: \\fileshare.contoso.int\jankyapp
    .PARAMETER FileName
    Name of the file to be queried, ex jankyapp.exe
    .PARAMETER Credential
    PSCredential object that is able to query the file share

    .EXAMPLE
    $creds = New-Object System.Management.Automation.PSCredential($shareuser, $secpass)
    Get-AppFromShare -SharePath '\\fileshare.contoso.int\jankyapp' -FileName 'jankyapp.exe' -Credential $creds
    .INPUTS
    System.String,System.Management.Automation.PSCredential

    .OUTPUTS
    PSCustomObject
  #>
  try {
    New-PSDrive -Name CustomApp -PSProvider FileSystem -Root $SharePath -Credential $Credential | Out-Null
  } catch {
    throw "Get-AppFromShare: Unable to mount drive at $SharePath with supplied credentials: $($_ | Out-String)"
  }
  $filePath = Join-Path 'CustomApp:' $FileName
  $fileCheck = Get-Item $filePath
  if ($fileCheck) {
    $returnObject = [PSCustomObject]@{
      URI = $fileCheck.FullName
      Version = $fileCheck.VersionInfo.ProductVersion
      Hash = (Get-FileHash $fileCheck.FullName).Hash
    }
    Remove-PSDrive -Name 'CustomApp' | Out-Null
    if ($returnObject.URI -and $returnObject.Version -and $returnObject.Hash) {
      return $returnObject
    } else {
      throw "Get-AppFromShare: Did not retrieve correct information for $FileName on $SharePath, results: $($returnObject | Out-String)"
    }
  } else {
    Remove-PSDrive -Name 'CustomApp' | Out-Null
    throw "Unable to find $FileName on $SharePath"
  }
}

function Copy-AppFromShare {
  param (
    [Parameter(Mandatory = $true)][String]$SharePath,
    [Parameter(Mandatory = $true)][String]$FileName,
    [Parameter(Mandatory = $true)][String]$DestinationPath,
    [Parameter(Mandatory = $false)][String]$CustomZip = '',
    [Parameter(Mandatory = $true)][System.Management.Automation.PSCredential]$Credential
  )
  <#
    .SYNOPSIS
    Retrieves file(s) hosted on a file share, and zips if required
    .DESCRIPTION
    Mounts a PS Drive and attempts copy down the desired file, or zips the entire directory to the desired location

    .PARAMETER SharePath
    UNC path for the directory that contains the file being retrieved, ex: \\fileshare.contoso.int\jankyapp
    .PARAMETER FileName
    Name of the file to be retrieved, ex jankyapp.exe
    .PARAMETER DestinationPath
    Path that the file is to be copied/unzipped to
    .PARAMETER CustomZip
    Currently only supports 'AllFiles' value, if set, it will take all the files in the mounted directory
    and zip them up, instead of only returning one specific file.
    .PARAMETER Credential
    PSCredential object that is able to query the file share

    .EXAMPLE
    $creds = New-Object System.Management.Automation.PSCredential($shareuser, $secpass)
    Copy-AppFromShare -SharePath '\\fileshare.contoso.int\jankyapp' -FileName 'jankyapp.zip' `
      -DestinationPath 'C:\temp\jankyapp.zip' -CustomZip 'AllFiles' -Credential $creds
    .INPUTS
    System.String,System.Management.Automation.PSCredential

    .OUTPUTS
    PSCustomObject
  #>
  try {
    New-PSDrive -Name CustomApp -PSProvider FileSystem -Root $SharePath -Credential $Credential | Out-Null
  } catch {
    throw "Copy-AppFromShare: Unable to mount drive at $SharePath with supplied credentials: $($_ | Out-String)"
  }
  if ($CustomZip -eq 'AllFiles') {
    $newDestination = $DestinationPath -replace '\.\w+$','.zip'
    Get-ChildItem -Path 'CustomApp:' | Compress-Archive -DestinationPath $DestinationPath
    Write-Output "Setting new filehash due to custom zip folder usage"
    $newHash = (Get-FileHash $DestinationPath).Hash
    Write-Output "##vso[task.setvariable variable=FileHash]$($newHash)"
  } else {
    $filePath = Join-Path 'CustomApp:' $FileName
    $fileCheck = Get-Item $filePath
    if ($fileCheck) {
      try {
        Copy-Item $filePath $DestinationPath
      } catch {
        Remove-PSDrive -Name 'CustomApp' | Out-Null
        throw "Unable to copy $FileName from $SharePath to $DestinationPath, error: $($_ | Out-String)"
      }
    }
  }
  Remove-PSDrive -Name 'CustomApp' | Out-Null
}
