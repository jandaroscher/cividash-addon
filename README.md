# CIVIDASH Civitas Dashboard Addon

This addon can deploy CIVIDASH Civitas Dashboard into the Civitas Core platform.

## Installation

Clone this repository into the addons folder of the `civitas_core` deployment repository. Alternatively, you may copy or link the files into the addons folder.

## Configuration

Add the corresponding addon settings to your inventory.

Activate the addon in your inventory by adding the following snippet:

```yaml
inv_addons:
  import: true
  addons:
    - 'addons/cividash_addon/tasks.yml'
```

Default values will be used from [default_inventory.yml](default_inventory.yml) and can be overwritten from your inventory.

## Execute

The addon will be installed after all other tasks of the core platform have been executed. If you want to pick a specific addon, use the tags `addons` and `addon_cividash` (tasks file exposes `addons` tag).
