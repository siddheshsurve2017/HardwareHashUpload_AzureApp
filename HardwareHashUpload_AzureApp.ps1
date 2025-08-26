<#
.SYNOPSIS
    Authenticates the technician using the Device Code Flow, gathers device info, 
    and sends it to the secure Autopilot Registration Service for processing.
#>

# --- CONFIGURATION ---
# You can find these IDs in your Entra ID App Registration overview page.
$clientId = "6b1311e5-123f-49db-acdf-8847c2d00bed"
$tenantId = "3c55a97a-ded8-475c-ad84-cd9db6955762"

# This is the URL of your Azure Function.
$functionUrl = "https://fa-intunedeviceauto.azurewebsites.net/api/RegisterDevice"

# --- SCRIPT START ---

# 1. Ensure MSAL.PS module is available
if (-not (Get-Module -ListAvailable -Name MSAL.PS)) {
    Write-Host "MSAL.PS module not found. Attempting to install..." -ForegroundColor Yellow
    try {
        Install-Module MSAL.PS -Scope CurrentUser -Force -AllowClobber
    } catch {
        Write-Host "Failed to install MSAL.PS module. Please install it manually and try again." -ForegroundColor Red
        exit 1
    }
}

# 2. Authenticate the user via Device Code Flow
Write-Host "Authenticating user..." -ForegroundColor Cyan
$scopes = "https://graph.microsoft.com/DeviceManagementServiceConfig.ReadWrite.All"
try {
    # This command will automatically display the code and URL to the user and wait for them to sign in.
    $authResult = Get-MsalToken -ClientId $clientId -TenantId $tenantId -DeviceCode -Scope $scopes
    Write-Host "Authentication successful for $($authResult.Account.Username)" -ForegroundColor Green
} catch {
    Write-Host "Authentication failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# 3. Prompt user to select a Group Tag from a menu
$groupTag = ""
do {
    Write-Host "`nPlease select the profile for this device:" -ForegroundColor Yellow
    Write-Host "  [1] Standard User (CORP)"
    Write-Host "  [2] Executive User (EO)"
    Write-Host "  [3] Kiosk Device (KSK)"
    $selection = Read-Host -Prompt "Enter your choice (1-3)"
    switch ($selection) {
        '1' { $groupTag = "CORP" }
        '2' { $groupTag = "EO" }
        '3' { $groupTag = "KSK" }
        default { Write-Host "Invalid selection." -ForegroundColor Red }
    }
} while ([string]::IsNullOrWhiteSpace($groupTag))

Write-Host "Profile selected: '$groupTag'" -ForegroundColor Green

try {
    # 4. Gather Local Device Info
    Write-Host "`nGathering device hardware information..." -ForegroundColor Yellow
    $SerialNumber = (Get-WmiObject -Class Win32_BIOS).SerialNumber
    $HardwareHash = (Get-WmiObject -Namespace root/cimv2/mdm/dmmap -Class MDM_DevDetail_Ext01 -Filter "InstanceID='Ext' AND ParentID='./DevDetail'").DeviceHardwareData
    if ([string]::IsNullOrEmpty($HardwareHash)) { throw "FATAL: Could not retrieve the device hardware hash." }

    # 5. Send Data to the Azure Function
    Write-Host "`nSending data to the registration service..." -ForegroundColor Yellow
    $headers = @{
        "Authorization" = "Bearer $($authResult.AccessToken)"
        "Content-Type"  = "application/json"
    }
    $payload = @{
        SerialNumber    = $SerialNumber
        HardwareHash    = $HardwareHash
        GroupTag        = $groupTag
    } | ConvertTo-Json
    
    $response = Invoke-RestMethod -Uri $functionUrl -Method POST -Body $payload -Headers $headers
    Write-Host "`nSUCCESS: Service responded: '$response'" -ForegroundColor Green

    # 6. Initiate System Reset
    $reset = Read-Host "`nRegistration complete. The device must be reset. Proceed? (Y/N)"
    if ($reset -eq 'Y' -or $reset -eq 'y') {
        Start-Process "systemreset" -ArgumentList "-factoryreset" -Wait
    }

} catch {
    Write-Host "`nAN ERROR OCCURRED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
