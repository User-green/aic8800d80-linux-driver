# AIC8800D80 Linux driver with working Bluetooth (AI-assisted patches)

> **WARNING - read before using**
>
> - The two patches in this repository and this README were written **with AI assistance
>   (Claude, by Anthropic)**. Review them yourself before you rely on them.
> - They were tested on **exactly one machine**: a **Radxa Dragon Q6A** (Qualcomm QCM6490,
>   aarch64) with its **on-board AIC8800D80** USB module (`a69c:8d80` boot ROM /
>   `a69c:8d81` application mode), running **Arch Linux ARM** with a self-built
>   **Linux 7.2.8** kernel (release string `7.2.8-q6a`). The controller came up and answered
>   HCI commands; **actual Bluetooth pairing and data transfer were not tested**.
> - Nothing here has been tested on other boards, chips (AIC8800, D80X2, DC, ...), kernels or
>   distributions.
> - **No warranty of any kind.** This is out-of-tree kernel code: a bad build or a wrong
>   modprobe configuration can cost you WiFi and/or Bluetooth until you fix it.
> - **No prebuilt binaries are provided.** You must build the modules yourself against your
>   own kernel.

## What this is

An out-of-tree Linux driver set for the AIC Semiconductor AIC8800 USB WiFi/Bluetooth combo
chips, with two small patches that make **Bluetooth work on the AIC8800D80**:

| Directory | Module | Role |
|---|---|---|
| `aic8800/aic_load_fw/` | `aic_load_fw.ko` | Boot-stage loader: binds to the boot ROM (`a69c:8d80`), uploads WiFi **and** BT firmware |
| `aic8800/aic8800_fdrv/` | `aic8800_fdrv.ko` | WiFi (fullmac) driver |
| `aic_btusb/` | `aic_btusb.ko` | Bluetooth USB driver |
| `fw/aic8800D80/` | - | Firmware files for the D80 (see "Licence") |

### Where it comes from

Per the notes kept while developing the patches, the tree is a merge of:

- the WiFi-oriented fork **[ronnyf/AIC8800-Linux-Driver](https://github.com/ronnyf/AIC8800-Linux-Driver)**, and
- a **Radxa**/vendor tree that supplies `aic_btusb` and the firmware set
  (which in turn derives from **AIC Semiconductor's** SDK).

All credit for the driver itself belongs to AIC Semiconductor, Radxa and the authors of the
fork above. This repository only adds the two patches below and a portable top-level `Makefile`.
Exact upstream commit IDs were not recorded; the first commit in this repository is the tree
as it was before the patches.

### The two patches (see `git log -p`)

1. **`aic_btusb/aic_btusb.h`: `CONFIG_BLUEDROID` 1 -> 0** (both branches of
   `#ifdef CONFIG_PLATFORM_UBUNTU`).
   With `1` (the Android default) the driver provides its own `hci_alloc_dev`/`hci_register_dev`
   shims and a `/dev/aic_bt` char device for Android's Bluetooth stack, and never registers a
   Linux HCI device, so `/sys/class/bluetooth/` stays empty. With `0` it registers with BlueZ.
   This is the same change as Radxa's `fix-aic_btusb-use-bluez-by-default.patch`.

2. **`aic8800/aic_load_fw/aic_compat_8800d80.c`: upload the D80 U02 BT firmware.**
   In `aicfw_download_fw_8800d80()` the BT-side patch setup and the adid / patch / ext-patch /
   patch-table uploads for the D80 U02 revision sat inside `#if 0` (dead code inherited from the
   WiFi-only fork), so only WiFi firmware was pushed and the Bluetooth core never received its
   firmware (symptom: `Bluetooth: hci0: Opcode 0x0c03 failed: -110`, i.e. `HCI_Reset` unanswered).
   The patch enables these blocks and adds the missing `aicbt_ext_patch_data_load()` helper.
   The WiFi firmware path is unchanged.

## Build and install

Legend: **[tested]** = exercised on the author's machine (Arch Linux ARM, see warning above).
**[generic]** = general guidance, not tested on other distributions.

### 1. Prerequisites [generic]

You need the kernel headers/build tree **matching the running kernel**
(`/lib/modules/$(uname -r)/build` must exist), `make` and `gcc` (use the same compiler family the kernel
was built with).

| Distribution | Packages (examples) |
|---|---|
| Debian / Ubuntu | `sudo apt install build-essential linux-headers-$(uname -r)` |
| Fedora | `sudo dnf install gcc make kernel-devel-$(uname -r)` |
| Arch | `sudo pacman -S base-devel linux-headers` (package name differs for other kernels, e.g. `linux-lts-headers`) |

A self-built kernel needs `make modules_prepare` (or a full build) done in its tree; its build
directory is then what `/lib/modules/$(uname -r)/build` points to. [tested for a self-built kernel]

### 2. Build [tested]

Build from the **top-level** directory:

```bash
make
```

This runs kbuild for `aic8800/` (producing `aic_load_fw.ko` and `aic8800_fdrv.ko`) and for
`aic_btusb/`. The default `KDIR` is `/lib/modules/$(uname -r)/build`; override with
`make KDIR=/path/to/kernel/build`.

**Do not build `aic_load_fw` on its own** (`make -C <kbuild> M=.../aic_load_fw modules`).
`aic_load_fw/Makefile` and `aic8800_fdrv/Makefile` default `CONFIG_PREALLOC_RX_SKB` to `n`; only
`aic8800/Makefile` exports `CONFIG_PREALLOC_RX_SKB=y` and `CONFIG_PREALLOC_TXQ=y`. A direct
subdirectory build silently drops `aicwf_rx_prealloc.o`, the loader loses its
`aicwf_prealloc_*` / `aicwf_rxbuff_size_get` exports, and `aic8800_fdrv` then fails to load with
`Unknown symbol aicwf_rxbuff_size_get (err -2)` - **WiFi disappears**. If you must build a
subdirectory, pass `CONFIG_PREALLOC_RX_SKB=y`. Sanity check before installing (expect the
exports to be listed):

```bash
nm aic8800/aic_load_fw/aic_load_fw.ko | grep __ksymtab_aicwf_
```

### 3. Install the modules [tested]

```bash
sudo install -d /lib/modules/$(uname -r)/updates
sudo install -p -m 644 aic8800/aic_load_fw/aic_load_fw.ko   /lib/modules/$(uname -r)/updates/
sudo install -p -m 644 aic8800/aic8800_fdrv/aic8800_fdrv.ko /lib/modules/$(uname -r)/updates/
sudo install -p -m 644 aic_btusb/aic_btusb.ko               /lib/modules/$(uname -r)/updates/
sudo depmod -a
```

(`depmod -a` was not needed on the author's machine because `modules.dep` already listed the
modules; running it is the generic, safe step. [generic])

**Do not use the `install*` / `uninstall*` targets in `aic8800/Makefile`.** They are not
suitable as shipped: `FIRMWARE_PATH` and `UDEV_RULES_SRC` point two directory levels up
(`../../fw/...`, `../../tools/aic.rules`) and resolve to the wrong place in this layout (there is
no `tools/` directory here); `install_modules` copies to
`/lib/modules/$(uname -r)/kernel/drivers/net/wireless/aic8800`, which creates a second copy that
can shadow `updates/`, and does not cover `aic_btusb`; the `uninstall_*` and `clean` targets use
`rm -rf`.

### 4. Install the firmware [tested]

The driver reads firmware as plain files from **`/lib/firmware/aic8800D80/`**
(`/lib/firmware` is the default base path in `aic_load_fw/aicbluetooth.c`, the chip sub-directory
`aic8800D80` is appended for the D80; the WiFi driver appends the same sub-directory in
`aic8800_fdrv/aicwf_compat_8800d80.c`). The base can be changed with the `aic_fw_path` module
parameter of `aic_load_fw`, but the default is the tested configuration.

```bash
sudo install -d /lib/firmware/aic8800D80
sudo cp fw/aic8800D80/* /lib/firmware/aic8800D80/
```

### 5. Keep mainline `btusb` away from the module [tested]

Mainline `btusb` has a catch-all USB match for Bluetooth-class interfaces
(`usb:v*p*d*dc*dsc*dp*icE0isc01ip01in*`) and no entry for AIC devices, so it binds the BT
interfaces of the AIC8800D80 first and `aic_btusb` never probes. Blacklist it:

```bash
echo "blacklist btusb" | sudo tee /etc/modprobe.d/aic8800-bt.conf
```

**Side effect:** generic USB Bluetooth dongles stop working while `btusb` is blacklisted.
Alternatives (e.g. binding by driver override per device) were not tried. [generic]

If `btusb` is built into your kernel or already loaded, a modprobe.d blacklist is not enough;
that case was not tested.

### 6. Optional: make the firmware upload visible in the log [tested]

```bash
echo "options aic_load_fw aicwf_dbg_level=3" | sudo tee /etc/modprobe.d/aic8800-debug.conf
```

Remove it when it gets noisy. Without it the `### Upload ...` lines below are not printed.

### 7. Load and verify [tested]

Reboot (or use the reload procedure below). On a healthy boot (with the debug option on) the
kernel log shows, in order:

```
chip_id=7, chip_mcu_id = 0
### Upload fw_patch_table_8800d80_u02.bin fw_patch_table, size=1384
addr_adid 0x201940, addr_patch 0x1e0000
### Upload fw_adid_8800d80_u02.bin firmware, @ = 201940  size=1708
### Upload fw_patch_8800d80_u02.bin firmware, @ = 1e0000  size=32700
### Upload fw_patch_8800d80_u02_ext0.bin firmware, @ = 20b43c  size=16136
aicbt_patch_table_load bt btmode[4]:5  ... bt tx_pwr[4]:6F2F
patch version - Aug 01 2025 11:05:26 - git a26f071
### Upload fmacfw_8800d80_u02.bin firmware, @ = 120000  size=358072
```

After that the device re-enumerates as `a69c:8d81`, `aic_btusb` binds the two BT interfaces and
`aic8800_fdrv` binds the vendor (WiFi) interface. `Bluetooth: hci0: Opcode 0x0c03 failed: -110`
must **not** appear.

```bash
journalctl -k -b --no-pager | grep -iE "### Upload|addr_adid|patch version|hci0|0x0c03"
ls /sys/class/bluetooth/        # hci0
bluetoothctl show               # a powered controller with a BD address
rfkill list                     # hci0 and the wireless phy, both unblocked
```

The sizes and dates above are those of the firmware files shipped in `fw/`; the chip IDs and
addresses are for the D80 U02 revision. Other revisions were not tested.

### After every kernel update [generic, reasoning confirmed on the author's machine]

The modules are built against one kernel (`vermagic` must match `uname -r`). Whenever the kernel
release string changes, rebuild against the new headers and reinstall into the new
`/lib/modules/<new release>/updates/` (steps 2-3). This repository does not set up DKMS or any
automatic rebuild; that is left to you.

### Uninstall [generic]

```bash
sudo modprobe -r aic8800_fdrv aic_btusb aic_load_fw
sudo rm /lib/modules/$(uname -r)/updates/{aic_load_fw,aic8800_fdrv,aic_btusb}.ko
sudo depmod -a
sudo rm /etc/modprobe.d/aic8800-bt.conf /etc/modprobe.d/aic8800-debug.conf   # restores mainline btusb
sudo rm -r /lib/firmware/aic8800D80                                          # only if nothing else uses it
```

## Recovery notes

- **The BT patch can only be written while the chip is in its boot-ROM window** (`a69c:8d80`).
  Once the chip runs the application firmware (`a69c:8d81`) the loader has no chance to push it.
- **Re-running the firmware push without a reboot [tested]:**

  ```bash
  sudo modprobe -r aic8800_fdrv aic_btusb aic_load_fw
  sudo modprobe aic_load_fw
  ```

  The loader's probe of the app-mode device resets the chip; it re-enumerates as `8d80`, the
  loader runs the full download and the device comes back as `8d81`. Afterwards load
  `aic8800_fdrv` again (`sudo modprobe aic8800_fdrv`).
- **Power-cycling the USB hub port [tested on the Q6A only]:** write `1` then `0` to the hub
  port's sysfs `disable` attribute (`/sys/devices/.../usbN/N-M/N-M:1.0/N-M-portP/disable`).
  The path is hardware-specific; on the Q6A the module sits behind an internal hub and is soldered
  on, so this is the only "physical" reset. A ganged hub also blips its other ports.
- **WiFi after a reload [tested]:** the WiFi netdev is replaced under NetworkManager and
  wpa_supplicant, which then report `unavailable` / `couldn't grab this interface`. This is stale
  supplicant state, not a driver fault; `sudo systemctl restart wpa_supplicant` and
  `sudo systemctl restart NetworkManager` (or a reboot) clears it. It does not happen on a clean
  boot.
- **WiFi gone, `Unknown symbol aicwf_*`:** you built `aic_load_fw` without the prealloc options
  (see Build). Rebuild from the top level.

## What was and was not verified

- Verified on the author's Q6A: top-level build, installation of the three modules into
  `updates/`, firmware from `fw/aic8800D80/`, `blacklist btusb`, the controller appearing as
  `hci0` and answering HCI (`bluetoothctl show`, `btmgmt info`), WiFi scanning still working,
  the module-reload recovery and the hub-port power cycle.
- **Not verified:** pairing/using a Bluetooth device; an unattended cold boot with the final
  modules was still pending when these notes were written; any other board, chip revision
  (e.g. `u04` firmware files are shipped but untested), kernel or distribution; the generic
  prerequisite package names and the uninstall steps above.

## Licence

The driver source is licensed under **GPL-2.0** (the modules declare `MODULE_LICENSE("GPL")`);
the licence text is in `LICENSE`. Only a few source files carry an explicit
licence header (most of the roughly 130 `.c`/`.h` files carry none); this repository does not add
or change any, so the GPL-2.0 designation rests on the `MODULE_LICENSE("GPL")` declarations and
should be checked against the upstream trees.

The files under **`fw/`** are **proprietary firmware blobs by AIC Semiconductor**, redistributed
here as they are in the upstream driver trees. They are **not covered by the GPL** and no licence
grant for them is made by this repository; check AIC's/Radxa's terms before redistributing them
further.

The two patches and the top-level `Makefile`/`README.md` were produced with AI assistance and are
offered under the same GPL-2.0 terms as the code they modify.
