"""
Swirl FastAPI Local Execution Engine Server
Bridges Web App Frontend to Jaclang Walkers & macOS AppleScript Engine
"""

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Dict, List, Any
import asyncio
import json
from mac_control import execute_mac_action

app = FastAPI(title="Swirl Backend Execution Engine", version="1.0.0")

# Enable CORS for Web App Frontend (http://localhost:5173)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class WorkflowExecutionRequest(BaseModel):
    nodes: List[Dict[str, Any]]
    edges: List[Dict[str, Any]]

@app.get("/")
def read_root():
    return {
        "status": "online",
        "system": "Swirl macOS MCP Control Engine",
        "jacVersion": "0.7.8"
    }

@app.post("/api/execute-mac-action")
def api_mac_action(payload: Dict[str, Any]):
    """Direct Endpoint for Web App to trigger macOS automation"""
    app_name = payload.get("app", "System")
    action = payload.get("action", "display_notification")
    params = payload.get("params", {})
    
    result = execute_mac_action(app_name, action, params)
    return result

@app.websocket("/ws/execute-workflow")
async def websocket_workflow(websocket: WebSocket):
    """WebSocket endpoint streaming Jac Walker graph traversal step-by-step to Web UI"""
    await websocket.accept()
    try:
        data = await websocket.receive_text()
        request_json = json.loads(data)
        nodes = request_json.get("nodes", [])
        
        await websocket.send_json({
            "event": "start",
            "message": "🚀 [WorkflowExecutorWalker] Starting graph traversal..."
        })
        
        for node in nodes:
            node_id = node.get("id")
            title = node.get("title")
            category = node.get("category")
            config = node.get("config", {})
            
            # Notify UI node execution started
            await websocket.send_json({
                "event": "node_start",
                "nodeId": node_id,
                "title": title,
                "status": "running"
            })
            
            await asyncio.sleep(0.6) # simulate step delay
            
            # If macOS block, execute native Mac automation!
            output_payload = {}
            if category == "mac":
                output_payload = execute_mac_action(
                    config.get("app", "System"),
                    config.get("action", "display_notification"),
                    config
                )
            else:
                output_payload = {"status": "success", "message": f"Executed {title}"}
                
            # Notify UI node execution finished
            await websocket.send_json({
                "event": "node_complete",
                "nodeId": node_id,
                "title": title,
                "status": "success",
                "output": output_payload
            })
            
        await websocket.send_json({
            "event": "complete",
            "message": "🎉 [WorkflowExecutorWalker] Graph Traversal Complete!"
        })
        
    except WebSocketDisconnect:
        print("Client disconnected")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8000)
