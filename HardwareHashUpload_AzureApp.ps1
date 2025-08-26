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

# --- 1. Prompt for Group Tag ---
$groupTag = ""
do {
    $groupTag = Read-Host -Prompt "Please enter the Autopilot Group Tag for this device"
    if ([string]::IsNullOrWhiteSpace($groupTag)) {
        Write-Host "Group Tag cannot be empty. Please try again." -ForegroundColor Red
    }
} while ([string]::IsNullOrWhiteSpace($groupTag))

Write-Host "Using Group Tag: '$groupTag'" -ForegroundColor Green

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

    # --- 4. Prompt for Restart ---
    $restart = Read-Host "`nRegistration complete. A restart is required. Restart now? (Y/N)"
    if ($restart -eq 'Y' -or $restart -eq 'y') {
        Restart-Computer -Force
    }

} catch {
    Write-Host "`nAN ERROR OCCURRED:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
