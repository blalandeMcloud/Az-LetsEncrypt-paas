#######################################################################################
# Script that renews a Let's Encrypt certificate in Azure Key Vault (that are used on Application gateway)
# Pre-requirements:
#      - Have a storage account in which the folder path has been created: 
#        '/.well-known/acme-challenge/', to put here the Let's Encrypt DNS check files

#      - Add "Path-based" rule in the Application Gateway with this configuration: 
#           - Path: '/.well-known/acme-challenge/*'
#           - Check the configure redirection option
#           - Choose redirection type: permanent
#           - Choose redirection target: External site
#           - Target URL: <Blob public path of the previously created storage account>
#                - Example: 'https://test.blob.core.windows.net/public'
#
#
#        Following modules are needed now: Az.Accounts, Az.Network, Az.Storage, Az.KeyVault, ACME-PS
#
#######################################################################################
# Input bindings are passed in via param block.
param($Timer)

    $ExpiresInDays = 14
    [string]$EmailAddress = $env:EmailAddress
    [string]$STResourceGroupName = $env:STResourceGroupName
    [string]$storageName = $env:storageName
    [string]$KeyVaultName = $env:KeyVaultName
    [string]$SubName = $env:SubName

function Generate-RandomPassword {
    param (
        [Parameter(Mandatory)]
        [int] $length
    )
 
    $charSet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789$!'.ToCharArray()
 
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $bytes = New-Object byte[]($length)
  
    $rng.GetBytes($bytes)
  
    $result = New-Object char[]($length)
  
    for ($i = 0 ; $i -lt $length ; $i++) {
        $result[$i] = $charSet[$bytes[$i]%$charSet.Length]
    }
 
    return -join $result
}

#import Module Explicit
Import-module ACME-PS


Write-host "Connect to $SubName ..."
set-azcontext -subscription $SubName

$daysFromNow = (Get-Date).AddDays($ExpiresInDays)

# Get all certificates from Azure Key Vault
 $sslCerts = Get-AzKeyVaultCertificate -VaultName $KeyVaultName | where-object {$_.name -like "LetsEnc-*"}

Write-host "Check for certificates that expire in $ExpiresInDays days (on $daysFromNow)"

Foreach ($sslCert in $sslCerts) {

    $cert = Get-AzKeyVaultCertificate -VaultName $KeyVaultName -Name $sslCert.name
    # Save ID of the current certificate versions, that will be used for disabling later
    $certificateOldVersion = $cert.Version
    
    # Check if the certificate corresponds naming agreement (starts with 'LetsEncrypt' and whether it is expiring)
    if ($cert.Expires -le $daysFromNow) {
            
        [string]$Secret = Generate-RandomPassword 10

        # Extract domain name from the Subject
        $domain = $cert.Certificate.Subject.Replace("CN=", "")
        $OldCertName = $cert.Name
        
        Write-Output "Start renewing of the certificate: $OldCertName for $domain"

        # Create a state object and save it to the harddrive
        $tempFolderPath = "temp/" + $domain
        
        # Preparing folder for certificate renewal
        # Remove folder used for certificate renewal if existing
        if(Test-Path $tempFolderPath -PathType Container)
        {            
            Get-ChildItem -Path $tempFolderPath -Recurse | Remove-Item -force -recurse
            Remove-Item $tempFolderPath -Force -recurse
        }        
        
        $tempFolder = New-Item -Path $tempFolderPath -ItemType "directory"
        $state = New-ACMEState -Path $tempFolder
        $serviceName = 'LetsEncrypt'

        # Fetch the service directory and save it in the state
        Get-ACMEServiceDirectory $state -ServiceName $serviceName -PassThru;

        # Get the first anti-replay nonce
        New-ACMENonce $state;

        # Create an account key. The state will make sure it's stored.
        New-ACMEAccountKey $state -PassThru;

        # Register the account key with the acme service. The account key will automatically be read from the state
        New-ACMEAccount $state -EmailAddresses $EmailAddress -AcceptTOS;

        # Load an state object to have service directory and account keys available
        $state = Get-ACMEState -Path $tempFolder;

        # It might be neccessary to acquire a new nonce, so we'll just do it for the sake of the example.
        New-ACMENonce $state -PassThru;

        # Create the identifier for the DNS name
        $identifier = New-ACMEIdentifier $domain;

        # Create the order object at the ACME service.
        $order = New-ACMEOrder $state -Identifiers $identifier;

        # Fetch the authorizations for that order
        $authZ = Get-ACMEAuthorization -State $state -Order $order;

        # Select a challenge to fullfill
        $challenge = Get-ACMEChallenge $state $authZ "http-01";

        # Inspect the challenge data
        $challenge.Data;

        # Create the file requested by the challenge
        $fileName = $tempFolderPath + '\' + $challenge.Token;
        Set-Content -Path $fileName -Value $challenge.Data.Content -NoNewline;

        $blobName = ".well-known/acme-challenge/" + $challenge.Token
        $storageAccount = Get-AzStorageAccount -ResourceGroupName $STResourceGroupName -Name $StorageName
        $ctx = $storageAccount.Context
        Set-AzStorageBlobContent -File $fileName -Container "public" -Context $ctx -Blob $blobName

        # Signal the ACME server that the challenge is ready
        $challenge | Complete-ACMEChallenge $state;

        # Wait a little bit and update the order, until we see the states
        while ($order.Status -notin ("ready", "invalid")) {
            Start-Sleep -Seconds 10;
            $order | Update-ACMEOrder $state -PassThru;
        }

        # We should have a valid order now and should be able to complete it
        # Therefore we need a certificate key
        $certKey = New-ACMECertificateKey -Path "$tempFolder\$domain.key.xml";

        # Complete the order - this will issue a certificate singing request
        Complete-ACMEOrder $state -Order $order -CertificateKey $certKey;

        # Now we wait until the ACME service provides the certificate url
        while (-not $order.CertificateUrl) {
            Start-Sleep -Seconds 15
            $order | Update-Order $state -PassThru
        }

        # As soon as the url shows up we can create the PFX
        $password = ConvertTo-SecureString -String $secret -Force -AsPlainText
        Export-ACMECertificate $state -Order $order -CertificateKey $certKey -Path "$tempFolder\$domain.pfx" -Password $password;

        # Delete blob to check DNS
        Remove-AzStorageBlob -Container "public" -Context $ctx -Blob $blobName

        ### Upload new Certificate version to KeyVault
        Import-AzKeyVaultCertificate -VaultName $KeyVaultName -Name $OldCertName -FilePath "$tempFolder\$domain.pfx" -Password $password

        # Disable older certificate version
        Update-AzKeyVaultCertificate -VaultName $KeyVaultName -Name $OldCertName -Version $certificateOldVersion -Enable $false
        Write-Output "Older version ID: '$certificateOldVersion' for certificate $AGOldCertName is disabled"

        Write-Output "Completed renewing of the certificate: $AGOldCertName for $domain. New certificate version is uploaded."
    } else {
	Write-Output "$($cert.Name) expires in $($cert.Expires) days and does not need a renewal yet"
	}
}

Write-Output "Completed"

