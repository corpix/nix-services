{ config, lib, pkgs, ... }:

with builtins;
with lib;

let
  name = "infotty";
  cfg = config.services."${name}";
in {
  options = with types; {
    services."${name}" = {
      enable = mkEnableOption "Reports information about host.";
      tty = mkOption {
        type = int;
        default = 12;
        description = ''
          TTY number to show information on.
        '';
      };
      interval = mkOption {
        type = str;
        default = "60s";
        description = ''
          Pause between information updates.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    systemd.services.infotty = {
      enable = true;
      description = "report system information to specified TTY";
      wantedBy = [ "multi-user.target" ];
      script = with pkgs; ''
        export PATH=${makeBinPath [ systemd coreutils findutils eject openssh osquery nettools ]}

        while true
        do
          # Clear sequence
          echo -e '\033\0143'

          hostname --long
          echo

          echo Network interface details:
          # Errors dev/null'ed because of this shit:
          # I0227 00:22:06.202585 16250 init.cpp:612] Cannot start extension manager: Extensions disabled
          # It does not react to --disable_extensions or --disable_kernel flags, so fuck it
          osqueryi 'select interface, mac, mtu from interface_details;' 2> /dev/null

          echo
          echo Network interface addresses:
          osqueryi 'select interface, address, mask from interface_addresses;' 2> /dev/null

          echo
          echo Host SSH keys fingerprints:
          ls /etc/ssh/ssh_host_*.pub | xargs -I'{}' ssh-keygen -E sha256 -lf '{}' | column -t

          echo
          echo Failed systemd units:
          systemctl list-units --state=failed

          echo
          echo -n 'Generated at(updates every ${cfg.interval}): '
          date
          uptime

          sleep ${cfg.interval}
        done > /dev/tty${toString cfg.tty} 2>&1
      '';
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        NoNewPrivileges = "yes";
      };
    };
  };
}
