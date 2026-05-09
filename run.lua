plugin = {}

local PLUGIN_NAME = "RPM"
local PLUGIN_VERSION = "0.1.0"
local REQUIRED_BINARY = "rpm"

local ARCH_TOKENS = {
    aarch64 = true,
    armhfp = true,
    armv6hl = true,
    armv7hl = true,
    i386 = true,
    i486 = true,
    i586 = true,
    i686 = true,
    loongarch64 = true,
    noarch = true,
    ppc64 = true,
    ppc64le = true,
    riscv64 = true,
    s390x = true,
    sparc64 = true,
    src = true,
    x86_64 = true,
}

local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function split_lines(value)
    local lines = {}
    for line in (tostring(value or "") .. "\n"):gmatch("(.-)\n") do
        table.insert(lines, (line:gsub("\r$", "")))
    end
    return lines
end

local function emit_event(context, name, payload)
    if context == nil or context.events == nil then
        return
    end

    local fn = context.events[name]
    if type(fn) == "function" then
        fn(payload)
    end
end

local function begin_step(context, label)
    if context == nil or context.tx == nil then
        return
    end

    local fn = context.tx.begin_step
    if type(fn) == "function" then
        fn(label)
    end
end

local function tx_success(context)
    if context == nil or context.tx == nil then
        return
    end

    local fn = context.tx.success
    if type(fn) == "function" then
        fn()
    end
end

local function tx_failed(context, message)
    if context == nil or context.tx == nil then
        return
    end

    local fn = context.tx.failed
    if type(fn) == "function" then
        fn(message)
    end
end

local function tx_status(context, value)
    if context == nil or context.tx == nil then
        return
    end

    local fn = context.tx.status
    if type(fn) == "function" then
        fn(value)
    end
end

local function tx_progress(context, value)
    if context == nil or context.tx == nil then
        return
    end

    local fn = context.tx.progress
    if type(fn) == "function" then
        fn(value)
    end
end

local function update_parse_progress(context, state, done, total)
    if context == nil or done == nil or done < 1 then
        return
    end

    if state == nil then
        state = {}
    end

    local should_update_status = state.last_status == nil
        or done == 1
        or (total ~= nil and done == total)
        or done - state.last_status >= 25

    if should_update_status then
        tx_status(context, done)
        state.last_status = done
    end

    if total == nil or total < 1 then
        return
    end

    local percent = math.floor((done / total) * 100)
    local should_update_progress = state.last_progress == nil
        or done == 1
        or done == total
        or percent - state.last_progress >= 5

    if should_update_progress then
        tx_progress(context, percent)
        state.last_progress = percent
    end
end

local function normalize_run_result(first, second, third, fourth, fifth)
    if type(first) == "table" then
        return first
    end

    local result = {}

    local function merge_exec_like(value)
        local probes = {
            "success",
            "ok",
            "stdout",
            "stderr",
            "exitCode",
            "exit_code",
            "code",
            "status",
        }

        for _, key in ipairs(probes) do
            local ok, item = pcall(function()
                return value[key]
            end)
            if ok and item ~= nil and result[key] == nil then
                result[key] = item
            end
        end
    end

    local function merge_table(value)
        for key, item in pairs(value or {}) do
            result[key] = item
        end
    end

    local function apply_scalar(value)
        local value_type = type(value)
        if value_type == "table" then
            merge_table(value)
        elseif value_type == "userdata" then
            merge_exec_like(value)
        elseif value_type == "boolean" then
            if result.success == nil then
                result.success = value
            end
        elseif value_type == "number" then
            if result.exitCode == nil then
                result.exitCode = value
            end
        elseif value_type == "string" then
            if result.stdout == nil then
                result.stdout = value
            elseif result.stderr == nil then
                result.stderr = value
            end
        end
    end

    apply_scalar(first)
    apply_scalar(second)
    apply_scalar(third)
    apply_scalar(fourth)
    apply_scalar(fifth)

    if result.exitCode == nil then
        result.exitCode = result.exit_code or result.code or result.status
    end
    if result.success == nil and result.ok ~= nil then
        result.success = result.ok
    end
    if result.success == nil and result.exitCode ~= nil then
        result.success = result.exitCode == 0
    end

    return result
end

local function is_command_success(result, extra_exit_codes)
    if type(result) ~= "table" then
        return false
    end

    if result.success then
        return true
    end

    if result.ok then
        return true
    end

    local exit_code = result.exitCode
    if exit_code == nil then
        exit_code = result.exit_code
    end
    if exit_code == nil then
        exit_code = result.code
    end
    if exit_code == nil then
        exit_code = result.status
    end

    if exit_code == 0 then
        return true
    end

    if type(extra_exit_codes) == "table" and exit_code ~= nil then
        for _, allowed in ipairs(extra_exit_codes) do
            if exit_code == allowed then
                return true
            end
        end
    end

    return false
end

local function run(context, command)
    local first, second, third, fourth, fifth
    if context ~= nil and context.exec ~= nil and type(context.exec.run) == "function" then
        first, second, third, fourth, fifth = context.exec.run(command)
        return normalize_run_result(first, second, third, fourth, fifth)
    end

    first, second, third, fourth, fifth = reqpack.exec.run(command)
    return normalize_run_result(first, second, third, fourth, fifth)
end

local function command_exists(binary, context)
    if trim(binary) == "" then
        return false
    end

    return is_command_success(run(context, "command -v " .. shell_quote(binary) .. " >/dev/null 2>&1"))
end

local function get_repo_helper(context)
    if command_exists("dnf", context) then
        return "dnf"
    elseif command_exists("yum", context) then
        return "yum"
    end

    return nil
end

local function make_package_id(name, architecture)
    name = trim(name)
    architecture = trim(architecture)

    if name == "" then
        return nil
    end

    if architecture ~= "" then
        return name .. "." .. architecture
    end

    return name
end

local function split_name_arch(token)
    token = trim(token)
    if token == "" then
        return nil, nil
    end

    local name, arch = token:match("^(.+)%.([^.]+)$")
    if name ~= nil and ARCH_TOKENS[arch] then
        return name, arch
    end

    return token, nil
end

local function package_token(pkg)
    local name = trim(pkg and pkg.name)
    local version = trim(pkg and pkg.version)

    if name == "" then
        return ""
    end

    if version ~= "" then
        return name .. "-" .. version
    end

    return name
end

local function is_installed(context, name)
    name = trim(name)
    if name == "" then
        return false
    end

    return is_command_success(run(context, "rpm -q --quiet " .. shell_quote(name)))
end

local function normalize_field_key(value)
    return trim(value):lower():gsub("[^%w]+", "")
end

local function normalize_extra_fields(extra)
    if type(extra) ~= "table" or next(extra) == nil then
        return nil
    end
    return extra
end

local function parse_rpm_list(stdout, context)
    local items = {}
    local lines = {}

    for _, line in ipairs(split_lines(stdout)) do
        if trim(line) ~= "" then
            table.insert(lines, line)
        end
    end

    tx_status(context, 0)
    tx_progress(context, 0)

    local state = {}
    local total = #lines
    for index, line in ipairs(lines) do
        local name, version, architecture, summary = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
        name = trim(name)
        version = trim(version)
        architecture = trim(architecture)
        summary = trim(summary)

        if name ~= "" then
            local item = {
                name = name,
                packageId = make_package_id(name, architecture),
                installed = true,
                status = "installed",
                type = "package",
                packageType = "rpm",
            }

            if version ~= "" then
                item.version = version
            end
            if architecture ~= "" then
                item.architecture = architecture
            end
            if summary ~= "" then
                item.summary = summary
            end

            table.insert(items, item)
        end

        update_parse_progress(context, state, index, total)
    end

    tx_progress(context, 100)
    return items
end

local function parse_search_output(stdout, context)
    local items = {}
    local candidates = {}
    local seen = {}

    for _, line in ipairs(split_lines(stdout)) do
        local trimmed = trim(line)
        local token, summary = trimmed:match("^([%w%._+%-]+)%s*:%s+(.+)$")
        if token ~= nil and trim(summary) ~= "" then
            table.insert(candidates, trimmed)
        end
    end

    tx_status(context, 0)
    tx_progress(context, 0)

    local state = {}
    local total = #candidates
    for index, line in ipairs(candidates) do
        local token, summary = line:match("^([%w%._+%-]+)%s*:%s+(.+)$")
        local name, architecture = split_name_arch(token)
        local package_id = make_package_id(name, architecture)

        if package_id ~= nil and not seen[package_id] then
            seen[package_id] = true
            local item = {
                name = name,
                packageId = package_id,
                installed = false,
                status = "available",
                summary = trim(summary),
                type = "package",
                packageType = "rpm",
            }

            if trim(architecture) ~= "" then
                item.architecture = architecture
            end

            table.insert(items, item)
        end

        update_parse_progress(context, state, index, total)
    end

    tx_progress(context, 100)
    return items
end

local function parse_info_block(stdout, installed_default)
    local fields = {}
    local description_lines = {}
    local current_key = nil
    local installed = installed_default and true or false

    for _, raw_line in ipairs(split_lines(stdout)) do
        local line = raw_line:gsub("\r$", "")
        local trimmed = trim(line)

        if trimmed == "Installed Packages" then
            installed = true
            current_key = nil
        elseif trimmed == "Available Packages" then
            installed = false
            current_key = nil
        else
            local key, value = line:match("^([%w][%w%s/%-]+)%s*:%s*(.*)$")
            if key ~= nil then
                current_key = normalize_field_key(key)
                if current_key == "description" then
                    description_lines = {}
                    if trim(value) ~= "" then
                        table.insert(description_lines, trim(value))
                    end
                else
                    fields[current_key] = trim(value)
                end
            elseif current_key == "description" and line:match("^%s+") then
                local continued = trim(line):gsub("^:%s*", "")
                table.insert(description_lines, continued)
            end
        end
    end

    while #description_lines > 0 and description_lines[1] == "" do
        table.remove(description_lines, 1)
    end
    while #description_lines > 0 and description_lines[#description_lines] == "" do
        table.remove(description_lines, #description_lines)
    end

    if #description_lines > 0 then
        fields.description = table.concat(description_lines, "\n")
    end

    local name = trim(fields.name)
    if name == "" then
        return nil
    end

    local version = trim(fields.version)
    local release = trim(fields.release)
    local architecture = trim(fields.architecture)
    local repository = trim(fields.repository)
    if repository == "" then
        repository = trim(fields.repo)
    end

    local item = {
        name = name,
        packageId = make_package_id(name, architecture),
        installed = installed,
        status = installed and "installed" or "available",
        type = "package",
        packageType = "rpm",
    }

    if version ~= "" and release ~= "" then
        item.version = version .. "-" .. release
    elseif version ~= "" then
        item.version = version
    end
    if architecture ~= "" then
        item.architecture = architecture
    end
    if trim(fields.summary) ~= "" then
        item.summary = trim(fields.summary)
    end
    if trim(fields.description) ~= "" then
        item.description = trim(fields.description)
    end
    if trim(fields.license) ~= "" then
        item.license = trim(fields.license)
    end
    if trim(fields.url) ~= "" then
        item.homepage = trim(fields.url)
    end
    if repository ~= "" then
        item.repository = repository
    end

    local extra = {}
    if release ~= "" then
        extra.release = release
    end
    if trim(fields.epoch) ~= "" then
        extra.epoch = trim(fields.epoch)
    end
    if trim(fields.source) ~= "" then
        extra.source = trim(fields.source)
    end
    if trim(fields.sourcerpm) ~= "" then
        extra.sourceRpm = trim(fields.sourcerpm)
    end
    if trim(fields.size) ~= "" then
        extra.size = trim(fields.size)
    end
    if trim(fields.installsize) ~= "" then
        extra.installSize = trim(fields.installsize)
    end
    if trim(fields.builddate) ~= "" then
        extra.buildDate = trim(fields.builddate)
    end
    if trim(fields.installdate) ~= "" then
        extra.installDate = trim(fields.installdate)
    end
    if trim(fields.packager) ~= "" then
        extra.packager = trim(fields.packager)
    end
    if trim(fields.vendor) ~= "" then
        extra.vendor = trim(fields.vendor)
    end
    if trim(fields.signature) ~= "" then
        extra.signature = trim(fields.signature)
    end

    item.extraFields = normalize_extra_fields(extra)
    return item
end

local function parse_check_update(stdout, context)
    local items = {}
    local candidates = {}

    for _, line in ipairs(split_lines(stdout)) do
        local trimmed = trim(line)
        local token, latest_version, repository = trimmed:match("^([%w%._+%-]+)%s+([^%s]+)%s+(.+)$")
        local name, architecture = split_name_arch(token)
        if token ~= nil and latest_version ~= nil and repository ~= nil and name ~= nil and trim(latest_version):match("%d") ~= nil then
            table.insert(candidates, trimmed)
        end
    end

    tx_status(context, 0)
    tx_progress(context, 0)

    local state = {}
    local total = #candidates
    for index, line in ipairs(candidates) do
        local token, latest_version, repository = line:match("^([%w%._+%-]+)%s+([^%s]+)%s+(.+)$")
        local name, architecture = split_name_arch(token)
        local item = {
            name = name,
            packageId = make_package_id(name, architecture),
            installed = true,
            status = "outdated",
            latestVersion = trim(latest_version),
            repository = trim(repository),
            type = "package",
            packageType = "rpm",
        }

        if trim(architecture) ~= "" then
            item.architecture = architecture
        end

        table.insert(items, item)
        update_parse_progress(context, state, index, total)
    end

    tx_progress(context, 100)
    return items
end

local function collect_package_names(packages)
    local names = {}

    for _, pkg in ipairs(packages or {}) do
        local name = trim(pkg and pkg.name)
        if name ~= "" then
            table.insert(names, name)
        end
    end

    return names
end

local function collect_package_tokens(packages)
    local tokens = {}

    for _, pkg in ipairs(packages or {}) do
        local token = package_token(pkg)
        if token ~= "" then
            table.insert(tokens, token)
        end
    end

    return tokens
end

local function query_outdated_lookup(context)
    local helper = get_repo_helper(context)
    if helper == nil then
        return nil
    end

    local result = run(context, helper .. " check-update")
    if not is_command_success(result, { 100 }) then
        return nil
    end

    local lookup = {}
    for _, item in ipairs(parse_check_update(result.stdout or "")) do
        lookup[item.name] = true
        if item.packageId ~= nil then
            lookup[item.packageId] = true
        end
    end

    return lookup
end

plugin.fileExtensions = { ".rpm" }

function plugin.getName()
    return PLUGIN_NAME
end

function plugin.getVersion()
    return PLUGIN_VERSION
end

function plugin.getRequirements()
    return {}
end

function plugin.getCategories()
    return { "Linux", "RPM", "Wrapper" }
end

function plugin.getMissingPackages(packages)
    local missing = {}
    local outdated_lookup = nil
    local helper = nil
    local helper_checked = false

    for _, pkg in ipairs(packages or {}) do
        local name = trim(pkg and pkg.name)
        local action = trim(pkg and pkg.action)

        if name ~= "" then
            if action == "remove" then
                if is_installed(nil, name) then
                    table.insert(missing, pkg)
                end
            elseif action == "update" then
                if not helper_checked then
                    helper = get_repo_helper(nil)
                    helper_checked = true
                    if helper ~= nil then
                        outdated_lookup = query_outdated_lookup(nil) or {}
                    end
                end

                if helper ~= nil then
                    if outdated_lookup[name] or outdated_lookup[make_package_id(name, trim(pkg and pkg.architecture))] then
                        table.insert(missing, pkg)
                    end
                elseif is_installed(nil, name) then
                    table.insert(missing, pkg)
                end
            else
                if not is_installed(nil, name) then
                    table.insert(missing, pkg)
                end
            end
        end
    end

    return missing
end

function plugin.install(context, packages)
    packages = packages or {}
    if #packages == 0 then
        return true
    end

    begin_step(context, "install rpm packages")

    local helper = get_repo_helper(context)
    if helper == nil then
        tx_failed(context, "repo install requires dnf or yum")
        return false
    end

    local tokens = collect_package_tokens(packages)
    if #tokens == 0 then
        tx_failed(context, "no package names to install")
        return false
    end

    tx_progress(context, 0)

    local quoted = {}
    for _, token in ipairs(tokens) do
        table.insert(quoted, shell_quote(token))
    end

    local result = run(context, helper .. " install -y " .. table.concat(quoted, " "))
    if not is_command_success(result) then
        tx_failed(context, "rpm install failed")
        return false
    end

    tx_progress(context, 85)
    emit_event(context, "installed", packages)
    tx_progress(context, 100)
    tx_success(context)
    return true
end

function plugin.installLocal(context, path)
    path = trim(path)
    if path == "" then
        tx_failed(context, "local rpm path missing")
        return false
    end

    begin_step(context, "install local rpm artifact")
    tx_progress(context, 0)

    local result = run(context, "rpm -Uvh " .. shell_quote(path))
    if not is_command_success(result) then
        tx_failed(context, "local rpm install failed")
        return false
    end

    tx_progress(context, 90)
    emit_event(context, "installed", { path = path, localTarget = true })
    tx_progress(context, 100)
    tx_success(context)
    return true
end

function plugin.remove(context, packages)
    packages = packages or {}
    if #packages == 0 then
        return true
    end

    begin_step(context, "remove rpm packages")

    local names = collect_package_names(packages)
    if #names == 0 then
        tx_failed(context, "no package names to remove")
        return false
    end

    tx_progress(context, 0)

    local quoted = {}
    for _, name in ipairs(names) do
        table.insert(quoted, shell_quote(name))
    end

    local result = run(context, "rpm -e " .. table.concat(quoted, " "))
    if not is_command_success(result) then
        tx_failed(context, "rpm remove failed")
        return false
    end

    tx_progress(context, 90)
    emit_event(context, "deleted", packages)
    tx_progress(context, 100)
    tx_success(context)
    return true
end

function plugin.update(context, packages)
    packages = packages or {}
    if #packages == 0 then
        return true
    end

    begin_step(context, "update rpm packages")

    local helper = get_repo_helper(context)
    if helper == nil then
        tx_failed(context, "repo update requires dnf or yum")
        return false
    end

    local tokens = collect_package_tokens(packages)
    if #tokens == 0 then
        tx_failed(context, "no package names to update")
        return false
    end

    tx_progress(context, 0)

    local quoted = {}
    for _, token in ipairs(tokens) do
        table.insert(quoted, shell_quote(token))
    end

    local command = helper == "dnf" and "dnf upgrade -y " or "yum update -y "
    local result = run(context, command .. table.concat(quoted, " "))
    if not is_command_success(result) then
        tx_failed(context, "rpm update failed")
        return false
    end

    tx_progress(context, 85)
    emit_event(context, "updated", packages)
    tx_progress(context, 100)
    tx_success(context)
    return true
end

function plugin.list(context)
    begin_step(context, "list installed rpm packages")

    local result = run(context, "rpm -qa --queryformat '%{NAME}\t%{VERSION}-%{RELEASE}\t%{ARCH}\t%{SUMMARY}\n'")
    if not is_command_success(result) then
        tx_failed(context, "rpm list failed")
        return false
    end

    local items = parse_rpm_list(result.stdout or "", context)
    emit_event(context, "listed", items)
    return items
end

function plugin.outdated(context)
    begin_step(context, "check outdated rpm packages")

    local helper = get_repo_helper(context)
    if helper == nil then
        tx_status(context, 0)
        tx_progress(context, 100)
        local empty = {}
        emit_event(context, "outdated", empty)
        return empty
    end

    local result = run(context, helper .. " check-update")
    if not is_command_success(result, { 100 }) then
        tx_failed(context, "rpm outdated check failed")
        return false
    end

    local items = parse_check_update(result.stdout or "", context)
    emit_event(context, "outdated", items)
    return items
end

function plugin.search(context, prompt)
    prompt = trim(prompt)
    if prompt == "" then
        tx_status(context, 0)
        tx_progress(context, 100)
        local empty = {}
        emit_event(context, "searched", empty)
        return empty
    end

    begin_step(context, "search rpm repositories")

    local helper = get_repo_helper(context)
    if helper == nil then
        tx_status(context, 0)
        tx_progress(context, 100)
        local empty = {}
        emit_event(context, "searched", empty)
        return empty
    end

    local result = run(context, helper .. " search " .. shell_quote(prompt))
    if not is_command_success(result) then
        tx_failed(context, "rpm search failed")
        return false
    end

    local items = parse_search_output(result.stdout or "", context)
    emit_event(context, "searched", items)
    return items
end

function plugin.info(context, name)
    name = trim(name)
    if name == "" then
        emit_event(context, "unavailable", { name = name, packageType = "rpm" })
        return nil
    end

    begin_step(context, "inspect rpm package info")

    local installed_result = run(context, "rpm -qi " .. shell_quote(name))
    if is_command_success(installed_result) then
        tx_status(context, 0)
        tx_progress(context, 0)
        local item = parse_info_block(installed_result.stdout or "", true)
        if item ~= nil then
            tx_status(context, 1)
            tx_progress(context, 100)
            emit_event(context, "informed", item)
            return item
        end
    end

    local helper = get_repo_helper(context)
    if helper == nil then
        tx_status(context, 0)
        tx_progress(context, 100)
        emit_event(context, "unavailable", { name = name, packageType = "rpm" })
        return nil
    end

    local result = run(context, helper .. " info " .. shell_quote(name))
    if not is_command_success(result) then
        tx_failed(context, "rpm info failed")
        return false
    end

    tx_status(context, 0)
    tx_progress(context, 0)
    local item = parse_info_block(result.stdout or "", false)
    if item == nil then
        tx_progress(context, 100)
        emit_event(context, "unavailable", { name = name, packageType = "rpm" })
        return nil
    end

    tx_status(context, 1)
    tx_progress(context, 100)
    emit_event(context, "informed", item)
    return item
end

function plugin.init()
    return true
end

function plugin.shutdown()
    return true
end

return plugin
