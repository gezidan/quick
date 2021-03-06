local Const = require 'const'
local Sign = require 'cls.sign'

local apis ={}

function apis:init_sign()
    self.sign = Sign(self._role_td.sign)
end

function apis:view_sign()
    return {
        errcode = 0,
        sign = self.sign:gen_proto(),
    }
end

local triggers = {
    [Const.EVT_ONLINE] = function(self)
        self:init_sign()
        return
    end,

    [Const.EVT_OFFLINE] = function(self)
        return
    end
}

return {apis = apis, triggers = triggers}
