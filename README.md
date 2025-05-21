# blink-cmp-env
[blink.cmp](https://github.com/Saghen/blink.cmp) source for environment variables.

https://github.com/user-attachments/assets/df1576e6-0d44-40a8-9abb-a6c491710a33

## Installation

### `lazy.nvim`
```lua
{
    "saghen/blink.cmp",
    dependencies = {
        "adrianAzoitei/blink-cmp-helm",
    },
    opts = {
        sources = {
            default = { "lsp", "path", "snippets", "buffer", "helm" },
            providers = {
                helm = {
                    name = "Helm",
                    module = "blink-cmp-helm",
                }
            }
        }
    }
}
```


### Prerequisites
This plugin relies on the [lyaml](https://github.com/gvvaughan/lyaml) rock. For `LazyVim` users it's recommended to install it using the [luarocks neovim plugin](https://github.com/vhyrro/luarocks.nvim).
```lua
return {
  "vhyrro/luarocks.nvim",
  priority = 1000, -- Very high priority is required, luarocks.nvim should run as the first plugin in your config.
  config = true,
  opts = {
    rocks = { "lyaml" },
  },
}

```

## Usage
This `blink` completion source is meant to make working with `Helm` subcharts easier by providing auto-completion capabilities for them.

Annotate the block containing subchart value overrides with `# @repository/chart-name`. For example:

```yaml
jenkins: # @jenkins/jenkins
  controller:
    ingress:
```

## TODO
- [] List all possible completion options without typing a character.
- [] Show section of subchart values around current yaml path on documentation trigger.
- [] Support versioning of subcharts.
