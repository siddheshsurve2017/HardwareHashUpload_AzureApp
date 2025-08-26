<#
.SYNOPSIS
    Authenticates the technician using the Device Code Flow, gathers device info, 
    and sends it to the secure Autopilot Registration Service for processing.
#>

# --- CONFIGURATION ---
# You can find these IDs in your Entra ID App Registration overview page.
$clientId = "3c55a97a-ded8-475c-ad84-cd9db6955762"
$tenantId = "6b1311e5-123f-49db-acdf-8847c2d00bed"

# This is the URL of your Azure Function.
$functionUrl = "https://fa-intunedeviceauto.azurewebsites.net/api/RegisterDevice"

# --- SCRIPT START ---

# 1. Ensure MSAL.PS module is available with a robust installation strategy.
if (-not (Get-Module -ListAvailable -Name MSAL.PS)) {
    Write-Host "MSAL.PS module not found. Attempting to install..." -ForegroundColor Yellow
    try {
        # First, try to get the latest version from the gallery.
        Install-Module MSAL.PS -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        Write-Host "Successfully installed the latest version of MSAL.PS." -ForegroundColor Green
    } catch {
        Write-Host "Failed to install the latest version of MSAL.PS from the PowerShell Gallery." -ForegroundColor Yellow
        Write-Host "Attempting to install a known-stable older version as a fallback..." -ForegroundColor Yellow
        try {
            # If the latest fails, try an older, reliable version.
            Install-Module MSAL.PS -RequiredVersion 4.36.1.0 -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            Write-Host "Successfully installed a fallback version of MSAL.PS." -ForegroundColor Green
        } catch {
            Write-Host "FATAL: All attempts to install the MSAL.PS module have failed." -ForegroundColor Red
            Write-Host "Please check your internet connection or install the module manually and try again." -ForegroundColor Red
            exit 1
        }
    }
} else {
    # If the module is already present, try to update it.
    Write-Host "MSAL.PS module is already installed. Attempting to update..." -ForegroundColor Yellow
    try {
        Install-Module MSAL.PS -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        Write-Host "MSAL.PS is now up to date." -ForegroundColor Green
    } catch {
        Write-Host "Could not update MSAL.PS. Proceeding with the currently installed version." -ForegroundColor Yellow
    }
}


# 2. Authenticate the user via Device Code Flow
Write-Host "Authenticating user..." -ForegroundColor Cyan
$scopes = "https://graph.microsoft.com/DeviceManagementServiceConfig.ReadWrite.All", "https://graph.microsoft.com/GroupMember.Read.All"
try {
    # Check MSAL.PS version to determine if the custom callback is supported
    $msalModule = Get-Module -Name MSAL.PS
    $requiredVersion = [System.Version]"4.29.0.0" # Version when -DeviceCodeCallback was introduced

    if ($msalModule.Version -ge $requiredVersion) {
        # Use the enhanced callback for modern versions
        $authResult = Get-MsalToken -ClientId $clientId -TenantId $tenantId -DeviceCode -Scope $scopes -DeviceCodeCallback {
            param($deviceCode)
            Write-Host " "
            Write-Host "========================================================================" -ForegroundColor Cyan
            Write-Host "            >>> TECHNICIAN AUTHENTICATION REQUIRED <<<" -ForegroundColor White
            Write-Host "========================================================================" -ForegroundColor Cyan
            Write-Host " "
            Write-Host "   Please use another device (like your phone) to complete the login." -ForegroundColor Yellow
            Write-Host " "
            Write-Host "   Open a web browser and go to:" -ForegroundColor Yellow
            Write-Host "      -> $($deviceCode.VerificationUri)" -ForegroundColor White
            Write-Host " "
            Write-Host "   And enter this code:" -ForegroundColor Yellow
            Write-Host "      -> $($deviceCode.UserCode)" -ForegroundColor White
            Write-Host " "
            Write-Host "========================================================================" -ForegroundColor Cyan
            Write-Host "`nWaiting for you to complete the sign-in process..." -ForegroundColor Yellow
        }
    } else {
        # Fallback to default behavior for older versions
        Write-Host "Older MSAL.PS version detected. Using default authentication prompt." -ForegroundColor Yellow
        $authResult = Get-MsalToken -ClientId $clientId -TenantId $tenantId -DeviceCode -Scope $scopes
    }
    
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

    # --- 6. Initiate System Reset with Detailed Instructions ---
    Write-Host "`nRegistration is complete. The device must now be reset to apply the Autopilot profile."
    $resetConfirmation = Read-Host "Press 'Y' to open the Windows Reset tool. (Y/N)"
    
    if ($resetConfirmation -eq 'Y' -or $resetConfirmation -eq 'y') {
        try {
            # Provide clear, step-by-step instructions for the user to follow in the GUI
            Write-Host " "
            Write-Host "========================================================================" -ForegroundColor Cyan
            Write-Host "            >>> ACTION REQUIRED: FOLLOW THESE STEPS <<<" -ForegroundColor White
            Write-Host "========================================================================" -ForegroundColor Cyan
            Write-Host " "
            Write-Host "   In the 'Reset this PC' window that will open shortly:" -ForegroundColor Yellow
            Write-Host " "
            Write-Host "   1. On the 'Choose an option' screen, select:" -ForegroundColor Yellow
            Write-Host "      -> [Remove everything]" -ForegroundColor White
            Write-Host " "
            Write-Host "   2. On the next screen, select:" -ForegroundColor Yellow
            Write-Host "      -> [Just remove my files]" -ForegroundColor White
            Write-Host " "
            Write-Host "   3. On the final 'Ready to reset this PC' screen, click:" -ForegroundColor Yellow
            Write-Host "      -> [Reset]" -ForegroundColor White
            Write-Host " "
            Write-Host "========================================================================" -ForegroundColor Cyan
            
            # Add a delay for the technician to read the instructions
            Write-Host "`nOpening the reset window in 20 seconds. Please review the steps above." -ForegroundColor Yellow
            Start-Sleep -Seconds 20

            # Attempt to launch the system reset tool
            Start-Process "systemreset" -ArgumentList "-factoryreset" -ErrorAction Stop
            
        } catch {
            # Error handling if systemreset.exe is not found or fails to start
            Write-Host "`nERROR: Could not automatically start the reset tool." -ForegroundColor Red
            Write-Host "Please reset the device manually:" -ForegroundColor Yellow
            Write-Host "  1. Go to Settings > Update & Security > Recovery."
            Write-Host "  2. Under 'Reset this PC', click 'Get started'."
            Write-Host "  3. Follow the on-screen instructions, choosing to 'Remove everything'."
        }
    } else {
        Write-Host "Reset cancelled. Please manually reset the device to complete the Autopilot process." -ForegroundColor Yellow
    }

} catch {
    Write-Host "`nAN ERROR OCCURRED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
