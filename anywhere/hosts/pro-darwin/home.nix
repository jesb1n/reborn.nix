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

    jq.enable = true;
    htop.enable = true;
  };

  home.packages = with pkgs; [
    fd
    ripgrep
    yq-go
    tree
    kubectl
    kubectx
    opencode
    tailscale
    k9s
    wireguard-tools
    _1password-gui
    firefox
    google-cloud-sdk
    iterm2
    vscode
  ];

  # iTerm2 Dynamic Profile — Dracula theme + JetBrains Mono
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
