# Fixing kexec on Raspberry Pi 4 (BCM2711)

> **Note:** The kexec packages (`packages/`) were removed. To restore them,
> see commit `8839460` (`Add Wi-Fi Tailscale kexec image`).

A story of getting `nixos-anywhere` to work on a Raspberry Pi 4, where kexec
refuses to cooperate due to the platform's SMP boot method.

## The Goal

Install NixOS on a Raspberry Pi 4 running Debian, remotely, using
`nixos-anywhere` with a custom kexec image that includes WiFi and Tailscale
support. The kexec phase boots the Pi into a NixOS installer environment
running entirely from RAM, freeing the SD card for repartitioning.

## The Journey

### Problem 1: No space left on device

The kexec tarball (~524MB) is uploaded to the Pi and extracted in the user's
home directory. With the root filesystem 99% full, extraction fails:

```
tar: kexec/initrd: Wrote only 7680 of 10240 bytes
tar: kexec/run: Cannot write: No space left on device
```

**Fix**: Redirect extraction to tmpfs. The Pi has 1.9GB available in `/tmp`:

```bash
rm -rf ~/kexec
mkdir -p /tmp/kexec
ln -s /tmp/kexec ~/kexec
```

nixos-anywhere extracts to `~/kexec`, which now points to RAM-backed storage.

---

### Problem 2: CPUs are stuck in the kernel

With space sorted, kexec extraction completes but the actual kexec syscall
fails:

```
kexec_file_load failed: Device or resource busy
```

And from `dmesg`:

```
Can't kexec: CPUs are stuck in the kernel.
```

This is the big one. Let's understand why.

#### Why this happens

The Raspberry Pi 4's firmware boots secondary CPUs using the **spin-table**
method. Unlike PSCI (the standard ARM power management interface), spin-table
parks secondary CPUs in a busy-loop at a known memory address. They spin
forever, waiting for the primary CPU to write a jump address.

The Linux kernel knows that spin-table CPUs cannot be cleanly stopped or
offlined. In `arch/arm64/kernel/smp.c`, the function
`cpus_are_stuck_in_kernel()` explicitly checks for this:

```c
bool cpus_are_stuck_in_kernel(void)
{
    bool smp_spin_tables = (num_possible_cpus() > 1 && !have_cpu_die());

    return !!cpus_stuck_in_kernel || smp_spin_tables ||
        is_protected_kvm_enabled();
}
```

If `smp_spin_tables` is true, kexec is blocked — period. This check exists
because jumping to a new kernel while secondary CPUs are still spinning in the
old kernel's memory would corrupt the system.

#### What doesn't work

**Enabling `CONFIG_HOTPLUG_CPU`**: Already enabled in `bcm2711_defconfig`.
Doesn't help because spin-table CPUs can't be hotplugged regardless of the
config flag. The `/sys/devices/system/cpu/cpu1/online` file simply doesn't
exist.

**Booting with `maxcpus=1` alone**: Prevents secondary CPUs from being brought
online, but the kernel still sees them in the device tree and still sets
`smp_spin_tables = true`. The check is about what the device tree *declares*,
not what's actually running.

**Bootloader hijack (booting NixOS kernel/initrd directly)**: The NixOS kexec
initrd is 503MB. The Pi's boot partition (`/dev/mmcblk0p1`) is only 510MB. It
physically can't fit alongside the existing firmware files.

---

### The Fix: Patch the kernel + maxcpus=1

The solution has two parts:

1. **Patch the kernel** to remove the spin-table kexec block
2. **Boot with `maxcpus=1`** so no secondary CPUs are actually running

Together, these are safe: with only CPU0 active and the spin-table check
removed, kexec can proceed because there truly are no other CPUs executing
code.

#### Step 1: Build a custom kernel with kexec support

On the Pi, clone the Raspberry Pi kernel source and configure it:

```bash
git clone --depth=1 https://github.com/raspberrypi/linux.git raspberrypi-linux-kexec
cd raspberrypi-linux-kexec

make bcm2711_defconfig

# Enable kexec-related options
./scripts/config --enable KEXEC
./scripts/config --enable KEXEC_CORE
./scripts/config --enable KEXEC_FILE
./scripts/config --enable HOTPLUG_CPU

make olddefconfig

# Verify
grep -E '^CONFIG_KEXEC=|^CONFIG_KEXEC_CORE=|^CONFIG_KEXEC_FILE=|^CONFIG_HOTPLUG_CPU=' .config
```

All four should show `=y`.

#### Step 2: Patch out the spin-table kexec block

The critical one-liner:

```bash
sed -i 's/!!cpus_stuck_in_kernel || smp_spin_tables ||/!!cpus_stuck_in_kernel ||/' arch/arm64/kernel/smp.c
```

This changes the return expression in `cpus_are_stuck_in_kernel()` from:

```c
return !!cpus_stuck_in_kernel || smp_spin_tables ||
    is_protected_kvm_enabled();
```

to:

```c
return !!cpus_stuck_in_kernel ||
    is_protected_kvm_enabled();
```

The function still checks if CPUs are genuinely stuck (the
`cpus_stuck_in_kernel` counter) — we're only removing the blanket "spin-table
exists, therefore refuse" logic.

Verify the patch:

```bash
grep -A5 'cpus_are_stuck_in_kernel' arch/arm64/kernel/smp.c
```

You should see the function without `smp_spin_tables` in the return statement.

#### Step 3: Build and install the kernel

```bash
make -j"$(nproc)" LOCALVERSION=-kexec Image.gz modules dtbs
sudo make modules_install
sudo cp arch/arm64/boot/Image.gz /boot/firmware/kernel8-kexec.img
```

Update `/boot/firmware/config.txt` to use the new kernel. Add or modify:

```ini
[pi4]
kernel=kernel8-kexec.img
```

#### Step 4: Add maxcpus=1 to the kernel command line

Edit `/boot/firmware/cmdline.txt` and append `maxcpus=1`:

```
console=serial0,115200 console=tty1 root=PARTUUID=... rootfstype=ext4 fsck.repair=yes rootwait maxcpus=1
```

This ensures only CPU0 starts. Combined with the patch, kexec now has a clear
path: no spin-table block, and no secondary CPUs actually running.

#### Step 5: Reboot and verify

```bash
sudo reboot
```

After reboot:

```bash
uname -r              # Should show 6.x.y-v8-kexec
nproc                 # Should show 1
```

#### Step 6: Run nixos-anywhere

From your Mac (or wherever you run nixos-anywhere):

```bash
nix develop -c nixos-anywhere \
  --flake .#rpi \
  --kexec ./nixos-kexec-wifi-tailscale-aarch64-linux.tar.gz \
  --phases kexec \
  duck@rpi
```

You should see:

```
machine will boot into nixos in 6s...
```

The Pi is now running NixOS from RAM. Proceed with the install phases:

```bash
nix develop -c nixos-anywhere \
  --flake .#rpi \
  --phases "disko,install" \
  root@<pi-local-ip>
```

---

## Quick Reference

For anyone coming back to this later, here's the condensed version:

```bash
# On the Pi, in the kernel source directory:

# 1. Enable kexec configs
./scripts/config --enable KEXEC
./scripts/config --enable KEXEC_CORE
./scripts/config --enable KEXEC_FILE
./scripts/config --enable HOTPLUG_CPU
make olddefconfig

# 2. Patch out spin-table kexec block
sed -i 's/!!cpus_stuck_in_kernel || smp_spin_tables ||/!!cpus_stuck_in_kernel ||/' arch/arm64/kernel/smp.c

# 3. Build and install
make -j"$(nproc)" LOCALVERSION=-kexec Image.gz modules dtbs
sudo make modules_install
sudo cp arch/arm64/boot/Image.gz /boot/firmware/kernel8-kexec.img

# 4. Set kernel in config.txt and add maxcpus=1 to cmdline.txt
# 5. Reboot and run nixos-anywhere
```

## Notes

- The `maxcpus=1` parameter means the Pi runs on a single core until NixOS
  takes over. This is only needed for the kexec phase — once NixOS is
  installed, it boots with all 4 cores normally.

- The kernel patch is safe *with* `maxcpus=1`. Without it, kexec-ing while
  secondary CPUs are spinning in memory could theoretically cause issues. Don't
  remove `maxcpus=1` unless you're sure about the implications.

- The compiler warning about `unused variable 'smp_spin_tables'` after the
  patch is harmless. The variable declaration remains but is no longer
  referenced. You can remove the declaration line too if it bothers you.

- Tailscale state copied into the kexec initrd may not survive the boot
  properly (the state file ends up being 119 bytes — too small to contain valid
  credentials). Use the local network IP for the install phases instead.

- The custom kexec tarball is ~524MB. Ensure the Pi has at least 1.5GB free in
  `/tmp` (or wherever `~/kexec` points) for extraction.

## Why Not Other Approaches?

| Approach | Why it didn't work |
|----------|-------------------|
| USB boot + nixos-anywhere | Needed a USB drive we didn't have |
| Bootloader hijack (boot NixOS kernel/initrd from config.txt) | NixOS initrd is 503MB, boot partition is 510MB — doesn't fit |
| `CONFIG_HOTPLUG_CPU` alone | Already enabled; spin-table CPUs can't be hotplugged regardless |
| `maxcpus=1` alone | Kernel still checks device tree for spin-table CPUs, blocks kexec |
| Netboot/PXE | Requires TFTP server setup, EEPROM changes — overkill |
