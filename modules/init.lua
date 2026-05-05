-- modules/init.lua — Convenience re-exporter for all modules.
--
-- This file is not used by init.lua (which requires each module directly).
-- It exists so external tools or test scripts can load all modules in one call:
--   local M = require("modules")
--   local logger = M.logger.new(config)
--
-- Do not add logic here; this file should remain a pure index.

local M = {}

M.logger = require("modules.logger")
M.messages = require("modules.messages")
M.overlay = require("modules.overlay")
M.schedule = require("modules.schedule")
M.location_mode = require("modules.location_mode")
M.browser_filter = require("modules.browser_filter")
M.http_blocker = require("modules.http_blocker")
M.file_path_blocker = require("modules.file_path_blocker")
M.folder_blocker = require("modules.folder_blocker")
M.activity_classifier = require("modules.activity_classifier")
M.app_blocker = require("modules.app_blocker")
M.block_screen_overlay = require("modules.block_screen_overlay")
M.red_warning_overlay = require("modules.red_warning_overlay")

return M
