function Assert-MicrosoftRuntimeSignature {
  param([Parameter(Mandatory)][string]$Path)
  $signature = Get-AuthenticodeSignature -LiteralPath $Path
  if ($null -eq $signature -or $signature.Status -ne 'Valid' -or
      $null -eq $signature.SignerCertificate -or
      $signature.SignerCertificate.Subject -notmatch '(^|,\s*)CN=Microsoft Corporation(,|$)' -or
      $signature.SignerCertificate.Subject -notmatch '(^|,\s*)O=Microsoft Corporation(,|$)') {
    throw "Runtime must retain a valid original Microsoft signature: $Path"
  }
}
