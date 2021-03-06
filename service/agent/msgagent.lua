local skynet = require "skynet"
local queue = require "skynet.queue"
local snax = require "snax"
local netpack = require "netpack"
local lfs = require"lfs"
local SprotoLoader = require "sprotoloader"
local SprotoEnv = require "sproto_env"
local Env = require 'env'
local Cmd = require 'command'
local RoleApi = require 'apis.role_api'
local OnlineClient = require 'client.online'

local c2s_sp = SprotoLoader.load(SprotoEnv.PID_C2S)
local c2s_host = c2s_sp:host(SprotoEnv.PACKAGE)

local cs = queue()
local UID
local SUB_ID
local SECRET
local afktime = 0

local gate		-- 游戏服务器gate地址
local fd        -- msgagent对应的fd应用层套接字
local zinc_client   -- msgagent对应的zinc_client服务

local CMD = {}

local worker_co
local running = false

local timer_list = {}

local function add_timer(id, interval, f)
	local timer_node = {}
	timer_node.id = id
	timer_node.interval = interval
	timer_node.callback = f
	timer_node.trigger_time = skynet.now() + interval

	timer_list[id] = timer_node
end

local function del_timer(id)
	timer_list[id] = nil
end

local function clear_timer()
	timer_list = {}
end

local function dispatch_timertask()
	local now = skynet.now()
	for k, v in pairs(timer_list) do
		if now >= v.trigger_time then
			v.callback()
			v.trigger_time = now + v.interval
		end
	end
end

local function worker()
	local t = skynet.now()
	while running do
		dispatch_timertask()
		local n = 100 + t - skynet.now()
		skynet.sleep(n)
		t = t + 100
	end
end

local function logout()
	if running then
		running = false
		skynet.wakeup(worker_co)	-- 通知协程退出
	end

	if gate then
		skynet.call(gate, "lua", "logout", UID, SUB_ID)
	end
	
	OnlineClient.offline(UID)

	gate = nil
	UID = nil
	SUB_ID = nil
	SECRET = nil
	fd = nil

	ti = {}
	afktime = 0
	
	skynet.kill(zinc_client)
	zinc_client = nil

	-- 卸载玩家数据
	RoleApi.apis.close()
	
	--这里不退出agent服务，以便agent能复用
	--skynet.exit()	-- 玩家显示登出，需要退出agent服务
end

-- 空闲登出
local function idle()
	if afktime > 0 then
		if skynet.time() - afktime >= 60 then		-- 玩家断开连接后一分钟强制登出
			logout()
		end
	end
end

local function reg_timers()
	add_timer(1, 500, idle)
end

-- 玩家登录游服后调用
function CMD.login(source, uid, subid, secret)
	-- you may use secret to make a encrypted data stream
	LOG_INFO(string.format("%d is login", uid))
	gate = source
	UID = uid
	SUB_ID = subid
	SECRET = secret
    
	ti = {}
	afktime = 0
end

-- 玩家登录游服，握手成功后调用
function CMD.auth(source, uid,fd)
	LOG_INFO(string.format("%d is real login", uid))
	
	fd = fd
	
	zinc_client = skynet.launch("zinc_client", fd)
	
	LOG_INFO(
	    "init agent's environmnet uid=%d fd=%d zinc_client=%x", 
	    uid, fd,zinc_client
    )
	RoleApi.apis.start({uid = uid,zinc_client = zinc_client})
	
    local ret = OnlineClient.online(NODE_NAME, skynet.self(),UID,SUB_ID)
    if ret.errcode ~= ERRNO.E_OK then
        LOG_INFO('OnlineClient.online fail, ac:<%s>, errcode<%s>', UID, ret.errcode)
    end
	
	if not running then
		running = true
		reg_timers()
		worker_co = skynet.fork(worker)
	end
end

function CMD.logout(source)
	-- NOTICE: The logout MAY be reentry
	skynet.error(string.format("%s is logout,subid=%d", UID, SUB_ID))
	logout()
end

function CMD.afk(source)
	-- the connection is broken, but the user may back
	afktime = skynet.time()
	skynet.error(string.format("AFK"))
end

local request_handlers = {}

local function load_request_handlers()
    local path = skynet.getenv('rpc_path') or './service/agent/rpc'
    for file in lfs.dir(path) do
        local _,suffix = file:match "([^.]*).(.*)"
        if suffix == 'lua' then
            local module_data = setmetatable({}, { __index = _ENV })
            local routine, err = loadfile(path..'/'..file, "bt", module_data)
            assert(routine, err)()
            
            for k, v in pairs(module_data) do
                if type(v) == 'function' then
                    request_handlers[k] = v
                end
            end
        end
    end
end

local function msg_unpack(msg, sz)
	local netmsg = netpack.tostring(msg, sz, 0) 
	if not netmsg then
		LOG_ERROR("msg_unpack error")
		error("msg_unpack error")
	end
	
	return netmsg
end

local function format_errmsg(errno, errmsg)
	local err = {}
	err.code = errno or 0
	err.desc = errmsg
	return err
end

local function msg_dispatch(netmsg)
    local begin = skynet.time()
	local type, name, request, response = c2s_host:dispatch(netmsg)
	
	if not request_handlers[name] then
	    LOG_ERROR('request_handler %s not exist or not loaded',name)
	end
	
	local r = request_handlers[name](request)
	
	LOG_INFO("process %s time used %f ms", name, (skynet.time()-begin)*10)
	return response(r)	
end

skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,

	unpack = function (msg, sz)
		return msg_unpack(msg, sz)
	end,

	dispatch = function (_, _, netmsg)
		skynet.ret(msg_dispatch(netmsg))
	end
}

skynet.start(function()
    -- If you want to fork a work thread , you MUST do it in CMD.login
	skynet.dispatch("lua", function(session, source, command, ...)
		if Cmd[command] then 
		    Cmd[command](...)
		else
		    local f = assert(CMD[command],string.format('illegal command:%s',command))
		    skynet.retpack(cs(f, source, ...))
	    end
	end)
	
	load_request_handlers()
end)
