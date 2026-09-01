$selectors = @(
    'MediaPlayback'
    'MicrosoftWindowsPowerShellV2Root'
    'MicrosoftWindowsPowerShellV2'
    'Recall'
    'Microsoft-SnippingTool'
    'WorkFolders-Client'
    'Printing-Foundation-Features'
    'Printing-Foundation-InternetClients'
    'Printing-Foundation-LPDPrintService'
    'Printing-Foundation-LPRngPrintService'
    'SmbDirect'
    'MSRDC-Infrastructure'
    'FaxServicesClientPackage'
    'WCF-TCP-PortSharing45'
    'WCF-HTTP-Activation45'
    'WCF-NonHTTP-Activation'
    'Internet-Explorer-Optional-amd64'
)

$getCommand = {
    Get-WindowsOptionalFeature -Online | Where-Object -Property 'State' -NotIn -Value @(
        'Disabled'
        'DisabledWithPayloadRemoved'
    )
}

$filterCommand = {
    $_.FeatureName -eq $selector
}

$removeCommand = {
    [CmdletBinding()]
    param(
        [Parameter( Mandatory, ValueFromPipeline )]
        $InputObject
    )
    process {
        $InputObject | Disable-WindowsOptionalFeature -Online -Remove -NoRestart -ErrorAction 'Continue'
    }
}

$type = 'Feature'
$installed = & $getCommand;

foreach( $selector in $selectors ) {
    $result = [ordered] @{
        Selector = $selector
    }
    $found = $installed | Where-Object -FilterScript $filterCommand
    if( $found ) {
        $result.Output = $found | & $removeCommand
        if( $? ) {
            $result.Message = "$type removed."
        } else {
            $result.Message = "$type not removed."
            $result.Error = $Error[0]
        }
    } else {
        $result.Message = "$type not installed."
    }
    $result | ConvertTo-Json -Depth 3 -Compress
}
