{ pkgs ? import <nixpkgs> { }
, pkgsLinux ? import <nixpkgs> { system = "x86_64-linux"; }
}:
let
  startScript = pkgs.writeScriptBin "start-services" ''
    #!/bin/bash
    set -e
    
    # Create necessary directories
    mkdir -p /tmp/runtime
    
    # Start pipewire (will use host's D-Bus via socket)
    ${pkgs.pipewire}/bin/pipewire &
    
    # Keep container running
    pw-jack scsynth -u 57110 &
    sleep 2
    pw-jack sclang server.scd
  '';
in
pkgs.dockerTools.buildImage {
  name = "yassinsiouda/akm-server";
  tag = "latest";
  config = {
    Cmd = [ "${pkgs.bash}/bin/bash" "${startScript}/bin/start-services" ];
    Env = [
      "XDG_RUNTIME_DIR=/run/user/1000"
      "PIPEWIRE_RUNTIME_DIR=/run/user/1000"
      "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
      "DISABLE_RTKIT=y"
      "QT_QPA_PLATFORM=offscreen"
    ];
  };
  contents = with pkgs; [
    bash
    uutils-coreutils-noprefix
    supercollider-with-plugins
    pipewire
    pipewire.jack 
    wireplumber
    startScript
  ];
  runAsRoot = ''
    #!${pkgs.runtimeShell}
    mkdir -p /run/user/1000
    chmod 700 /run/user/1000
    cp ${./akM_spatServer.scd} /server.scd
  '';
}
