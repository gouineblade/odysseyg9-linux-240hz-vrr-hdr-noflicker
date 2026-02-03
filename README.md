# Samsung Odyssey G9 on Linux - 240Hz, VRR & HDR Without Flicker or Ghosting

Tested on Arch Linux with KDE, but should work on other distros as well.

## About this Project

This repository provides a Linux fix for the **Samsung Odyssey G9** monitor to achieve **240Hz**, **VRR (Variable Refresh Rate)**, **HDR**, and eliminate flickering or ghosting issues, particularly over DisplayPort.

An **automated installer script** is now available to simplify the process. However, if:
- You **don’t use GRUB** as your bootloader (e.g., using systemd-boot, rEFInd, etc.),
- Or if you want **full control and understanding** of each step,

you can follow the manual guide below. For non-GRUB users, you can adapt the GRUB instructions to match your bootloader’s method for setting kernel parameters.

---

## Why this guide?

This guide complements the work found [here](https://gitlab.freedesktop.org/drm/amd/-/issues/1442#note_1017689), which managed to enable 240Hz at the cost of losing Variable Refresh Rate (VRR). You might have either followed that guide and lost VRR, or your monitor keeps turning on and off with artifacts when trying to use 240Hz.

This guide specifically targets the **LC49G95** model (5120x1440 - 240Hz - VA - FreeSync Premium - FreeSync range 60-240Hz - HDR). It might work with another models but I don't recommend it since you'll inherit of all the **LC49G95** settings.

Many affected users seem to own an **AMD RX 6XXX series GPU**, such as my **6900 XT**, but this solution is potentially effective regardless of GPU vendor. Proceed carefully.

---

## Disclaimer

Before proceeding, it is highly recommended to **set up SSH access** to your machine, in case a misconfiguration prevents graphical boot. This ensures you can reverse the changes remotely.

---

## Manual Installation Guide

### 1. Adding the EDID file to initramfs

Copy the provided EDID file to the firmware directory:
```bash
sudo cp edids/LC49G95.bin /usr/lib/firmware/edid/LC49G95.bin
```

Edit your initramfs configuration:
```bash
sudo nano /etc/mkinitcpio.conf
```

Add the EDID path to the `FILES` array:
```bash
FILES=(/usr/lib/firmware/edid/LC49G95.bin)
```

Then regenerate the initramfs:
```bash
sudo mkinitcpio -P
```

### 2. Adding the EDID to Linux kernel parameters

If you are using GRUB, edit:
```bash
sudo nano /etc/default/grub
```

Add this to `GRUB_CMDLINE_LINUX_DEFAULT` (replace `DP-1` with your actual DisplayPort connection):
```bash
drm.edid_firmware=DP-1:edid/LC49G95.bin
```

Example:
```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash drm.edid_firmware=DP-1:edid/LC49G95.bin"
```

Regenerate GRUB’s configuration:
```bash
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

For other bootloaders, adapt this parameter accordingly.

---

### 3. Optional: Updating the Monitor Firmware

If your monitor's firmware is outdated, download it here:  
[Samsung LC49G95 Firmware](https://www.samsung.com/fr/support/model/LC49G95TSSUXEN/#downloads)

Follow Samsung’s instructions to flash it using a FAT-formatted USB drive.

---

## Uninstall / Rollback Instructions

If the display breaks after reboot:
1. **SSH into your system**, or use a recovery medium with chroot.
2. Edit `/etc/mkinitcpio.conf` to remove the EDID from the `FILES` array.
3. Rebuild initramfs:
```bash
sudo mkinitcpio -P
```
4. Remove the `drm.edid_firmware=...` from your bootloader’s kernel parameters.
5. Rebuild the bootloader config (for GRUB: `sudo grub-mkconfig -o /boot/grub/grub.cfg`).
6. Reboot.

---

## Background Story

I spent over **15 hours** troubleshooting this issue via trial and error. On **Windows**, everything works out of the box, but not on Linux.

After testing EDID dumps between OSes, I crafted a compatible EDID that restores full **240Hz**, **VRR**, and **HDR** capabilities — without flicker or ghosting.

Most GUI EDID editors failed because the G9's EDID is unconventional, so this was mostly handcrafted.

🚀 Everything now works flawlessly on Linux!

---

For the automated installation process, check out the `install.sh` script provided in this repository. 🎉
