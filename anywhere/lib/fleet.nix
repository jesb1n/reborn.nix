{
  oracle-eu-micro2 = {
    system = "x86_64-linux";
    role = "agent";
    class = "micro";
    wave = "x86-canary";
    order = 10;
    activationTimeout = 600;
    confirmTimeout = 60;
    remoteBuild = false;
    fastConnection = true;
  };

  oracle-eu-arm1 = {
    system = "aarch64-linux";
    role = "agent";
    class = "arm";
    wave = "arm-canary";
    order = 20;
    activationTimeout = 600;
    confirmTimeout = 60;
    remoteBuild = true;
    fastConnection = false;
  };

  oracle-eu-micro1 = {
    system = "x86_64-linux";
    role = "agent";
    class = "micro";
    wave = "workers";
    order = 30;
    activationTimeout = 600;
    confirmTimeout = 60;
    remoteBuild = false;
    fastConnection = true;
  };

  oracle-in-micro1 = {
    system = "x86_64-linux";
    role = "agent";
    class = "micro";
    wave = "workers";
    order = 40;
    activationTimeout = 600;
    confirmTimeout = 60;
    remoteBuild = false;
    fastConnection = true;
  };

  oracle-in-micro2 = {
    system = "x86_64-linux";
    role = "agent";
    class = "micro";
    wave = "workers";
    order = 50;
    activationTimeout = 600;
    confirmTimeout = 60;
    remoteBuild = false;
    fastConnection = true;
  };

  oracle-in-arm1 = {
    system = "aarch64-linux";
    role = "agent";
    class = "arm";
    wave = "workers";
    order = 60;
    activationTimeout = 600;
    confirmTimeout = 60;
    remoteBuild = true;
    fastConnection = false;
  };

  rpi = {
    system = "aarch64-linux";
    role = "agent";
    class = "rpi";
    wave = "workers";
    order = 70;
    activationTimeout = 900;
    confirmTimeout = 60;
    remoteBuild = true;
    fastConnection = false;
  };

  hp348 = {
    system = "x86_64-linux";
    role = "agent";
    class = "on-prem";
    wave = "workers";
    order = 80;
    activationTimeout = 600;
    confirmTimeout = 60;
    remoteBuild = true;
    fastConnection = true;
  };

  nuc7i3 = {
    system = "x86_64-linux";
    role = "agent";
    class = "on-prem";
    wave = "workers";
    order = 90;
    activationTimeout = 600;
    confirmTimeout = 60;
    remoteBuild = true;
    fastConnection = true;
  };

  s145 = {
    system = "x86_64-linux";
    role = "server";
    class = "on-prem";
    wave = "control-plane";
    order = 100;
    activationTimeout = 600;
    confirmTimeout = 60;
    remoteBuild = true;
    fastConnection = false;
  };
}
