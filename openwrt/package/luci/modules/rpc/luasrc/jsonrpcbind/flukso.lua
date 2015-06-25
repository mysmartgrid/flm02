local table = require "table"
local luci = require "luci"

module "luci.jsonrpcbind.flukso"
_M, _PACKAGE, _NAME = nil, nil, nil

function fsync()
	luci.util.exec("fsync")
	return 1;
end
