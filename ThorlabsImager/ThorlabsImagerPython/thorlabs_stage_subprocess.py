"""
Stage control wrapper that communicates with a persistent stage server process.
This avoids the overhead of starting a new Python process for each command.

The server stays alive for the duration of the scan, dramatically improving performance.
"""

import subprocess
import sys
import json
import os
import atexit

# Global server process
_server_process = None


def _start_server():
    """Start the persistent stage server process."""
    global _server_process
    
    if _server_process is not None:
        return  # Already started
    
    # Get path to server script
    module_dir = os.path.dirname(os.path.abspath(__file__))
    server_script = os.path.join(module_dir, 'thorlabs_stage_server.py')
    
    if not os.path.exists(server_script):
        raise FileNotFoundError(f"Stage server script not found: {server_script}")
    
    # Start server process
    _server_process = subprocess.Popen(
        [sys.executable, server_script],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,  # Line buffered
    )
    
    # Wait for ready signal
    try:
        ready_line = _server_process.stdout.readline()
        ready_msg = json.loads(ready_line.strip())
        if ready_msg.get("status") != "ready":
            raise RuntimeError("Server failed to start")
    except Exception as e:
        _stop_server()
        raise RuntimeError(f"Failed to start stage server: {e}")
    
    # Register cleanup on exit
    atexit.register(_stop_server)


def _stop_server():
    """Stop the persistent stage server process."""
    global _server_process
    
    if _server_process is None:
        return
    
    try:
        # Send shutdown command
        cmd = {"command": "shutdown", "args": []}
        _server_process.stdin.write(json.dumps(cmd) + '\n')
        _server_process.stdin.flush()
        
        # Wait for server to exit
        _server_process.wait(timeout=5)
    except:
        # Force kill if shutdown fails
        _server_process.kill()
    finally:
        _server_process = None


def _send_command(command, *args):
    """Send a command to the stage server and get response.
    
    Args:
        command (str): Command name ('init', 'move', 'close')
        *args: Arguments for the command
    
    Returns:
        Result from the command (if any)
    
    Raises:
        RuntimeError: If command fails
    """
    global _server_process
    
    # Ensure server is running
    _start_server()
    
    try:
        # Send command
        cmd = {"command": command, "args": [str(arg) for arg in args]}
        _server_process.stdin.write(json.dumps(cmd) + '\n')
        _server_process.stdin.flush()
        
        # Read response
        response_line = _server_process.stdout.readline()
        if not response_line:
            raise RuntimeError("Server terminated unexpectedly")
        
        response = json.loads(response_line.strip())
        
        if response["status"] == "ok":
            return response.get("result")
        else:
            error_msg = response.get("message", "Unknown error")
            raise RuntimeError(f"Stage command '{command}' failed: {error_msg}")
            
    except json.JSONDecodeError as e:
        raise RuntimeError(f"Failed to parse server response: {e}")
    except BrokenPipeError:
        _server_process = None
        raise RuntimeError("Lost connection to stage server")


def yOCTStageInit_1axis(axis):
    """
    Initialize stage for one axis using persistent server.
    
    Args:
        axis (str): 'x', 'y', or 'z'
    
    Returns:
        float: Current position in mm
    """
    result = _send_command('init', axis)
    if result is None:
        raise RuntimeError(f"Stage init returned no output for axis {axis}")
    return float(result)


def yOCTStageSetPosition_1axis(axis, position_mm):
    """
    Move stage axis to position using persistent server.
    
    Args:
        axis (str): 'x', 'y', or 'z'
        position_mm (float): Target position in mm
    """
    _send_command('move', axis, position_mm)


def yOCTStageClose_1axis(axis):
    """
    Close stage axis using persistent server.
    
    Args:
        axis (str): 'x', 'y', or 'z'
    """
    _send_command('close', axis)


def yOCTStageShutdown():
    """
    Shutdown the persistent stage server.
    Call this at the end of scanning to ensure clean shutdown.
    """
    _stop_server()
