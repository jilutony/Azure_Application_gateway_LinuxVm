#basic
resource "azurerm_resource_group" "rg1" {
  name     = "myResourceGroupAG"
  location = "eastus"
}

resource "azurerm_virtual_network" "vnet1" {
  name                = "myVNet"
  resource_group_name = azurerm_resource_group.rg1.name
  location            = azurerm_resource_group.rg1.location
  address_space       = ["10.21.0.0/16"]
}

resource "azurerm_subnet" "frontend" {
  name                 = "myAGSubnet"
  resource_group_name  = azurerm_resource_group.rg1.name
  virtual_network_name = azurerm_virtual_network.vnet1.name
  address_prefixes     = ["10.21.0.0/24"]
}

resource "azurerm_subnet" "backend" {
  name                 = "myBackendSubnet"
  resource_group_name  = azurerm_resource_group.rg1.name
  virtual_network_name = azurerm_virtual_network.vnet1.name
  address_prefixes     = ["10.21.1.0/24"]
}

resource "azurerm_public_ip" "pip1" {
  name                = "myAGPublicIPAddress"
  resource_group_name = azurerm_resource_group.rg1.name
  location            = azurerm_resource_group.rg1.location
  allocation_method   = "Static"
  sku                 = "Standard"
}



resource "azurerm_application_gateway" "network" {
  name                = "myAppGateway"
  resource_group_name = azurerm_resource_group.rg1.name
  location            = azurerm_resource_group.rg1.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "my-gateway-ip-configuration"
    subnet_id = azurerm_subnet.frontend.id
  }

  frontend_port {
    name = var.frontend_port_name
    port = 80
  }

  frontend_ip_configuration {
    name                 = var.frontend_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.pip1.id
  }

  backend_address_pool {
    name = var.backend_address_pool_name
  }

  backend_http_settings {
    name                  = var.http_setting_name
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = var.listener_name
    frontend_ip_configuration_name = var.frontend_ip_configuration_name
    frontend_port_name             = var.frontend_port_name
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = var.request_routing_rule_name
    rule_type                  = "Basic"
    priority                   = 10
    http_listener_name         = var.listener_name
    backend_address_pool_name  = var.backend_address_pool_name
    backend_http_settings_name = var.http_setting_name
  }
}

resource "azurerm_network_interface" "nic" {
  count = 2
  name                = "nic-${count.index+1}"
  location            = azurerm_resource_group.rg1.location
  resource_group_name = azurerm_resource_group.rg1.name

  ip_configuration {
    name                          = "nic-ipconfig-${count.index+1}"
    subnet_id                     = azurerm_subnet.backend.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_application_gateway_backend_address_pool_association" "nic-assoc01" {
  count = 2
  network_interface_id    = azurerm_network_interface.nic[count.index].id
  ip_configuration_name   = "nic-ipconfig-${count.index+1}"
  backend_address_pool_id = tolist(azurerm_application_gateway.network.backend_address_pool).0.id
}

resource "random_password" "password" {
  length = 16
  special = true
  lower = true
  upper = true
  number = true
}
# Create virtual machine
resource "azurerm_linux_virtual_machine" "my_terraform_vm" {
  count = 2
  name                  = "Jilu${count.index+1}"
  location              = azurerm_resource_group.rg1.location
  resource_group_name   = azurerm_resource_group.rg1.name
  size                  = "Standard_DS1_v2"
  admin_username      = "azureadmin"
  admin_password      = random_password.password.result
  disable_password_authentication = false


  network_interface_ids = [
    azurerm_network_interface.nic[count.index].id,
  ]

  os_disk {
    name                 = "myOsDisk${count.index+1}"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

 
  boot_diagnostics {
    storage_account_uri = null
  }
}

resource "azurerm_virtual_machine_extension" "vm-extensions" {
  count = 2
  name                 = "Jilunew${count.index+1}-ext"
  virtual_machine_id   = azurerm_linux_virtual_machine.my_terraform_vm[count.index].id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.0"

  settings = <<SETTINGS
 {
  "commandToExecute": "sudo apt update && sudo apt install nginx -y"
 }
SETTINGS


  tags = {
    environment = "Production"
  }
}

