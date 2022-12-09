#!/bin/bash
##############################################
###### MSI GS65 LAPTOP PREP SCRIPT v1.0 ######
######  For Kubuntu (and derivatives?)  ######
##############################################

## Q: What is this script for?
## A: Setting up Kubuntu (and derivatives?) for use with my MSI GS65 laptop.

## Q: Is it a good script?
## A: Probably not, and you shouldn't run it.

## Q: What does it do?
## 1) Enables Fn Key Combos (for Airplane Mode). This is needed to reenable wireless radios after resuming from sleep (because apparently it's impossible unless it is rebooted entirely). Modifies GRUB.
## 2) Enables write support to ec_sys for fan control functions. Modifies GRUB.
## 3) Updates the GRUB config so the previous changes will be loaded after rebooting.
## 4) Enables the ec_sys module (if necessary).
## 5) Updates and upgrades installed packages.
## 6) Updates drivers using the Ubuntu drivers tool.

echo " "
echo "MSI GS65 LAPTOP PREP SCRIPT v1.1"
echo " "
echo "IMPORTANT: RUN AS ROOT!"
echo " "
echo "Starting pre-check in 5 seconds..."
sleep 5

#####################################
######### START PRE-CHECK: ##########
#####################################

echo " "
echo "-------------------------------------------------------------------------"
echo PRE-CHECK: Running sudo rmmod ec_sys...
echo " "
sudo rmmod ec_sys
echo " "
echo 'Above output should show "ERROR: Module ec_sys is not currently loaded."'
echo "If not, please exit the script now and run Steps 1 and 3 manually."
echo "-------------------------------------------------------------------------"
echo " "
read -p "Press any key to resume, or use ALT+C to exit this script."
echo " "

#####################################
######## START MAIN SCRIPT: #########
#####################################

echo STARTING MAIN SCRIPT:
echo "-------------------------------------------------------------------------"
echo "STEP 1: Enable Fn Key Combos (for Airplane Mode)"
sed -i '/GRUB_CMDLINE_LINUX_DEFAULT=/c\GRUB_CMDLINE_LINUX_DEFAULT="acpi_osi=! acpi_osi=\x27Windows 2009\x27 quiet splash"' /etc/default/grub
echo "-------------------------------------------------------------------------"
echo "STEP 2: Enable write support to ec_sys" ## For fan control functions
sed -i '/GRUB_CMDLINE_LINUX=/c\GRUB_CMDLINE_LINUX="ec_sys.write_support=1"' /etc/default/grub
echo "-------------------------------------------------------------------------"
echo "STEP 3: Update grub config"
sudo update-grub
echo "-------------------------------------------------------------------------"
echo "STEP 4: Load the ec_sys module when Kubuntu starts"
if grep -Rq "ec_sys" "/etc/modules"
    then
        echo "ec_sys already added to /etc/modules"
    else
        echo "Adding to /etc/modules..."
        sudo sed -i '$a ec_sys' /etc/modules
fi
echo "-------------------------------------------------------------------------"
echo "STEP 5: Update and upgrade packages"
sudo apt update && sudo apt upgrade -y
echo "-------------------------------------------------------------------------"
echo "STEP 6: Run Ubuntu driver installer (usually just GPU drivers)"
ubuntu-drivers install
echo "-------------------------------------------------------------------------"
echo "GS-65 PREP SCRIPT DONE!"
