# profiles/hermes-agent.nix — Hermes Agent gateway with Codex (ChatGPT OAuth)
#
# Provides the shared `services.hermes-agent` config: native systemd mode,
# OpenAI Codex as the LLM provider (device-code OAuth, no API key), and
# the Telegram messaging gateway.
#
# Gating: nothing is enabled until the host's SOPS secrets file exists —
# same pattern as profiles/k3s-server.nix. Hosts that import this profile
# also need to supply `services.hermes-agent.environmentFiles` (typically
# a SOPS template producing TELEGRAM_BOT_TOKEN + TELEGRAM_ALLOWED_USERS).
#
# Bootstrap (one-time, after first deploy):
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

    # Declarative config.yaml. The module deep-merges this with anything the
    # user has saved interactively via `hermes model` / `hermes config set`,
    # so OAuth-flow side effects are preserved across deploys.
    settings = {
      model = {
        # `openai-codex` is the ChatGPT-OAuth provider — uses Codex models
        # against the user's ChatGPT Plus/Pro/Team subscription.
        provider = "openai-codex";
        # Default model. ChatGPT-OAuth surfaces base GPT models alongside the
        # `*-codex` specialty variants; if you want a Codex-tuned model
        # instead, change to e.g. "gpt-5-codex" or "gpt-5.3-codex" (latest
        # Codex variant as of June 2026). Override interactively any time
        # with `hermes model` or `/model <name>` mid-session.
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

