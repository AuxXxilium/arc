
# Check for Hypervisor
if grep -q ^flags.*\ hypervisor\  /proc/cpuinfo; then
    MACHINE="VIRTUAL"
    HYPERVISOR=$(lscpu | grep Hypervisor | awk '{print $3}')
    VIRTUALMACHINE="1"
else
    MACHINE="NATIVE"
    VIRTUALMACHINE="0"
fi

# Check for RAID/SCSI
if [ $(lspci -nn | grep -ie "\[0104\]" -ie "\[0107\]" | wc -l) -gt 0 ]; then
    ADRAID="1"
else
    ADRAID="0"
fi

# Check for SATA
if [ $(lspci -nn | grep -ie "\[0106\]" | wc -l) -gt 0 ]; then
    ADSATA="1"
else
    ADSATA="0"
fi