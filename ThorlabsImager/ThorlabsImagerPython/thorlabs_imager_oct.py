"""
Low-level hardware functions for Thorlabs OCT system.
This module provides direct hardware interaction functions similar to the MATLAB/C/DLL interface.

These functions are called by high-level scanning functions like yOCTScanTile and yOCTPhotobleachTile.

Function Naming Convention:
(Implemented)
- OCT functions: yOCTScannerInit, yOCTScannerClose, yOCTPhotobleachLine

(not yet implemented)
- OCT functions: yOCTScan3DVolume
- Stage functions: yOCTStageInit_1axis, yOCTStageSetPosition_1axis
- Laser functions: (DiodeCtrl equivalent functions)
- Optical switch: yOCTTurnOpticalSwitch
"""

from pyspectralradar import OCTSystem, RawData, RealData, ScanPattern
import pyspectralradar.types as pt
import numpy as np
import os
import time
from datetime import datetime
import configparser


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


def yOCTPhotobleachLine(startX: float, startY: float, endX: float, endY: float, 
                        duration: float, nPasses: int = 1) -> None:
    """Photobleach a line by repeatedly scanning galvo mirrors along specified path.
    
    Equivalent to C++/DLL: ThorlabsImagerNET.ThorlabsImager.yOCTPhotobleachLine(...)
    
    This function moves the galvo mirrors along a line from (startX, startY) to (endX, endY)
    repeatedly for the specified duration and number of passes. It does not acquire data,
    only moves the beam to photobleach the sample.
    
    Args:
        startX (float): Start X position in mm (in FOV coordinates)
        startY (float): Start Y position in mm (in FOV coordinates)
        endX (float): End X position in mm (in FOV coordinates)
        endY (float): End Y position in mm (in FOV coordinates)
        duration (float): Total duration to photobleach in seconds
        nPasses (int): Number of passes over the line (default: 1)
    
    Returns:
        None
    
    Raises:
        RuntimeError: If scanner is not initialized
    
    Example:
        >>> yOCTPhotobleachLine(-1, 0, 1, 0, duration=10, nPasses=10)
    """
    global _oct_system, _device, _probe, _scanner_initialized
    
    if not _scanner_initialized:
        raise RuntimeError("Scanner not initialized. Call yOCTScannerInit() first.")
    
    try:
        # Calculate line properties
        line_length_mm = np.sqrt((endX - startX)**2 + (endY - startY)**2)
        
        # Create a scan pattern that traces the line
        # We'll use a B-scan pattern where we scan along the line direction
        # Number of A-scans determines smoothness of the line
        n_ascans = max(100, int(line_length_mm * 100))  # ~100 points per mm
        
        # Create scan pattern
        scan_pattern = ScanPattern()
        
        # Set scan pattern to B-scan (2D line scan)
        # The pattern will scan from start to end position
        scan_pattern.set_b_scan(
            size_x=n_ascans,  # Number of A-scans along the line
            range_x=line_length_mm  # Length of the line in mm
        )
        
        # Calculate the angle of the line relative to X axis
        angle_rad = np.arctan2(endY - startY, endX - startX)
        angle_deg = np.degrees(angle_rad)
        
        # Set the rotation angle to align the B-scan with the line
        scan_pattern.set_rotation_angle(angle_deg)
        
        # Set the center position of the scan (midpoint of the line)
        center_x = (startX + endX) / 2.0
        center_y = (startY + endY) / 2.0
        scan_pattern.set_position(center_x, center_y)
        
        # Apply the scan pattern to the probe
        _probe.set_scan_pattern(scan_pattern)
        
        # Calculate time per pass
        time_per_pass = duration / nPasses if nPasses > 0 else duration
        
        # Execute the photobleach by running the scan pattern multiple times
        for pass_num in range(nPasses):
            # Start the measurement (moves galvo but doesn't acquire data)
            # We use a dummy acquisition that we discard
            _device.start_measurement()
            
            # Wait for the duration of this pass
            time.sleep(time_per_pass)
            
            # Stop the measurement
            _device.stop_measurement()
        
    except Exception as e:
        raise RuntimeError(f"Error during photobleaching: {e}")


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

            