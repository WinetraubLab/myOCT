"""
Low-level hardware functions for Thorlabs OCT system.
This module provides direct hardware interaction functions similar to the MATLAB/C/DLL interface.

These functions are called by high-level scanning functions like yOCTScanTile and yOCTPhotobleachTile.

Function Naming Convention:
(Implemented)
- OCT functions: yOCTScannerInit,  yOCTScannerClose

(not yet implemented)
- OCT functions: yOCTScan3DVolume, yOCTPhotobleachLine
- Stage functions: yOCTStageInit_1axis, yOCTStageSetPosition_1axis
- Laser functions: (DiodeCtrl equivalent functions)
- Optical switch: yOCTTurnOpticalSwitch
"""

from pyspectralradar import OCTSystem, RawData, RealData
import pyspectralradar.types as pt
import os
import time
from datetime import datetime
import configparser
import threading

import time
from xa_sdk.native_sdks.xa_sdk import XASDK
from xa_sdk.shared.tlmc_type_structures import *
from xa_sdk.shared.xa_error_factory import XADeviceException
from xa_sdk.products.kst201 import KST201

# Global variables to maintain state across function calls
_oct_system = None
_device = None
_probe = None
_processing = None
_probe_config = {}
_scanner_initialized = False

_stage_initialized = False
_stage_origin = {'x': 0, 'y': 0, 'z': 0}
_stage_angle = 0

_laser_on = False
_laser_power = 0

_optical_switch_on = False


# ============================================================================
# OCT SCANNER FUNCTIONS
# ============================================================================

def yOCTScannerInit(octProbePath : str) -> None:
    """Initialize scanner with a probe file.
    
    Equivalent to C++/DLL: ThorlabsImagerNET.ThorlabsImager.yOCTScannerInit(octProbePath)
    
    Args:
        octProbePath (str): Path to the probe configuration .ini file
    
    Returns:
        None
    
    Raises:
        FileNotFoundError: If probe file does not exist
        RuntimeError: If scanner is already initialized or OCT system initialization fails
    """
    global _oct_system, _device, _probe, _processing, _probe_config, _scanner_initialized
    
    # Check if scanner is already initialized
    if _scanner_initialized:
        raise RuntimeError("Scanner is already initialized. Call yOCTScannerClose() first.")
    
    try:
        # Initialize OCT system
        _oct_system = OCTSystem()
        _device = _oct_system.dev
        
        # Load probe configuration from .ini file
        # This dictionary contains all parameters, including myOCT-specific ones
        # (like DynamicFactorX, Oct2StageXYAngleDeg) that aren't SDK properties
        _probe_config = _read_probe_ini(octProbePath)
        
        # Create probe with default settings, then configure from .ini file
        _probe = _oct_system.probe_factory.create_default()
        
        # Apply calibration parameters from .ini file to probe
        _apply_probe_config_to_probe(_probe, _probe_config)
        
        # Create processing pipeline
        _processing = _oct_system.processing_factory.from_device()
        
        _scanner_initialized = True
        
    except Exception as e:
        _scanner_initialized = False
        raise


def yOCTScannerClose():
    """Free-up scanner resources.
    
    Equivalent to C++/DLL: ThorlabsImagerNET.ThorlabsImager.yOCTScannerClose()
    
    In Python SDK, cleanup is done by deleting objects in reverse order of creation.
    
    Args:
        None
    
    Returns:
        None
    
    Raises:
        None
    """
    global _oct_system, _device, _probe, _processing, _scanner_initialized
    
    # Delete objects in reverse order of creation (from most derived to base)
    # This follows the pattern shown in the official pySpectralRadar demos
    if _processing is not None:
        del _processing
    if _probe is not None:
        del _probe
    if _device is not None:
        del _device
    if _oct_system is not None:
        del _oct_system
    
    _scanner_initialized = False


# ============================================================================
# STAGE CONTROL FUNCTIONS
# ============================================================================


# Axis to serial number mapping
_stage_serial_numbers = {
    'x': '26006464',
    'y': '26006471',
    'z': '26006482'
}

# Stage handles for each axis
_stage_handles = {}

def yOCTStageInit_1axis(axes: str) -> float:
    """
    Initialize stage for one axis (C++ style: axes='x','y','z'). Returns current position in mm.
    Args:
        axes (str): Axis character ('x', 'y', or 'z')
    Returns:
        float: Current position in mm
    """
    axis = axes.lower()
    actuator_model = "ZST225"  
    if axis not in _stage_serial_numbers:
        raise ValueError(f"Invalid axis: {axes}")
    serial_no = _stage_serial_numbers[axis]
    try:
        if not hasattr(XASDK, '_oct_xa_started'):
            dll_path = os.path.dirname(__file__)
            XASDK.try_load_library(dll_path)
            XASDK.startup("")
            XASDK._oct_xa_started = True
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
    except XADeviceException as e:
        if axis in _stage_handles:
            _stage_handles[axis].close()
            del _stage_handles[axis]
        raise RuntimeError(f"XADeviceException during stage init: {e.error_code}")
    except Exception as e:
        # Surface initialization errors as exceptions for caller handling
        raise RuntimeError(f"Error initializing stage for axis '{axis}': {e}")
        # Clean up partially created device if possible
        if 'device' in locals():
            try:
                device.close()
            except Exception:
                pass
        if axis in _stage_handles:
            try:
                _stage_handles[axis].close()
            except Exception:
                pass
            del _stage_handles[axis]
        raise


def yOCTStageSetPosition_1axis(axis: str, position_mm: float) -> None:
    """
    Move stage axis to position in mm using XA SDK.
    Args:
        axis (str): 'x', 'y', or 'z'
        position_mm (float): Target position in mm
    Returns:
        None
    """
    axis = axis.lower()
    if axis not in _stage_handles:
        raise RuntimeError(f"Stage for axis {axis} not initialized.")
    device = _stage_handles[axis]
    try:
        # Validate travel limits (example: 0 to 13 mm, adjust for your actuator)
        min_mm, max_mm = 0.0, 13.0
        if not (min_mm <= position_mm <= max_mm):
            raise ValueError(f"Target {position_mm} mm out of range for axis {axis} [{min_mm}, {max_mm}] mm.")

        # Read current position (blocking wait) and compute delta
        current_counts = device.get_position_counter(TLMC_Wait.TLMC_InfiniteWait)
        current_conv = device.convert_from_device_units_to_physical(
            TLMC_ScaleType.TLMC_ScaleType_Distance,
            current_counts
        )
        current_mm = current_conv.converted_value
        delta_mm = float(position_mm) - float(current_mm)

        if abs(delta_mm) < 1e-6:
            # Already at target (within tolerance) — no action needed
            return

        # Use a relative move (safer than guessing absolute API signature).
        # Convert the delta to device units and set as relative move parameter.
        rel_param = device.convert_from_physical_to_device(
            TLMC_ScaleType.TLMC_ScaleType_Distance,
            TLMC_Unit.TLMC_Unit_Millimetres,
            delta_mm
        )
        device.set_move_relative_params(rel_param)

        MOVE_TIMEOUT_S = 60
        # Use the MoveMode_RelativeByProgrammedDistance mode which uses the previously set relative params
        _run_with_timeout(lambda: device.move_relative(
            TLMC_MoveModes.MoveMode_RelativeByProgrammedDistance,
            TLMC_Wait.TLMC_Unused,
            TLMC_Wait.TLMC_InfiniteWait
        ), MOVE_TIMEOUT_S)

        # Poll final position and report
        final_counts = device.get_position_counter(TLMC_Wait.TLMC_InfiniteWait)
        final_conv = device.convert_from_device_units_to_physical(
            TLMC_ScaleType.TLMC_ScaleType_Distance,
            final_counts
        )
        final_mm = final_conv.converted_value
    except XADeviceException as e:
        # Provide richer error info for diagnosis
        err_msg = getattr(e, 'message', None) or str(e)
        raise RuntimeError(f"XADeviceException during move: code={getattr(e,'error_code',None)} msg={err_msg}")
    except Exception as e:
        # Surface native/ctypes errors plainly (useful for access-violation cases)
        raise RuntimeError(f"Error during move for axis {axis}: {e}")


def yOCTStageClose_1axis(axis: str) -> None:
    """
    Close stage for one axis using XA SDK.
    Args:
        axis (str): 'x', 'y', or 'z'
    Returns:
        None
    """
    axis = axis.lower()
    if axis in _stage_handles:
        try:
            _stage_handles[axis].disconnect()
            _stage_handles[axis].close()
        except Exception as e:
            raise RuntimeError(f"Error closing stage for axis {axis}: {e}")
        del _stage_handles[axis]


# ============================================================================
# Helper Functions  
# ============================================================================


def _read_probe_ini(ini_path: str) -> dict:
    """Read probe configuration from .ini file.
    
    Args:
        ini_path (str): Path to the .ini file
    
    Returns:
        dict: Dictionary containing all probe configuration parameters
    
    Raises:
        FileNotFoundError: If the .ini file does not exist
        ValueError: If the .ini file cannot be parsed
    """
    if not os.path.exists(ini_path):
        raise FileNotFoundError(f"Probe configuration file not found: {ini_path}")
    
    config = {}
    
    try:
        with open(ini_path, 'r') as f:
            for line in f:
                line = line.strip()
                
                # Skip comments and empty lines
                if not line or line.startswith('#') or line.startswith('##'):
                    continue
                
                # Parse key = value pairs
                if '=' in line:
                    key, value = line.split('=', 1)
                    key = key.strip()
                    value = value.strip()
                    
                    # Remove quotes if present
                    if value.startswith("'") and value.endswith("'"):
                        value = value[1:-1]
                    
                    # Try to convert to appropriate type
                    try:
                        # Try float first
                        if '.' in value or 'e' in value.lower() or 'E' in value:
                            config[key] = float(value)
                        else:
                            # Try int
                            config[key] = int(value)
                    except ValueError:
                        # Handle lists (e.g., OpticalPathCorrectionPolynomial)
                        if '[' in value and ']' in value:
                            # Parse list of numbers
                            list_str = value.strip('[]')
                            config[key] = [float(x.strip()) for x in list_str.split(',')]
                        else:
                            # Keep as string
                            config[key] = value
        
        return config
        
    except Exception as e:
        raise ValueError(f"Error parsing probe configuration file: {e}")


def _apply_probe_config_to_probe(probe, config: dict) -> None:
    """Apply probe configuration parameters to probe object.
    
    This function sets probe properties from the parsed .ini file configuration.
    Only parameters that have corresponding SDK setter methods are applied.
    
    Args:
        probe: Probe object from probe_factory
        config (dict): Configuration dictionary from _read_probe_ini()
    
    Returns:
        None
    """
    # Mapping of .ini file keys to probe.properties setter methods
    # Format: 'IniKey': ('setter_method_name', conversion_function)
    property_mappings = {
        # Galvo calibration
        'FactorX': ('set_factor_x', float),
        'FactorY': ('set_factor_y', float),
        'OffsetX': ('set_offset_x', float),
        'OffsetY': ('set_offset_y', float),
        
        # Field of view
        'RangeMaxX': ('set_range_max_x', float),
        'RangeMaxY': ('set_range_max_y', float),
        
        # Apodization
        'ApoVoltage': ('set_apo_volt_x', float),  # Note: setting both X and Y to same value
        'FlybackTime': ('set_flyback_time_sec', float),
        
        # Camera calibration
        'CameraScalingX': ('set_camera_scaling_x', float),
        'CameraScalingY': ('set_camera_scaling_y', float),
        'CameraOffsetX': ('set_camera_offset_x', float),
        'CameraOffsetY': ('set_camera_offset_y', float),
        'CameraAngle': ('set_camera_angle', float),
    }
    
    # Apply each property if it exists in config
    for ini_key, (setter_name, converter) in property_mappings.items():
        if ini_key in config:
            try:
                # Get the setter method
                setter = getattr(probe.properties, setter_name)
                # Convert and set the value
                value = converter(config[ini_key])
                setter(value)
            except AttributeError:
                pass  # Setter not available in this SDK version
            except Exception:
                pass  # Could not set this property
    
    # Special case: ApoVoltage sets both X and Y
    if 'ApoVoltage' in config:
        try:
            value = float(config['ApoVoltage'])
            probe.properties.set_apo_volt_y(value)
        except Exception:
            pass  # Could not set ApoVoltageY

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


