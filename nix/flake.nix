{
  description = "envkit：各主机的 NixOS 配置（目前只有 hub）";

  inputs = {
    # 稳定分支；升级时改这里，再执行 nix flake update
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # 少数需要比稳定分支更新版本的软件包（通过 pkgs.unstable.<名字> 使用）
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    # 树莓派 4 的硬件支持（设备树、固件等）
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    # nixos-hardware 自带的 nixpkgs 只用于它自己的检查，这里统一用我们的，避免多下载一份
    nixos-hardware.inputs.nixpkgs.follows = "nixpkgs";
    # 密钥管理：仓库里存 sops 加密的 secrets/*.yaml，开机时用主机的 ssh 密钥解密到 /run/secrets
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, nixos-hardware, sops-nix, ... }:
    let
      # 自定义软件包，所有主机共用
      overlay = final: prev: {
        auth-thu = final.callPackage ./pkgs/auth-thu.nix { };
        sing-box = final.callPackage ./pkgs/sing-box.nix { };
        sing-box-rule-sets = final.callPackage ./pkgs/sing-box-rule-sets.nix { };
        sing-box-update-nodes = final.callPackage ./pkgs/sing-box-update-nodes { };
        corplink-base-image = final.callPackage ./pkgs/corplink/base-image.nix { };
        corplink-service = final.callPackage ./pkgs/corplink/service.nix { };
        corplink-headless = final.callPackage ./pkgs/corplink/headless.nix { };
        corplink-image = final.callPackage ./pkgs/corplink { };
        unstable = import nixpkgs-unstable {
          inherit (final.stdenv.hostPlatform) system;
        };
      };
    in
    {
      overlays.default = overlay;

      # sing-box 配置函数库（各角色共用规则，见 lib/sing-box.nix）
      lib.singBox = import ./lib/sing-box.nix { inherit (nixpkgs) lib; };

      # 构建时检查（nix flake check）：用假的密钥和节点渲染各角色的 sing-box 配置，跑 sing-box check。
      # 字段写错、引用了不存在的出站等问题在部署前就能发现；hub 启动 sing-box 前还会用真实配置再检查一次
      checks.aarch64-linux.sing-box-configs =
        let
          pkgs = nixpkgs.legacyPackages.aarch64-linux.extend overlay;
          inherit (nixpkgs) lib;
          singBox = self.lib.singBox;
          # 和 sing-box-update-nodes 生成的分组同名，每组只放一个假节点
          groups = [ "proxy" "proxy-ai" "fastest" "fastest_in_hmt" "fastest_in_asia" "fastest_in_americas"
                     "fixed_ip" "proxy_by_hmt" "proxy_by_asia" "proxy_by_americas" ];
          dummyOutbounds = map (tag: { inherit tag; type = "selector"; outbounds = [ "dummy-node" ]; }) groups ++ [{
            tag = "dummy-node"; type = "trojan"; server = "192.0.2.1"; server_port = 443; password = "dummy";
          }];
          nodes = lib.removePrefix "[" (lib.removeSuffix "]" (builtins.toJSON dummyOutbounds));
          secrets = { clashApiSecret = "dummy"; tailnetGatewayUser = "dummy"; tailnetGatewayPassword = "dummy"; };
          render = role: pkgs.writeText "${role}.json" (singBox.toTemplate {
            inherit role secrets nodes;
            ruleSetDir = pkgs.sing-box-rule-sets;
          });
        in
        pkgs.runCommand "sing-box-configs-check" { } ''
          ${lib.concatMapStrings (role: ''
            echo "checking ${role}"
            ${pkgs.sing-box}/bin/sing-box check -c ${render role}
          '') (builtins.attrNames singBox.roles)}
          touch $out
        '';

      # 管理命令（在 hub 上、nix/ 目录下运行）：
      #   nix run .#sing-box-update-nodes -- [--url URL | --file PATH | --stored]  更新机场节点
      apps.aarch64-linux =
        let pkgs = nixpkgs.legacyPackages.aarch64-linux.extend overlay;
        in {
          sing-box-update-nodes = {
            type = "app";
            program = "${pkgs.sing-box-update-nodes}/bin/sing-box-update-nodes";
          };
        };

      # hub：树莓派 4，负责校园网认证、飞连、sing-box 网关和各项自托管服务
      # 构建：nix build .#nixosConfigurations.hub.config.system.build.toplevel
      nixosConfigurations.hub = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          nixos-hardware.nixosModules.raspberry-pi-4
          sops-nix.nixosModules.sops
          { nixpkgs.overlays = [ overlay ]; }
          ./hosts/hub
        ];
      };
    };
}
