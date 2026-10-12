# hosts/pro-darwin/home.nix — home-manager user config for jesbin
{ config, lib, pkgs, ... }:

{
  home = {
    username = "jesbin";
    homeDirectory = lib.mkForce "/Users/jesbin";
    stateVersion = "24.05";
    sessionPath = [ "/opt/homebrew/bin" "/opt/homebrew/sbin" ];
  };

  programs = {
    zsh = {
      enable = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      envExtra = ''
        export PATH="$HOME/.local/bin:$PATH"
        export PATH="$PATH:/Users/jesbin/Library/Python/3.9/bin"
      '';
      history = {
        size = 50000;
        save = 50000;
        ignoreDups = true;
        share = true;
      };
      shellAliases = {
        gs = "git status";
        gd = "git diff";
        gl = "git log --oneline -20";
        k = "kubectl";
        kx = "kubectx";
      };
      initContent = ''
        # kubectl-aliases (https://github.com/ahmetb/kubectl-aliases)
        [ -f ~/.kubectl_aliases ] && source ~/.kubectl_aliases

        # oh-my-zsh git plugin aliases (https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/git)
        [ -f ~/.oh-my-zsh/plugins/git/git.plugin.zsh ] && source ~/.oh-my-zsh/plugins/git/git.plugin.zsh


        # gx: permanently switch gcloud project
        gx() {
          local project
          project=$(gcloud projects list --format='value(projectId)' 2>/dev/null | fzf --prompt='gcloud project> ')
          [ -z "$project" ] && return 0
          if gcloud config set project "$project" 2>/dev/null; then
            echo "Switched to project: $project"
          fi
        }

        # tgx: temporarily switch gcloud project for this shell session only
        tgx() {
          local project
          project=$(gcloud projects list --format='value(projectId)' 2>/dev/null | fzf --prompt='gcloud project (temp)> ')
          [ -z "$project" ] && return 0
          export CLOUDSDK_CORE_PROJECT="$project"
          echo "CLOUDSDK_CORE_PROJECT=$project (session only)"
        }
      '';
    };

    git = {
      enable = true;
      settings = {
        user.name = "jesbinjoseph";
        user.email = "jesbin.joseph@egovernments.org";
        init.defaultBranch = "main";
        pull.rebase = true;
        push.autoSetupRemote = true;
        core.pager = "delta";
        interactive.diffFilter = "delta --color-only";
      };
    };

    bat = {
      enable = true;
      config.theme = "TwoDark";
    };

    delta = {
      enable = true;
      options = {
        navigate = true;
        side-by-side = true;
        line-numbers = true;
      };
    };

    starship = {
      enable = true;
      settings = {
        add_newline = true;
        character = {
          success_symbol = "[❯](bold green)";
          error_symbol = "[❯](bold red)";
        };
      };
    };

    fzf = {
      enable = true;
      enableZshIntegration = true;
    };

    direnv = {
      enable = true;
      nix-direnv.enable = true;
      enableZshIntegration = true;
    };

    jq.enable = true;
    htop.enable = true;
  };

  home.packages = with pkgs; [
    fd
    ripgrep
    yq-go
    tree
    gh
    tmux
    pre-commit
    kubectl
    kubectx
    kubernetes-helm
    # opencode # TEMP: 1.18.4 not cached; local build's smoke test is SIGKILLed on macOS 27 (2026-10-12)
    cloudflared
    k9s
    code-cursor
    firefox
    slack
    google-cloud-sdk
    opentofu
    awscli2
    ssm-session-manager-plugin
    oci-cli
    sops
    iterm2
    # spotify # TEMP: nixpkgs fetches the dmg from web.archive.org at ~70 KB/s (2026-10-12)
    ffmpeg
    k6
  ];

  # iTerm2 Dynamic Profile — Dracula theme + JetBrains Mono
  home.file.".kubectl_aliases".source = builtins.fetchurl {
    # Pinned to a commit: a branch URL breaks the fixed hash whenever upstream changes.
    url = "https://raw.githubusercontent.com/ahmetb/kubectl-aliases/7549fa45bbde7499b927c74cae13bfb9169c9497/.kubectl_aliases";
    sha256 = "sha256:1acyhhhbfxz17ch77nf26x0cj4immsl6drcpwwbklrl49n9gm9ia";
  };

  # oh-my-zsh git plugin — lightweight, single file, no full framework
  home.file.".oh-my-zsh/plugins/git/git.plugin.zsh".source = builtins.fetchurl {
    url = "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/083c339e0622bfc144b66ebf1a2e8dbe7d2ada0d/plugins/git/git.plugin.zsh";
    sha256 = "sha256:1l8kn2q9lc5jm552j08h821jyw4apysdywr30p2ganbq7dhnhig6";
  };

  home.file."Library/Application Support/iTerm2/DynamicProfiles/Nix.json".text = builtins.toJSON {
    Profiles = [
      {
        Name = "Nix";
        "Guid" = "nix-managed-pro-darwin";
        "Normal Font" = "JetBrainsMonoNerdFont-Regular 14";
        "Non Ascii Font" = "JetBrainsMonoNerdFont-Regular 14";
        "Horizontal Spacing" = 1.0;
        "Vertical Spacing" = 1.1;
        "Use Non-ASCII Font" = true;

        "Copy Selection" = true;
        "Silence Bell" = true;
        "Visual Bell" = false;
        "Flashing Bell" = false;
        "Blinking Cursor" = true;
        "Cursor Type" = 2;
        "ASCII Anti Aliased" = true;
        "Non Ascii Anti Aliased" = true;
        "Use Tabular Widths" = true;

        "Scrollback Lines" = 10000;

        "Background Color" = "#282A36FF";
        "Foreground Color" = "#F8F8F2FF";
        "Cursor Color" = "#F8F8F2FF";
        "Cursor Text Color" = "#282A36FF";
        "Selection Color" = "#44475AFF";
        "Selected Text Color" = "#F8F8F2FF";
        "Bold Color" = "#F8F8F2FF";
        "Link Color" = "#8BE9FDFF";

        "Ansi 0 Color" = "#21222CFF";
        "Ansi 1 Color" = "#FF5555FF";
        "Ansi 2 Color" = "#50FA7BFF";
        "Ansi 3 Color" = "#F1FA8CFF";
        "Ansi 4 Color" = "#BD93F9FF";
        "Ansi 5 Color" = "#FF79C6FF";
        "Ansi 6 Color" = "#8BE9FDFF";
        "Ansi 7 Color" = "#F8F8F2FF";
        "Ansi 8 Color" = "#6272A4FF";
        "Ansi 9 Color" = "#FF6E6EFF";
        "Ansi 10 Color" = "#69FF94FF";
        "Ansi 11 Color" = "#FFFFA5FF";
        "Ansi 12 Color" = "#D6ACFFFF";
        "Ansi 13 Color" = "#FF92DFFF";
        "Ansi 14 Color" = "#A4FFFFFF";
        "Ansi 15 Color" = "#FFFFFFFF";
      }
    ];
  };
}
