-- Create the extra databases for cache, queue, and cable.
-- The primary database (automatic_patch_production) is created automatically
-- by the POSTGRES_DB env var.
CREATE DATABASE automatic_patch_production_cache;
CREATE DATABASE automatic_patch_production_queue;
CREATE DATABASE automatic_patch_production_cable;
