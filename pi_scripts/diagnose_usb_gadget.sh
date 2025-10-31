#!/bin/bash
# Diagnostic script to identify USB gadget configuration
# Run this on the Pi2W: ssh milugo@localhost -p 9702 'bash -s' < diagnose_usb_gadget.sh

echo "=== USB Gadget Diagnostic Report ==="
echo

echo "1. Checking loaded USB-related kernel modules:"
lsmod | grep -E "(usb|gadget|mass_storage)"
echo

echo "2. Checking for g_mass_storage module:"
if lsmod | grep -q "g_mass_storage"; then
    echo "✓ g_mass_storage module is loaded"
    modinfo g_mass_storage 2>/dev/null | grep -E "(filename|description|parm)"
else
    echo "✗ g_mass_storage module not loaded"
fi
echo

echo "3. Checking for libcomposite/configfs gadget:"
if [ -d "/sys/kernel/config/usb_gadget" ]; then
    echo "✓ ConfigFS USB gadget detected"
    ls -la /sys/kernel/config/usb_gadget/
    echo
    for gadget in /sys/kernel/config/usb_gadget/*; do
        if [ -d "$gadget" ]; then
            echo "Gadget: $(basename $gadget)"
            echo "  UDC: $(cat $gadget/UDC 2>/dev/null || echo 'Not bound')"
            echo "  Functions:"
            ls -1 "$gadget/functions/" 2>/dev/null || echo "    None"
            if [ -d "$gadget/functions/mass_storage.usb0" ]; then
                echo "  Mass Storage Config:"
                echo "    LUN 0 file: $(cat $gadget/functions/mass_storage.usb0/lun.0/file 2>/dev/null || echo 'Not set')"
                echo "    LUN 0 ro: $(cat $gadget/functions/mass_storage.usb0/lun.0/ro 2>/dev/null || echo 'Unknown')"
            fi
        fi
    done
else
    echo "✗ No ConfigFS USB gadget found"
fi
echo

echo "4. Checking /boot/config.txt and /boot/cmdline.txt for dtoverlay:"
grep -i "dtoverlay.*dwc2" /boot/config.txt /boot/firmware/config.txt 2>/dev/null | head -1
grep -i "modules-load.*dwc2" /boot/cmdline.txt /boot/firmware/cmdline.txt 2>/dev/null | head -1
echo

echo "5. Checking /etc/modules for g_mass_storage or libcomposite:"
grep -E "(g_mass_storage|libcomposite|dwc2)" /etc/modules 2>/dev/null
echo

echo "6. Checking for USB gadget initialization scripts:"
ls -la /usr/local/bin/*usb* /etc/rc.local 2>/dev/null
echo

echo "7. Checking mount points for /mnt/usb_share:"
df -h | grep "/mnt/usb_share"
mount | grep "/mnt/usb_share"
echo

echo "8. Checking backing file/device for mass storage:"
for file in /piusb.bin /usb_share.img /home/*/usb*.img; do
    if [ -f "$file" ]; then
        echo "Found potential backing file: $file"
        ls -lh "$file"
    fi
done
echo

echo "9. Checking dmesg for USB gadget messages:"
dmesg | grep -i "usb\|gadget\|mass_storage" | tail -20
echo

echo "=== Diagnostic Complete ==="
echo
echo "Next steps:"
echo "1. Save this output and share with your assistant"
echo "2. Based on the configuration, we'll create an appropriate refresh script"
