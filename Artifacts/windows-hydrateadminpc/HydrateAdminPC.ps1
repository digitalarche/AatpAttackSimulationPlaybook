﻿$ErrorActionPreference = "Stop"

// turn on network discovery
Get-NetFirewallRule -DisplayGroup 'Network Discovery'|Set-NetFirewallRule -Profile 'Private, Domain' `
    -Enabled true -PassThru|select Name,DisplayName,Enabled,Profile

// Add Helpdesk to Local Admin Group
// TODO

// Remove Domain Admins from Local Admin Group
// TODO
