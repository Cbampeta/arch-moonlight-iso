# ~/.bashrc
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias ll='ls -lah'
alias wifi='nmtui'
alias ts='tailscale status'
alias tsup='sudo tailscale up'
alias usbip-status='sudo /usr/local/bin/usbip-status'
alias usbip-scan='sudo /usr/local/bin/usbip-scan'
alias unlock='sudo /usr/local/bin/thin-unlock-state'

PS1='\[\e[1;36m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '

if [[ "$(tty)" != "/dev/tty1" ]]; then
    echo "=== Arch ThinClient Terminal ($(tty)) ==="
    echo "Useful commands: wifi | ts | tsup | usbip-status | usbip-scan | unlock | archinstall"
    echo "Return to Moonlight: Ctrl+Alt+F1"
fi
