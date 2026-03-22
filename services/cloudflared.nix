{ pkgs, ... }:

let
  tokenEnvFile = "/persist/etc/secrets/cloudflared-token.env";
in
{
  environment.systemPackages = [ pkgs.cloudflared ];

  systemd.services.cloudflared = {
    description = "Cloudflare Tunnel";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig.ConditionPathExists = tokenEnvFile;

    serviceConfig = {
      Type = "simple";
      EnvironmentFile = tokenEnvFile;
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate run --token $TUNNEL_TOKEN";
      Restart = "always";
      RestartSec = "5s";
    };
  };
}
