#######################################################################################
# Script that gets Let's Encrypt certificate and uploads it to Azure Key Vault (that are used on Application gateway)
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

#######################################################################################
 
using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

    [string]$Domain = $Request.body.domain
    [string]$AppGwName = $Request.body.AppgwName
#Temp Variable
    [string]$AppGwSub = $Request.body.AppGwSub

#General Variable 
    [string]$SubName = $env:SubName
    [string]$EmailAddress = $env:EmailAddress

# Resource group name where blob storage resides
    [string]$STResourceGroupName = $env:STResourceGroupName
    [string]$storageName = $env:storageName

#Keyvault variable
    [string]$KeyVaultName = $env:KeyVaultName
    [string]$CertNameinKeyVault = "LetsEnc-" + $domain.replace("-","").replace(".","-")

#import Module Explicit
Import-module ACME-PS

#Function Random Password
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

[string]$Secret = Generate-RandomPassword 10


### Main

Write-host "Connect to $SubName ..."
Set-AzContext -subscription $SubName



# Create a state object and save it to the harddrive
$tempFolderPath =  "temp/" + $domain
        
#Preparing folder for certificate renewal
# Remove folder used for certificate renewal if existing
if(Test-Path $tempFolderPath -PathType Container)
    {            
        Get-ChildItem -Path $tempFolderPath -Recurse | Remove-Item -force -recurse
        Remove-Item $tempFolderPath -Force -recurse
    }        

Write-host "Creating folder $tempFolderPath ..."
$tempFolder = New-Item -Path $tempFolderPath -ItemType "directory"

Write-host "Begin ACME process to $tempFolder ..."
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

Write-host "Copy Token content to Storage Account to $Storagename ..."
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

Write-host "Create ACME certificate Key in $tempFolder ..."
# We should have a valid order now and should be able to complete it
# Therefore we need a certificate key
$certKey = New-ACMECertificateKey -Path "$tempFolder\$domain.key.xml";

Write-host "Complete ACME Order ..."
# Complete the order - this will issue a certificate singing request
Complete-ACMEOrder $state -Order $order -CertificateKey $certKey;

# Now we wait until the ACME service provides the certificate url
while (-not $order.CertificateUrl) {
    Start-Sleep -Seconds 15
    $order | Update-Order $state -PassThru
}

Write-host "Exporting ACME Certificate ..."
# As soon as the url shows up we can create the PFX
$password = ConvertTo-SecureString -String $Secret -Force -AsPlainText
Export-ACMECertificate $state -Order $order -CertificateKey $certKey -Path "$tempFolder\$domain.pfx" -Password $password;

# Delete blob to check DNS
Write-host "blobname : $blobName  Context = $ctx"
Remove-AzStorageBlob -Container "public" -Context $ctx -Blob $blobName


Write-host "Import Certificate to Keyvault to $KeyVaultName ..."
### Upload new Certificate version to KeyVault
Import-AzKeyVaultCertificate -VaultName $KeyVaultName -Name $CertNameinKeyVault -FilePath "$tempFolder\$domain.pfx" -Password $password

Write-host "KVname :  $KeyVaultName  Certname : $CertNameinKeyVault"
$secret = Get-AzKeyVaultCertificate -VaultName $KeyVaultName -Name $CertNameinKeyVault
Write-host "Secret Name = $($secret.name)"
$secretId = $secret.secretId.Replace($secret.Version, "") # https://<keyvaultname>.vault.azure.net/secrets/
Write-host "Secretid = $secretId"

##Temp Bloc
Write-host "Connect to $AppGwSub ..."
Set-AzContext -subscription $AppGwSub

##Temp 

Write-host "Get Application Gateway and Add certificate $CertNameinKeyVault from Keyvault $KeyVaultName ..."
$AppGw = Get-azapplicationGateway -name $AppgwName

Write-host "appgw name = $($AppGW.name)"
$AppGW = Add-AzApplicationGatewaySslCertificate -ApplicationGateway $AppGW -Name $CertNameinKeyVault -KeyVaultSecretId $secretId
$null = Set-AzApplicationGateway -ApplicationGateway $AppGw 
Write-host "Completed. Check the certificates in Key Vault. there should be the new one named $CertNameinKeyVault"

$Output = "Domain : $domain `nKeyvault : $KeyVaultName `nCertname : $CertNameinKeyVault `nAdd to Appgw : $AppGwName"

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body = $Output
})
