#Connect to Azure
Connect-AzureRmAccount

# Create Resource Groups and Storage Accounts
  $csv = import-csv AzureStorage.csv 
  $csv | foreach-object {
  $Location = $_.'Location'
  $ResourceGroup = $_.'ResourceGroup'
  $StorageAccountName = $_.'StorageAccount'
  $Redundancy = $_.'Redundancy'

  # Create a Resource Rroup
  New-AzureRmResourceGroup -Name $ResourceGroup `
    -Location $Location

  # Create a new storage account
  $StorageAccount = New-AzureRMStorageAccount `
    -Location $Location `
    -ResourceGroupName $ResourceGroup `
    -SkuName $Redundancy `
    -Name $StorageAccountName

  Set-AzureRmCurrentStorageAccount `
    -StorageAccountName $StorageAccountName `
    -ResourceGroupName $ResourceGroup `

  # Create a storage container to store the virtual machine image
  $containerName = 'osdisks'
  $container = New-AzureStorageContainer `
    -Name $containerName `
    -Permission Blob
  }

# Create Virtual Network
  $csv = import-csv AzureNetwork.csv
  $csv | foreach-object {
  $Location = $_.'Location'
  $ResourceGroup = $_.'ResourceGroup'
  $vnetAddress = $_.'Address'
  $VirtualNetworkName = $_.'VirtualNetwork'

  $virtualNetwork = New-AzureRmVirtualNetwork `
    -ResourceGroupName $ResourceGroup `
    -Location $Location `
    -Name $VirtualNetworkName `
    -AddressPrefix $vnetAddress `
    -Force
  }

 # Create RDP Rule
  $rdpRule = New-AzureRmNetworkSecurityRuleConfig `
    -Name RDP `
    -Description "Allow RDP" `
    -Access Allow `
    -Protocol Tcp `
    -Direction Inbound `
    -Priority 100 `
    -SourceAddressPrefix Internet `
    -SourcePortRange * `
    -DestinationAddressPrefix * `
    -DestinationPortRange 3389

  #Create subnets and NSGs
  $csv = import-csv AzureNetwork.csv
  $csv | foreach-object {
  $VirtualNetworkName = $_.'VirtualNetwork'
  $SubnetName = $_.'Subnet'
  $SubnetAddress = $_.'Network'

  $subnetConfig = Add-AzureRmVirtualNetworkSubnetConfig `
    -Name $SubnetName `
    -AddressPrefix $SubnetAddress `
    -VirtualNetwork $virtualNetwork

  # Create network security groups
  $nsgName = "$SubnetName-nsg"
  $networkSecurityGroup = New-AzureRmNetworkSecurityGroup `
   -ResourceGroupName $ResourceGroup `
   -Location $Location `
   -Name $nsgName `
   -SecurityRules $rdpRule

  # Assign NSGs to Subnets
  Set-AzureRmVirtualNetworkSubnetConfig `
  -Name $SubnetName `
  -VirtualNetwork $virtualNetwork `
  -AddressPrefix $SubnetAddress `
  -NetworkSecurityGroup $networkSecurityGroup
  }

  $virtualNetwork | Set-AzureRmVirtualNetwork

# Create virtual machines

 # Prompt for credentials
  $cred = Get-Credential -Message "Enter a username and password for the virtual machine."

  # Create username and password creds for the virtual machines
  #$UserName='xxx'
  #$Password='xxx'| ConvertTo-SecureString -Force -AsPlainText
  #$Credential=New-Object PSCredential($UserName,$Password)
  
 $csv = import-csv AzureVMS.csv 
  $csv | foreach-object {
  $Location = $_.'Location'
  $ResourceGroup = $_.'ResourceGroup' 
  $VMName = $_.'VMName'
  $VMSize = $_.'VMSize' 
  $VirtualNetworkName = $_.'VirtualNetwork' 
  $Subnet = $_.'Subnet'
  $IPAddress = $_.'IPAddress'
  $PublisherName = $_.'PublisherName'
  $Offer = $_.'Offer'
  $Skus = $_.'Skus'
  $osDiskSAUri = $_.'osDiskSAUri'

  #Create Virtual Network Interface
  $SubnetID = Get-AzureRmVirtualNetwork `
    -Name $VirtualNetworkName `
    -ResourceGroupName $ResourceGroup | `
    Get-AzureRmVirtualNetworkSubnetConfig `
    -Name $Subnet | `
    Select -ExpandProperty Id
  $nic = New-AzureRmNetworkInterface `
    -Name "$VMName-vnic" `
    -ResourceGroupName $ResourceGroup `
    -Location $Location `
    -SubnetID $SubnetID `
    -PrivateIpAddress $IPAddress `
    -PublicIpAddressId $pip.Id `

  # Create the virtual machine configuration object
  $VirtualMachine = New-AzureRmVMConfig `
    -VMName $VMName `
    -VMSize $VMSize

  $VirtualMachine = Set-AzureRmVMOperatingSystem `
    -VM $VirtualMachine `
    -Windows `
    -ComputerName $VMName `
    -Credential $Credential

  $VirtualMachine = Set-AzureRmVMSourceImage `
    -VM $VirtualMachine `
    -PublisherName $PublisherName `
    -Offer $Offer `
    -Skus $Skus `
    -Version "latest"

  # Sets the operating system disk properties
  $VirtualMachine = Set-AzureRmVMOSDisk `
    -VM $VirtualMachine `
    -Name $VMName-osd `
    -VhdUri $osDiskSAUri `
    -CreateOption FromImage | `
    Add-AzureRmVMNetworkInterface -Id $nic.Id

  # Disables creating boot diagnostics drive
    $VirtualMachine = Set-AzureRmVMBootDiagnostics `
      -VM $VirtualMachine -Disable

  # Create the virtual machine
  New-AzureRmVM `
    -ResourceGroupName $ResourceGroup `
    -Location $Location `
    -VM $VirtualMachine
  }
  