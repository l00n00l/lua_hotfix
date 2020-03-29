Hotfix = {}

function Hotfix.FailNotify(...)
    if Hotfix.NotifyFunc then Hotfix.NotifyFunc(...) end
end
function Hotfix.DebugNofity(...)
    if Hotfix.DebugNofityFunc then Hotfix.DebugNofityFunc(...) end
end

function Hotfix.ReadFileByModuleName(ModuleName)
    ModuleName = "/" .. string.gsub(ModuleName, "%.", "/") .. ".lua"
    for _, path in pairs(Hotfix.Paths) do
        local FileSysPath = path .. ModuleName
        if pcall(function() io.input(FileSysPath) end) then
            local file_data = io.read("*all")
            io.input():close()
            return true, file_data, FileSysPath
        end
    end

    return false
end

function Hotfix.InitFakeTable()
    local meta = {}
    Hotfix.Meta = meta
    local function FakeT() return setmetatable({}, meta) end
    local function EmptyFunc() end
    local function pairs() return EmptyFunc end
    local function setmetatable(t, metaT)
        Hotfix.MetaMap[t] = metaT
        return t
    end
    local function getmetatable(t, metaT)
        return setmetatable({}, t)
    end
    local function require(LuaPath)
        if not Hotfix.RequireMap[LuaPath] then
            local FakeTable = FakeT()
            Hotfix.RequireMap[LuaPath] = FakeTable
        end
        return Hotfix.RequireMap[LuaPath]
    end
    function meta.__index(t, k)
        if k == "setmetatable" then
            return setmetatable
        elseif k == "pairs" or k == "ipairs" then
            return pairs
        elseif k == "next" then
            return EmptyFunc
        elseif k == "require" then
            return require
        else
            local FakeTable = FakeT()
            rawset(t, k, FakeTable)
            return FakeTable
        end
    end
    function meta.__newindex(t, k, v) rawset(t, k, v) end
    function meta.__call() return FakeT(), FakeT(), FakeT() end
    function meta.__add() return meta.__call() end
    function meta.__sub() return meta.__call() end
    function meta.__mul() return meta.__call() end
    function meta.__div() return meta.__call() end
    function meta.__mod() return meta.__call() end
    function meta.__pow() return meta.__call() end
    function meta.__unm() return meta.__call() end
    function meta.__concat() return meta.__call() end
    function meta.__eq() return meta.__call() end
    function meta.__lt() return meta.__call() end
    function meta.__le() return meta.__call() end
    function meta.__len() return meta.__call() end
    return FakeT
end

function Hotfix.InitProtection()
    Hotfix.Protection = {}
    Hotfix.Protection[setmetatable] = true
    Hotfix.Protection[pairs] = true
    Hotfix.Protection[ipairs] = true
    Hotfix.Protection[next] = true
    Hotfix.Protection[require] = true
    Hotfix.Protection[Hotfix] = true
    Hotfix.Protection[Hotfix.Meta] = true
    Hotfix.Protection[math] = true
    Hotfix.Protection[string] = true
    Hotfix.Protection[table] = true
end

function Hotfix.AddFileFromHFList()
    package.loaded[Hotfix.UpdateListFile] = nil
    Hotfix.HFMap = require(Hotfix.UpdateListFile)
end

function Hotfix.ErrorHandle(e)
    Hotfix.FailNotify("HotUpdate Error\n" .. tostring(e))
    Hotfix.ErrorHappen = true
end

function Hotfix.BuildNewCode(LuaPath)
    -- 读取文件
    local IsSuccess, NewCode, FileSysPath = Hotfix.ReadFileByModuleName(LuaPath)
    if not IsSuccess then
        Hotfix.FailNotify("The file of module " .. LuaPath .. "is not exist!")
        collectgarbage("collect")
        return false
    end
    -- 如果没有此文件的导入
    if Hotfix.AllFile and Hotfix.OldCode[LuaPath] == nil then
        Hotfix.OldCode[LuaPath] = NewCode
        return
    end

    -- 代码是否有更改	
    if Hotfix.OldCode[LuaPath] == NewCode then
        return false
    end

    -- 加载代码
    local NewFunction = loadstring(NewCode)
    if not NewFunction then
        Hotfix.FailNotify(FileSysPath .. " has syntax error.")
        collectgarbage("collect")
        return false
    end

    -- 初始化一个沙盒
    Hotfix.FakeENV = Hotfix.FakeT()
    Hotfix.MetaMap = {}
    Hotfix.RequireMap = {}

    -- 将函数环境改为沙盒
    setfenv(NewFunction, Hotfix.FakeENV)
    local NewObject
    Hotfix.ErrorHappen = false

    -- 在沙盒中执行初始化函数
    xpcall(function() NewObject = NewFunction() end, Hotfix.ErrorHandle)
    if not Hotfix.ErrorHappen then					-- 如果成功返回新的 module table	
        Hotfix.OldCode[FileSysPath] = NewCode
        return true, NewObject
    else											-- 否则做垃圾回收，代码无引用将自动回收
        collectgarbage("collect")
        return false
    end
end

function Hotfix.Travel_G()
    local visited = {}
    visited[Hotfix] = true
    local function f(t)
        if (type(t) ~= "function" and type(t) ~= "table") or visited[t] or Hotfix.Protection[t] then return end
        visited[t] = true
        if type(t) == "function" then
            for i = 1, math.huge do
                local name, value = debug.getupvalue(t, i)
                if not name then break end
                if type(value) == "function" then
                    for _, funcs in ipairs(Hotfix.ChangedFuncList) do
                        if value == funcs[1] then
                            debug.setupvalue(t, i, funcs[2])
                        end
                    end
                end
                f(value)
            end
        elseif type(t) == "table" then
            f(debug.getmetatable(t))
            local changeIndexs = {}
            for k, v in pairs(t) do
                f(k); f(v);
                if type(v) == "function" then
                    for _, funcs in ipairs(Hotfix.ChangedFuncList) do
                        if v == funcs[1] then t[k] = funcs[2] end
                    end
                end
                if type(k) == "function" then
                    for index, funcs in ipairs(Hotfix.ChangedFuncList) do
                        if k == funcs[1] then changeIndexs[#changeIndexs + 1] = index end
                    end
                end
            end
            for _, index in ipairs(changeIndexs) do
                local funcs = Hotfix.ChangedFuncList[index]
                t[funcs[2]] = t[funcs[1]]
                t[funcs[1]] = nil
            end
        end
    end

    f(_G)
    local registryTable = debug.getregistry()
    f(registryTable)

    for _, funcs in ipairs(Hotfix.ChangedFuncList) do
        if funcs[3] == "HUDebug" then funcs[4]:HUDebug() end
    end
end

function Hotfix.ReplaceOld(OldObject, NewObject, LuaPath, From, Deepth)
    if type(OldObject) == type(NewObject) then
        if type(NewObject) == "table" then
            Hotfix.UpdateAllFunction(OldObject, NewObject, LuaPath, From, "")
        elseif type(NewObject) == "function" then
            Hotfix.UpdateOneFunction(OldObject, NewObject, LuaPath, nil, From, "")
        end
    end
end

function Hotfix.ResetENV(object, name, From, Deepth)
    local visited = {}
    local function f(object, name)
        if not object or visited[object] then return end
        visited[object] = true
        if type(object) == "function" then
            Hotfix.DebugNofity(Deepth .. "Hotfix.ResetENV", name, "  from:" .. From)
            xpcall(function() setfenv(object, Hotfix.ENV) end, Hotfix.FailNotify)
        elseif type(object) == "table" then
            Hotfix.DebugNofity(Deepth .. "Hotfix.ResetENV", name, "  from:" .. From)
            for k, v in pairs(object) do
                f(k, tostring(k) .. "__key", " Hotfix.ResetENV ", Deepth .. "    ")
                f(v, tostring(k), " Hotfix.ResetENV ", Deepth .. "    ")
            end
        end
    end
    f(object, name)
end

function Hotfix.UpdateUpvalue(OldFunction, NewFunction, Name, From, Deepth)
    Hotfix.DebugNofity(Deepth .. "Hotfix.UpdateUpvalue", Name, "  from:" .. From)
    local OldUpvalueMap = {}
    local OldExistName = {}
    for i = 1, math.huge do
        local name, value = debug.getupvalue(OldFunction, i)
        if not name then break end
        OldUpvalueMap[name] = value
        OldExistName[name] = true
    end
    for i = 1, math.huge do
        local name, value = debug.getupvalue(NewFunction, i)
        if not name then break end
        if OldExistName[name] then
            local OldValue = OldUpvalueMap[name]
            if type(OldValue) ~= type(value) then
                debug.setupvalue(NewFunction, i, OldValue)
            elseif type(OldValue) == "function" then
                Hotfix.UpdateOneFunction(OldValue, value, name, nil, "Hotfix.UpdateUpvalue", Deepth .. "    ")
            elseif type(OldValue) == "table" then
                Hotfix.UpdateAllFunction(OldValue, value, name, "Hotfix.UpdateUpvalue", Deepth .. "    ")
                debug.setupvalue(NewFunction, i, OldValue)
            else
                debug.setupvalue(NewFunction, i, OldValue)
            end
        else
            Hotfix.ResetENV(value, name, "Hotfix.UpdateUpvalue", Deepth .. "    ")
        end
    end
end

function Hotfix.UpdateOneFunction(OldObject, NewObject, FuncName, OldTable, From, Deepth)
    -- 是否在保护队列
    if Hotfix.Protection[OldObject] or Hotfix.Protection[NewObject] then
        return
    end
    -- 新老对象是否相同
    if OldObject == NewObject then
        return
    end
    -- 是否已经更新过
    local signature = tostring(OldObject) .. tostring(NewObject)
    if Hotfix.VisitedSig[signature] then
        return
    end

    Hotfix.VisitedSig[signature] = true
    Hotfix.DebugNofity(Deepth .. "Hotfix.UpdateOneFunction " .. FuncName .. "  from:" .. From)
    if pcall(debug.setfenv, NewObject, getfenv(OldObject)) then
        Hotfix.UpdateUpvalue(OldObject, NewObject, FuncName, "Hotfix.UpdateOneFunction", Deepth .. "    ")
        Hotfix.ChangedFuncList[#Hotfix.ChangedFuncList + 1] = { OldObject, NewObject, FuncName, OldTable }
    end
end

function Hotfix.UpdateAllFunction(OldTable, NewTable, Name, From, Deepth)
    if Hotfix.Protection[OldTable] or Hotfix.Protection[NewTable] then return end
    if OldTable == NewTable then return end
    -- bxy DOTween error
    if Hotfix.Forbidden[Name] then return end
    if tostring(OldTable) == nil then return end
    -- log(Name)
    -- print(tostring(OldTable))
    -- print(tostring(NewTable))
    local signature = tostring(OldTable) .. tostring(NewTable)
    if Hotfix.VisitedSig[signature] then return end
    Hotfix.VisitedSig[signature] = true
    Hotfix.DebugNofity(Deepth .. "Hotfix.UpdateAllFunction " .. Name .. "  from:" .. From)
    for ElementName, Element in pairs(NewTable) do
        local OldElement = OldTable[ElementName]
        if type(Element) == type(OldElement) then
            if type(Element) == "function" then
                Hotfix.UpdateOneFunction(OldElement, Element, ElementName, OldTable, "Hotfix.UpdateAllFunction", Deepth .. "    ")
            elseif type(Element) == "table" then
                Hotfix.UpdateAllFunction(OldElement, Element, ElementName, "Hotfix.UpdateAllFunction", Deepth .. "    ")
            end
        elseif OldElement == nil and type(Element) == "function" then
            if pcall(setfenv, Element, Hotfix.ENV) then
                OldTable[ElementName] = Element
            end
        end
    end
    local OldMeta = debug.getmetatable(OldTable)
    local NewMeta = Hotfix.MetaMap[NewTable]
    if type(OldMeta) == "table" and type(NewMeta) == "table" then
        Hotfix.UpdateAllFunction(OldMeta, NewMeta, Name .. "'s Meta", "Hotfix.UpdateAllFunction", Deepth .. "    ")
    end
end

function Hotfix.LoadFunction(func_str)
    -- 加载函数
    if not func_str then
        Hotfix.FailNotify("load_function error!  func_str is empty.")
        collectgarbage("collect")
        return false
    end

    local NewFunction = loadstring(func_str)
    if not NewFunction then
        Hotfix.FailNotify("load_function " .. func_str .. " has syntax error.")
        collectgarbage("collect")
        return false
    end
    -- 构建沙盒
    Hotfix.FakeENV = Hotfix.FakeT()
    Hotfix.MetaMap = {}
    Hotfix.RequireMap = {}
    -- 将函数环境设置为沙盒
    setfenv(NewFunction, Hotfix.FakeENV)
    local NewObject
    Hotfix.ErrorHappen = false
    -- 在沙盒内执行函数
    xpcall(function() NewObject = NewFunction() end, Hotfix.ErrorHandle)
    if not Hotfix.ErrorHappen then
        return true, NewObject
    else
        collectgarbage("collect")
        return false
    end
end

function Hotfix.UpdateFunction(ModuleName, ClassName, FuncName, FuncStr)
    Hotfix.InfoNotify("[Update Function]:{ModuleName = " .. tostring(ModuleName)
    .. ", ClassName = " .. tostring(ClassName)
    .. ", FuncName = " .. tostring(FuncName))
    Hotfix.ChangedFuncList = {}
    -- 加载函数
    local IsSuccess, newObj = Hotfix.LoadFunction(FuncStr)
    if not IsSuccess then
        collectgarbage("collect")
        return false
    end
    -- table是否存在
    local OldTable
    -- 优先在class中寻找
    if ClassName ~= nil then
        OldTable = class_type()[ClassName]
        if not OldTable then
            Hotfix.FailNotify("In class_type Table which name is " .. ModuleName .. " is not exist.")
            collectgarbage("collect")
            return false
        end
    else
        -- 而后在module中寻找
        OldTable = package.loaded[ModuleName]
        if not OldTable then
            Hotfix.FailNotify("In package.loaded Table which name is " .. ModuleName .. " is not exist.")
            collectgarbage("collect")
            return false
        end
    end

    -- 模块是否返回为table
    if type(OldTable) == "table" then
        local OldObject = OldTable[FuncName]
        if OldObject then
            -- 如果存在，将老的upvalue更新到新的函数上，将新函数的环境改为老函数的环境
            Hotfix.UpdateOneFunction(OldObject, newObj, FuncName, OldTable, "UpdateFunction", "")
            -- 更新沙盒内的功能性函数和未返回的函数
            setmetatable(Hotfix.FakeENV, nil)
            Hotfix.UpdateAllFunction(Hotfix.ENV, Hotfix.FakeENV, " ENV ", "UpdateFunction", "")
            if #Hotfix.ChangedFuncList > 0 then
                Hotfix.Travel_G()
            end
        else
            -- 如果不存在，直接在表中添加此函数
            if Hotfix.Protection[newObj] then
                return
            end
            -- 更该函数环境
            if pcall(debug.setfenv, NewObject, Hotfix.ENV) then
                -- 将新函数添加进表中
                OldTable[FuncName] = newObj
            end
        end
    elseif type(OldTable) == "boolean" then
        -- 如果模块没有返回值则更新沙盒里面的东西（class必须有返回值）
        setmetatable(Hotfix.FakeENV, nil)
        Hotfix.UpdateAllFunction(Hotfix.ENV, Hotfix.FakeENV, " ENV ", "UpdateFunction", "")
        if #Hotfix.ChangedFuncList > 0 then
            Hotfix.Travel_G()
        end
    end
    -- 垃圾清理
    collectgarbage("collect")
end

function Hotfix.UpdateFile(ModuleName, ClassName)
    Hotfix.InfoNotify("[Update file]:{ModuleName = " .. tostring(ModuleName) .. ", ClassName = " .. tostring(ClassName))
    --优先到class里面去找这个
    local OldObject
    if ClassName then
        OldObject = class_type()[ClassName]
    else
        OldObject = package.loaded[ModuleName]
    end

    if OldObject ~= nil then
        Hotfix.VisitedSig = {}
        Hotfix.ChangedFuncList = {}
        local Success, NewObject = Hotfix.BuildNewCode(ModuleName)
        if Success then
            Hotfix.ReplaceOld(OldObject, NewObject, ModuleName, "UpdateFile", "")
            setmetatable(Hotfix.FakeENV, nil)
            Hotfix.UpdateAllFunction(Hotfix.ENV, Hotfix.FakeENV, " ENV ", "UpdateFile", "")
            if #Hotfix.ChangedFuncList > 0 then
                Hotfix.Travel_G()
            end
            collectgarbage("collect")
        end
    elseif Hotfix.OldCode[ModuleName] == nil then
        local IsSuccess, NewCode = Hotfix.ReadFileByModuleName(ModuleName)
        if not IsSuccess then
            Hotfix.FailNotify("The file of module " .. ModuleName .. "is not exist!")
            collectgarbage("collect")
            return
        end
        Hotfix.OldCode[ModuleName] = NewCode
    end
end

function Hotfix.Init(UpdateListFile, RootPath, FailNotify, InfoNotify, ENV)
    Hotfix.UpdateListFile = UpdateListFile
    Hotfix.HFMap = {}
    Hotfix.FileMap = {}
    Hotfix.NotifyFunc = FailNotify
    Hotfix.InfoNotify = InfoNotify
    Hotfix.OldCode = {}
    Hotfix.ChangedFuncList = {}
    Hotfix.VisitedSig = {}
    Hotfix.FakeENV = nil
    Hotfix.ENV = ENV or _G
    Hotfix.LuaPathToSysPath = {}
    Hotfix.Paths = RootPath
    Hotfix.FakeT = Hotfix.InitFakeTable()
    Hotfix.InitProtection()
    Hotfix.AllFile = false
    Hotfix.Forbidden = Hotfix.InitForbiddenTable()
end

function Hotfix.InitForbiddenTable()
    local names = {}
    return names
end

function Hotfix.Update()
    xpcall(
    function()
        package.loaded[Hotfix.UpdateListFile] = nil
        local f = require(Hotfix.UpdateListFile)
        f()
    end, Hotfix.ErrorHandle)
end

return Hotfix