{
  lib,
  ramMB,
}: let
  div = a: b: builtins.floor (a / b);
  toMB = mb: "${toString mb}MB";

  sharedBuffersMB = lib.max 256 ramMB;
  effectiveCacheMB = lib.max 512 (sharedBuffersMB * 2);
  maintenanceWorkMemMB = lib.max 256 (div ramMB 8);
  autovacuumWorkMemMB = lib.max 128 (div ramMB 16);
  workMemMB = lib.max 8 (div ramMB 256);

  walBuffersMB = lib.max 16 (lib.min 256 (div ramMB 16));
  minWalSizeMB = lib.max 512 (div ramMB 2);
  maxWalSizeMB = lib.max 4096 (ramMB * 2);
in {
  inherit
    sharedBuffersMB
    effectiveCacheMB
    maintenanceWorkMemMB
    autovacuumWorkMemMB
    workMemMB
    walBuffersMB
    minWalSizeMB
    maxWalSizeMB
    ;

  settings = {
    jit = "off";
    shared_buffers = toMB sharedBuffersMB;
    effective_cache_size = toMB effectiveCacheMB;
    work_mem = toMB workMemMB;
    maintenance_work_mem = toMB maintenanceWorkMemMB;
    autovacuum_work_mem = toMB autovacuumWorkMemMB;
    wal_buffers = toMB walBuffersMB;
    wal_compression = "on";
    min_wal_size = toMB minWalSizeMB;
    max_wal_size = toMB maxWalSizeMB;
    checkpoint_timeout = "15min";
    checkpoint_completion_target = "0.9";
    random_page_cost = "1.3";
    effective_io_concurrency = "64";
  };
}
