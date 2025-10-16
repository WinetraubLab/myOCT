"""
Low-level hardware functions for Thorlabs OCT system.
This module provides direct hardware interaction functions similar to the MATLAB/C/DLL interface.

These functions are called by high-level scanning functions like yOCTScanTile and yOCTPhotobleachTile.

Function Naming Convention:
(Implemented)
- OCT functions: yOCTScannerInit, yOCTScannerClose, yOCTScan3DVolume

(not yet implemented)
- OCT functions: yOCTPhotobleachLine
- Stage functions: yOCTStageInit_1axis, yOCTStageSetPosition_1axis
- Laser functions: (DiodeCtrl equivalent functions)
- Optical switch: yOCTTurnOpticalSwitch
"""

from pyspectralradar import OCTSystem, RawData, RealData, OCTFile
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


def yOCTScan3DVolume(centerX_mm: float, centerY_mm: float, 
                     rangeX_mm: float, rangeY_mm: float,
                     rotationAngle_deg: float,
                     nXPixels: int, nYPixels: int,
                     nBScanAvg: int,
                     outputFolder: str):
    """Scan 3D OCT volume.
    
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
    
    # Create output directory
    os.makedirs(outputFolder, exist_ok=True)
    
    try:
        # Set B-scan averaging on probe and processing
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
        
        # Get raw data from acquisition
        _device.acquisition.get_raw_data(buffer=raw_data)
        
        # Stop acquisition
        _device.acquisition.stop()
        time_end = time.time()
        
        # Create OCT file with proper metadata 
        oct_file = OCTFile(filetype=pt.FileFormat.OCITY)
        
        # Save calibration (includes Chirp.data, OffsetErrors.data)
        oct_file.save_calibration(_processing, 0)
        
        # Add raw spectral data
        oct_file.add_data(raw_data, f"data\\Spectral0.data")
        
        # Set metadata properties
        oct_file.properties.set_process_state = pt.ProcessingStates.RAW_SPECTRA
        oct_file.properties.set_acquisition_mode("Mode3D")
        oct_file.properties.set_comment("Created using Python SDK - yOCTScan3DVolume")
        oct_file.set_metadata(_device, _processing, _probe, scan_pattern)
        
        # Set acquisition time
        acq_time = time_end - time_start
        oct_file.properties.set_scan_time_sec(acq_time)
        
        # Set timestamp
        current_time = int(time.time())
        oct_file.timestamp = current_time
        
        # Save to temporary .oct file in the output folder
        import zipfile
        import shutil
        
        temp_oct_path = os.path.join(outputFolder, '_temp_scan.oct')
        oct_file.save(temp_oct_path)
        
        # Extract .oct file to output folder (matching C++ DLL behavior)
        # .oct is a zip archive containing Header.xml and data/*.data files
        with zipfile.ZipFile(temp_oct_path, 'r') as zip_ref:
            zip_ref.extractall(outputFolder)
        
        # Remove temporary .oct file
        os.remove(temp_oct_path)
        
        # Split concatenated spectral data into individual B-scan files
        # (MATLAB loader expects Spectral0.data, Spectral1.data, etc., not concatenated Spectral0.data)
        _split_spectral_files_by_bscan(outputFolder, nYPixels, nXPixels)
        
        # Clean up OCT file object
        del oct_file
        del raw_data
        del scan_pattern
        
    except Exception as e:
        # Clean up output folder on error
        if os.path.exists(outputFolder):
            import shutil
            shutil.rmtree(outputFolder)
        raise


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
    """Split concatenated Spectral0.data into individual B-scan files.
    
    The Python SDK's OCTFile saves all spectral data in a single concatenated file: Spectral0.data
    However, the MATLAB loader (yOCTLoadInterfFromFile_ThorlabsData.m) expects individual files:
    Spectral0.data, Spectral1.data, Spectral2.data, ..., Spectral(nYPixels-1).data
    
    This function:
    1. Reads the Header.xml to get exact spectral data dimensions
    2. Calculates byte offsets for each B-scan
    3. Splits the concatenated data into individual files
    
    The output is MATLAB-compatible: each file contains one complete B-scan worth of spectral data.
    
    Args:
        outputFolder (str): Path to scan output folder containing Header.xml and data/
        nYPixels (int): Number of B-scans (Y pixels/frames in volume)
        nXPixels (int): Number of A-scans per B-scan (X pixels)
    
    Returns:
        None
    
    Raises:
        FileNotFoundError: If Header.xml or Spectral0.data not found
        ValueError: If dimensions in Header.xml don't match expected size
    """
    import xml.etree.ElementTree as ET
    
    header_path = os.path.join(outputFolder, 'Header.xml')
    data_folder = os.path.join(outputFolder, 'data')
    spectral_concat_path = os.path.join(data_folder, 'Spectral0.data')
    
    if not os.path.exists(header_path):
        raise FileNotFoundError(f"Header.xml not found in {outputFolder}")
    
    if not os.path.exists(spectral_concat_path):
        raise FileNotFoundError(f"Spectral0.data not found in {data_folder}")
    
    # Parse Header.xml to get exact dimensions
    try:
        tree = ET.parse(header_path)
        root = tree.getroot()
        
        # Extract dimension info from Header.xml
        # The XML has two places with dimensions:
        # 1. <Image><SizePixel>: Contains SizeZ, SizeX, SizeY (pixel count)
        # 2. <DataFile> attributes: Contains SizeZ (spectral points), SizeX (A-scans)
        
        # For spectral file splitting, we need:
        # - SizeZ from DataFile: number of spectral points (wavelengths) - for data structure
        # - SizeX from DataFile: number of A-scans per B-scan - for data structure
        # - SizeY from Image/SizePixel: number of B-scans in volume - for number of files
        
        size_z_spectral = None  # Spectral points (wavelengths)
        size_x_ascans = None    # A-scans per B-scan
        size_y_bscans = None    # B-scans in volume
        
        # Find the Raw DataFile (contains spectral data)
        for datafile_elem in root.findall('.//DataFile[@Type="Raw"]'):
            size_z_spectral = int(datafile_elem.get('SizeZ', 0)) if datafile_elem.get('SizeZ') else None
            size_x_ascans = int(datafile_elem.get('SizeX', 0)) if datafile_elem.get('SizeX') else None
        
        # Find the Image dimensions for number of B-scans
        for size_elem in root.findall('.//SizePixel/SizeY'):
            size_y_bscans = int(float(size_elem.text)) if size_elem.text else None
        
        # Fallback: use the nYPixels parameter if we couldn't find it
        if size_y_bscans is None:
            size_y_bscans = nYPixels
        
        if size_z_spectral is None or size_x_ascans is None or size_y_bscans is None:
            raise ValueError(
                f"Could not extract all dimensions from Header.xml. "
                f"Got: SizeZ_spectral={size_z_spectral}, SizeX_ascans={size_x_ascans}, SizeY_bscans={size_y_bscans}"
            )
        
    except ET.ParseError as e:
        raise ValueError(f"Failed to parse Header.xml: {e}")
    
    # Read concatenated spectral data
    # Data format: uint16 (2 bytes per value)
    # Layout: [B-scan 0][B-scan 1]...[B-scan N-1]
    # Each B-scan: [SizeZ_spectral wavelengths × (SizeX_ascans + ApodPixels)]
    with open(spectral_concat_path, 'rb') as f:
        concat_data = f.read()
    
    # Calculate bytes per B-scan
    # Total size should be: SizeZ_spectral × (SizeX_ascans + ApodPixels) × 2 bytes × SizeY_bscans
    total_bytes = len(concat_data)
    bytes_per_bscan = total_bytes // size_y_bscans
    
    # Verify the split is clean (no remainder)
    if total_bytes % size_y_bscans != 0:
        raise ValueError(
            f"Cannot cleanly split spectral data. "
            f"Total bytes ({total_bytes}) not divisible by number of B-scans ({size_y_bscans}). "
            f"Got remainder: {total_bytes % size_y_bscans} bytes"
        )
    
    # Split concatenated data into individual B-scan files
    for bscan_idx in range(size_y_bscans):
        start_byte = bscan_idx * bytes_per_bscan
        end_byte = start_byte + bytes_per_bscan
        
        bscan_data = concat_data[start_byte:end_byte]
        
        # Create filename: Spectral0.data, Spectral1.data, etc.
        output_filename = f'Spectral{bscan_idx}.data'
        output_path = os.path.join(data_folder, output_filename)
        
        # Write individual B-scan file
        with open(output_path, 'wb') as f:
            f.write(bscan_data)

    os.remove(spectral_concat_path)  

