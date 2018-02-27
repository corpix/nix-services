{ config, lib, pkgs, ... }:

with lib;

let
  name = "firewall";
  cfg = config.services."${name}";
in {
  options = with types; {
    services."${name}" = let
      ruleCriteria = submodule ({ ... }: {
        options = {
          ports = mkOption {
            type = listOf int;
            default = [ ];
            example = [ 22 ];
            description = ''
              List of ports to use with this rule.
            '';
          };
          protocols = mkOption {
            type = listOf str;
            default = [ ];
            example = [ "tcp" ];
            description = ''
              List of protocols to use with this rule.
            '';
          };
          interfaces = mkOption {
            type = listOf str;
            default = [ ];
            example = [ "enp3s0" ];
            description = ''
              List of network interfaces to use with this rule.
            '';
          };
        };
      });
    in {
      enable = mkEnableOption "High-level firewall helper service";
      chains = mkOption {
        type = submodule ({ ... }: {
          options = {
            names = mkOption {
              type = listOf str;
              default = [
                "INPUT"
                "FORWARD"
              ];
              description = ''
                List of chains to apply policy for.
              '';
            };

            policy = mkOption {
              type = nullOr str;
              default = "DROP";
              description = ''
                Default policy for chains.
              '';
            };
          };
        });
        default = { };
        example = { policy = "REJECT"; };
        description = ''
          Firewall chains and policy for them.
        '';
      };

      accept = mkOption {
        type = listOf ruleCriteria;
        default = [];
        example = [ { ports = [ 22 ]; protocols = [ "tcp" ]; interfaces = [ "enp3s0" ]; } ];
        description = ''
          List of attrs with port number, protocols and interface to accept.
        '';
      };

      reject = mkOption {
        type = listOf ruleCriteria;
        default = [];
        example = [ { ports = [ 22 ]; protocols = [ "tcp" ]; interfaces = [ "enp3s0" ]; } ];
        description = ''
          List of attrs with port number, protocols and interface to reject traffic on.
        '';
      };

      rejectSilently = mkOption {
        type = listOf ruleCriteria;
        default = [];
        example = [ { ports = [ 22 ]; protocols = [ "tcp" ]; interfaces = [ "enp3s0" ]; } ];
        description = ''
          List of attrs with port number, protocols and interface to reject traffic on without logging.
        '';
      };
    };
  };

  config = with lib; let
    rejectChain = silent:
      if silent
        then "nixos-fw-refuse"
        else "nixos-fw-log-refuse";
    foldRecord = fn: record:
      foldl
        (acc: interfaces:
          foldl
            (acc: protocols:
              foldl
                (acc: ports: acc ++ [ports])
                acc
                protocols)
            acc
            interfaces)
        []
        (map
          (interface: map
            (protocol: map (port: fn port protocol interface) record.ports)
            (attrByPath ["protocols"] [ "tcp" "udp" ] record))
          (attrByPath ["interfaces"] [ "" ] record));
    mkPolicy = policy: chain:
      "ip46tables -P ${chain} ${policy}";
    mkReject = port: protocol: interface: silent:
      "ip46tables -A nixos-fw ${optionalString (interface != "") "-i ${interface}"} -p ${protocol} --dport ${toString port} -j ${rejectChain silent}";
    mkAccept = port: protocol: interface:
      "ip46tables -A nixos-fw ${optionalString (interface != "") "-i ${interface}"} -p ${protocol} --dport ${toString port} -j nixos-fw-accept";
  in mkIf cfg.enable {
    networking.firewall = {
      enable = true;
      extraCommands =
        mkAfter
        (concatStringsSep
          "\n"
          (flatten (
            (map (foldRecord mkAccept) cfg.accept)
            ++ (map (v: map (fn: fn false) (foldRecord mkReject v)) cfg.reject)
            ++ (map (v: map (fn: fn true) (foldRecord mkReject v)) cfg.rejectSilently)
            ++ (
              if cfg.chains.policy != null
              then (map (mkPolicy cfg.chains.policy) cfg.chains.names)
              else []
            ))));
      };
  };
}
