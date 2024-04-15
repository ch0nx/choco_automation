<#
.Synopsis
  Verifies folder structure naming and nuspec id requirements
.DESCRIPTION
  By default, this will scan all nuspec files in the repo
	A list of nuspec files can also be passed manually in order to target specific files.
	Or the GitChangedOnly switch can be used to target only files changed between the current branch and the main branch
	In order to pass parameters to a Pester test you have to define a container and then pass it to the Invoke-Pester command.
.EXAMPLE
	Testing specific file paths:
	$testPaths = @(
	'C:\Repos\Chocolatey\tests\public\chocolateyinstall.acceptance.tests.ps1',
	'C:\Repos\Chocolatey\tests\public\choco-naming.acceptance.tests.ps1'
	)
	$filePaths = @(
		'C:\Repos\Chocolatey\packages\core\google-chrome-stable\tools\chocolateyinstall.ps1',
		'C:\Repos\Chocolatey\packages\core\google-chrome-stable\google-chrome-stable.nuspec'
	)
	$container = New-PesterContainer -Path $testPaths -Data @{ FilePaths=$filePaths }
	$config = New-PesterConfiguration
	$config.output.StackTraceVerbosity = 'None'
	$config.Run.Container = $container
	Invoke-Pester -Configuration $config

	Testing only changed files identified by git:
	$testPaths = @(
	'C:\Repos\Chocolatey\tests\public\chocolateyinstall.acceptance.tests.ps1',
	'C:\Repos\Chocolatey\tests\public\choco-naming.acceptance.tests.ps1'
	)
	$container = New-PesterContainer -Path $testPaths -Data @{ GitChangedOnly = $true }
	$config = New-PesterConfiguration
	$config.output.StackTraceVerbosity = 'None'
	$config.Run.Container = $container
	Invoke-Pester -Configuration $config

	Test all files in current directory and subdirectories:
	$config = New-PesterConfiguration
	$config.run.path = 'C:\Repos\Chocolatey\tests\public'
	$config.output.StackTraceVerbosity = 'None'
	Invoke-Pester -Configuration $config

	Get standard output from a test run:
	$config = New-PesterConfiguration
	$config.run.path = 'C:\Repos\Chocolatey\tests\public'
	$config.run.passthru = $true
	$config.output.StackTraceVerbosity = 'None'
	$test = Invoke-Pester -Configuration $config
	$test.tests.StandardOutput
#>
param(
	[Parameter(Mandatory=$false)]
  [ValidateScript({
		foreach ($path in $_){
			if (!(Test-Path $path -PathType 'leaf')){
				throw "No file exists at $path"
				$false
			}
		}
		$true
  })]
  [string[]]$FilePaths,
	[Parameter(Mandatory=$false)][switch]$GitChangedOnly
)

BeforeDiscovery {
	# Depending on parameters supplied, we either need to identify changes made in this branch,
	# or we scan all files, or we scan the supplied specific files to test
	if ($GitChangedOnly -and !$FilePaths) {
		try {
			$mainBranch = (git remote show origin | Select-String 'HEAD branch').ToString().Split(' ')[-1]
			if (-not $?) { throw }
			$gitRoot = (git rev-parse --show-toplevel)
			if (-not $?) { throw }
			$changedFiles = (git diff --diff-filter=d --name-only origin/${mainBranch}...)
			if (-not $?) { throw }
		} catch {
			Write-Error "Error running git commands to detect changed files: `n$($_ | Select-Object * | Out-String)"
			return
		}
		$filesToTest = foreach ($file in ($changedFiles | Where-Object {$_ -like '*.nuspec'})) {
			$testFile = Join-Path $gitRoot $file
			if (Test-Path $testFile) {
				@{
					FullPath = $testFile
					RelativePath = $file
				}
			} else {
				throw "Error testing path at $($testfile), this should not happen"
			}
		}
	} elseif (!$FilePaths) {
		$filesToTest = (Get-ChildItem $PWD -filter '*.nuspec' -Recurse) | ForEach-Object {
			@{
				FullPath = $_.FullName
				RelativePath = $_.FullName.Substring($_.FullName.IndexOf('packages'))
			}
		}
	} else {
		$filesToTest = $FilePaths | Where-Object {$_ -like '*.nuspec'} | ForEach-Object {
			@{
				FullPath = $_
				RelativePath = $_.Substring($_.IndexOf('packages'))
			}
		}
	}
	$filesToTest = $filesToTest | Where-Object {$_['FullPath'] -notlike '*templates*' -and $_ -notlike '*test-*'}
	$filesToTest | Write-Debug
}
Describe "Nuspec Testing" -ForEach $filesToTest {
	BeforeEach {
		$nuspecFile      = $NULL
		$directoryName   = $NULL
		$nuspecXml       = $NULL
		$nuspecPackageId = $NULL
		$nuspecFile      = Get-Item -Path $_.FullPath
		$directoryName   = Split-Path -Path $nuspecFile.DirectoryName -Leaf
		$nuspecXml       = [xml](Get-Content -Path $nuspecFile.FullName -Raw)
		$nuspecPackageId = $nuspecXml.package.metadata.id
	}
	$_ | out-string | write-debug
	# Colons added to the end of assertion names to make published summaries look better
	Context "Naming" {
		# Loop through each folder and perform the tests
		It "Nuspec file name should match parent directory name: (<RelativePath>)" {
			# Assert that each nuspec file has a corresponding directory with the same name
			$nuspecfile.BaseName | Should -Be $directoryName
		}
		It "Nuspec id field should match nuspec file name: (<RelativePath>)" {
			# Assert that each nuspec file's package.metadata.id matches the directory name
			$nuspecPackageId | Should -Be $nuspecfile.BaseName
		}
		It "Nuspec id field should match parent directory name: (<RelativePath>)" {
			# Assert that each nuspec file's package.metadata.id matches the directory name
			$nuspecPackageId | Should -Be $directoryName
		}
	}
}