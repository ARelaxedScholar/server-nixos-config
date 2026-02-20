{
disko.devices = {
    disk = {
      os_drive = {
        type = "disk";
        device = "/dev/disk/by-id/ata-SSD_HB202409900900016861"; 
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
            luks_os = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted_os";
                content = {
                  type = "zfs";
                  pool = "zroot";
                };
              };
            };
          };
        };
      };

      data_drive = {
        type = "disk";
        device = "/dev/disk/by-id/ata-ST4000VN006-3CW104_ZW6365MF";
        content = {
          type = "gpt";
          partitions = {
            luks_data = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted_data";
                content = {
                  type = "zfs";
                  pool = "datapool";
                };
              };
            };
          };
        };
      };
    };

    zpool = {
      zroot = {
        type = "zpool";
        rootFsOptions = {
          acltype = "posixacl";
          atime = "off";
          compression = "zstd";
          mountpoint = "none";
          xattr = "sa";
        };
        options.ashift = "12";
        datasets = {
          "root" = {
            type = "zfs_fs";
            mountpoint = "/";
            postCreateHook = "zfs list -t snapshot -H -o name | grep -E '^zroot/root@blank$' || zfs snapshot zroot/root@blank";
          };
          "nix" = {
            type = "zfs_fs";
            mountpoint = "/nix";
          };
          "persist" = {
            type = "zfs_fs";
            mountpoint = "/persist";
          };
        };
      };
      
      datapool = {
        type = "zpool";
        rootFsOptions = {
          acltype = "posixacl";
          atime = "off";
          compression = "zstd";
          mountpoint = "none";
          xattr = "sa";
        };
        options.ashift = "12";
        datasets = {
          "storage" = {
            type = "zfs_fs";
            mountpoint = "/mnt/data"; 
          };
        };
      };
    };
  };
}
