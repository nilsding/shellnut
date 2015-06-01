# shellnut 
_Mumble-to-IRC/IRC-to-Mumble Chat Gateway_

## What you need

* Ruby (**>=2.1.0**)
* A Mumble and an IRC-server to connect to

## Preparations

* Edit and copy `config.yml.example` to `config.yml`

## Usage

`ruby shellnut.rb`

### Commands (prefix with the prefix you set in your config.yml)

* `ping` will return "pong" or, if possible, return given arguments
* `help` will show a list of available commands
* `mumble` will send a message to the Mumble server set in the config *(from IRC)*
* `irc` will send a message to the IRC server set in the config *(from Mumble)*
* `users` will show a list of all online users on the Mumble and which channel they are in *(on IRC)*

## Thanks to

* [nilsding](https://github.com/nilsding) for helping me to parse colors from IRC to Mumble

## Licensed

Licensed under the [MIT License](http://opensource.org/licenses/MIT)