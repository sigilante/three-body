# The Three-Body Problem (Server-Side Demo)

![](./img/header.jpeg)

A [NockApp](https://github.com/nockchain/nockchain) demo demonstrating NockApp application design principles.

This version of the demo only serves content (HTML, JavaScript, and CSS) from the NockApp server. It does not maintain state on the server side at all.

## Usage

```sh
git clone https://github.com/sigilante/three-body-clientside.git
cd three-body-clientside
nockup package install
nockup project build
nockup project run

# for more detailed logging during development, run:
RUST_BACKTRACE=1 RUST_LOG=debug,gnort=off MINIMAL_LOG_FORMAT=true nockup project run
```