#!/bin/bash

ask_execution() {
    read -rp "▶️ Run the following command? (y/n) : $* " answer
    if [[ "$answer" == [Yy] ]]; then
        "$@"
    else
        echo "⏭️ Installation aborted."
        exit 0
    fi
}

# Check for grub-mkconfig
if ! command -v grub-mkconfig &> /dev/null; then
    echo "❌ grub-mkconfig not found in \$PATH. Install wizard aborted."
    exit 2
else
    echo "✅ grub-mkconfig found! Proceeding..."
fi

# Check for sshd
if ! command -v sshd &> /dev/null; then
    echo "❌ sshd not found. 🔐 SSH access is recommended to recover your system if needed."
    read -rp "Would you like to install it and relaunch the install wizard afterwards? (y/n) " SSHD_WANTED
    if [[ "$SSHD_WANTED" == [Yy] ]]; then
        echo "👉 Please install sshd according to your distribution and relaunch the install wizard afterwards."
        exit 0
    else
        echo "⚠️ Without SSH, you'll need to chroot using an installer medium if recovery is necessary."
    fi
else
    if ! systemctl is-active --quiet sshd; then
        read -rp "🔐 sshd is installed but not running. Enable SSH for remote access? (y/n) " ENABLE_SSHD
        if [[ "$ENABLE_SSHD" == [Yy] ]]; then
            echo "⚙️ Enabling sshd service..."
            sudo systemctl enable --now sshd
            if [[ $? -ne 0 ]]; then
                echo "❌ Failed to enable sshd. Exiting..."
                exit 1
            fi
            echo "🔑 SSH is now enabled. You can connect remotely via SSH."
            echo "🔒 Please ensure you have set a password or SSH key for secure access."

            if ! command -v ip &> /dev/null; then
                echo "ℹ️ Please find your local IP address manually and note it."
            else
                echo "🌐 Connect on your local network using: ssh username@IP"
                ip -4 addr show | grep inet | awk '{print $2}' | cut -d/ -f1 | grep '192' || echo "⚠️ No typical local 192.x.x.x IP found."
            fi
        fi
    fi
fi

# Detect DisplayPort outputs with EDID
DP_PORTS=()
for i in $(ls /sys/class/drm | grep 'DP'); do
    # Check if the EDID file contains any non-null bytes by removing null characters (\0)
    # and testing if the result is non-empty, indicating valid EDID data is present.
    if [[ -n $(tr -d '\0' < "/sys/class/drm/$i/edid") ]]; then
        echo "🔍 EDID found in /sys/class/drm/$i"
        DP_PORTS+=($(echo "$i" | grep -o 'DP.*'))
    fi
done

if [[ ${#DP_PORTS[@]} -eq 0 ]]; then
    echo "❌ No DisplayPort outputs with EDID found."
    exit 1
fi

# Prompt user to select DP output
echo "🖥️ Select the DisplayPort output connected to your monitor:"
PS3="Please enter your choice number: "

select DP_PORT in "${DP_PORTS[@]}"; do
    if [[ -n "$DP_PORT" ]]; then
        echo "✅ You chose: $DP_PORT"
        break
    else
        echo "❌ Invalid choice. Try again."
    fi
done

echo "📁 Select the EDID file corresponding to your monitor:"

select EDID in "$(ls edids)"; do
    if [[ -n "$EDID" ]]; then
        echo "✅ You chose: $EDID"
        break
    else
        echo "❌ Invalid choice. Try again."
    fi
done

prepare_environment() {
    mkdir -p backup
    mkdir -p tmp
    cp /etc/default/grub backup/grub
    cp /etc/default/grub tmp/grub

    ask_execution sudo mkdir -p /usr/lib/firmware/edid && sudo cp edids/$EDID /usr/lib/firmware/edid/$EDID

    EDID_PARAM="drm.edid_firmware=$DP_PORT:edid/$EDID"

    # removes any existing drm.edid_firmware parameter from GRUB_CMDLINE_LINUX_DEFAULT and appends a new one defined by the variable $EDID_PARAM
    sudo sed -i -E \
    "s@(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*) drm\.edid_firmware=[^ ]*@\1@g; \
    s@(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*)\"@\1 $EDID_PARAM\"@" \
    tmp/grub

    echo "🔍 Comparing original GRUB config with the updated version:"
    output=$(diff /etc/default/grub tmp/grub)
    if [[ -z "$output" ]]; then
        echo "No changes"
    else
        echo "$output"
    fi
        printf "\n"
}

apply_changes() {
    ask_execution sudo sh -c "echo 'FILES+=(/usr/lib/firmware/edid/$EDID)' > /etc/mkinitcpio.conf.d/99-edid.conf"
    ask_execution sudo mkinitcpio -P
    ask_execution sudo cp tmp/grub /etc/default/grub
    ask_execution sudo grub-mkconfig -o /boot/grub/grub.cfg
    echo "✅ All done! You can now safely reboot your system to apply the changes."
}

prepare_environment
read -rp "Do you want to proceed with those changes? (y/n) " PROCEED
if [[ $PROCEED == [Yy] ]]; then
    apply_changes
fi
