# sops-nix：开机（以及每次切换配置）时把 secrets/hub.yaml 解密到 /run/secrets（内存文件系统，不落盘）。
# 解密用的是 ssh 主机密钥；迁移到 NixOS 时沿用原 Debian 的 /etc/ssh/ssh_host_ed25519_key，
# 所以 .sops.yaml 里 hub 的接收方不用改，各设备记录的 ssh 主机指纹也不会变。
{ ... }:

{
  sops = {
    defaultSopsFile = ../../secrets/hub.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    # 不使用 gpg
    gnupg.sshKeyPaths = [ ];
  };
}
