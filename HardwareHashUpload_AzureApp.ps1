<#
.SYNOPSIS
    Gathers device info, prompts for a Group Tag, and sends the data 
    to the secure Autopilot Registration Service.
.PARAMETER TechnicianEmail
    The email of the technician running the script for logging purposes.
#>
param (
    [Parameter(Mandatory = $true)]
    [string]$TechnicianEmail
)

# --- CONFIGURATION ---
$functionUrl = "https://fa-intunedeviceauto.azurewebsites.net/api/RegisterDevice" # <-- PASTE YOUR FUNCTION URL HERE (without the code part)
$functionApiKey = "gVcy7hy90cLNwnQarLU6PGAqYUv2af0MHIrc1ksPCXZyAzFu4zj_Gg==" # <-- PASTE YOUR KEY HERE

Write-Host "Starting Autopilot registration..." -ForegroundColor Cyan

# --- 1. Prompt user to select a Group Tag from a menu ---
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
        default {
            Write-Host "Invalid selection. Please enter a number from 1 to 3." -ForegroundColor Red
        }
    }
} while ([string]::IsNullOrWhiteSpace($groupTag))

Write-Host "Profile selected: '$groupTag'" -ForegroundColor Green

try {
    # --- 2. Gather Local Device Info ---
    Write-Host "`nGathering device hardware information..." -ForegroundColor Yellow
    $SerialNumber = (Get-WmiObject -Class Win32_BIOS).SerialNumber
    $HardwareHash = (Get-WmiObject -Namespace root/cimv2/mdm/dmmap -Class MDM_DevDetail_Ext01 -Filter "InstanceID='Ext' AND ParentID='./DevDetail'").DeviceHardwareData

    if ([string]::IsNullOrEmpty($HardwareHash)) {
        throw "FATAL: Could not retrieve the device hardware hash."
    }
    Write-Host "  - Serial Number: $SerialNumber" -ForegroundColor Green
    Write-Host "  - Hardware Hash successfully retrieved." -ForegroundColor Green

    # --- 3. Send Data to the Azure Function ---
    Write-Host "`nSending data to the registration service..." -ForegroundColor Yellow
    
    $payload = @{
        SerialNumber    = $SerialNumber
        HardwareHash    = $HardwareHash
        GroupTag        = $groupTag
        TechnicianEmail = $TechnicianEmail
    } | ConvertTo-Json

    $headers = @{
        "Content-Type"    = "application/json"
        "x-functions-key" = $functionApiKey
    }

    $response = Invoke-RestMethod -Uri $functionUrl -Method POST -Body $payload -Headers $headers
    
    Write-Host "`nSUCCESS: Service responded: '$response'" -ForegroundColor Green

    # --- 4. Initiate System Reset ---
    Write-Host "`nRegistration complete. The device must be reset to apply the Autopilot profile." -ForegroundColor Yellow
    $resetConfirmation = Read-Host "WARNING: This will erase all data and reset Windows. Proceed with reset? (Y/N)"
    if ($resetConfirmation -eq 'Y' -or $resetConfirmation -eq 'y') {
        Write-Host "Initiating system reset..." -ForegroundColor Red
        Start-Process "systemreset" -ArgumentList "-factoryreset" -Wait
    } else {
        Write-Host "Reset cancelled. Please manually reset the device to complete the Autopilot process." -ForegroundColor Yellow
    }

} catch {
    Write-Host "`nAN ERROR OCCURRED:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
