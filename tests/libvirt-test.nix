# Sets up a NixOS integration test with two VMs running NixOS.
#
# This will run our test suite.

{
  lib,
  pkgs,
  libvirt-src,
  nixos-image,
  chv-ovmf,
  testScriptFile,
  enable_numa ? false,
}:
let
  common = import ./common.nix { inherit libvirt-src nixos-image chv-ovmf; };
  common_numa = import ./common_numa.nix { inherit libvirt-src nixos-image chv-ovmf; };

  tls =
    let
      c = pkgs.callPackage ./certificates.nix { };
    in
    {
      ca = c.tlsCA;
      controller = c.mkHostCert "controllerVM" "192.168.100.1";
      compute = c.mkHostCert "computeVM" "192.168.100.2";
    };
in
pkgs.testers.nixosTest {
  name = "Libvirt test suite for Cloud Hypervisor";

  extraPythonPackages =
    p: with p; [
      pytest
      libvirt
      test-helper
    ];

  nodes.controllerVM =
    { ... }:
    {
      imports = [
        common_numa
        ../modules/nfs-host.nix
        ../modules/numa-settings.nix
      ];

      virtualisation = {
        cores = 4;
        memorySize = 8192;
        interfaces.eth1.vlan = 1;
        diskSize = 8192;
        forwardPorts = [
          {
            from = "host";
            host.port = 2222;
            guest.port = 22;
          }
          # The testscript runs in the Host context while we want to connect to
          # the libvirt in the controllerVM
          {
            from = "host";
            host.port = 2223;
            guest.port = 16509;
          }
        ];
      };

      networking.extraHosts = ''
        192.168.100.2 computeVM computeVM.local
      '';

      systemd.network = {
        enable = true;
        wait-online.enable = false;
        networks = {
          eth0 = {
            matchConfig.Name = [ "eth0" ];
            networkConfig.DHCP = "yes";
          };
          eth1 = {
            matchConfig.Name = [ "eth1" ];
            networkConfig = {
              Address = "192.168.100.1/24";
              Gateway = "192.168.100.1";
              DNS = "8.8.8.8";
            };
          };
        };
      };

      systemd.tmpfiles.settings."11-certs" = {
        "/var/lib/libvirt/ch/pki/ca-cert.pem"."C+".argument = "${tls.ca}/ca-cert.pem";
        "/var/lib/libvirt/ch/pki/server-cert.pem"."C+".argument = "${tls.controller}/server-cert.pem";
        "/var/lib/libvirt/ch/pki/server-key.pem"."C+".argument = "${tls.controller}/server-key.pem";
      };
      virtualisation.qemu.options = lib.mkAfter (
        if enable_numa then
        [
          "-smp 4,sockets=4,cores=1,threads=1"
          "-object memory-backend-ram,size=2G,id=m0"
          "-object memory-backend-ram,size=2G,id=m1"
          "-object memory-backend-ram,size=2G,id=m2"
          "-object memory-backend-ram,size=2G,id=m3"
          "-numa node,nodeid=0,cpus=0,memdev=m0"
          "-numa node,nodeid=1,cpus=1,memdev=m1"
          "-numa node,nodeid=2,cpus=2,memdev=m2"
          "-numa node,nodeid=3,cpus=3,memdev=m3"
        ]
        else [ ]
      );
    };

  nodes.computeVM =
    { ... }:
    {
      imports = [
        common_numa
        ../modules/nfs-client.nix
      ];

      networking.extraHosts = ''
        192.168.100.1 controllerVM controllerVM.local
      '';

      virtualisation = {
        cores = 4;
        memorySize = 8192;
        interfaces.eth1.vlan = 1;
        diskSize = 2048;
        forwardPorts = [
          {
            from = "host";
            host.port = 3333;
            guest.port = 22;
          }
        ];
      };

      livemig.nfs.host = "192.168.100.1";

      systemd.network = {
        enable = true;
        wait-online.enable = false;
        networks = {
          eth0 = {
            matchConfig.Name = [ "eth0" ];
            networkConfig.DHCP = "yes";
          };
          eth1 = {
            matchConfig.Name = [ "eth1" ];
            networkConfig = {
              Address = "192.168.100.2/24";
              Gateway = "192.168.100.1";
              DNS = "8.8.8.8";
            };
          };
        };
      };

      systemd.tmpfiles.settings."11-certs" = {
        "/var/lib/libvirt/ch/pki/ca-cert.pem"."C+".argument = "${tls.ca}/ca-cert.pem";
        "/var/lib/libvirt/ch/pki/server-cert.pem"."C+".argument = "${tls.compute}/server-cert.pem";
        "/var/lib/libvirt/ch/pki/server-key.pem"."C+".argument = "${tls.compute}/server-key.pem";
      };

      virtualisation.qemu.options = lib.mkAfter (
        if enable_numa then
        [
          "-smp 4,sockets=2,cores=2,threads=1"
          "-object memory-backend-ram,size=4G,id=m0"
          "-object memory-backend-ram,size=4G,id=m1"
          "-numa node,nodeid=0,cpus=0-1,memdev=m0"
          "-numa node,nodeid=1,cpus=2-3,memdev=m1"
        ]
        else [ ]
      );
    };

  testScript = { ... }: builtins.readFile testScriptFile;
}
