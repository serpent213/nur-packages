# This file describes your repository contents.
# It should return a set of nix derivations
# and optionally the special attributes `lib`, `modules` and `overlays`.
# It should NOT import <nixpkgs>. Instead, you should take pkgs as an argument.
# Having pkgs default to <nixpkgs> is fine though, and it lets you use short
# commands such as:
#     nix-build -A mypackage
{
  pkgs ? import <nixpkgs> {},
  ramMB ? null,
  locales ? null,
  countries ? null,
  geofabrikBaseUrl ? null,
  osm2pgsqlImportCacheMB ? null,
  osm2pgsqlImportProcesses ? null,
  servingProfile ? null,
  maplibreCssUrl ? null,
  maplibreJsUrl ? null,
}: let
  inherit (pkgs.lib) optionalAttrs;

  osmTilesDemoArgs =
    optionalAttrs (ramMB != null) {inherit ramMB;}
    // optionalAttrs (locales != null) {inherit locales;}
    // optionalAttrs (countries != null) {inherit countries;}
    // optionalAttrs (geofabrikBaseUrl != null) {inherit geofabrikBaseUrl;}
    // optionalAttrs (osm2pgsqlImportCacheMB != null) {inherit osm2pgsqlImportCacheMB;}
    // optionalAttrs (osm2pgsqlImportProcesses != null) {inherit osm2pgsqlImportProcesses;}
    // optionalAttrs (servingProfile != null) {inherit servingProfile;}
    // optionalAttrs (maplibreCssUrl != null) {inherit maplibreCssUrl;}
    // optionalAttrs (maplibreJsUrl != null) {inherit maplibreJsUrl;};
in {
  # The `lib`, `modules`, and `overlays` names are special
  lib = import ./lib {inherit pkgs;}; # functions
  modules = import ./modules {inherit pkgs;}; # NixOS modules
  overlays = import ./overlays; # nixpkgs overlays

  martin = pkgs.callPackage ./pkgs/martin {};
  osm-tiles-demo = pkgs.callPackage ./pkgs/osm-tiles-demo osmTilesDemoArgs;
  osm-tiles-tests = pkgs.callPackage ./pkgs/osm-tiles-tests {};
  pushlog = pkgs.callPackage ./pkgs/pushlog {};
  remark42 = pkgs.callPackage ./pkgs/remark42 {};
}
