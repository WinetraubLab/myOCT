"""
Persistent stage control server that stays alive to avoid repeated initialization.
This dramatically improves performance by eliminating subprocess startup overhead.

Communication protocol:
- Commands sent via stdin as JSON: {"command": "init", "args": ["x"]}
- Responses sent via stdout as JSON: {"status": "ok", "result": 0.0}
- Errors sent as: {"status": "error", "message": "error details"}
"""

import sys
import json
import os

# Import stage control functions
import threading

def _run_with_timeout(func, timeout_s):
    result = [None]
    exc = [None]
    def target():
        try:
            result[0] = func()
        except Exception as e:
            exc[0] = e
    t = threading.Thread(target=target)
    t.start()
    t.join(timeout_s)
    if t.is_alive():
        raise TimeoutError(f"Operation timed out after {timeout_s} seconds.")
    if exc[0]:
        raise exc[0]
    return result[0]

# Import XA SDK
from xa_sdk.native_sdks.xa_sdk import XASDK
from xa_sdk.shared.tlmc_type_structures import (
    TLMC_OperatingModes, TLMC_ChannelEnableStates, TLMC_Wait, 
    TLMC_ScaleType, TLMC_Unit, TLMC_MoveModes
)
from xa_sdk.shared.xa_error_factory import XADeviceException
from xa_sdk.products.kst201 import KST201

# Axis to serial number mapping
_stage_serial_numbers = {
    'x': '26006464',
    'y': '26006471',
    'z': '26006482'
}

# Stage handles
_stage_handles = {}

# XA SDK initialized flag
_xa_initialized = False


def init_xa_sdk():
    """Initialize XA SDK once."""
    global _xa_initialized
    if not _xa_initialized:
        dll_path = os.path.dirname(__file__)
        XASDK.try_load_library(dll_path)
        XASDK.startup("")
        _xa_initialized = True


def handle_init(axis):
    """Initialize stage axis."""
    global _stage_handles
    
    axis = axis.lower()
    actuator_model = "ZST225"
    
    if axis not in _stage_serial_numbers:
        raise ValueError(f"Invalid axis: {axis}")
    
    serial_no = _stage_serial_numbers[axis]
    
    try:
        init_xa_sdk()
        
        device = KST201(serial_no, "", TLMC_OperatingModes.Default)
        device.set_enable_state(TLMC_ChannelEnableStates.ChannelEnabled)
        device.set_connected_product(actuator_model)
        
        pos_counts = device.get_position_counter(TLMC_Wait.TLMC_InfiniteWait)
        pos_conv = device.convert_from_device_units_to_physical(
            TLMC_ScaleType.TLMC_ScaleType_Distance,
            pos_counts
        )
        pos_mm = pos_conv.converted_value
        
        _stage_handles[axis] = device
        return pos_mm
        
    except Exception as e:
        if axis in _stage_handles:
            try:
                _stage_handles[axis].close()
            except:
                pass
            del _stage_handles[axis]
        raise


def handle_move(axis, position_mm):
    """Move stage axis to position."""
    global _stage_handles
    
    axis = axis.lower()
    
    # Auto-init if not initialized
    if axis not in _stage_handles:
        handle_init(axis)
    
    device = _stage_handles[axis]
    
    try:
        # Validate limits
        min_mm, max_mm = 0.0, 13.0
        if not (min_mm <= position_mm <= max_mm):
            raise ValueError(f"Position {position_mm} mm out of range [{min_mm}, {max_mm}]")
        
        # Get current position
        current_counts = device.get_position_counter(TLMC_Wait.TLMC_InfiniteWait)
        current_conv = device.convert_from_device_units_to_physical(
            TLMC_ScaleType.TLMC_ScaleType_Distance,
            current_counts
        )
        current_mm = current_conv.converted_value
        delta_mm = float(position_mm) - float(current_mm)
        
        if abs(delta_mm) < 1e-6:
            return  # Already at target
        
        # Relative move
        rel_param = device.convert_from_physical_to_device(
            TLMC_ScaleType.TLMC_ScaleType_Distance,
            TLMC_Unit.TLMC_Unit_Millimetres,
            delta_mm
        )
        device.set_move_relative_params(rel_param)
        
        _run_with_timeout(lambda: device.move_relative(
            TLMC_MoveModes.MoveMode_RelativeByProgrammedDistance,
            TLMC_Wait.TLMC_Unused,
            TLMC_Wait.TLMC_InfiniteWait
        ), 60)
        
    except Exception as e:
        raise RuntimeError(f"Move failed for axis {axis}: {e}")


def handle_close(axis):
    """Close stage axis."""
    global _stage_handles
    
    axis = axis.lower()
    
    if axis in _stage_handles:
        try:
            _stage_handles[axis].disconnect()
            _stage_handles[axis].close()
        except:
            pass
        del _stage_handles[axis]


def handle_shutdown():
    """Close all axes and shutdown."""
    for axis in list(_stage_handles.keys()):
        handle_close(axis)


def send_response(status, result=None, message=None):
    """Send JSON response to stdout."""
    response = {"status": status}
    if result is not None:
        response["result"] = result
    if message is not None:
        response["message"] = message
    print(json.dumps(response), flush=True)


def main():
    """Main server loop - read commands from stdin, execute, send responses."""
    
    # Ensure unbuffered I/O
    sys.stdin.reconfigure(line_buffering=True)
    sys.stdout.reconfigure(line_buffering=True)
    
    # Send ready signal
    send_response("ready")
    
    try:
        while True:
            # Read command from stdin
            line = sys.stdin.readline()
            if not line:
                break  # EOF
            
            try:
                cmd = json.loads(line.strip())
                command = cmd.get("command")
                args = cmd.get("args", [])
                
                if command == "init":
                    result = handle_init(args[0])
                    send_response("ok", result=result)
                    
                elif command == "move":
                    handle_move(args[0], float(args[1]))
                    send_response("ok", result="OK")
                    
                elif command == "close":
                    handle_close(args[0])
                    send_response("ok", result="OK")
                    
                elif command == "shutdown":
                    handle_shutdown()
                    send_response("ok", result="OK")
                    break
                    
                else:
                    send_response("error", message=f"Unknown command: {command}")
                    
            except Exception as e:
                send_response("error", message=str(e))
                
    except KeyboardInterrupt:
        pass
    finally:
        handle_shutdown()


if __name__ == '__main__':
    main()
