-- Subscribe a collector to bus events: returns a table events[eventName] = { payload, ... }.
return function(ns, names)
    local got = {}
    for _, name in ipairs(names) do
        got[name] = {}
        ns.Bus.On(name, function(_, payload) table.insert(got[name], payload) end, "Spec")
    end
    return got
end
