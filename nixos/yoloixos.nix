{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}: {
  imports = [ ./common.nix ];

  networking.hostName = "yoloixos";

  wsl.wslConf.automount.enabled = lib.mkForce false;
  wsl.interop.register = lib.mkForce false;
  wsl.interop.includePath = false;

  users.users = {
    agent = {
      isNormalUser = true;
      shell = pkgs.zsh;
      linger = true;
    };
  };

  systemd.slices."user-1000" = {
    description = "User 1000 (agent) slice";
    sliceConfig = {
      MemoryMax = "4G";
      CPUQuota = "200%";
      TasksMax = 1024;
    };
  };

  networking.firewall.enable = true;
  networking.firewall.extraCommands = ''
    iptables -A OUTPUT -d 169.254.169.254/32 -j DROP
    
    iptables -A OUTPUT -d 10.0.0.0/8 -p tcp --dport 53 -j ACCEPT
    iptables -A OUTPUT -d 10.0.0.0/8 -p udp --dport 53 -j ACCEPT
    iptables -A OUTPUT -d 172.16.0.0/12 -p tcp --dport 53 -j ACCEPT
    iptables -A OUTPUT -d 172.16.0.0/12 -p udp --dport 53 -j ACCEPT
    iptables -A OUTPUT -d 192.168.0.0/16 -p tcp --dport 53 -j ACCEPT
    iptables -A OUTPUT -d 192.168.0.0/16 -p udp --dport 53 -j ACCEPT
    
    iptables -A OUTPUT -d 10.0.0.0/8 -j DROP
    iptables -A OUTPUT -d 172.16.0.0/12 -j DROP
    iptables -A OUTPUT -d 192.168.0.0/16 -j DROP
  '';

  home-manager.users.agent = import ../home/agent.nix;
}
