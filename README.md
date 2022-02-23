Discourse + Blockstack
=================

This is a [Discourse](http://discourse.org) plugin to enable log in with Blockstack.

### Demo: https://forum.stacks.org

## Installation

-  Edit your `containers/app.yml` to include this under `hooks > after_code > exec > cmd`:

        - git clone https://github.com/stacks-network/discourse-blockstack.git

## Development

To forward your local Blockstack API to your Discourse Vagrant instance use:
  $ vagrant ssh -- -R 6270:localhost:6270
