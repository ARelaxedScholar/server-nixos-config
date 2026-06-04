{
  disko.devices = {
    disk = {
      system = {
        type = "disk";
        # Install thesentry onto the internal HDD identified by its stable WWN path.
        device = "/dev/disk/by-id/wwn-0x50014ee65d825f45";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "zroot";
              };
            };
          };
        };
      };
    };

    zpool.zroot = {
      type = "zpool";
      options.ashift = "12";
      rootFsOptions = {
        acltype = "posixacl";
        atime = "off";
        compression = "zstd";
        mountpoint = "none";
        xattr = "sa";
      };
      datasets = {
        root = {
          type = "zfs_fs";
          mountpoint = "/";
        };
        nix = {
          type = "zfs_fs";
          mountpoint = "/nix";
        };
        home = {
          type = "zfs_fs";
          mountpoint = "/home";
        };
        containers = {
          type = "zfs_fs";
          mountpoint = "/var/lib/containers";
        };
        srv = {
          type = "zfs_fs";
          mountpoint = "/srv";
        };
        backups = {
          type = "zfs_fs";
          mountpoint = "/backups";
        };
      };
    };
  };
}
