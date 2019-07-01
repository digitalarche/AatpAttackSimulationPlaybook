Configuration CreateADForest
{
	param(
		[Parameter(Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[string]$DomainName='Contoso.Azure',

		[Parameter(Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[string]$NetBiosName='Contoso',

		[Parameter(Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[PSCredential]$AdminCreds,

		[Parameter(Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[string]$UserPrincipalName = "seccxp.ninja",

		[Parameter(Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[PSCredential]$JeffLCreds,

		[Parameter(Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[PSCredential]$SamiraACreds,

		[Parameter(Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[PSCredential]$RonHdCreds,

		[Parameter(Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[PSCredential]$LisaVCreds,

		[Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [PsCredential]$AipServiceCreds,

		[int]$RetryCount=20,
		[int]$RetryIntervalSec=30
	)

	Import-DscResource -ModuleName PSDesiredStateConfiguration, xActiveDirectory, xPendingReboot, `
		xNetworking, xStorage, xDefender, cChoco, ComputerManagementDsc

	$Interface=Get-NetAdapter | Where-Object Name -Like "Ethernet*"|Select-Object -First 1
	$InterfaceAlias=$($Interface.Name)

	[PSCredential]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${NetBiosName}\$($AdminCreds.UserName)", $AdminCreds.Password)
	
	[string]$AadConnectProductId = '6069C45A-B2D7-488C-AEC6-9364D11D4314'

	Node localhost
	{
		LocalConfigurationManager
		{
			RebootNodeIfNeeded = $true
		}

		Service DisableWindowsUpdate
        {
            Name = 'wuauserv'
            State = 'Stopped'
            StartupType = 'Disabled'
        }
		
		WindowsFeature DNS
		{
			Ensure = 'Present'
			Name = 'DNS'
		}
		
		xDnsServerAddress DnsServerAddress 
		{ 
			Address        = '127.0.0.1'
			InterfaceAlias = $InterfaceAlias
			AddressFamily  = 'IPv4'
			DependsOn = "[WindowsFeature]DNS"
		}

		WindowsFeature DnsTools
		{
			Ensure = "Present"
			Name = "RSAT-DNS-Server"
			DependsOn = "[WindowsFeature]DNS"
		}

		WindowsFeature ADDSInstall
		{
			Ensure = 'Present'
			Name = 'AD-Domain-Services'
		}

		WindowsFeature ADDSTools
		{
			Ensure = "Present"
			Name = "RSAT-ADDS-Tools"
			DependsOn = "[WindowsFeature]ADDSInstall"
		}

		WindowsFeature ADAdminCenter
		{
			Ensure = "Present"
			Name = "RSAT-AD-AdminCenter"
			DependsOn = "[WindowsFeature]ADDSInstall"
		}

		xADDomain ContosoDC
		{
			DomainName = $DomainName
			DomainNetbiosName = $NetBiosName
			DomainAdministratorCredential = $DomainCreds
			SafemodeAdministratorPassword = $DomainCreds
			ForestMode = 'Win2012R2'
			DatabasePath = 'C:\Windows\NTDS'
			LogPath = 'C:\Windows\NTDS'
			SysvolPath = 'C:\Windows\SYSVOL'
			DependsOn = '[WindowsFeature]ADDSInstall'
		}
	
		xADForestProperties ForestProps
		{
			ForestName = $DomainName
			UserPrincipalNameSuffixToAdd = $UserPrincipalName
			DependsOn = '[xADDomain]ContosoDC'
		}

		xWaitForADDomain DscForestWait
		{
				DomainName = $DomainName
				DomainUserCredential = $DomainCreds
				RetryCount = $RetryCount
				RetryIntervalSec = $RetryIntervalSec
				DependsOn = "[xADDomain]ContosoDC"
		}

		Registry HideServerManager
        {
            Key = 'HKLM:\SOFTWARE\Microsoft\ServerManager'
            ValueName = 'DoNotOpenServerManagerAtLogon'
            ValueType = 'Dword'
            ValueData = '1'
            Force = $true
            Ensure = 'Present'
			DependsOn = @("[xADForestProperties]ForestProps", "[xWaitForADDomain]DscForestWait")
		}
		        
        Registry HideInitialServerManager
        {
            Key = 'HKLM:\SOFTWARE\Microsoft\ServerManager\Oobe'
            ValueName = 'DoNotOpenInitialConfigurationTasksAtLogon'
            ValueType = 'Dword'
            ValueData = '1'
            Force = $true
            Ensure = 'Present'
			DependsOn = @("[xADForestProperties]ForestProps", "[xWaitForADDomain]DscForestWait")
		}

		cChocoInstaller InstallChoco
        {
			InstallDir = 'C:\choco'
			DependsOn = @('[xADForestProperties]ForestProps', '[xWaitForADDomain]DscForestWait')
        }

        cChocoPackageInstaller InstallSysInternals
        {
            Name = 'sysinternals'
			Ensure = 'Present'
			AutoUpgrade = $false
            DependsOn = '[cChocoInstaller]InstallChoco'
		}
	
        Script DownloadBginfo
        {
            SetScript =
            {
                if ((Test-Path -PathType Container -LiteralPath 'C:\BgInfo\') -ne $true){
					New-Item -Path 'C:\BgInfo\' -ItemType Directory
				}
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $ProgressPreference = 'SilentlyContinue' # used to speed this up from 30s to 100ms
                Invoke-WebRequest -Uri 'https://github.com/ciberesponce/AatpAttackSimulationPlaybook/blob/master/Downloads/BgInfo/contosodc.bgi?raw=true' -Outfile 'C:\BgInfo\BgInfoConfig.bgi'
			}
            GetScript =
            {
                if (Test-Path -LiteralPath 'C:\BgInfo\BgInfo.bgi' -PathType Leaf){
                    return @{
                        result = $true
                    }
                }
                else {
                    return @{
                        result = $false
                    }
                }
            }
            TestScript = 
            {
                if (Test-Path -LiteralPath 'C:\BgInfo\BgInfo.bgi' -PathType Leaf){
                    return $true
                }
                else {
                    return $false
                }
			}
			DependsOn = @('[xADForestProperties]ForestProps', '[xWaitForADDomain]DscForestWait')
		}

		Registry BgInfoRun
		{
			Key = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
			ValueType = 'String'
			ValueName = 'BgInfo'
			ValueData = 'BgInfo64 C:\BgInfo\BgInfoConfig.bgi /accepteula /timer:0'
			DependsOn = '[Script]DownloadBginfo','[cChocoPackageInstaller]InstallSysInternals'
		}

		Script TurnOnNetworkDiscovery
        {
            SetScript = 
            {
                Get-NetFirewallRule -DisplayGroup 'Network Discovery' | Set-NetFirewallRule -Profile 'Domain' -Enabled true
            }
            GetScript = 
            {
                $fwRules = Get-NetFirewallRule -DisplayGroup 'Network Discovery'
                $result = $true
                foreach ($rule in $fwRules){
                    if ($rule.Enabled -eq 'False'){
                        $result = $false
                        break
                    }
                }
                return @{
                    result = $result
                }
            }
            TestScript = 
            {
                $fwRules = Get-NetFirewallRule -DisplayGroup 'Network Discovery'
                $result = $true
                foreach ($rule in $fwRules){
                    if ($rule.Enabled -eq 'False'){
                        $result = $false
                        break
                    }
                }
                return $result
            }
			DependsOn = @("[xADForestProperties]ForestProps", "[xWaitForADDomain]DscForestWait")
        }
        

		Script DownloadAadMsi
		{
			SetScript = 
            {
				if ((Test-Path -PathType Container -LiteralPath 'C:\LabTools\') -ne $true){
					New-Item -Path 'C:\LabTools\' -ItemType Directory
				}
				[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Start-BitsTransfer -Source 'https://github.com/ciberesponce/AatpAttackSimulationPlaybook/blob/master/Downloads/AzureADConnect.msi?raw=true' -Destination 'C:\LabTools\aadconnect.msi'
            }
			GetScript = 
            {
				if (Test-Path -LiteralPath 'C:\LabTools\aadconnect.msi'){
					return @{
						result = $true
					}
				}
				else {
					return @{
						result = $false
					}
				}
            }
            TestScript = 
            {
				if (Test-Path -LiteralPath 'C:\LabTools\aadconnect.msi'){
					return $true
				}
				else {
					return $false
				}
			}
			DependsOn = @("[xADForestProperties]ForestProps", "[xWaitForADDomain]DscForestWait")
		}

		Package InstallAadConnect
		{
			Name = 'Microsoft Azure AD Connect'
			ProductId = $AadConnectProductId
			Ensure = 'Present'
			Path = 'C:\LabTools\aadconnect.msi'
			Arguments = '/quiet'
			DependsOn = @("[Script]DownloadAadMsi","[xADForestProperties]ForestProps","[xWaitForADDomain]DscForestWait")
		}

		xADUser SamiraA
		{
			DomainName = $DomainName
			UserName = 'SamiraA'
			Password = $SamiraACreds
			Ensure = 'Present'
			GivenName = 'Samira'
			Surname = 'A'
			PasswordNeverExpires = $true
			DependsOn = @("[xADForestProperties]ForestProps", "[xWaitForADDomain]DscForestWait")
		}

		xADUser AipService
		{
			DomainName = $DomainName
			UserName = $AipServiceCreds.UserName
			Password = $AipServiceCreds
			Ensure = 'Present'
			GivenName = 'AipService'
			Surname = 'Account'
			PasswordNeverExpires = $true
			DependsOn = @("[xADForestProperties]ForestProps", "[xWaitForADDomain]DscForestWait")
		}

		xADUser RonHD
		{
			DomainName = $DomainName
			UserName = 'RonHD'
			Password = $RonHdCreds
			Ensure = 'Present'
			GivenName = 'Ron'
			Surname = 'HD'
			PasswordNeverExpires = $true
			DisplayName = 'RonHD'
			DependsOn = @("[xADForestProperties]ForestProps", "[xWaitForADDomain]DscForestWait")
		}

		xADUser JeffL
		{
			DomainName = $DomainName
			UserName = 'JeffL'
			GivenName = 'Jeff'
			Surname = 'Leatherman'
			Password = $JeffLCreds
			Ensure = 'Present'
			PasswordNeverExpires = $true
			DisplayName = 'JeffL'
			DependsOn = @("[xADForestProperties]ForestProps", "[xWaitForADDomain]DscForestWait")
		}

		xADUser LisaV
		{
			DomainName = $DomainName
			UserName = 'LisaV'
			GivenName = 'Lisa'
			Surname = 'Valentine'
			Password =  $LisaVCreds
			Ensure = 'Present'
			PasswordNeverExpires = $true
			DependsOn = @("[xADForestProperties]ForestProps", "[xWaitForADDomain]DscForestWait")
		}

		xADGroup DomainAdmins
		{
			GroupName = 'Domain Admins'
			Category = 'Security'
			GroupScope = 'Global'
			MembershipAttribute = 'SamAccountName'
			MembersToInclude = "SamiraA"
			Ensure = 'Present'
			DependsOn = @("[xADUser]SamiraA", "[xWaitForADDomain]DscForestWait")
		}

		xADGroup Helpdesk
		{
			GroupName = 'Helpdesk'
			Category = 'Security'
			GroupScope = 'Global'
			Description = 'Tier-2 (desktop) Helpdesk for this domain'
			DisplayName = 'Helpdesk'
			MembershipAttribute = 'SamAccountName'
			MembersToInclude = "RonHD"
			Ensure = 'Present'
			DependsOn = @("[xADUser]RonHD","[xWaitForADDomain]DscForestWait")
		}

		xMpPreference DefenderSettings
		{
			Name = 'DefenderProperties'
			DisableRealtimeMonitoring = $true
			ExclusionPath = 'c:\Temp'
		}
	} #end of node
} #end of configuration