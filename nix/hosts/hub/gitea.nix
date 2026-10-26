# gitea：只对 tailnet 提供（tailscale serve：网页 /gitea，ssh tcp 10022），本身只监听 127.0.0.1。
#
# 数据目录 /var/lib/gitea 是数据盘的 bind mount（见 data.nix），布局沿用原来的 rootless 镜像：
#   git/repositories、git/lfs、data/gitea.db、data/{sessions,avatars,attachments,log}、ssh/（内置 ssh 服务的主机密钥）等。
# 所以这里把各路径显式设成原来的位置，APP_DATA_PATH 也是 /var/lib/gitea 本身（模块默认是 data/ 子目录）。
#
# 密钥：模块把 SECRET_KEY 等放在 custom/conf/ 下的文件里，文件不存在时才生成。
# SECRET_KEY 加密了数据库中的 2FA 等字段，必须沿用原值，所以这些文件由 sops-nix 提供（值在 secrets/hub.yaml）：
# 解密到 /run/secrets/gitea/，gitea 启动前（在模块的生成逻辑之前）链接到 custom/conf/。
# 不直接让 sops-nix 写到 custom/conf/：sops-nix 在系统激活时放置文件，而数据盘的 bind mount 在之后才挂上，
# 文件会落在被盖住的系统盘目录里，gitea 看不到就会生成新的密钥。
{ config, lib, ... }:

let
  stateDir = "/var/lib/gitea";
  domain = "hub.angora-wall.ts.net";
  cfg = config.services.gitea;
  secretFiles = {
    "gitea/secret-key" = "secret_key";
    "gitea/internal-token" = "internal_token";
    "gitea/oauth2-jwt-secret" = "oauth2_jwt_secret";
    "gitea/lfs-jwt-secret" = "lfs_jwt_secret";
  };
in
{
  sops.secrets = lib.mapAttrs (_: _: {
    owner = cfg.user;
    restartUnits = [ "gitea.service" ];
  }) secretFiles;

  services.gitea = {
    enable = true;
    inherit stateDir;
    appName = "Gitea: Git with a cup of tea";
    repositoryRoot = "${stateDir}/git/repositories";
    database = {
      type = "sqlite3";
      path = "${stateDir}/data/gitea.db";
    };
    lfs = {
      enable = true;
      contentDir = "${stateDir}/git/lfs";
    };

    settings = {
      server = {
        DOMAIN = domain;
        ROOT_URL = "https://${domain}/gitea/";
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = 8083;
        APP_DATA_PATH = stateDir;
        OFFLINE_MODE = true;
        # 内置 ssh 服务（不依赖系统 sshd）：只监听本机，由 tailscale serve 的 tcp 10022 对 tailnet 开放；
        # 克隆地址里的用户名保持 git（git@gitea:user/repo.git）
        START_SSH_SERVER = true;
        BUILTIN_SSH_SERVER_USER = "git";
        SSH_DOMAIN = domain;
        SSH_PORT = 10022;
        SSH_LISTEN_HOST = "127.0.0.1";
        SSH_LISTEN_PORT = 10022;
      };
      session = {
        PROVIDER = "file";
        PROVIDER_CONFIG = "${stateDir}/data/sessions";
      };
      picture = {
        AVATAR_UPLOAD_PATH = "${stateDir}/data/avatars";
        REPOSITORY_AVATAR_UPLOAD_PATH = "${stateDir}/data/repo-avatars";
      };
      attachment.PATH = "${stateDir}/data/attachments";
      log = {
        ROOT_PATH = "${stateDir}/data/log";
        # 日志进 journald
        MODE = "console";
        LEVEL = "Info";
      };
      security = {
        INSTALL_LOCK = true;
        PASSWORD_HASH_ALGO = "pbkdf2";
        # 请求都经本机的 tailscale serve 转发过来，只信任本机给出的 X-Forwarded-For
        REVERSE_PROXY_LIMIT = 1;
        REVERSE_PROXY_TRUSTED_PROXIES = "127.0.0.0/8,::1/128";
      };
      service = {
        DISABLE_REGISTRATION = true;
        REQUIRE_SIGNIN_VIEW = false;
        REGISTER_EMAIL_CONFIRM = false;
        ENABLE_NOTIFY_MAIL = false;
        ALLOW_ONLY_EXTERNAL_REGISTRATION = false;
        ENABLE_CAPTCHA = false;
        DEFAULT_KEEP_EMAIL_PRIVATE = false;
        DEFAULT_ALLOW_CREATE_ORGANIZATION = true;
        DEFAULT_ENABLE_TIMETRACKING = true;
        # 沿用原值：已有提交里的隐藏邮箱用的是这个域名
        NO_REPLY_ADDRESS = "noreply.166.111.238.16";
      };
      openid = {
        ENABLE_OPENID_SIGNIN = true;
        ENABLE_OPENID_SIGNUP = true;
      };
      mailer.ENABLED = false;
      "cron.update_checker".ENABLED = false;
      "repository.pull-request".DEFAULT_MERGE_STYLE = "merge";
      "repository.signing".DEFAULT_TRUST_MODEL = "committer";
    };
  };

  systemd.services.gitea = {
    # 数据盘没挂上时不启动（见 data.nix）
    unitConfig.RequiresMountsFor = [ stateDir ];
    preStart = lib.mkBefore (lib.concatStrings (lib.mapAttrsToList (name: file: ''
      ln -sfn ${config.sops.secrets.${name}.path} ${cfg.customDir}/conf/${file}
    '') secretFiles));
  };
}
