-- http_blocker.lua — Port-based traffic enforcement using macOS firewall rules.
--
-- ROLE IN THE SYSTEM
-- ------------------
-- HTTPBlocker enforces network traffic restrictions at the system level using macOS
-- firewall rules (pfctl). When BLOCK mode is active, it blocks all ports EXCEPT
-- port 443 (HTTPS) and 53 (DNS). This effectively blocks HTTP, custom ports, and
-- other non-HTTPS traffic.
--
-- This is a NETWORK-LEVEL blocker that prevents ANY application from accessing
-- non-HTTPS ports, including browsers, curl, wget, APIs, etc.
--
-- Called from init.lua:
--   updateForStrictMode(wasStrict, isStrict)  → enables/disables firewall when mode changes
--   cleanup()  → called on hs.reload() to clean up any dangling firewall rules
--
-- FIREWALL IMPLEMENTATION
-- ----------------------
-- The approach:
--   1. When entering BLOCK mode: Allow port 443 (HTTPS) and 53 (DNS), block everything else
--   2. When exiting BLOCK mode: Flush all rules from the anchor
--   3. Requires sudo/admin access (first time will prompt for password)

local HTTPBlocker = {}
HTTPBlocker.__index = HTTPBlocker

-- Firewall anchor name for identifying our rules
local FIREWALL_ANCHOR = "com.hammerspoon/http-blocker"

-- File paths for firewall state
local function getFirewallStatePath()
    return "/tmp/hammerspoon-http-blocker.state"
end

-- Shell-escape a string for safe use in shell commands
local function shellEscape(str)
    return "'" .. tostring(str):gsub("'", "'\\''") .. "'"
end

function HTTPBlocker.new(config, logger)
    local self = setmetatable({}, HTTPBlocker)
    self.config = config.browser or {}
    self.logger = logger
    self.enabled = false
    return self
end

function HTTPBlocker:title()
    return "Network Blocker"
end

function HTTPBlocker:description()
    return "Blocks all network ports except 443 (HTTPS) and 53 (DNS) during block mode."
end

-- isEnabled returns true if the HTTP blocker firewall rules are currently active
function HTTPBlocker:isEnabled()
    return self.enabled
end

-- enable activates the firewall rules using pfctl
function HTTPBlocker:enable()
    if self.enabled then
        return true  -- Already enabled
    end

    self.logger:marker("http_blocker firewall enable_requested")

    -- Block all ports EXCEPT 443 (HTTPS) and 53 (DNS)
    -- This is done by allowing only those ports and blocking everything else
    local rules = [[pass out proto tcp from any to any port 443
pass out proto udp from any to any port 53
block drop out proto tcp from any to any
block drop out proto udp from any to any]]

    self.logger:marker("http_blocker firewall_activating_rules block_all_except_https_and_dns")

    -- Write rules to a temp file and apply with pfctl
    local tmpFile = "/tmp/hammerspoon-http-blocker-rules-" .. tostring(os.time()) .. ".txt"
    local rulesFile = io.open(tmpFile, "w")
    if not rulesFile then
        self.logger:marker("http_blocker firewall_error failed_to_create_rules_file")
        return false
    end
    rulesFile:write(rules)
    rulesFile:close()

    -- Apply the rules using pfctl
    local cmd = "sudo pfctl -a " .. shellEscape(FIREWALL_ANCHOR) .. " -f " .. shellEscape(tmpFile) .. " && rm " .. shellEscape(tmpFile)

    local exitCode = os.execute(cmd)

    if exitCode == 0 then
        self.enabled = true
        self.logger:marker("http_blocker firewall_enabled successfully")

        -- Write state file
        local stateFile = io.open(getFirewallStatePath(), "w")
        if stateFile then
            stateFile:write("enabled=true\n")
            stateFile:close()
        end

        return true
    else
        self.logger:marker("http_blocker firewall_enable_failed exitcode=" .. tostring(exitCode))
        -- Clean up temp file
        os.remove(tmpFile)
        return false
    end
end

-- disable deactivates the HTTP firewall rules
function HTTPBlocker:disable()
    if not self.enabled then
        return true  -- Already disabled
    end

    self.logger:marker("http_blocker firewall disable_requested")

    -- Remove all rules from the anchor (flush rules)
    local flushCmd = "sudo pfctl -a " .. shellEscape(FIREWALL_ANCHOR) .. " -Fr"

    local exitCode = os.execute(flushCmd)

    if exitCode == 0 then
        self.enabled = false
        self.logger:marker("http_blocker firewall_disabled successfully")

        -- Write state file
        local stateFile = io.open(getFirewallStatePath(), "w")
        if stateFile then
            stateFile:write("enabled=false\n")
            stateFile:close()
        end

        return true
    else
        self.logger:marker("http_blocker firewall_disable_failed exitcode=" .. tostring(exitCode))
        return false
    end
end

-- updateForStrictMode is called by init.lua when strictMode changes
-- If we're entering BLOCK mode, enable firewall rules
-- If we're exiting BLOCK mode, disable firewall rules
function HTTPBlocker:updateForStrictMode(wasStrict, isStrict)
    if not wasStrict and isStrict then
        -- Entering BLOCK mode - enable HTTP blocking
        self:enable()
    elseif wasStrict and not isStrict then
        -- Exiting BLOCK mode - disable HTTP blocking
        self:disable()
    end
end

-- cleanup removes all firewall rules (called on config reload)
function HTTPBlocker:cleanup()
    if self.enabled then
        self:disable()
    end

    -- Remove temporary state file
    os.remove(getFirewallStatePath())

    self.logger:marker("http_blocker firewall cleanup completed")
end

function HTTPBlocker:statusSummary()
    local status = self.enabled and "ACTIVE (only HTTPS+DNS allowed)" or "standby"
    return "Network Blocker: " .. status
end

return HTTPBlocker
