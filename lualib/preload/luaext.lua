function enum(begin_idx)
    local enum_idx = (begin_idx or 0) - 1
    return function()
        enum_idx = enum_idx + 1
        return enum_idx
    end
end

--打印table
table.print = function(T, CR)
    assert(type(T) == "table",'arg should be a table!')

    CR = CR or '\r\n'
    local cache = {  [T] = "." }
    local function _dump(t,space,name)
        local temp = {}
        for k,v in next,t do
            local key = tostring(k)
            if cache[v] then
                table.insert(temp,"+" .. key .. " {" .. cache[v].."}")
            elseif type(v) == "table" then
                local new_key = name .. "." .. key
                cache[v] = new_key
                table.insert(temp,
                    "+" .. key .. _dump(
                    v,
                    space .. (next(t,k) and "|" or " " ).. string.rep(" ",#key),
                    new_key
                ))
            else
                table.insert(temp,"+" .. key .. " [" .. tostring(v).."]")
            end
        end
        return table.concat(temp,CR..space)
    end
    print(_dump(T, "",""))
end

-- 返回table大小
table.size = function(t)
	local count = 0
	for _ in pairs(t) do
		count = count + 1
	end
	return count
end

-- 判断table是否为空
table.empty = function(t)
    return not next(t)
end

-- 返回table索引列表
table.indices = function(t)
    local result = {}
    for k, v in pairs(t) do
        table.insert(result, k)
    end
end

-- 返回table值列表
table.values = function(t)
    local result = {}
    for k, v in pairs(t) do
        table.insert(result, v)
    end
end

-- 浅拷贝
table.clone = function(t, nometa)
    local result = {}
    if not nometa then
        setmetatable(result, getmetatable(t))
    end
    for k, v in pairs (t) do
        result[k] = v
    end
    return result
end

-- 深拷贝
table.copy = function(t, nometa)
    local result = {}

    if not nometa then
        setmetatable(result, getmetatable(t))
    end

    for k, v in pairs(t) do
        if type(v) == "table" then
            result[k] = copy(v)
        else
            result[k] = v
        end
    end
    return result
end


-- string扩展

-- 下标运算
do
    local mt = getmetatable("")
    local _index = mt.__index

    mt.__index = function (s, ...)
        local k = ...
        if "number" == type(k) then
            return _index.sub(s, k, k)
        else
            return _index[k]
        end
    end
end

string.split = function(s, delim)
    local split = {}
    local pattern = "[^" .. delim .. "]+"
    string.gsub(s, pattern, function(v) table.insert(split, v) end)
    return split
end

string.ltrim = function(s, c)
    local pattern = "^" .. (c or "%s") .. "+"
    return (string.gsub(s, pattern, ""))
end

string.rtrim = function(s, c)
    local pattern = (c or "%s") .. "+" .. "$"
    return (string.gsub(s, pattern, ""))
end

string.trim = function(s, c)
    return string.rtrim(string.ltrim(s, c), c)
end

local function dump(obj)
    local getIndent, quoteStr, wrapKey, wrapVal, dumpObj
    getIndent = function(level)
        return string.rep("\t", level)
    end
    quoteStr = function(str)
        return '"' .. string.gsub(str, '"', '\\"') .. '"'
    end
    wrapKey = function(val)
        if type(val) == "number" then
            return "[" .. val .. "]"
        elseif type(val) == "string" then
            return "[" .. quoteStr(val) .. "]"
        else
            return "[" .. tostring(val) .. "]"
        end
    end
    wrapVal = function(val, level)
        if type(val) == "table" then
            return dumpObj(val, level)
        elseif type(val) == "number" then
            return val
        elseif type(val) == "string" then
            return quoteStr(val)
        else
            return tostring(val)
        end
    end
    dumpObj = function(obj, level)
        if type(obj) ~= "table" then
            return wrapVal(obj)
        end
        level = level + 1
        local tokens = {}
        tokens[#tokens + 1] = "{"
        for k, v in pairs(obj) do
            tokens[#tokens + 1] = getIndent(level) .. wrapKey(k) .. " = " .. wrapVal(v, level) .. ","
        end
        tokens[#tokens + 1] = getIndent(level - 1) .. "}"
        return table.concat(tokens, "\n")
    end
    return dumpObj(obj, 0)
end

do
    local _tostring = tostring
    tostring = function(v)
        if type(v) == 'table' then
            return dump(v)
        else
            return _tostring(v)
        end
    end
end

-- math扩展
do
	local _floor = math.floor
	math.floor = function(n, p)
		if p and p ~= 0 then
			local e = 10 ^ p
			return _floor(n * e) / e
		else
			return _floor(n)
		end
	end
end

math.round = function(n, p)
        local e = 10 ^ (p or 0)
        return math.floor(n * e + 0.5) / e
end