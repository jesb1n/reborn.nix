{ pkgs, lib, ... }:

{
  home = {
    username = "duck";
    homeDirectory = lib.mkForce "/Users/duck";
    stateVersion = "26.11";
    sessionPath = [ "/opt/homebrew/bin" ];
  };

  programs = {
    zsh = {
      enable = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      oh-my-zsh = {
        enable = true;
        plugins = [ "git" ];
      };
      plugins = [
        {
          name = "powerlevel10k";
          src = pkgs.zsh-powerlevel10k;
          file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
        }
      ];
      history = {
        size = 50000;
        save = 50000;
      };
      shellAliases = {
        gs = "git status";
        gd = "git diff";
        gl = "git log --oneline -20";
        k = "kubectl";
        kx = "kubectx";
        brewup = "brew update && brew upgrade --greedy";
      };
      initContent = ''
        source ~/.p10k.zsh
        source ~/.kubectl_aliases
      '';
    };

    git = {
      enable = true;
      settings = {
        user.name = "jesb1n";
        user.email = "joseph@jesb.in";
        init.defaultBranch = "main";
        pull.rebase = true;
        push.autoSetupRemote = true;
      };
    };

    ssh = {
      enable = true;
      enableDefaultConfig = false;
      includes = [ "~/.orbstack/ssh/config" ];
      settings.s145 = {
        HostName = "s145.panther-company.ts.net";
        User = "duck";
      };
    };

    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    fzf.enable = true;
    jq.enable = true;
    htop.enable = true;
  };

  home.packages = with pkgs; [
    age
    ffmpeg
    gh
    k9s
    kubectl
    kubectx
    kubernetes-helm
    oci-cli
    opencode
    opentofu
    pre-commit
    sops
    tree
  ];

  home.file = {
    ".p10k.zsh".text = ''
      source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/config/p10k-lean.zsh
      typeset -g POWERLEVEL9K_CONFIG_FILE=~/.p10k.zsh
      typeset -g POWERLEVEL9K_INSTANT_PROMPT=off

      typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(os_icon $POWERLEVEL9K_LEFT_PROMPT_ELEMENTS)
      POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS+=(time)
      typeset -g POWERLEVEL9K_TIME_FORMAT='%D{%I:%M:%S %p}'
      typeset -g POWERLEVEL9K_TRANSIENT_PROMPT=always

      typeset -g POWERLEVEL9K_RULER_FOREGROUND=242
      typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_FOREGROUND=242
      typeset -g POWERLEVEL9K_VCS_BRANCH_ICON=' '
      typeset -g POWERLEVEL9K_BATTERY_STAGES=(
        $'' $'' $'' $'' $'' $''
        $'' $'' $'' $'' $''
      )

      typeset -g POWERLEVEL9K_VCS_PREFIX='%fon '
      typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_PREFIX='%ftook '
      typeset -g POWERLEVEL9K_CONTEXT_PREFIX='%fwith '
      typeset -g POWERLEVEL9K_KUBECONTEXT_PREFIX='%fat '
      typeset -g POWERLEVEL9K_TOOLBOX_PREFIX='%fin '
      typeset -g POWERLEVEL9K_TIME_PREFIX='%fat '
    '';

    ".kubectl_aliases".source = builtins.fetchurl {
      url = "https://raw.githubusercontent.com/ahmetb/kubectl-aliases/7549fa45bbde7499b927c74cae13bfb9169c9497/.kubectl_aliases";
      sha256 = "sha256:1acyhhhbfxz17ch77nf26x0cj4immsl6drcpwwbklrl49n9gm9ia";
    };
  };
}
