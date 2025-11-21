"""
Low-level hardware functions for Thorlabs OCT system.
This module provides direct hardware interaction functions similar to the MATLAB/C/DLL interface.

These functions are called by high-level scanning functions like yOCTScanTile and yOCTPhotobleachTile.

Function Naming Convention:
(Implemented)
- OCT functions: yOCTScannerInit,  yOCTScannerClose, yOCTScan3DVolume
- Stage functions: yOCTStageInit_1axis, yOCTStageSetPosition_1axis, yOCTStageClose_1axis

(not yet implemented)
- OCT functions: yOCTPhotobleachLine
- Laser functions: (DiodeCtrl equivalent functions)
- Optical switch: yOCTTurnOpticalSwitch
"""

from pyspectralradar import OCTSystem, RawData, OCTFile
import pyspectralradar.types as pt
import os
import time
import gc  
import threading
import zipfile
import shutil

from xa_sdk.native_sdks.xa_sdk import XASDK
from xa_sdk.shared.tlmc_type_structures import (
    TLMC_Wait,
    TLMC_ScaleType,
    TLMC_Unit,
    TLMC_MoveModes,
    TLMC_OperatingModes,
    TLMC_ChannelEnableStates,
)
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

# Lock to make shutdown/close operations thread-safe. Use RLock so nested
# cleanup calls (e.g., yOCTCloseAll -> yOCTScannerClose) don't deadlock.
_shutdown_lock = threading.RLock()


# ============================================================================
# OCT SCANNER FUNCTIONS
# ============================================================================

def yOCTScannerInit(octProbePath : str) -> None:
    """Initialize scanner with a probe file.
    
    Equivalent to C++/DLL: ThorlabsImagerNET.ThorlabsImager.yOCTScannerInit(octProbePath)
    
    If scanner is already initialized, closes it first to release hardware.
    This ensures clean re-initialization on subsequent runs.
    
    Args:
        octProbePath (str): Path to the probe configuration .ini file
    
    Returns:
        None
    
    Raises:
        FileNotFoundError: If probe file does not exist
        RuntimeError: If OCT system initialization fails
    """
    global _oct_system, _device, _probe, _processing, _probe_config, _scanner_initialized
    
    # Check file exists early for clearer error message
    if not os.path.exists(octProbePath):
        raise FileNotFoundError(f"Probe configuration file not found: {octProbePath}")
    
    # If scanner is already initialized, close it first
    # This is critical for repeated runs - hardware must be released properly
    if _scanner_initialized or _oct_system is not None:
        try:
            yOCTScannerClose()
            # Give USB hardware extra time to fully release and reset
            # SpectralRadar SDK needs this to avoid "No initialization response" errors
            time.sleep(1.0)
        except Exception as e:
            # Best-effort cleanup - log but continue to try init
            print(f"Warning: Error during cleanup before re-init: {e}")
            # Still wait even if cleanup failed
            time.sleep(1.0)
    
    # Initialize OCT system - SDK will connect to hardware
    try:
        _oct_system = OCTSystem()
        _device = _oct_system.dev
    except Exception as e:
        # Provide helpful error message for common hardware issues
        error_msg = str(e)
        if "No initialization response" in error_msg or "Failed to open data device" in error_msg:
            raise RuntimeError(
                f"Failed to connect to OCT device: {error_msg}\n"
                "Common causes:\n"
                "  1. OCT base unit is powered OFF - check power LED\n"
                "  2. USB cable is disconnected or loose\n"
                "  3. Device still held by previous connection - try restarting MATLAB\n"
                "  4. USB hub/port issue - try different USB port"
            ) from e
        else:
            # Re-raise other errors as-is
            raise
    
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


def yOCTScannerClose():
    """Free-up scanner resources.
    
    Equivalent to C++/DLL: ThorlabsImagerNET.ThorlabsImager.yOCTScannerClose()
    
    Sets scanner objects to None to release resources. Python's garbage collector
    will clean up naturally without forcing immediate destructors.
    
    Args:
        None
    
    Returns:
        None
    
    Raises:
        None
    """
    global _oct_system, _device, _probe, _processing, _scanner_initialized, _shutdown_lock

    with _shutdown_lock:
        # Stop any ongoing acquisition before closing
        if _device is not None:
            try:
                # Ensure acquisition is fully stopped
                _device.acquisition.stop()
                time.sleep(0.1)
            except:
                pass  # May already be stopped
        
        # Explicitly delete objects in reverse order to force destructors
        # This ensures SDK releases USB device immediately
        if _processing is not None:
            try:
                del _processing
            except:
                pass
        if _probe is not None:
            try:
                del _probe
            except:
                pass
        if _device is not None:
            try:
                del _device
            except:
                pass
        if _oct_system is not None:
            try:
                del _oct_system
            except:
                pass
        
        # Now set all to None to clear references
        _processing = None
        _probe = None
        _device = None
        _oct_system = None
        _scanner_initialized = False
        
        # Force garbage collection NOW - critical in MATLAB environment
        # Without this, Python might keep objects alive indefinitely
        gc.collect()
        
        # Give hardware extra time to fully release USB connection
        # This is critical for SpectralRadar SDK - it needs time to release USB properly
        time.sleep(1.0)


def yOCTScan3DVolume(centerX_mm: float, centerY_mm: float, 
                     rangeX_mm: float, rangeY_mm: float,
                     rotationAngle_deg: float,
                     nXPixels: int, nYPixels: int,
                     nBScanAvg: int,
                     outputFolder: str):
    """Scan 3D OCT volume and save MATLAB-compatible data files.
    
    Equivalent to C++/DLL: ThorlabsImagerNET.ThorlabsImager.yOCTScan3DVolume()
    
    Creates an output folder with Header.xml, data/Spectral*.data files, and calibration files
    
    Args:
        centerX_mm (float): Center position X in mm
        centerY_mm (float): Center position Y in mm
        rangeX_mm (float): Scan range X in mm
        rangeY_mm (float): Scan range Y in mm
        rotationAngle_deg (float): Rotation angle in degrees
        nXPixels (int): Number of pixels in X (A-scans per B-scan)
        nYPixels (int): Number of pixels in Y (B-scans in volume)
        nBScanAvg (int): Number of B-scans to average
        outputFolder (str): Output directory path (must not exist)
    
    Returns:
        None (data is saved to outputFolder/Header.xml and outputFolder/data/*.data)
    
    Raises:
        RuntimeError: If scanner is not initialized
        FileExistsError: If outputFolder already exists
    """
    global _scanner_initialized, _device, _probe, _processing
    
    if not _scanner_initialized:
        raise RuntimeError("Scanner not initialized. Call yOCTScannerInit() first.")
    
    # Check if output folder already exists
    if os.path.exists(outputFolder):
        raise FileExistsError(f"Output folder already exists: {outputFolder}")
    
    # Create output directory (without exist_ok since we already checked)
    os.makedirs(outputFolder)
    
    scan_pattern = None
    raw_data = None
    oct_file = None
    acquisition_started = False
    
    try:
        # Set B-scan averaging on probe and processing (persists like C++ version)
        if nBScanAvg > 1:
            _probe.properties.set_oversampling_slow_axis(nBScanAvg)
            _processing.properties.set_bscan_avg(nBScanAvg)
        
        # Create volume scan pattern
        scan_pattern = _probe.scan_pattern.create_volume_pattern(
            rangeX_mm,  # range X in mm
            nXPixels,   # A-scans per B-scan
            rangeY_mm,  # range Y in mm
            nYPixels,   # B-scans in volume
            pt.ApodizationType.EACH_BSCAN,  # Apodization type
            pt.AcquisitionOrder.ACQ_ORDER_ALL  # Acquisition order
        )
        
        # Apply center offset (shift scan pattern to center position)
        scan_pattern.shift(centerX_mm, centerY_mm)
        
        # Apply rotation if specified
        if rotationAngle_deg != 0:
            scan_pattern.rotate(rotationAngle_deg * 3.14159265359 / 180.0)  # Convert to radians
        
        # Allocate data buffers
        raw_data = RawData()
        
        # Start acquisition
        time_start = time.time()
        _device.acquisition.start(scan_pattern, pt.AcqType.ASYNC_FINITE)
        acquisition_started = True
        
        # Get raw data from acquisition
        _device.acquisition.get_raw_data(buffer=raw_data)
        
        # Stop acquisition
        _device.acquisition.stop()
        acquisition_started = False
        time_end = time.time()
        
        # Create OCT file with proper metadata 
        oct_file = OCTFile(filetype=pt.FileFormat.OCITY)

        # Add raw data to OCT file
        oct_file.add_data(raw_data, "data\\Spectral0.data")

        # Save calibration files: Chirp and Offset
        oct_file.save_calibration(_processing, 0)

        # Set metadata from the scan
        oct_file.set_metadata(_device, _processing, _probe, scan_pattern)

        # Set acquisition time
        acq_time = time_end - time_start
        oct_file.properties.set_scan_time_sec(acq_time)

        # Add comment
        oct_file.properties.set_comment("Created using Python SDK - yOCTScan3DVolume()")

        # Save to .oct file in the output folder
        oct_file_path = os.path.join(outputFolder, 'scan.oct')
        oct_file.save(oct_file_path)

        # Extract .oct file for MATLAB compatibility
        # The .oct file is a ZIP archive, we need to extract it so MATLAB can read it
        with zipfile.ZipFile(oct_file_path, 'r') as zip_ref:
            zip_ref.extractall(outputFolder)

        # Delete the .oct file after extraction to avoid duplication
        # MATLAB expects to find extracted files, not the .oct archive
        os.remove(oct_file_path)

        # Split the concatenated Spectral0.data into individual B-scan files
        # MATLAB expects Spectral0.data, Spectral1.data, ..., Spectral(N-1).data
        _split_spectral_files_by_bscan(outputFolder, nYPixels, nXPixels)

        # Fix Header.xml metadata for MATLAB compatibility
        _fix_header_xml_for_matlab(outputFolder, raw_data, _probe)

        # Clean up OCT file object and data buffers
        del oct_file
        del raw_data
        del scan_pattern
        oct_file = None
        raw_data = None
        scan_pattern = None
        
    except Exception as e:
        # Ensure acquisition is stopped if it was started
        if acquisition_started:
            try:
                _device.acquisition.stop()
            except Exception:
                pass  # Best effort
        
        # Clean up partially created objects
        if oct_file is not None:
            try:
                del oct_file
            except Exception:
                pass
        if raw_data is not None:
            try:
                del raw_data
            except Exception:
                pass
        if scan_pattern is not None:
            try:
                del scan_pattern
            except Exception:
                pass
        
        # Clean up output folder on error
        if os.path.exists(outputFolder):
            try:
                shutil.rmtree(outputFolder)
            except Exception:
                pass  # Best effort
        raise


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
    
    # Thread-safe XA SDK startup (or restart if previously shut down)
    # This refreshes the device list, similar to C++ TLI_BuildDeviceList()
    if not hasattr(XASDK, '_oct_xa_started') or not XASDK._oct_xa_started:
        with _shutdown_lock:  # Use existing lock for thread safety
            if not hasattr(XASDK, '_oct_xa_started') or not XASDK._oct_xa_started:  # Double-check inside lock
                # Get absolute path to directory containing this Python module
                dll_path = os.path.abspath(os.path.dirname(__file__))
                
                # Add DLL directory to Windows DLL search path (Python 3.8+)
                if hasattr(os, 'add_dll_directory'):
                    os.add_dll_directory(dll_path)
                
                # WORKAROUND: XASDK.try_load_library() ignores the path parameter
                # and looks in current working directory. Temporarily change CWD.
                original_cwd = os.getcwd()
                try:
                    os.chdir(dll_path)
                    XASDK.try_load_library(dll_path)
                    XASDK.startup("")
                    XASDK._oct_xa_started = True
                finally:
                    # Always restore original working directory
                    os.chdir(original_cwd)
    
    device = None
    try:
        # Create device instance (KST201 handles open internally)
        device = KST201(serial_no, "", TLMC_OperatingModes.Default)
        device.set_enable_state(TLMC_ChannelEnableStates.ChannelEnabled)
        device.set_connected_product(actuator_model)
        
        # Read initial position
        pos_counts = device.get_position_counter(TLMC_Wait.TLMC_InfiniteWait)
        pos_conv = device.convert_from_device_units_to_physical(
            TLMC_ScaleType.TLMC_ScaleType_Distance,
            pos_counts
        )
        pos_mm = pos_conv.converted_value
        
        # Only save to handles if everything succeeded
        _stage_handles[axis] = device
        return pos_mm
        
    except XADeviceException as e:
        # Cleanup on XA-specific errors
        if device is not None:
            try:
                device.disconnect()
            except Exception:
                pass
            try:
                device.close()
            except Exception:
                pass
        if axis in _stage_handles:
            del _stage_handles[axis]
        raise RuntimeError(f"XADeviceException during stage init: {e.error_code}")
        
    except Exception as e:
        # Cleanup on general errors
        if device is not None:
            try:
                device.disconnect()
            except Exception:
                pass
            try:
                device.close()
            except Exception:
                pass
        if axis in _stage_handles:
            del _stage_handles[axis]
        raise RuntimeError(f"Error initializing stage for axis '{axis}': {e}")


def yOCTStageSetPosition_1axis(axis: str, position_mm: float) -> None:
    """
    Move stage axis to position in mm using XA SDK.
    Negative targets are allowed; the device will enforce its own travel limits.
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
        # Convert position from mm to device units
        abs_param = device.convert_from_physical_to_device(
            TLMC_ScaleType.TLMC_ScaleType_Distance,
            TLMC_Unit.TLMC_Unit_Millimetres,
            float(position_mm)
        )
        
        # Use SDK's built-in timeout (120 seconds = 120000 ms)
        MOVE_TIMEOUT_MS = 120000
        
        # MoveMode_Absolute requires passing the position inline
        device.move_absolute(
            TLMC_MoveModes.MoveMode_Absolute,
            abs_param,
            MOVE_TIMEOUT_MS
        )

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
    
    Per Thorlabs recommendation: disconnect() → close() to avoid sporadic cleanup issues,
    especially with benchtop controllers.
    
    Args:
        axis (str): 'x', 'y', or 'z'
    Returns:
        None
    Raises:
        RuntimeError: If cleanup fails (but still removes handle from dict)
    """
    axis = axis.lower()
    if axis in _stage_handles:
        device = _stage_handles[axis]
        error_occurred = None
        
        # Always try disconnect before close (Thorlabs recommendation for benchtops)
        try:
            device.disconnect()
        except Exception as e:
            error_occurred = e
        
        # Always try close even if disconnect failed
        try:
            device.close()
        except Exception as e:
            if error_occurred is None:
                error_occurred = e
        
        # Always remove from dict even if errors occurred
        del _stage_handles[axis]
        
        # Raise error after cleanup to inform caller but not leave stale handle
        if error_occurred is not None:
            raise RuntimeError(f"Error closing stage for axis {axis}: {error_occurred}")


def yOCTCloseAll():
    """Close all open hardware resources (stages and OCT scanner).

    This is the primary cleanup function that should be called at program exit.
    It coordinates cleanup of all resources in the correct order:
    1. Close all stage axes (disconnect → close each device)
    2. Close OCT scanner resources
    3. Shutdown XA SDK if we started it
    
    Per Thorlabs: Always call disconnect() before close() to avoid sporadic 
    cleanup issues, especially with benchtop controllers. The XA SDK has a 
    garbage collector but it doesn't always work reliably.
    
    This function is idempotent and thread-safe - safe to call multiple times.
    It checks actual resource state rather than using a flag, so it will properly
    clean up even if previous cleanup attempts failed.
    
    Args:
        None
    Returns:
        None
    """
    global _stage_handles, _oct_system, _device, _probe, _processing, _shutdown_lock, _scanner_initialized

    # Make cleanup thread-safe using a lock
    with _shutdown_lock:
        # Check actual resource state - no separate flag needed
        # If nothing is open, return early
        has_resources = (
            bool(_stage_handles) or 
            _scanner_initialized or 
            (_oct_system is not None) or
            (hasattr(XASDK, '_oct_xa_started') and XASDK._oct_xa_started)
        )
        
        if not has_resources:
            return  # Nothing to clean up

        # 1. Close all stage handles first (hardware before software SDK)
        #    Use popitem() to safely empty dict during iteration
        while _stage_handles:
            axis, dev = _stage_handles.popitem()
            # Best effort: disconnect → close (Thorlabs recommendation)
            try:
                dev.disconnect()
            except Exception:
                pass  # Continue to close even if disconnect fails
            
            try:
                dev.close()
            except Exception:
                pass  # Best effort - don't stop cleanup

        # 2. Close OCT scanner resources (in reverse order of creation)
        #    Call yOCTScannerClose() to ensure consistent cleanup
        try:
            if _scanner_initialized:
                yOCTScannerClose()
        except Exception:
            pass  # Best effort - continue to SDK shutdown

        # 3. DO NOT shutdown XA SDK - this causes crashes
        #    The SDK will be restarted automatically on next init (idempotent behavior)
        #    Leaving SDK running between calls is safer than shutting it down
        
        # 4. Force final garbage collection to ensure all resources released
        gc.collect()


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


def _split_spectral_files_by_bscan(outputFolder: str, nYPixels: int, nXPixels: int) -> None:
    """
    Split concatenated Spectral0.data into individual B-scan files for MATLAB compatibility.
        Args:
            outputFolder (str): Output directory containing Header.xml and data/Spectral0.data
            nYPixels (int): Number of B-scans in the volume
            nXPixels (int): Number of pixels in the X direction
        Returns:
            None 
""" 
    import xml.etree.ElementTree as ET
    
    header_path = os.path.join(outputFolder, 'Header.xml')
    data_folder = os.path.join(outputFolder, 'data')
    spectral_concat_path = os.path.join(data_folder, 'Spectral0.data')
    
    if not os.path.exists(header_path) or not os.path.exists(spectral_concat_path):
        return
    
    try:
        tree = ET.parse(header_path)
        root = tree.getroot()
        
        # Get dimensions from XML
        size_z = None
        size_x = None
        for datafile_elem in root.findall('.//DataFile[@Type="Raw"]'):
            size_z = int(datafile_elem.get('SizeZ', 0)) if datafile_elem.get('SizeZ') else None
            size_x = int(datafile_elem.get('SizeX', 0)) if datafile_elem.get('SizeX') else None
        
        size_y = nYPixels
        for size_elem in root.findall('.//SizePixel/SizeY'):
            if size_elem.text:
                size_y = int(float(size_elem.text))
        
        if not size_z or not size_x or not size_y:
            return
        
        # Rename concatenated file temporarily
        spectral_temp_path = os.path.join(data_folder, 'Spectral_temp.data')
        os.rename(spectral_concat_path, spectral_temp_path)
        
        # Read concatenated data
        with open(spectral_temp_path, 'rb') as f:
            concat_data = f.read()
        
        # Calculate bytes per B-scan
        total_bytes = len(concat_data)
        bytes_per_bscan = total_bytes // size_y
        
        # Split into individual files
        for bscan_idx in range(size_y):
            start_byte = bscan_idx * bytes_per_bscan
            end_byte = start_byte + bytes_per_bscan
            bscan_data = concat_data[start_byte:end_byte]
            
            output_filename = f'Spectral{bscan_idx}.data'
            output_path = os.path.join(data_folder, output_filename)
            
            with open(output_path, 'wb') as f:
                f.write(bscan_data)
        
        # Remove temporary file
        os.remove(spectral_temp_path)
        
    except Exception as e:
        # If splitting fails, restore original file
        if os.path.exists(spectral_temp_path):
            os.rename(spectral_temp_path, spectral_concat_path)


def _fix_header_xml_for_matlab(outputFolder: str, raw_data: RawData, probe) -> None:
    """
    Fix Header.xml metadata for MATLAB compatibility.
        Args:
            outputFolder (str): Output directory containing Header.xml  
            raw_data (RawData): Raw data object from the scan
        Returns:
            None
    """
    import xml.etree.ElementTree as ET
    
    header_path = os.path.join(outputFolder, 'Header.xml')
    if not os.path.exists(header_path):
        return
    
    try:
        tree = ET.parse(header_path)
        root = tree.getroot()
        
        # Get dimensions from raw_data
        data_shape = raw_data.shape
        size_z = data_shape[0]  # Spectral points
        total_x = data_shape[1]  # Total width
        size_y = data_shape[2] if len(data_shape) > 2 else 1  # B-scans
        
        # Get apodization size
        apo_size = 25  # Default
        try:
            actual_apo_elem = root.find('.//Acquisition/ActualSizeOfApodization')
            if actual_apo_elem is not None and actual_apo_elem.text:
                apo_size = int(actual_apo_elem.text)
        except:
            pass
        
        # Calculate sizes from split files
        spectral_0_path = os.path.join(outputFolder, 'data', 'Spectral0.data')
        if os.path.exists(spectral_0_path):
            file_size_bytes = os.path.getsize(spectral_0_path)
            elements_per_file = file_size_bytes // 2  # 2 bytes per uint16
            width_per_bscan = elements_per_file // size_z
            interf_size = width_per_bscan
        else:
            width_per_bscan = total_x // size_y if size_y > 0 else total_x
            interf_size = width_per_bscan
        
        # Count actual B-scans
        data_folder = os.path.join(outputFolder, 'data')
        actual_bscans = 0
        if os.path.exists(data_folder):
            spectral_files = [f for f in os.listdir(data_folder) 
                            if f.startswith('Spectral') and f.endswith('.data')]
            actual_bscans = len(spectral_files)
        
        final_size_y = actual_bscans if actual_bscans > 0 else size_y
        actual_interf_size = interf_size - apo_size
        
        # Update XML metadata
        for datafile_elem in root.findall('.//DataFile[@Type="Raw"]'):
            datafile_elem.set('SizeZ', str(size_z))
            datafile_elem.set('SizeX', str(interf_size))
            datafile_elem.set('SizeY', str(final_size_y))
            datafile_elem.set('ApoRegionEnd0', str(apo_size))
            datafile_elem.set('ApoRegionStart0', '0')
            datafile_elem.set('ScanRegionStart0', str(apo_size))
            datafile_elem.set('ScanRegionEnd0', str(interf_size))
        
        for sizex_elem in root.findall('.//Image/SizePixel/SizeX'):
            sizex_elem.text = str(actual_interf_size)
        
        for sizey_elem in root.findall('.//Image/SizePixel/SizeY'):
            sizey_elem.text = str(final_size_y)
        
        for image_elem in root.findall('.//Image'):
            if image_elem.get('Type') == 'Processed':
                image_elem.set('Type', 'RawSpectra')
        
        tree.write(header_path, encoding='utf-8', xml_declaration=True)
        
    except:
        pass  # If fixing fails, continue anyway