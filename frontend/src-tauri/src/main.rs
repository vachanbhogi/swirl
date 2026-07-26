// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::process::Command;
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct MacActionResult {
    pub success: bool,
    pub output: Option<String>,
    pub error: Option<String>,
}

/// Native Tauri Command: Executes AppleScript on macOS directly via Rust Command
#[tauri::command]
fn execute_mac_applescript(script: String) -> MacActionResult {
    println!("💻 [Tauri Rust Native] Executing AppleScript:\n{}", script);
    
    match Command::new("osascript").arg("-e").arg(&script).output() {
        Ok(output) => {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
                MacActionResult {
                    success: true,
                    output: Some(stdout),
                    error: None,
                }
            } else {
                let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
                MacActionResult {
                    success: false,
                    output: None,
                    error: Some(stderr),
                }
            }
        }
        Err(err) => MacActionResult {
            success: false,
            output: None,
            error: Some(err.to_string()),
        },
    }
}

/// Native Tauri Command: Executes Zsh / Bash CLI command on macOS
#[tauri::command]
fn execute_mac_shell(command: String) -> MacActionResult {
    println!("⚡ [Tauri Rust Native] Executing Shell Command: {}", command);

    match Command::new("/bin/zsh").arg("-c").arg(&command).output() {
        Ok(output) => {
            let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
            MacActionResult {
                success: output.status.success(),
                output: if stdout.is_empty() { None } else { Some(stdout) },
                error: if stderr.is_empty() { None } else { Some(stderr) },
            }
        }
        Err(err) => MacActionResult {
            success: false,
            output: None,
            error: Some(err.to_string()),
        },
    }
}

fn main() {
    println!("🌀 Starting Swirl Tauri Desktop Application...");
    
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            execute_mac_applescript,
            execute_mac_shell
        ])
        .run(tauri::generate_context!())
        .expect("error while running swirl tauri desktop application");
}
