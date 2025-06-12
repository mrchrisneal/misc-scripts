#!/bin/bash
##############################################
###### MSI GS65 LAPTOP PREP SCRIPT v1.3 ######
######  For Kubuntu (and derivatives?)  ######
##############################################

## IMPORTANT NOTE (June 11th, 2025):
## As of writing, this script has not been updated in over two years, and will not be updated in the future. 
## I no longer use Kubuntu myself, but I will keep this script here in case someone else finds it useful.
## Thank you for understanding!

## Q: What is this script for?
## A: Setting up Kubuntu (and derivatives?) for use with my MSI GS65 laptop.

## Q: Is it a good script?
## A: Probably not, and you shouldn't run it.

## Q: What does it do?
## 1) Enables Fn Key Combos (for Airplane Mode). This is needed to reenable wireless radios after resuming 
##    from sleep (because apparently it's impossible unless it is rebooted entirely). Modifies GRUB.
## 2) Enables write support to ec_sys for fan control functions. Modifies GRUB.
## 3) Updates the GRUB config so the previous changes will be loaded after rebooting.
## 4) Enables the ec_sys module (if necessary).
## 5) Updates and upgrades installed packages.
## 6) Updates drivers using the Ubuntu drivers tool.
## 7) Installs some applications.
## 8) Runs the Tailscale install script. Don't forget to set it up after you're done!
## 9) Some note-to-self reminders. ;)


echo " "
echo "MSI GS65 LAPTOP PREP SCRIPT v1.3"
echo " "
if [[ $(/usr/bin/id -u) -ne 0 ]]; then
    echo "Script must be run as ROOT, exiting... <3"
    exit
fi
echo "Starting pre-check in 5 seconds..."
sleep 5

#####################################
######### START PRE-CHECK: ##########
#####################################

echo " "
echo "-------------------------------------------------------------------------"
echo " "
echo PRE-CHECK: Running rmmod ec_sys...
echo " "
rmmod ec_sys
echo " "
result=$(rmmod ec_sys 2>&1 | grep "not currently loaded")
if [[ "$result" == "rmmod: ERROR: Module ec_sys is not currently loaded" ]]; then
    echo "PASSED! Continuing..."
else
	echo "^ UNEXPECTED OUTPUT, PLEASE REVIEW BEFORE CONTINUING."
	echo " "
    sleep 365d
fi
echo " "
echo "-------------------------------------------------------------------------"
echo " "
read -p "Press any key to resume, or use ALT+C to exit this script."
echo " "

#####################################
######## START MAIN SCRIPT: #########
#####################################

echo STARTING MAIN SCRIPT:
echo "-------------------------------------------------------------------------"
echo "STEP 0: Fix incorrect system time when dual booting Windows"
timedatectl set-local-rtc 1
echo "-------------------------------------------------------------------------"
echo "STEP 1: Enable Fn Key Combos (for Airplane Mode)"
sed -i '/GRUB_CMDLINE_LINUX_DEFAULT=/c\GRUB_CMDLINE_LINUX_DEFAULT="acpi_osi=! acpi_osi=\x27Windows 2009\x27 quiet splash"' /etc/default/grub
echo "-------------------------------------------------------------------------"
echo "STEP 2: Enable write support to ec_sys" ## For fan control functions -- currently unused
sed -i '/GRUB_CMDLINE_LINUX=/c\GRUB_CMDLINE_LINUX="ec_sys.write_support=1"' /etc/default/grub
echo "-------------------------------------------------------------------------"
echo "STEP 3: Update grub config"
update-grub
echo "-------------------------------------------------------------------------"
echo "STEP 4: Load the ec_sys module when Kubuntu starts"
if grep -Rq "ec_sys" "/etc/modules"
    then
        echo "ec_sys already added to /etc/modules"
    else
        echo "Adding to /etc/modules..."
        sed -i '$a ec_sys' /etc/modules
fi
echo "-------------------------------------------------------------------------"
echo "STEP 5: Update and upgrade packages"
apt update && apt upgrade -y
echo "-------------------------------------------------------------------------"
echo "STEP 6: Run Ubuntu driver installer (usually just GPU drivers)"
ubuntu-drivers install
echo "-------------------------------------------------------------------------"
echo "STEP 7A: Install packages (Blender, Steam, OBS, etc...)" ## Add/remove desired packages here
apt install k4dirstat blender steam-installer obs-studio timeshift filelight htop handbrake youtube-dl youtubedl-gui stress-ng -y
echo "-------------------------------------------------------------------------"
echo "STEP 7B: Install Snap packages (Discord, nvtop, Chromium, Gnome Logs, VSCode)" ## Add/remove desired snaps here
snap install discord && snap install nvtop && snap install chromium && snap install gnome-logs 
snap install code && snap install code --classic ## It's a "classic" snap package, wowzers
echo "-------------------------------------------------------------------------"
echo "STEP 7C: Install Docker from official repository (via https://docs.docker.com/engine/install/ubuntu/)"
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh ./get-docker.sh
apt update && apt upgrade -y
echo "NOTE: CONFIRM DOCKER IS INSTALLED BY RUNNING: docker run hello-world"
echo "-------------------------------------------------------------------------"
echo "STEP 8: Run Tailscale setup"
curl -fsSL https://tailscale.com/install.sh | sh
echo "-------------------------------------------------------------------------"

echo "STEP 9: Reminders"
echo "(!) Don't forget to log in to Tailscale, Discord, Firefox, Google, Steam, etc."
echo " "
echo "These are nice to have... ;)"
echo "  - BeautyLine (icon pack)"
echo "  - QuarksSplashDark (splash screen)"
echo "-------------------------------------------------------------------------"
echo "GS-65 PREP SCRIPT DONE!"
