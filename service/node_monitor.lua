local Skynet = require "skynet"
local Acceptor = require 'acceptor'
local Connector = require 'connector'
local OnlineClient = require 'client.online'
local ServiceStateClient = require "client.service_state"
local ClusterMonitorClient = require 'client.cluster_monitor'

local _call_gated = function(api, ...)
    local ok, ret = pcall(Cluster.call, NODE_NAME, 'gated', api, ...)
    if ok then return ret end
    return {errcode = ERRNO.E_SERVICE_UNAVAILABLE, errdata=ret}
end

local is_shutdown = false
local services_monitered = {}
local cluster_monitor_connector = nil

local function connect_cluster_monitor_cb(...)
    LOG_INFO("trying to connect cluster_monitor", ...)
    return ClusterMonitorClient.connect(...)
end

local function connected_cluster_monitor_cb()
    LOG_INFO("cluster_monitor is connected")
    
    local ret = ClusterMonitorClient.register_node(NODE_NAME, Skynet.self())
    if ret.errcode ~= ERRNO.E_OK then
        LOG_ERROR(
            "cluster_monitor is connected, register node fail, errcode<%s>",
            ret.errcode
        )
        return false
    end
    
    ret = OnlineClient.clear_node(NODE_NAME)
    if ret.errcode ~= ERRNO.E_OK then
        LOG_ERROR("online service clear node fail, errcode<%s>", ret.errcode)
        return false
    end
    
    if not ServiceStateClient.is_useable('gated') then
        return true
    end
   
    local users = _call_gated('get_users')
    if users then
        ret = OnlineClient.register_node(NODE_NAME, users)
        if ret.errcode ~= ERRNO.E_OK then
            LOG_ERROR('register online users fail, errcode<%s>', ret.errcode)
            return false
        end
        
        if table.empty(ret.fail_list) then
            return true
        end
        
        for _, item in ipairs(fail_list) do
            local ok, ret = _call_gated('kick', item.uid, item.subid)
            if not ok then
                LOG_INFO(
                    'kick fail, user uid<%s> subid<%s> node<%s> , err<%s>',
                    item.uid, item.subid,node,  ret
                )
            end
        end
    end
    
    return true
end

local function disconnect_cluster_monitor_cb()
    LOG_ERROR("cluster_monitor is disconnect !")
    return true
end

local Cmd = {}

function Cmd.connect(...)
    return Acceptor.connect_handler(...)
end

function Cmd.register(service_addr, service_name)
    assert(service_addr, 'illgal service_addr')
    assert(service_name, 'illgal service_name')
    
    if is_shutdown then
        LOG_ERROR(
            "system is shutdown, register fail, addr<%s> type<%s>",
            service_addr, service_name
        )
        return
    end

    services_monitered[service_addr] = service_name
    
    LOG_INFO(
        "register service_addr<%x> service_name<%s>", 
        service_addr, service_name
    )
    
    local ret = ClusterMonitorClient.register_service_name(NODE_NAME,service_name)
    if ret.errcode ~= ERRNO.E_OK then
        LOG_ERROR(
            "cluster_monitor is connected, register_service_name fail, errcode<%s>",
            ret.errcode
        )
        return false
    end
end

function Cmd.unregister(service_addr)
    assert(service_addr, 'illgal service_addr')
    
    local service_name = services_monitered[service_addr]
    if not service_name then
        LOG_INFO("service<%x> exit", service_addr)
        return
    end
    
    services_monitered[service_addr] = nil
    
    LOG_INFO(
        "service<%s> exit, unregister service_name<%s>", 
        service_addr,service_name
    )
end

function Cmd.get_service_num(service_name)
    assert(service_name, 'illgal service_name')
    
    local count = 0
    for _addr, _name in pairs(services_monitered) do
        if _name == service_name then
            count = count + 1
        end
    end
    
    Skynet.retpack(count)
end

function Cmd.close_service(service_name)
    for _addr, _name in pairs(services_monitered) do
        if _name == service_name then
            LOG_INFO(
                "close service, addr<%s>, type<%s>", 
                _addr, _name
            )
            
            Skynet.send(_addr, "sys", "EXIT")
        end
    end
    
    Skynet.retpack({errcode = ERRNO.E_OK})
end

function Cmd.close_node()
    is_shutdown = true
    Skynet.retpack({errcode = ERRNO.E_OK})

    local seconds = 3
    LOG_INFO("node will close in %s seconds", seconds)
    Skynet.sleep(seconds * 100)
    Skynet.abort()
end

function Cmd.reload_res()
    for _addr, _name in pairs(services_monitered) do
        if _name == 'res_mgr' then
            LOG_INFO(
                "reload_res, service_addr<%s>, service_name<%s>", 
                _addr, _name
            )
            
            Skynet.call(_addr,'lua', "reload_res")
        end
    end
    
    Skynet.retpack({errcode = ERRNO.E_OK})
end

Skynet.register_protocol {
    name = "client",
    id = 3,
    unpack = function() end,
    dispatch = function(_, service_addr)
        Cmd.unregister(service_addr)
    end
}

Skynet.start(function()
    Skynet.dispatch("lua",function(session, addr, cmd, ...)
        local f = assert(Cmd[cmd], cmd)
        f(...)
    end)
    
    cluster_monitor_connector = Connector(
        connect_cluster_monitor_cb,
        connected_cluster_monitor_cb,
        disconnect_cluster_monitor_cb
    )
    cluster_monitor_connector:start()
    
    LOG_INFO('node_moniter booted')
end)

