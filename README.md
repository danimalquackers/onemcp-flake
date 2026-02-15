# 1MCP Nix Flake

A Nix flake for running the [1MCP Agent](https://github.com/1mcp-app/agent) as a systemd user service via Home Manager.

## Features

- **Nix-Native**: Reference Nix packages directly in your server configuration, avoiding `npx` or `uvx`.
- **Reproducible Package**: Builds the 1MCP agent from source using `pnpm` and pinned dependencies.
- **HTTP & Stdio Support**: Full support for both transport types and all MCP options.
- **Automatic Configuration**: Generates the `mcp.json` file automatically from your Nix configuration.
- **Home Manager Integration**: Manage the agent as a systemd user service with ease.
- **Advanced Process Control**: Supports automatic restarts, environment filtering, and timeouts.

## Installation

Add this flake to your `flake.nix` inputs:

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  onemcp.url = "github:danimalquackers/1mcp-flake";
};
```

## Usage (Home Manager)

Import the module and configure the service in your Home Manager configuration:

```nix
{ inputs, pkgs, ... }: {
  imports = [
    inputs.onemcp.homeModules.default
  ];

  services.onemcp-agent = {
    enable = true;
    port = 3000; # Default port
    
    # Declarative MCP Server Configuration
    servers = {
      # Use Nix packages directly (Stdio transport)
      # This handles absolute paths automatically
      "nixos-mcp" = {
        transport = "stdio";
        command = "${pkgs.mcp-nixos}/bin/mcp-nixos";
        tags = [ "nixos" "system" ];
      };

      # Remote server (HTTP transport)
      "remote-api" = {
        transport = "http";
        url = "https://api.example.com/mcp";
        tags = [ "remote" ];
      };

      # Python server with dependencies
      "weather" = let
        pythonEnv = pkgs.python3.withPackages (ps: with ps; [
          mcp
          requests
          pandas
        ]);
      in {
        transport = "stdio";
        command = "${pythonEnv}/bin/python3";
        args = [ "/path/to/weather_server.py" ];
        env = {
          API_KEY = "your-secret-key";
        };
      };
    };

    # (Optional) Low-level settings for mcp.json
    settings = {
      # Additional raw configuration
    };
  };
}
```


## Development

to build the package locally:

```bash
nix build .#default
```

To run the checks:

```bash
nix flake check
```
