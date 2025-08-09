# make-runner.nvim

A base plugin for running make commands in a buffer.

## Features

Run `make` commands in a buffer.

- Highlights build errors in the buffer
- Jump to build errors
- Cancel build process
- Show build errors/warnings in Trouble

## Installation

Should work with most plugin managers.

By default has no configuration.
You can set up the default keybindings by calling `setup_default` in your config.
```lua
require('make-runner').setup_default()
```
Which will set up the following keybindings:
- `<leader>m` Toggle Make Output buffer
- `<leader>c` Cancel build process
- `<leader>t` Show build errors/warnings in Trouble

## Requirements

- Neovim 0.11+ (May work with older versions but not tested)
