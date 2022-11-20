# ARC Redpill Loader

# Important

## It is highly recommended to use an SSD for the loader in the case of the option via DoM or a fast USB flash drive

## You must have at least 4GB of RAM, both in baremetal and VMs

## The DSM kernel is compatible with SATA ports, not SAS/SCSI/etc. For device-tree models only SATA ports work. For the other models, another type of disks may work.

# Use

To use this project, download the latest image available and burn it to a USB stick or SATA disk-on-module. Set the PC to boot from the burned media and follow the informations on the screen. When booting, the user can call the "arc.sh" (automated setup) command from the computer itself, access via SSH. You can also use the virtual terminal (ttyd) by typing the address provided on the screen (http://(ip):7681). The Loader will start "arc.sh" and you can select wich menu you want. The loader will automatically increase the size of the last partition and use this space as cache if it is larger than 2GiB.

The menu system is dynamic and I hope it is intuitive enough that the user can use it without any problems. Its allows you to choose a model, the existing buildnumber for the chosen model, type or randomly create a serial number, add/remove addons, add/remove/view "cmdline" and "synoinfo" entries, choose the LKM version, create the loader, boot, manually edit the configuration file, choose a keymap, update and exit.

Changing addons and synoinfo entries require re-creating the loader, cmdline entries do not.

There is no need to configure the VID/PID (if using a USB stick) or define the MAC Addresses of the network interfaces. If the user wants to modify the MAC Address of any interface, uses the "Change MAC" into "cmdline" menu.

If a model is chosen that uses the Device-tree system to define the HDs, there is no need to configure anything. In the case of models that do not use device-tree, the configurations must be done manually and for this there is an option in the "cmdline" menu to display the SATA controllers, DUMMY ports and ports in use, to assist in the creation of the "SataPortMap", "DiskIdxMap" and "sata_remap" if necessary.

Another important point is that the loader detects whether or not the CPU has the FMA3 instruction and does not display the models that require it. So if the DS918+ and DVA3221 models are not displayed it is because of the CPU's lack of support for FMA instructions. You can disable this restriction and test at your own risk.

I developed a simple patch to no longer display the DUMMY port error on models without device-tree, the user will be able to install without having to worry about it.

# Choose a Model

- DS3622xs+ / RS4021xs+
  - For best Hardwaresupport you should use one of them.
  - Support for RAID/SCSI/HBA Controllers

- DS920+ / DS1621+ / DVA3219 / DVA3221
  - Possible to get i915 (Intel Graphics) working
  - No Support for RAID/SCSI/HBA Controllers

# ARC Loader - Confirmed working

- CPU:
  - Intel (looks like all)
  - AMD (working for me with 5600X, if not use manual setup and select V1000)

- Ethernet:
  - Aquantia AQtion AQC107 / AQC111 / AQC113
  - Intel E1000 / E1000e
  - Realtek RTL 8125 / 8169
  - VMWare VMXNet3
  - VirtIO Net

- SAS/SCSI:
  - VMWare PVSCSI (with Comandline - SataPortMap = 1)
  - VirtIO SCSI (with Comandline - SataPortMap = 1)

- SATA:
  - VMWare SATA
  - Intel Native SATA 3rd to 12th Gen

- Hypervisor:
  - VMware vSphere ESXi (up to 7.0U3)
  - unRaid
  - Proxmox

- NVMe
  - WD SN700
  - WD SN850
  - Samsung 970 Evo (Plus)

# Thanks

All code was based on the work of TTG, pocopico, jumkey, fbelavenuto and others involved in continuing TTG's original redpill-load project.

More information will be added in the future.