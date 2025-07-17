help:
    @just --list

eval-pkgs:
    @nix-env -f . -qa \* --meta \
        --allowed-uris https://static.rust-lang.org \
        --option restrict-eval true \
        --option allow-import-from-derivation true \
        --drv-path --show-trace \
        -I nixpkgs=$(nix-instantiate --find-file nixpkgs) \
        -I ./ \
        --json | jq -r 'values | .[].name'

trigger-update:
    curl -XPOST https://nur-update.nix-community.org/update?repo=serpent213
