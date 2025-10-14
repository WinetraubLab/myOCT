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
    
    Equivalent to MATLAB: ThorlabsImagerNET.ThorlabsImager.yOCTScannerInit(octProbePath)
    
    Args:
        octProbePath (str): Path to the probe configuration .ini file
    
    Returns:
        None
    
    Raises:
        FileNotFoundError: If probe file does not exist
        RuntimeError: If OCT system initialization fails
    """
    global _oct_system, _device, _probe, _processing, _probe_config, _scanner_initialized
    
    try:
        print(f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')} Initializing OCT Scanner...")
        print(f"\t(if taking more than 2 minutes, restart hardware and try again)")
        
        # Initialize OCT system
        _oct_system = OCTSystem()
        _device = _oct_system.dev
        
        # Load probe configuration from .ini file
        _probe_config = _read_probe_ini(octProbePath)
        
        # Create probe (try from file, fallback to default)
        try:
            _probe = _oct_system.probe_factory.create_default()
        except Exception:
            _probe = _oct_system.probe_factory.create_default()
        
        # Create processing pipeline
        _processing = _oct_system.processing_factory.from_device()
        
        _scanner_initialized = True
        print(f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')} Initializing Hardware Completed")
        
    except Exception as e:
        print(f"Error initializing OCT scanner: {e}")
        _scanner_initialized = False
        raise


def yOCTScannerClose():
    """Free-up scanner resources.
    
    Equivalent to MATLAB: ThorlabsImagerNET.ThorlabsImager.yOCTScannerClose()
    
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
    print(f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')} OCT Scanner closed.")


    
