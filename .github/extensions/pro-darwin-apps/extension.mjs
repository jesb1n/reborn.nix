// Extension: pro-darwin-apps
// Shared workspace helper for planning pro-darwin app installs without applying them.

import { joinSession } from "@github/copilot-sdk/extension";

const MANUAL_ONLY_PATTERNS = [
    { pattern: /xirp/i, reason: "Beta DMG installer with no stable declarative package source." },
];

const HOMEBREW_CASKS = new Map([
    ["arc", "Removed from nixpkgs (unmaintained)."],
    ["chatgpt", "Official desktop app is not supported in nixpkgs."],
    ["cloudflare-warp", "Needs macOS Network Extension entitlements."],
    ["docker-desktop", "Requires macOS system extensions and is not available in nixpkgs."],
    ["github-copilot-app", "GitHub Copilot desktop app is not in nixpkgs."],
    ["handy", "Not in nixpkgs; relies on macOS permissions and entitlements."],
    ["lens", "Proprietary app not packaged usefully in nixpkgs for macOS."],
    ["loom", "Not in nixpkgs; relies on macOS permissions and entitlements."],
    ["maccy", "Not in nixpkgs."],
    ["tailscale-app", "Needs macOS Network Extension entitlements."],
    ["visual-studio-code", "nixpkgs vscode has recurring build failures; Homebrew cask is the repo fallback."],
    ["warp", "Marked broken in nixpkgs."],
    ["whatsapp", "macOS app not in nixpkgs."],
]);

const MAS_APPS = new Map([
    ["bitwarden", { id: 1352778147, reason: "MAS version avoids the insecure nixpkgs desktop package." }],
    ["wireguard", { id: 1451685025, reason: "GUI VPN client is intentionally managed through the Mac App Store." }],
]);

const HOME_PACKAGES = new Set([
    "fd",
    "ripgrep",
    "yq-go",
    "tree",
    "gh",
    "tmux",
    "kubectl",
    "kubectx",
    "kubernetes-helm",
    "opencode",
    "tailscale",
    "k9s",
    "code-cursor",
    "firefox",
    "slack",
    "google-cloud-sdk",
    "opentofu",
    "awscli2",
    "oci-cli",
    "sops",
    "iterm2",
    "spotify",
    "ffmpeg",
    "k6",
  ]);

const SYSTEM_PACKAGES = new Set(["1password", "1password-gui", "_1password-gui"]);

const PACKAGE_ALIASES = new Map([
    ["node", { packageName: "nodejs", reason: "`node` is provided by the `nodejs` package in nixpkgs." }],
    ["nodejs", { packageName: "nodejs", reason: "Use the canonical nixpkgs package name." }],
    ["npm", { packageName: "nodejs", reason: "`npm` ships with `nodejs` in nixpkgs, so install `nodejs` instead of a standalone `npm` package." }],
    ["session-manager-plugin", { packageName: "ssm-session-manager-plugin", reason: "nixpkgs exposes the AWS Session Manager plugin as `ssm-session-manager-plugin`." }],
    ["sessionmanagerplugin", { packageName: "ssm-session-manager-plugin", reason: "nixpkgs exposes the AWS Session Manager plugin as `ssm-session-manager-plugin`." }],
    ["aws-session-manager-plugin", { packageName: "ssm-session-manager-plugin", reason: "nixpkgs exposes the AWS Session Manager plugin as `ssm-session-manager-plugin`." }],
]);

function normalizeAppName(name) {
    return String(name || "")
        .trim()
        .toLowerCase()
        .replace(/\.app$/, "")
        .replace(/\s+/g, "-");
}

function renderNixSnippet(appName, target) {
    if (target === "home.packages") {
        return `Add \`${appName}\` to \`home.packages\` in \`anywhere/hosts/pro-darwin/home.nix\`.`;
    }
    return `Add \`${appName}\` to \`environment.systemPackages\` in \`anywhere/hosts/pro-darwin/darwin-configuration.nix\`.`;
}

function classifyInstall(appName, preferredSource) {
    const normalized = normalizeAppName(appName);
    const source = normalizeAppName(preferredSource || "");
    const alias = PACKAGE_ALIASES.get(normalized);
    const effectiveName = alias?.packageName || appName;
    const effectiveNormalized = normalizeAppName(effectiveName);

    for (const entry of MANUAL_ONLY_PATTERNS) {
        if (entry.pattern.test(normalized)) {
            return {
                method: "manual",
                reason: entry.reason,
                files: [],
                change: "Do not encode this in nix-darwin yet; use the vendor installer manually and revisit once a stable cask or nixpkgs package exists.",
            };
        }
    }

    if (MAS_APPS.has(effectiveNormalized)) {
        const mas = MAS_APPS.get(effectiveNormalized);
        return {
            method: "mas",
            reason: mas.reason,
            files: ["anywhere/hosts/pro-darwin/darwin-configuration.nix"],
            change: `Add \"${effectiveName}\" = ${mas.id}; to \`homebrew.masApps\` in \`anywhere/hosts/pro-darwin/darwin-configuration.nix\`.`,
        };
    }

    if (HOMEBREW_CASKS.has(effectiveNormalized) || source === "homebrew" || source === "cask") {
        return {
            method: "homebrew-cask",
            reason: HOMEBREW_CASKS.get(effectiveNormalized) || "Homebrew cask requested explicitly.",
            files: ["anywhere/hosts/pro-darwin/darwin-configuration.nix"],
            change: `Add \"${effectiveNormalized}\" to \`homebrew.casks\` in \`anywhere/hosts/pro-darwin/darwin-configuration.nix\`.`,
        };
    }

    if (SYSTEM_PACKAGES.has(effectiveNormalized) || source === "system") {
        const pkg = effectiveNormalized === "1password" || effectiveNormalized === "1password-gui" ? "pkgs._1password-gui" : effectiveName;
        return {
            method: "nix-system-package",
            reason: "System-level GUI app belongs in `environment.systemPackages`.",
            files: ["anywhere/hosts/pro-darwin/darwin-configuration.nix"],
            change: renderNixSnippet(pkg, "environment.systemPackages"),
        };
    }

    return {
        method: "nix-home-package",
        reason: alias?.reason || (HOME_PACKAGES.has(effectiveNormalized)
            ? "Already follows the `home.packages` convention in this repo."
            : "Repo policy prefers Nix first for CLI tools and most user-scoped apps unless `AGENTS.md` says otherwise."),
        files: ["anywhere/hosts/pro-darwin/home.nix"],
        change: renderNixSnippet(effectiveName, "home.packages"),
    };
}

function buildResponse(args) {
    const appName = String(args.appName || "").trim();
    if (!appName) {
        return {
            textResultForLlm: "Missing `appName`. Provide the app or package name to plan a pro-darwin install.",
            resultType: "failure",
        };
    }

    const classification = classifyInstall(appName, args.preferredSource);
    const fileList = classification.files.length ? classification.files.map((file) => `- \`${file}\``).join("\n") : "- None";

    const notes = [
        `Install method: ${classification.method}`,
        `Why: ${classification.reason}`,
        "Target files:",
        fileList,
        `Suggested change: ${classification.change}`,
        "Validation: `cd anywhere && nix flake check`",
        "Safety: planning/code changes only — do not install the app or run `darwin-rebuild` automatically.",
    ];

    if (args.preferredSource) {
        notes.splice(1, 0, `Requested source: ${args.preferredSource}`);
    }

    return {
        textResultForLlm: notes.join("\n"),
        resultType: "success",
    };
}

const session = await joinSession({
    hooks: {
        onUserPromptSubmitted: async (input) => {
            if (/install .*pro-darwin|pro-darwin.*install/i.test(input.prompt)) {
                return {
                    additionalContext:
                        "For pro-darwin app installation requests, first call the `plan_pro_darwin_app_install` tool. Use its output to keep recommendations provider-agnostic, repo-aligned, and planning-only.",
                };
            }
        },
    },
    tools: [
        {
            name: "plan_pro_darwin_app_install",
            description: "Plans how to add an app or package to pro-darwin using repo rules. Returns rationale, target files, and suggested edits without installing or applying anything.",
            parameters: {
                type: "object",
                properties: {
                    appName: {
                        type: "string",
                        description: "App or package name to add for pro-darwin, such as tmux, arc, Bitwarden, or Xirp.",
                    },
                    preferredSource: {
                        type: "string",
                        description: "Optional hint like nix, homebrew, cask, mas, system, or manual.",
                    },
                },
                required: ["appName"],
            },
            handler: async (args) => buildResponse(args),
        },
    ],
});

await session.log("pro-darwin-apps extension loaded", { ephemeral: true });
