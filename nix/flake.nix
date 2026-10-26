{
  description = "envkit：各主机的 NixOS 配置（目前只有 hub）";

  inputs = {
    # 稳定分支；升级时改这里，再执行 nix flake update
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # 树莓派 4 的硬件支持（设备树、固件等）
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    # nixos-hardware 自带的 nixpkgs 只用于它自己的检查，这里统一用我们的，避免多下载一份
    nixos-hardware.inputs.nixpkgs.follows = "nixpkgs";
    # 密钥管理：仓库里存 sops 加密的 secrets/*.yaml，开机时用主机的 ssh 密钥解密到 /run/secrets
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nixos-hardware, sops-nix, ... }:
    let
      # 自定义软件包，所有主机共用
      overlay = final: prev: {
        auth-thu = final.callPackage ./pkgs/auth-thu.nix { };
      };
    in
    {
      overlays.default = overlay;

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
