<#
  .SYNOPSIS
  Returns the latest Rapid7InsightAgent version number and download url.
  .NOTES
  Author: Justin Cook
  Following general idea/format of PS functions in https://github.com/aaronparker/evergreen/tree/main/Evergreen/Apps
  Does not invoke a settings json file since this is homegrown and theres not much point in creating and distributing a
  JSON file that only really contains download URIs
#>
$r7URIs = @{
  x64 = 'https://s3.amazonaws.com/com.rapid7.razor.public/endpoint/agent/latest/windows/x86_64/PyForensicsAgent-x64.msi'
  x86 = 'https://s3.amazonaws.com/com.rapid7.razor.public/endpoint/agent/latest/windows/x86/PyForensicsAgent-x86.msi'
}
$dateFormat = "ddd, dd MMM yyyy HH:mm:ss 'GMT'"
# Get the version from Amazon S3 metadata, Rapid7's S3 bucket does not provide a hash.
$results = foreach ($uri in $r7URIs.GetEnumerator()) {
  try {
    $request = [System.Net.HttpWebRequest]::Create($uri.value)
    $request.Method = "HEAD"
    $response = $request.GetResponse()
    # Get the metadata from the response headers
    # Note, if you are reviewing output manually, $response.Headers looks like a list of strings,
    # but is actually a kind of hash table (WebHeaderCollection) without standard hash table methods.
    $headers = $response.Headers
  } catch {
    throw "Failed to resolve metadata: $($uri.value)."
    return
  }
  if (!$headers['x-amz-meta-semanticversion']) {
    throw "Missing return data for x-amz-meta-semanticversion on $(uri): $($headers['x-amz-meta-semanticversion'])"
    return
  }
  if (!$headers['Last-Modified']) {
    throw "Missing return data for Last-Modified on $(uri): $($headers['Last-Modified'])"
    return
  }
  if (!$headers['Content-Length']) {
    throw "Missing return data for Content-Length on $(uri): $($headers['Content-Length'])"
    return
  }
  try {
    $returnObject = [PSCustomObject] @{
      Version       = $headers['x-amz-meta-semanticversion']
      Type          = [System.IO.Path]::GetExtension($uri.value).Split(".")[-1]
      Date          = [System.DateTime]::ParseExact($headers['Last-Modified'], $dateFormat, [System.Globalization.CultureInfo]::InvariantCulture)
      Size          = $headers['Content-Length']
      Architecture  = $uri.Key
      Uri           = $uri.value
    }
    $returnObject
  } catch {
    throw "Failed to create return object for Rapid7InsightAgent using URI: $($uri.value)."
    return
  }
}
return $results