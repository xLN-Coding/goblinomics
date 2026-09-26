-- Fake price sources for specs: values[role][itemKey] = number.
return function(id, priority, values, extra)
    local src = { id = id, name = id, priority = priority, roles = {}, calls = 0 }
    for role in pairs(values) do src.roles[role] = true end
    function src:Get(key, role)
        self.calls = self.calls + 1
        return values[role] and values[role][key]
    end
    for k, v in pairs(extra or {}) do src[k] = v end
    return src
end
