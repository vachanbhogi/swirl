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

"""Built-in MCP server definitions owned by the Jac workflow layer."""
def builtin_mcp_servers() -> list[dict] {
    return [
        {
            "name": "fetch-mcp-server",
            "transport": "stdio",
            "command": "npx",
            "args": ["-y", "@modelcontextprotocol/server-fetch"],
            "description": "Fetch web pages for downstream AI transforms.",
        },
        {
            "name": "filesystem",
            "transport": "stdio",
            "command": "npx",
            "args": ["-y", "@modelcontextprotocol/server-filesystem", "/Users"],
            "description": "Read approved local files through the MCP filesystem server.",
        },
        {
            "name": "brave-search-mcp",
            "transport": "stdio",
            "command": "npx",
            "args": ["-y", "@modelcontextprotocol/server-brave-search"],
            "description": "Search the web through a configured Brave MCP server.",
        },
    ];
}

def builtin_mcp_server(name: str) -> dict {
    for server in builtin_mcp_servers() {
        if str(server.get("name", "")) == name {
            return server;
        }
    }
    raise ValueError(f"Unknown built-in MCP server: {name}");
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


obj MCPResponse {
    has jsonrpc: str = "2.0";
    has id: int;
    has result: dict = {};
    has error: dict = {};

    def is_error() -> bool {
        return bool(self.error);
    }

    def error_message() -> str {
        if self.is_error() {
            return str(self.error.get("message", "Unknown error"));
        }
        return "";
    }

    def to_dict() -> dict {
        res: dict = {
            "jsonrpc": self.jsonrpc,
            "id": self.id,
        };
        if self.is_error() {
            res["error"] = self.error;
        } else {
            res["result"] = self.result;
        }
        return res;
    }
}


obj MCPToolSchema {
    has name: str;
    has description: str = "";
    has input_schema: dict = {};

    def to_dict() -> dict {
        return {
            "name": self.name,
            "description": self.description,
            "inputSchema": self.input_schema,
        };
    }

    def to_block_definition() -> dict {
        return {
            "type": "tool",
            "name": self.name,
            "description": self.description,
            "schema": self.input_schema,
        };
    }
}


obj MCPServerConfig {
    has name: str;
    has transport: str;
    has command: str = "";
    has args: list[str] = [];
    has url: str = "";
    has env: dict = {};

    def validate() -> bool {
        if not validate_server_name(self.name) {
            return False;
        }
        if self.transport == "stdio" {
            return bool(self.command.strip());
        }
        if self.transport == "http" {
            return self.url.startswith("https://") or self.url.startswith("http://127.0.0.1") or self.url.startswith("http://localhost");
        }
        return False;
    }

    def to_dict() -> dict {
        return {
            "name": self.name,
            "transport": self.transport,
            "command": self.command,
            "args": self.args,
            "url": self.url,
            "env": self.env,
        };
    }
}


def validate_server_name(name: str) -> bool {
    if not name or len(name) > 80 {
        return False;
    }
    for char in name {
        if not (char.isalnum() or char == "-" or char == "_") {
            return False;
        }
    }
    return True;
}


def parse_tools_response(response: dict) -> list[MCPToolSchema] {
    tools_list: list[MCPToolSchema] = [];
    result: dict = response.get("result", {});
    tools: list = result.get("tools", []);
    for tool_data in tools {
        tools_list.append(
            MCPToolSchema(
                name=str(tool_data.get("name", "")),
                description=str(tool_data.get("description", "")),
                input_schema=dict(tool_data.get("inputSchema", {})),
            )
        );
    }
    return tools_list;
}


def validate_tool_arguments(schema: dict, arguments: dict) -> list[str] {
    errors: list[str] = [];
    properties: dict = schema.get("properties", {});
    required: list = schema.get("required", []);
    
    for req in required {
        if req not in arguments {
            errors.append(f"Missing required argument: {req}");
        }
    }
    
    for key, val in arguments.items() {
        if key in properties {
            expected_type: str = str(properties[key].get("type", ""));
            if expected_type == "string" and not isinstance(val, str) {
                errors.append(f"Argument '{key}' should be a string");
            }
            if expected_type == "integer" and not isinstance(val, int) {
                errors.append(f"Argument '{key}' should be an integer");
            }
            if expected_type == "boolean" and not isinstance(val, bool) {
                errors.append(f"Argument '{key}' should be a boolean");
            }
        }
    }
    
    return errors;
}


def notifications_initialized_request() -> MCPRequest {
    return MCPRequest(
        id=0,
        method="notifications/initialized",
        params={},
    );
}


def resources_list_request(request_id: int = 4) -> MCPRequest {
    return MCPRequest(
        id=request_id,
        method="resources/list",
        params={},
    );
}


def prompts_list_request(request_id: int = 5) -> MCPRequest {
    return MCPRequest(
        id=request_id,
        method="prompts/list",
        params={},
    );
}


walker MCPToolRegistryWalker {
    has tool_registry: dict[str, list[MCPToolSchema]] = {};
    has reports: list[dict] = [];

    can begin with Root entry {
        visit [-->[?:MCPServerNode]];
    }

    can register with MCPServerNode entry {
        self.tool_registry[here.name] = [];
    }

    can finish with Root exit {
        report self.tool_registry;
    }
}
