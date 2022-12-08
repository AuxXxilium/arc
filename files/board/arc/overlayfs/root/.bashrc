# ~/.bashrc: executed by bash(1) for non-login shells.

# Note: PS1 and umask are already set in /etc/profile. You should not
# need this unless you want different defaults for root.
PS1='\u@\h:\w# '
# umask 022

# You may uncomment the following lines if you want `ls' to be colorized:
export LS_OPTIONS='--color=auto'
alias ls='ls $LS_OPTIONS'
alias ll='ls $LS_OPTIONS -l'

# Save history in realtime
shopt -s histappend
PROMPT_COMMAND="history -a;$PROMPT_COMMAND"

export EDITOR="/bin/nano"
export BOOTLOADER_PATH="/mnt/p1"
export SLPART_PATH="/mnt/p2"  # Synologic partition
export CACHE_PATH="/mnt/p3"
export PATH="${PATH}:/opt/arc"
export DSMROOT_PATH="/mnt/dsmroot"

if [ ! -f ${HOME}/.initialized ]; then
  touch ${HOME}/.initialized
  /opt/arc/init.sh
fi
cd /opt/arc
if tty | grep -q "/dev/pts" && [ -z "${SSH_TTY}" ]; then
  /opt/arc/arc.sh
  exit
fi
