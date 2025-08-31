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

# Check what distro we're in
if command -v mkinitcpio &> /dev/null; then
    echo "Arch Linux based distribution detected."
    ARCHBTW=1
    GRUBCONFIG="$(grub-mkconfig -o /boot/grub/grub.cfg)"
    MKINITRAMFS="$(mkinitcpio -P)"
    INITRAMFSCFG="/etc/mkinitcpio.conf"
else
    if command -v update-initramfs &> /dev/null; then
        echo "Debian based distribution detected."
        DEBIAN=1
        GRUBCONFIG="$(grub-mkconfig -o /boot/grub/grub.cfg)"
        MKINITRAMFS="$(update-initramfs -u)"
        INITRAMFSCFG="/etc/mkinitcpio.conf"
    else
        if command -v dracut &> /dev/null; then
            echo "Fedora based distribution detected."
            FEDORA=1
            GRUBCONFIG="$(grub2-mkconfig -o /boot/grub2/grub.cfg)"
            MKINITRAMFS="$(dracut --regenerate-all --force)"
            INITRAMFSCFG="/etc/dracut.conf.d/l49g59.conf"
        else
            echo "Could not determine your Linux distribution."
            exit 2
        fi
    fi
fi

# Check for grub-mkconfig
if ! command -v ${GRUBCONFIG} &> /dev/null; then
    echo "❌ grub-mkconfig or grub2-mkconfig not found in \$PATH. Install wizard aborted."
    exit 2
else
    echo "✅ grub-mkconfig or grub2-mkconfig found! Proceeding..."
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
echo "🎯 Select the DisplayPort output connected to your monitor:"
PS3="Please enter your choice number: "

select DP_PORT in "${DP_PORTS[@]}"; do
    if [[ -n "$DP_PORT" ]]; then
        echo "✅ You chose: $DP_PORT"
        break
    else
        echo "❌ Invalid choice. Try again."
    fi
done

echo "🖥️ Select the EDID file corresponding to your monitor:"

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
    cp $INITRAMFSCFG backup/
    cp $INITRAMFSCFG tmp/
    cp /etc/default/grub backup/
    cp /etc/default/grub tmp/

    ask_execution sudo cp edids/$EDID /usr/lib/firmware/edid/$EDID

    if $ARCHBTW=1 || $DEBIAN=1; then
        CONF=mkinitcpio.conf
    else
        if $FEDORA=1; then
            CONF=l49g59.conf
        fi
    fi
    
    if grep -q "usr/lib/firmware/edid" tmp/$CONF; then
        sed -i -E "s|usr/lib/firmware/edid/[^ ]+\.bin|usr/lib/firmware/edid/$EDID|g" tmp/$CONF
    else
        sed -i -E "/^FILES=\(/ s|^FILES=\(([^)]*)\)|FILES=(\1 /usr/lib/firmware/edid/$EDID)|" tmp/$CONF
    fi


    EDID_PARAM="drm.edid_firmware=$DP_PORT:edid/$EDID"

    if grep -q "drm.edid_firmware=" tmp/grub; then
        sed -i "s|drm\.edid_firmware=[^ ]*|$EDID_PARAM|" tmp/grub
    else
        sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/ { /"/! s/=\(.*\)$/="\1"/ }' tmp/grub # Adds quotes if they don't exist
        sed -i "/^GRUB_CMDLINE_LINUX_DEFAULT=/s/\"/ $EDID_PARAM\"/" tmp/grub
    fi

    echo "🔍 Comparing original mkinitcpio.conf with the updated version:"
    diff $INITRAMFSCFG tmp/$CONF || echo "No changes"
    printf "\n"
    echo "🔍 Comparing original GRUB config with the updated version:" || echo "No changes"
    diff /etc/default/grub tmp/grub
    printf "\n"
}

apply_changes() {
    ask_execution sudo cp tmp/$CONF $INITRAMFSCFG
    ask_execution sudo ${MKINITRAMFS}
    ask_execution sudo cp tmp/grub /etc/default/grub
    ask_execution sudo ${GRUBCONFIG}
    echo "✅ All done! You can now safely reboot your system to apply the changes."
}

prepare_environment
read -rp "Do you want to proceed with those changes? (y/n) " PROCEED
if [[ $PROCEED == [Yy] ]]; then
    apply_changes
fi
