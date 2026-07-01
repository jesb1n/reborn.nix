# profiles/hermes-agent.nix — Hermes Agent gateway with Codex + Google Gemini
#
# Provides the shared `services.hermes-agent` config: native systemd mode,
# OpenAI Codex as the default ChatGPT-OAuth provider, Google Gemini as an
# OpenAI-compatible API-key provider, and the Telegram messaging gateway.
#
# Gating: nothing is enabled until the host's SOPS secrets file exists —
# same pattern as profiles/k3s-server.nix. Hosts that import this profile
# also need to supply `services.hermes-agent.environmentFiles` (typically
# a SOPS template producing Telegram credentials + GOOGLE_API_KEY).
#
# Codex bootstrap (one-time, after first deploy):
#   ssh <host>
#   sudo systemctl status hermes-agent           # confirm unit is up
#   hermes auth add codex-oauth                  # device-code OAuth flow
#   # open the printed URL in a browser, sign in with ChatGPT, paste the code
#   sudo systemctl restart hermes-agent
#
# Depends on the upstream NixOS module from inputs.hermes-agent.nixosModules.default,
# which is wired in at flake.nix for hosts that need it.
{ lib, ... }:

let
  hostSecretsFile = ../secrets/oracle-eu-arm1/secrets.yaml;
  hasHostSecretsFile = builtins.pathExists hostSecretsFile;
in
{
  services.hermes-agent = lib.mkIf hasHostSecretsFile {
    enable = true;

    # Install `hermes` on system PATH and export HERMES_HOME so interactive
    # shells share state (auth.json, sessions, skills) with the gateway.
    addToSystemPackages = true;

    # Declarative config.yaml. Nix-managed keys win during the activation-time
    # deep merge, while unrelated user-saved settings are preserved.
    settings = {
      providers = {
        # Google Gemini's OpenAI-compatible endpoint. The API key is supplied
        # through the host SOPS-rendered environment file as GOOGLE_API_KEY.
        google = {
          name = "Google Gemini";
          base_url = "https://generativelanguage.googleapis.com/v1beta/openai/";
          key_env = "GOOGLE_API_KEY";
          default_model = "gemini-3.5-flash";
          models = [
            "gemini-3.5-flash"
          ];
          discover_models = false;
        };
      };

      model = {
        # Keep Codex as the default provider. Google Gemini is available in
        # the picker as the replacement for the old NVIDIA endpoint.
        provider = "openai-codex";
        default = "gpt-5.5";
      };

      # Run shell tools directly on the host. The systemd unit is hardened
      # (NoNewPrivileges, ProtectSystem=strict, ReadWritePaths restricted),
      # so the agent can only write under /var/lib/hermes/. For stronger
      # isolation, switch to terminal.backend = "docker" later.
      terminal.backend = "local";
    };
  };

  # Let `duck` run `hermes` against the service's HERMES_HOME without sudo.
  # The state dir is mode 2770 (setgid), so group members inherit access.
  # Gated on the same condition as the service itself — the `hermes` group
  # is only created when services.hermes-agent.enable is true.
  users.users.duck.extraGroups = lib.mkIf hasHostSecretsFile [ "hermes" ];
}
