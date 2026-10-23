function Assert-MicrosoftRuntimeSignature {
  param([Parameter(Mandatory)][string]$Path)
  $signature = Get-AuthenticodeSignature -LiteralPath $Path
  if ($null -eq $signature -or $signature.Status -ne 'Valid' -or
      $null -eq $signature.SignerCertificate -or
      $signature.SignerCertificate.Subject -notmatch '(^|,\s*)CN=Microsoft (Corporation|Windows Software Compatibility Publisher)(,|$)' -or
      $signature.SignerCertificate.Subject -notmatch '(^|,\s*)O=Microsoft Corporation(,|$)') {
    $detail = if ($null -eq $signature) { 'signature result=null' } else {
      $subject = if ($null -eq $signature.SignerCertificate) { 'null' } else { $signature.SignerCertificate.Subject }
      $statusMessage = if ($signature.PSObject.Properties['StatusMessage']) { $signature.StatusMessage } else { '' }
      "status=$($signature.Status); statusMessage=$statusMessage; subject=$subject"
    }
    throw "Runtime must retain a valid original Microsoft signature: $Path ($detail)"
  }
}
