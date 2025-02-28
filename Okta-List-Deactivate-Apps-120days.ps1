# Set Okta API Credentials
$OktaDomain = "XYZ.okta.com"   # Example: yourcompany.okta.com
$ApiToken = "Your_OKTA_API_TOKEN"

# Headers for API Authentication
$headers = @{
    "Authorization" = "SSWS $ApiToken"
    "Accept" = "application/json"
    "Content-Type" = "application/json"
}

# Get the date 120 days ago in ISO format
$SinceDate = (Get-Date).AddDays(-120).ToString("yyyy-MM-ddTHH:mm:ssZ")

# Step 1: Retrieve all active applications from Okta
$appsUrl = "https://$OktaDomain/api/v1/apps"
$appsResponse = Invoke-RestMethod -Uri $appsUrl -Headers $headers -Method Get
$allApps = $appsResponse | Where-Object { $_.status -eq "ACTIVE" }

# Step 2: Get authentication logs for the last 120 days
$logsUrl = "https://$OktaDomain/api/v1/logs?since=$SinceDate&limit=1000"
$logsResponse = @()
$nextUrl = $logsUrl

do {
    $response = Invoke-RestMethod -Uri $nextUrl -Headers $headers -Method Get
    $logsResponse += $response

    # Check if there is a next page
    $nextLink = ($response | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -eq "next" })
    if ($nextLink) {
        $nextUrl = $nextLink.Value
    } else {
        $nextUrl = $null
    }
} while ($nextUrl)

# Extract App IDs from login logs
$usedAppIds = $logsResponse | ForEach-Object {
    $_.target | Where-Object { $_.type -eq "AppInstance" } | Select-Object -ExpandProperty id -Unique
}

# Step 3: Identify unused apps
$unusedApps = $allApps | Where-Object { $_.id -notin $usedAppIds }

# Step 4: Deactivate Unused Apps
if ($unusedApps.Count -eq 0) {
    Write-Host "No unused applications found in the last 120 days."
} else {
    Write-Host "Deactivating unused applications:"
    $unusedApps | ForEach-Object {
        Write-Host "Deactivating: $($_.label) (App ID: $($_.id))"

        # Okta API call to deactivate the app
        $deactivateUrl = "https://$OktaDomain/api/v1/apps/$($_.id)/lifecycle/deactivate"
        try {
            Invoke-RestMethod -Uri $deactivateUrl -Headers $headers -Method Post
            Write-Host "Successfully deactivated: $($_.label)"
        } catch {
            Write-Host "❌ Failed to deactivate: $($_.label). Error: $_"
        }
    }

    # Export unused apps list to CSV before deactivation (for reference)
    $unusedApps | Select-Object label, id | Export-Csv -Path "Unused_Okta_Apps.csv" -NoTypeInformation
    Write-Host "Report saved as Unused_Okta_Apps.csv"
}
