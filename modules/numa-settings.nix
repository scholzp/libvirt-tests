{ lib, config, ... }:

let
  cfg = config.numa-settings;

  profiles = {
    four-numa-nodes = [
       "-smp 4,sockets=4,cores=1,threads=1"
        "-object memory-backend-ram,size=1G,id=m0"
        "-object memory-backend-ram,size=1G,id=m1"
        "-object memory-backend-ram,size=1G,id=m2"
        "-object memory-backend-ram,size=1G,id=m3"
        "-numa node,nodeid=0,cpus=0,memdev=m0"
        "-numa node,nodeid=1,cpus=1,memdev=m1"
        "-numa node,nodeid=2,cpus=2,memdev=m0"
        "-numa node,nodeid=3,cpus=3,memdev=m1"
    ];
    two-numa-nodes = [
       "-smp 4,sockets=2,cores=2,threads=1"
        "-object memory-backend-ram,size=2G,id=m0"
        "-object memory-backend-ram,size=2G,id=m1"
        "-numa node,nodeid=0,cpus=0-1,memdev=m0"
        "-numa node,nodeid=1,cpus=2-3,memdev=m1"
    ];
  };

  enabled = cfg.profile != null;
in
{
  options.numa-settings.profile = lib.mkOption {
    type = lib.types.nullOr (lib.types.enum [ "four-numa-nodes" "two-numa-nodes" ]);
    default = null;
  };

  config = lib.mkIf enabled {
    virtualisation.qemu.options = lib.mkAfter profiles.${cfg.profile};
  };
}

