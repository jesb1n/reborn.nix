# hosts/oracle-eu-arm1/sops.nix — Secret declarations for the ARM control-plane.
#
# This follows the same pattern as retire.nix:
# - generate a dedicated age key on the host
# - keep the host private key at /var/lib/sops-nix/key.txt
# - commit only encrypted secrets under secrets/oracle-eu-arm1/
#
# Generate on the host:
#   sudo mkdir -p /var/lib/sops-nix
#   sudo age-keygen -o /var/lib/sops-nix/key.txt
#   sudo chmod 600 /var/lib/sops-nix/key.txt
#
# Then add the PUBLIC age key to .sops.yaml as &oracle_eu_arm1.
{ config, lib, ... }:

let
  clusterSecretsFile = ../../secrets/k3s/secrets.yaml;
  hasClusterSecretsFile = builtins.pathExists clusterSecretsFile;
  tailscaleSecretsFile = ../../secrets/tailscale/secrets.yaml;
  hasTailscaleSecretsFile = builtins.pathExists tailscaleSecretsFile;
  hostSecretsFile = ../../secrets/oracle-eu-arm1/secrets.yaml;
  hasHostSecretsFile = builtins.pathExists hostSecretsFile;
in
{
  sops = {
    age.keyFile = "/var/lib/sops-nix/key.txt";
    age.generateKey = false;
    age.sshKeyPaths = [ ];

    defaultSopsFormat = "yaml";

    secrets = lib.mkMerge [
      # Tailscale pre-auth key for joining the tailnet on activation/boot.
      # Decrypted by sops-nix to /run/secrets/tailscale-auth-key.
      (lib.mkIf hasTailscaleSecretsFile {
        "tailscale-auth-key" = {
          sopsFile = tailscaleSecretsFile;
        };
      })

      (lib.mkIf hasClusterSecretsFile {
        # Shared k3s cluster token used by the server and tiny worker agents.
        "k3s-token" = {
          sopsFile = clusterSecretsFile;
        };
      })

      # Hermes Agent — Telegram gateway credentials.
      # The values themselves are tiny but secret-grade (a bot token grants
      # full control of the bot; the allowed-users list reveals operator IDs;
      # the Google key authorizes Gemini API usage.
      (lib.mkIf hasHostSecretsFile {
        "hermes/telegram-bot-token" = {
          sopsFile = hostSecretsFile;
        };

        "hermes/telegram-allowed-users" = {
          sopsFile = hostSecretsFile;
        };

        "hermes/google-api-key" = {
          sopsFile = hostSecretsFile;
        };
      })
    ];

    # Compose the SOPS-decrypted values into a KEY=VALUE file that the
    # hermes-agent module merges into $HERMES_HOME/.env at activation time.
    templates = lib.mkIf hasHostSecretsFile {
      "hermes-agent.env" = {
        owner = "hermes";
        group = "hermes";
        mode = "0640";
        content = ''
          TELEGRAM_BOT_TOKEN=${config.sops.placeholder."hermes/telegram-bot-token"}
          TELEGRAM_ALLOWED_USERS=${config.sops.placeholder."hermes/telegram-allowed-users"}
          GOOGLE_API_KEY=${config.sops.placeholder."hermes/google-api-key"}
        '';
      };
    };
  };
}
