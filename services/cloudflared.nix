{ pkgs, ... }:

let
  tunnelId = "9e22ebf2-d0bc-48e9-be09-1c1f8d29e66f";
  configFile = "/etc/cloudflared/config.yml";
  credentialsFile = "/persist/etc/cloudflared/remote-engine.json";
in
{
  environment.systemPackages = [ pkgs.cloudflared ];

  environment.etc."cloudflared/config.yml".text = ''
    tunnel: ${tunnelId}
    credentials-file: ${credentialsFile}

    ingress:
      - hostname: engine.swagwatch.app
        service: http://127.0.0.1:3001
      - service: http_status:404
  '';

  systemd.services.cloudflared = {
    description = "Cloudflare Tunnel";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig.ConditionPathExists = credentialsFile;

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --config ${configFile} --no-autoupdate run";
      Restart = "always";
      RestartSec = "5s";
    };
  };
}
