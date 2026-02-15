{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.onemcp-agent;

  # Format the configuration to JSON
  configFile = pkgs.writeText "mcp.json" (builtins.toJSON cfg.settings);
in
{
  options.services.onemcp-agent = {
    enable = mkEnableOption "1MCP Agent service";

    package = mkOption {
      type = types.package;
      default = self.packages.${pkgs.system}.default;
      description = "The 1MCP agent package to use.";
    };

    port = mkOption {
      type = types.port;
      default = 3000;
      description = "Port to listen on (sets ONE_MCP_PORT).";
    };

    logFile = mkOption {
      type = types.str;
      default = "${config.xdg.dataHome}/1mcp/agent.log";
      description = "Path to the log file (sets ONE_MCP_LOG_FILE).";
    };

    settings = mkOption {
      type = types.attrs;
      default = { };
      description = ''
        Configuration settings for the 1MCP agent.
        These will be written to the mcp.json configuration file.
      '';
      example = literalExpression ''
        {
          mcpServers = {
            filesystem = {
              command = "npx";
              args = [ "-y" "@modelcontextprotocol/server-filesystem" "/home/user/allowed-dir" ];
            };
          };
        }
      '';
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Extra environment variables to pass to the service.";
    };

    servers = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            transport = mkOption {
              type = types.enum [
                "stdio"
                "http"
              ];
              description = "Transport type: stdio or http.";
            };
            command = mkOption {
              type = types.nullOr (
                types.oneOf [
                  types.str
                  types.package
                ]
              );
              default = null;
              description = "Executable to run (stdio transport). Can be a string (absolute path or in PATH) or a package.";
            };
            url = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "URL for the remote MCP server (http transport).";
            };
            args = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Arguments to pass to the command.";
            };
            cwd = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Working directory for the process.";
            };
            env = mkOption {
              type = types.attrsOf types.str;
              default = { };
              description = "Environment variables for the server.";
            };
            inheritParentEnv = mkOption {
              type = types.bool;
              default = false;
              description = "Inherit environment variables from parent process.";
            };
            envFilter = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Patterns for filtering inherited environment variables.";
            };
            restartOnExit = mkOption {
              type = types.bool;
              default = false;
              description = "Automatically restart the process when it exits.";
            };
            maxRestarts = mkOption {
              type = types.nullOr types.int;
              default = null;
              description = "Maximum number of restart attempts.";
            };
            restartDelay = mkOption {
              type = types.nullOr types.int;
              default = null;
              description = "Delay in milliseconds between restart attempts.";
            };
            tags = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Tags for routing and access control.";
            };
            connectionTimeout = mkOption {
              type = types.nullOr types.int;
              default = null;
              description = "Connection timeout in milliseconds.";
            };
            requestTimeout = mkOption {
              type = types.nullOr types.int;
              default = null;
              description = "Request timeout in milliseconds.";
            };
            enabled = mkOption {
              type = types.bool;
              default = true;
              description = "Enable or disable the server.";
            };
          };
        }
      );
      default = { };
      description = "Declarative configuration of MCP servers.";
    };
  };

  config = mkIf cfg.enable {
    services.onemcp-agent.settings.mcpServers = lib.mapAttrs (
      name: server:
      let
        fullConfig = {
          inherit (server)
            transport
            tags
            enabled
            connectionTimeout
            requestTimeout
            ;
        }
        // (
          if server.transport == "stdio" then
            {
              command =
                if server.command != null && lib.types.package.check server.command then
                  lib.getExe server.command
                else
                  server.command;
              inherit (server)
                args
                cwd
                env
                inheritParentEnv
                envFilter
                restartOnExit
                maxRestarts
                restartDelay
                ;
            }
          else
            {
              inherit (server) url;
            }
        );
      in
      lib.filterAttrs (
        n: v:
        v != null
        && v != [ ]
        && v != { }
        && !(v == false && (n == "restartOnExit" || n == "inheritParentEnv"))
        && !(v == true && n == "enabled")
      ) fullConfig
    ) cfg.servers;

    systemd.user.services.onemcp-agent = {
      Unit = {
        Description = "1MCP Agent Service";
        After = [ "network.target" ];
      };

      Service = {
        ExecStart = "${cfg.package}/bin/1mcp --config ${configFile}";
        Environment = [
          "ONE_MCP_PORT=${toString cfg.port}"
          "ONE_MCP_LOG_FILE=${cfg.logFile}"
          "NODE_ENV=production"
        ]
        ++ (mapAttrsToList (n: v: "${n}=${v}") cfg.environment);
        ExecStartPre =
          let
            logDir = builtins.dirOf cfg.logFile;
          in
          "${pkgs.coreutils}/bin/mkdir -p ${logDir}";
        Restart = "on-failure";
        RestartSec = "10";
      };

      Install = {
        WantedBy = [ "default.target" ];
      };
    };
  };
}
