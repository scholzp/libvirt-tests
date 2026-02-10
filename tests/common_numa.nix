# This file exports a function that returns a NixOS module.
#
# The module defines the common parts of the host VMs.

{
  libvirt-src,
  nixos-image,
  chv-ovmf,
}:
{ pkgs, lib, ... }:
let
  cirros_qcow = pkgs.fetchurl {
    url = "https://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img";
    hash = "sha256-B+RKc+VMlNmIAoUVQDwe12IFXgG4OnZ+3zwrOH94zgA=";
  };

  cirros_raw = pkgs.runCommand "cirros_raw" { } ''
    ${pkgs.qemu-utils}/bin/qemu-img convert -O raw ${cirros_qcow} $out
  '';

  virsh_ch_xml =
    {
      image ? "/var/lib/libvirt/storage-pools/nfs-share/nixos.img",
      numa ? false,
      hugepages ? false,
      prefault ? false,
      serial ? "pty",
      # Whether all device will be assigned a static BDF through the XML or only some
      all_static_bdf ? false,
      # Whether we add a function ID to specific BDFs or not
      use_bdf_function ? false,
    }:
    ''
      <domain type='kvm' id='21050'>
        <name>testvm</name>
        <uuid>4eb6319a-4302-4407-9a56-802fc7e6a422</uuid>
        <memory unit='KiB'>1048576</memory>
        <currentMemory unit='KiB'>1048576</currentMemory>
        <vcpu placement='static'>2</vcpu>
        <cputune>
          <vcpupin vcpu='0' cpuset='0-1'/>
          <vcpupin vcpu='1' cpuset='2-3'/>
          <emulatorpin cpuset='0-1'/>
        </cputune>
        <cpu>
          <topology sockets='2' dies='1' cores='1' threads='1'/>
          <numa>
            <!-- Defines the guest NUMA topology -->
            <cell id='0' cpus='0-1' memory='1048576' unit='KiB'/>
          </numa>
        </cpu>
        <numatune>
          <memory mode='strict' nodeset='3'/>
            <!-- Maps memory from guest to host NUMA topology. nodeset refers to host NUMA node, cellid to guest NUMA -->
          <memnode cellid='0' mode='strict' nodeset='3'/>
        </numatune>
        <os>
          <type arch='x86_64'>hvm</type>
          <kernel>/etc/CLOUDHV.fd</kernel>
          <boot dev='hd'/>
        </os>
        <clock offset='utc'/>
        <on_poweroff>destroy</on_poweroff>
        <on_reboot>restart</on_reboot>
        <on_crash>destroy</on_crash>
        <devices>
          <emulator>cloud-hypervisor</emulator>
          <disk type='file' device='disk'>
            <source file='${image}'/>
            <target dev='vda' bus='virtio'/>
          </disk>
          <interface type='ethernet'>
            <mac address='52:54:00:e5:b8:01'/>
            <target dev='tap1'/>
            <model type='virtio'/>
            <driver queues='1'/>
            <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x0'/>
          </interface>
          <serial type='pty'>
            <source path='/dev/pts/2'/>
            <target port='0'/>
          </serial>
        </devices>
      </domain>
    '';

  virsh_ch_updated =
    {
      image ? "/var/lib/libvirt/storage-pools/nfs-share/nixos.img",
      numa ? false,
      hugepages ? false,
      prefault ? false,
      serial ? "pty",
      # Whether all device will be assigned a static BDF through the XML or only some
      all_static_bdf ? false,
      # Whether we add a function ID to specific BDFs or not
      use_bdf_function ? false,
    }:
    ''
      <domain type='kvm' id='21050'>
        <name>testvm</name>
        <uuid>4eb6319a-4302-4407-9a56-802fc7e6a422</uuid>
        <memory unit='KiB'>1048576</memory>
        <currentMemory unit='KiB'>1048576</currentMemory>
        <vcpu placement='static'>2</vcpu>
        <cputune>
          <vcpupin vcpu='0' cpuset='2'/>
          <vcpupin vcpu='1' cpuset='3'/>
          <emulatorpin cpuset='0-1'/>
        </cputune>
        <cpu>
          <topology sockets='2' dies='1' cores='1' threads='1'/>
          <numa>
            <!-- Defines the guest NUMA topology -->
            <cell id='0' cpus='0-1' memory='1048576' unit='KiB'/>
          </numa>
        </cpu>
        <numatune>
          <memory mode='strict' nodeset='1'/>
            <!-- Maps memory from guest to host NUMA topology. nodeset refers to host NUMA node, cellid to guest NUMA -->
          <memnode cellid='0' mode='strict' nodeset='1'/>
        </numatune>
        <os>
          <type arch='x86_64'>hvm</type>
          <kernel>/etc/CLOUDHV.fd</kernel>
          <boot dev='hd'/>
        </os>
        <clock offset='utc'/>
        <on_poweroff>destroy</on_poweroff>
        <on_reboot>restart</on_reboot>
        <on_crash>destroy</on_crash>
        <devices>
          <emulator>cloud-hypervisor</emulator>
          <disk type='file' device='disk'>
            <source file='${image}'/>
            <target dev='vda' bus='virtio'/>
          </disk>
          <interface type='ethernet'>
            <mac address='52:54:00:e5:b8:01'/>
            <target dev='tap1'/>
            <model type='virtio'/>
            <driver queues='1'/>
            <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x0'/>
          </interface>
          <serial type='pty'>
            <source path='/dev/pts/2'/>
            <target port='0'/>
          </serial>
        </devices>
      </domain>
    '';

  # Please keep in sync with documentation in networks.md!
  libvirt_test_network = ''
    <network>
      <name>libvirt-testnetwork</name>
      <forward mode='nat'/>
      <bridge name='br3' stp='on' delay='0'/>
      <ip address='192.168.3.1' netmask='255.255.255.0'>
        <!--
        Not strictly required for our setup, but libvirt still expects a DHCP
        range to configure its dnsmasq instance. Without an explicit range,
        libvirt chooses one dynamically.
         -->
        <dhcp>
          <!-- Static interface in VM has 192.168.3.2. -->
          <range start='192.168.3.42' end='192.168.3.42'/>
        </dhcp>
      </ip>
    </network>
  '';
in
{
  # Silence the monolithic libvirtd, which otherwise starts before the virtchd
  # and is then shutdown as soon as virtchd starts. Disabling prevents a lot of
  # distracting log messages of libvirtd in the startup phase.
  systemd.services.libvirtd.enable = false;
  systemd.services.virtchd = {
    environment.ASAN_OPTIONS = "detect_leaks=1:fast_unwind_on_malloc=0:halt_on_error=1:symbolize=1";
    environment.LSAN_OPTIONS = "report_objects=1";
  };

  # We use the freshest kernel available to reduce nested virtualization bugs.
  boot.kernelPackages = pkgs.linuxPackages_6_18;
  virtualisation.libvirtd = {
    enable = true;
    sshProxy = false;
    package = pkgs.libvirt.overrideAttrs (old: {
      src = libvirt-src;
      name = "libvirt-gardenlinux";
      version =
        let
          fallback = builtins.trace "WARN: cannot obtain version from libvirt fork" "0.0.0-unknown";
          mesonBuild = builtins.readFile "${libvirt-src}/meson.build";
          # Searches for the line `version: '11.3.0'` and captures the version.
          matches = builtins.match ".*[[:space:]]*version:[[:space:]]'([0-9]+.[0-9]+.[0-9]+)'.*" mesonBuild;
          version = builtins.elemAt matches 0;
        in
        if matches != null then version else fallback;
      debug = true;
      doInstallCheck = false;
      doCheck = false;
      patches = [
        ../patches/libvirt/0001-meson-patch-in-an-install-prefix-for-building-on-nix.patch
        ../patches/libvirt/0002-substitute-zfs-and-zpool-commands.patch
      ];

      # Use the optimized debug build
      mesonBuildType = "debugoptimized";

      # IMPORTANT: donStrip is required because otherwise, nix will strip all
      # debug info from the binaries in its fixupPhase. Having the debug info
      # is crucial for getting source code info from the sanitizers, as well as
      # when using GDB.
      dontStrip = true;

      # Reduce files needed to compile. We cut the build-time in half.
      mesonFlags =
        old.mesonFlags
        # Helps to keep track of the commit hash in the libvirt log. Nix strips
        # all `.git`, so we need to be explicit here.
        #
        # This is a non-standard functionality of our own libvirt fork.
        ++ lib.optional (libvirt-src ? rev) "-Dcommit_hash=${libvirt-src.rev}"
        ++ [
          # Disabling tests: 1500 -> 1200
          "-Dtests=disabled"
          "-Dexpensive_tests=disabled"
          # Disabling docs: 1200 -> 800
          "-Ddocs=disabled"
          # Disabling unneeded backends: 800 -> 685
          "-Ddriver_ch=enabled"
          "-Ddriver_qemu=disabled"
          "-Ddriver_bhyve=disabled"
          "-Ddriver_esx=disabled"
          "-Ddriver_hyperv=disabled"
          "-Ddriver_libxl=disabled"
          "-Ddriver_lxc=disabled"
          "-Ddriver_openvz=disabled"
          "-Ddriver_secrets=disabled"
          "-Ddriver_vbox=disabled"
          "-Ddriver_vmware=disabled"
          "-Ddriver_vz=disabled"
          "-Dstorage_dir=disabled"
          "-Dstorage_disk=disabled"
          "-Dstorage_fs=enabled" # for netfs
          "-Dstorage_gluster=disabled"
          "-Dstorage_iscsi=disabled"
          "-Dstorage_iscsi_direct=disabled"
          "-Dstorage_lvm=disabled"
          "-Dstorage_mpath=disabled"
          "-Dstorage_rbd=disabled"
          "-Dstorage_scsi=disabled"
          "-Dstorage_vstorage=disabled"
          "-Dstorage_zfs=disabled"
          "-Dapparmor=disabled"
          "-Dwireshark_dissector=disabled"
          "-Dselinux=disabled"
          "-Dsecdriver_apparmor=disabled"
          "-Dsecdriver_selinux=disabled"
          "-Db_sanitize=leak"
          "-Db_sanitize=address,undefined"
          # Enabling the sanitizers has led to warnings about inlining macro
          # generated cleanup methods of the glib which spam the build log.
          # Ignoring and suppressing the warnings seems like the only option.
          # "warning: inlining failed in call to 'glib_autoptr_cleanup_virNetlinkMsg': call is unlikely and code size would grow [-Winline]"
          "-Dc_args=-Wno-inline"
        ];
    });
  };

  systemd.services.virtstoraged.path = [ pkgs.mount ];

  systemd.services.virtchd.wantedBy = [ "multi-user.target" ];
  systemd.services.virtchd.path = [ pkgs.openssh ];
  systemd.services.virtnetworkd.path = with pkgs; [
    dnsmasq
    iproute2
    nftables
  ];
  systemd.sockets.virtproxyd-tcp.wantedBy = [ "sockets.target" ];
  systemd.sockets.virtstoraged.wantedBy = [ "sockets.target" ];
  systemd.sockets.virtnetworkd.wantedBy = [ "sockets.target" ];

  systemd.services.virtchd = {
    serviceConfig = {
      Restart = "always";
      RestartSec = 1;
    };
    startLimitIntervalSec = 0;
    startLimitBurst = 0;
  };

  systemd.network = {
    enable = true;
    wait-online.enable = false;

    # Created devices.
    netdevs = {
      "10-br4" = {
        netdevConfig = {
          Kind = "bridge";
          Name = "br4";
        };
      };
    };

    networks = {
      "10-tap1" = {
        enable = true;
        matchConfig.Name = "tap1";
        networkConfig = {
          Description = "Main network";
          DHCPServer = "no";
        };

        # Please keep in sync with documentation in networks.md!
        address = [
          "192.168.1.1/24" # Main network
        ];
      };
      "10-tap2" = {
        enable = true;
        matchConfig.Name = "tap2";
        networkConfig = {
          Description = "Hotplug device";
          DHCPServer = "no";
        };

        # Please keep in sync with documentation in networks.md!
        address = [
          "192.168.2.1/24" # hotplugged interface
        ];
      };
      # Bridge interface configuration
      "10-br4" = {
        enable = true;
        matchConfig.Name = "br4";
        networkConfig = {
          Description = "Hot Plug Bridge";
          DHCPServer = "no";
        };

        # Please keep in sync with documentation in networks.md!
        address = [
          "192.168.4.1/24" # hotplugged interface
        ];
      };
    };
  };

  # Please keep in sync with documentation in networks.md!
  networking = {
    useDHCP = false;
    networkmanager.enable = false;
    useNetworkd = true;
    firewall.enable = false;
  };

  services.getty.autologinUser = "root";
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PermitEmptyPasswords = "yes";
    };
  };

  # The following works around the infamous
  # `Bad owner or permissions on /nix/store/ymmaa926pv3f3wlgpw9y1aygdvqi1m7j-systemd-257.6/lib/systemd/ssh_config.d/20-systemd-ssh-proxy.conf`
  # error. The current assumption is, that this is a nixos/nixpkgs bug handling
  # file permissions incorrectly. But the error is only appearing on certain
  # systems (AMD only?).
  environment.etc."ssh/ssh_config".enable = false;

  environment.variables = {
    LIBVIRT_DEFAULT_URI = "ch:///session";
  };

  security.pam.services.sshd.allowNullPassword = true;

  environment.systemPackages = with pkgs; [
    bridge-utils
    btop
    cloud-hypervisor
    expect
    fcntl-tool
    gdb
    htop
    jq
    lsof
    mount
    numactl
    numatop
    python3
    qemu_kvm
    screen
    screen
    socat
    sshpass
    tcpdump
    tshark
    tunctl
  ];

  systemd.tmpfiles.settings =
    let
      chv-firmware = pkgs.fetchurl {
        url = "https://github.com/cloud-hypervisor/rust-hypervisor-firmware/releases/download/0.5.0/hypervisor-fw";
        hash = "sha256-Sgoel3No9rFdIZiiFr3t+aNQv15a4H4p5pU3PsFq2Vg=";
      };
    in
    {
      "10-chv" = {
        "/etc/hypervisor-fw" = {
          "L+" = {
            argument = "${chv-firmware}";
          };
        };
        "/etc/CLOUDHV.fd" = {
          "C+" = {
            argument = "${chv-ovmf.fd}/FV/CLOUDHV.fd";
          };
        };
        "/etc/nixos.img" = {
          "L+" = {
            argument = "${nixos-image}";
          };
        };
        "/etc/cirros.img" = {
          "L+" = {
            argument = "${cirros_raw}";
          };
        };
        "/etc/domain-chv.xml" = {
          "C+" = {
            argument = "${pkgs.writeText "domain.xml" (virsh_ch_xml { })}";
          };
        };
        "/etc/domain-chv-target.xml" = {
          "C+" = {
            argument = "${pkgs.writeText "domain-target.xml" (virsh_ch_updated { })}";
          };
        };
        "/etc/libvirt_test_network.xml" = {
          "C+" = {
            argument = "${pkgs.writeText "libvirt_test_network.xml" libvirt_test_network}";
          };
        };
        "/var/lib/libvirt/network.conf" = {
          "C+" = {
            argument = "${pkgs.writeText "network.conf" ''
              firewall_backend = "nftables"
            ''}";
          };
        };
        "/var/log/libvirt/" = {
          D = {
            mode = "0755";
            user = "root";
          };
        };
        "/var/log/libvirt/ch" = {
          D = {
            mode = "0755";
            user = "root";
          };
        };
      };
    };
}
