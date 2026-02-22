{
  pkgs,
  lib,
  locales,
  profile ? "compact",
}:
if profile == "openmaptiles"
then
  import ./mk-flex-lua-openmaptiles.nix {
    inherit pkgs;
  }
else
  import ./mk-flex-lua-compact.nix {
    inherit
      lib
      locales
      pkgs
      ;
  }
