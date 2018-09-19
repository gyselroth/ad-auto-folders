# ad-auto-folders

Dynamically create folders according active directory objects with a specific acl ruleset.

## Install

Get the latest version of `src/main.ps1` and install it on your server where you would like to create folders.

## Requirements

* Windows
* Powershell >= v3
* Active Directory environment

## Configuration

The configuration is done using a json configuration file. By default the config must be places in the same directory where you placed main.ps1
and must be named config.json.

You can copy the example configuration `example_config.json` to get started.

## Run
After you configured the config.json, just execute the script using powershell: `powershell.exe main.ps1`

## Cron
You may want to install this script as a windows task to let it automatically execute in a specific interval, for example every 5min.
