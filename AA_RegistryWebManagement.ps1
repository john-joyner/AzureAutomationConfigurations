
##############################################################################################
#
# RegistryWebManagement config by John Joyner 04/17/2018 - v0.8.03
# Modified for Azure Automation 11/10/2019 - v.1.0.7
#
# (Windows) Enables and starts remote administration of a local IIS instance.
#
##############################################################################################

Configuration AA_RegistryWebManagement
 
{

Import-DscResource -ModuleName PSDesiredStateConfiguration

        WindowsFeature WebMgmtService {
            Name   = "Web-Mgmt-Service" 
            Ensure = "Present"
        }        

	Registry RegistryWebManagement {
            Ensure    = "Present"
            Key       = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\WebManagement\Server"
            ValueName = "EnableRemoteManagement"
            ValueData = "1"
            ValueType = "Dword"
            Dependson = '[WindowsFeature]WebMgmtService'
        }

        Registry RegistryWMSVCAutoStart {
            Ensure    = "Present"
            Key       = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\WMSVC"
            ValueName = "Start"
            ValueData = "2"
            ValueType = "Dword"
            Dependson = '[Registry]RegistryWebManagement'
        }

	Service WMSvc {
     		Name = "WMSvc"
		StartupType = "Manual"
     		State = "Running"
	}

}
