"""Jac MCP schema validation and JSON-RPC request construction."""


obj MCPRequest {
    has method: str;
    has jsonrpc: str = "2.0";
    has id: int = 1;
    has params: dict = {};

    def to_dict() -> dict {
        return {
            "jsonrpc": self.jsonrpc,
            "id": self.id,
            "method": self.method,
            "params": self.params,
        };
    }
}


node MCPServerNode {
    has name: str;
    has transport: str;
    has config: dict = {};
}


walker MCPDiscoveryWalker {
    has requests: list[MCPRequest] = [];
    has reports: list[list[MCPRequest]] = [];

    can begin with Root entry {
        visit [-->[?:MCPServerNode]];
    }

    can discover with MCPServerNode entry {
        self.requests.append(
            MCPRequest(
                id=len(self.requests) + 1,
                method="tools/list",
                params={},
            )
        );
    }

    can finish with Root exit {
        report self.requests;
    }
}


walker MCPExecuteWalker {
    has tool_name: str;
    has arguments: dict = {};
    has request: MCPRequest | None = None;
    has reports: list[MCPRequest] = [];

    can build with MCPServerNode entry {
        self.request = tool_call_request(self.tool_name, self.arguments, 1);
        if self.request is not None {
            report self.request;
        }
    }
}


def initialize_request(client_version: str, request_id: int = 1) -> MCPRequest {
    return MCPRequest(
        id=request_id,
        method="initialize",
        params={
            "protocolVersion": "2025-06-18",
            "capabilities": {},
            "clientInfo": {"name": "swirl", "version": client_version},
        },
    );
}


def tools_list_request(request_id: int = 2) -> MCPRequest {
    return MCPRequest(id=request_id, method="tools/list", params={});
}


def tool_call_request(tool_name: str, arguments: dict, request_id: int = 3) -> MCPRequest {
    if not tool_name.strip() {
        raise ValueError("MCP tool name cannot be empty");
    }
    return MCPRequest(
        id=request_id,
        method="tools/call",
        params={"name": tool_name, "arguments": arguments},
    );
}


def validate_transport(config: dict) -> bool {
    transport: str = str(config.get("transport", "")).lower();
    if transport == "stdio" {
        return bool(str(config.get("command", "")).strip());
    }
    if transport == "http" {
        url: str = str(config.get("url", ""));
        return url.startswith("https://") or url.startswith("http://127.0.0.1") or url.startswith("http://localhost");
    }
    return False;
}
