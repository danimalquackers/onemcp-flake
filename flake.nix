{
  description = "A flake for building and running the 1MCP agent";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      home-manager,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        packages.default = pkgs.stdenv.mkDerivation rec {
          pname = "1mcp-agent";
          version = "0.29.0-beta7";

          # Fetch by tag from GitHub
          src = pkgs.fetchFromGitHub {
            owner = "1mcp-app";
            repo = "agent";
            rev = "v${version}";
            hash = "sha256-WgdOSmckr3K+VwIJrkCFFUAxa70EssX3I/DeaO7CEfc=";
          };

          pnpmDeps = pkgs.fetchPnpmDeps {
            inherit (self.packages.${system}.default) pname version src;
            fetcherVersion = 3;
            hash = "sha256-nVmKnqvS36EXIUlAi2xMysMoANpWVQAkc4pQJzcdH2w=";
          };

          nativeBuildInputs = with pkgs; [
            # Runtime
            nodejs_22
            pnpm

            # Build tools
            pnpmConfigHook

            # Nix utilities
            makeWrapper
          ];

          buildPhase = ''
            runHook preBuild

            pnpm install --frozen-lockfile
            pnpm build

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            # Copy to insstallation directory
            mkdir -p $out/bin $out/lib
            cp -r build $out/lib/
            cp -r node_modules $out/lib/

            # Generate a wrapper script to call Node
            makeWrapper ${pkgs.nodejs_22}/bin/node $out/bin/1mcp \
              --add-flags "$out/lib/build/index.js"

            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "A unified Model Context Protocol server implementation that aggregates multiple MCP servers into one";
            homepage = "https://github.com/1mcp-app/agent";
            license = licenses.asl20;
            maintainers = with maintainers; [ ];
          };
        };

        checks = {
          version =
            pkgs.runCommand "verify-version"
              {
                buildInputs = [ self.packages.${system}.default ];
              }
              ''
                1mcp --help > $out
              '';

          moduleTest = pkgs.testers.nixosTest {
            name = "1mcp-module-test";
            nodes.machine =
              { pkgs, lib, ... }:
              {
                imports = [ home-manager.nixosModules.home-manager ];

                users.users.testuser = {
                  isNormalUser = true;
                  uid = 1000;
                  linger = true;
                };

                home-manager.users.testuser = {
                  imports = [ self.homeModules.onemcp ];
                  home.stateVersion = "24.11";

                  services.onemcp-agent = {
                    enable = true;
                    servers = {
                      "test-pkg" = {
                        transport = "stdio";
                        command = pkgs.hello;
                        args = [
                          "-g"
                          "Hello from MCP"
                        ];
                        envFilter = [ "PATH" ];
                        tags = [ "test" ];
                      };
                      "test-http" = {
                        transport = "http";
                        url = "http://localhost:8080/sse";
                        enabled = true;
                        tags = [ "remote" ];
                      };
                      "test-str" = {
                        transport = "stdio";
                        command = "${pkgs.coreutils}/bin/echo";
                        args = [ "Raw string command" ];
                      };
                    };
                  };
                };
              };
            testScript = ''
              machine.wait_for_unit("user@1000.service")
              machine.wait_until_succeeds("su - testuser -c 'XDG_RUNTIME_DIR=/run/user/1000 systemctl --user is-active onemcp-agent.service'")

              # Find the config file path from systemd unit
              cmd = "su - testuser -c \"XDG_RUNTIME_DIR=/run/user/1000 systemctl --user cat onemcp-agent.service | grep 'ExecStart=' | sed 's/.*--config //'\""
              config_path = machine.succeed(cmd).strip()

              # Verify that the config contains the absolute path to hello
              machine.succeed(f"grep '${pkgs.hello}/bin/hello' {config_path}")

              # Verify HTTP server URL is present
              machine.succeed(f"grep 'http://localhost:8080/sse' {config_path}")

              # Verify tags and envFilter are present in the JSON
              machine.succeed(f"grep 'envFilter' {config_path}")
              machine.succeed(f"grep 'tags' {config_path}")

              # Verify default values are NOT present
              machine.fail(f"grep 'restartOnExit' {config_path}")
              machine.fail(f"grep 'inheritParentEnv' {config_path}")
              machine.fail(f"grep '\"enabled\": true' {config_path}")
            '';
          };
        };
      }
    )
    // {
      nixosModules.onemcp = self.homeModules.onemcp;
      nixosModules.default = self.nixosModules.onemcp;
      homeModules.onemcp = import ./module.nix { inherit self; };
      homeModules.default = self.homeModules.onemcp;
    };
}
