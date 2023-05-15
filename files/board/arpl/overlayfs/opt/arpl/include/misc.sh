# Get actual IP
IP=`ip route 2>/dev/null | sed -n 's/.* via .* src \(.*\)  metric .*/\1/p' | head -1`

# Get Number of Ethernet Ports
NETNUM=`lshw -class network -short | grep -ie "eth[0-9]" | wc -l`
[ ${NETNUM} -gt 8 ] && NETNUM=8 && WARNON=3

# Memory: Check Memory installed
RAMTOTAL=0
while read -r line; do
  RAMSIZE=$line
  RAMTOTAL=$((RAMTOTAL +RAMSIZE))
done <<< `dmidecode -t memory | grep -i "Size" | cut -d" " -f2 | grep -i [1-9]`
RAMTOTAL=$((RAMTOTAL *1024))

# Check for Hypervisor
if grep -q ^flags.*\ hypervisor\  /proc/cpuinfo; then
  MACHINE="VIRTUAL"
  # Check for Hypervisor
  HYPERVISOR=`lscpu | grep Hypervisor | awk '{print $3}'`
else
  MACHINE="NATIVE"
fi