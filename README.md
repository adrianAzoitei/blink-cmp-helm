# blink-cmp-env

[blink.cmp](https://github.com/Saghen/blink.cmp) source for environment variables.

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
