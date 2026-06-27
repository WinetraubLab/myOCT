"""
Low-level hardware functions for Thorlabs OCT system.
This module provides direct hardware interaction functions similar to the MATLAB/C/DLL interface.

These functions are called by high-level scanning functions like yOCTScanTile and yOCTPhotobleachTile.

Function Naming Convention:
(Implemented)
- OCT functions: yOCTScannerInit,  yOCTScannerClose, yOCTScan3DVolume

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
import zipfile
import shutil


# Global variables to maintain state across function calls
_oct_system = None
_device = None
_probe = None
_processing = None
_probe_config = {}
_scanner_initialized = False


def yOCTScannerInit(octProbePath : str) -> None:
    """Initialize scanner with a probe file.
    
    Equivalent to C++/DLL: ThorlabsImagerNET.ThorlabsImager.yOCTScannerInit(octProbePath)
    
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


def yOCTScannerIsInitialized():
    """Check if scanner is initialized.
    
    Returns:
        bool: True if scanner is initialized, False otherwise
    """
    return _scanner_initialized


def yOCTScannerClose():
    """Free-up scanner resources.
    
    Equivalent to C++/DLL: ThorlabsImagerNET.ThorlabsImager.yOCTScannerClose()
    
    Explicitly deletes scanner objects and forces garbage collection to ensure
    immediate resource cleanup and USB device release.
    
    Args:
        None
    
    Returns:
        None
    
    Raises:
        None
    """
    global _oct_system, _device, _probe, _processing, _scanner_initialized

    # Stop any ongoing acquisition before closing
    if _device is not None:
        try:
            # Ensure acquisition is fully stopped
            _device.acquisition.stop()
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

        # Split the concatenated Spectral0.data into individual B-scan files.
        # With B-scan averaging the slow axis is oversampled, so there are
        # nYPixels * nBScanAvg B-scans, and MATLAB expects ONE per file:
        # Spectral0.data, Spectral1.data, ..., Spectral(nYPixels*nBScanAvg - 1).data
        _split_spectral_files_by_bscan(outputFolder, nYPixels, nXPixels, nBScanAvg)

        # Fix Header.xml metadata for MATLAB compatibility (also records the
        # B-scan averaging count so MATLAB averages the repeats per Y position
        # instead of laying them out side-by-side in X)
        _fix_header_xml_for_matlab(outputFolder, raw_data, _probe, nYPixels, nBScanAvg)

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
        'ApoVoltage': ('set_apo_volt_x', float),  # Sets both X and Y to same value
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


def _split_spectral_files_by_bscan(outputFolder: str, nYPixels: int, nXPixels: int,
                                   nBScanAvg: int = 1) -> None:
    """
    Split concatenated Spectral0.data into individual B-scan files for MATLAB compatibility.

    With B-scan averaging (nBScanAvg > 1) the slow axis is oversampled, so the
    acquisition holds nYPixels * nBScanAvg B-scans, ordered Y-major / average-minor
    (all averages of Y position 0, then all averages of Y position 1, ...). MATLAB's
    reader (yOCTLoadInterfFromFile_ThorlabsData) expects exactly that ordering, one
    B-scan per Spectral{i}.data file, with fileIndex = (y-1)*nBScanAvg + (avg-1).
    Splitting in order therefore already lines up with what MATLAB indexes.

        Args:
            outputFolder (str): Output directory containing Header.xml and data/Spectral0.data
            nYPixels (int): Number of distinct Y positions (B-scans in the volume)
            nXPixels (int): Number of A-scans per B-scan (kept for signature clarity)
            nBScanAvg (int): Number of averaged B-scans acquired per Y position
        Returns:
            None
    """
    data_folder = os.path.join(outputFolder, 'data')
    spectral_concat_path = os.path.join(data_folder, 'Spectral0.data')
    spectral_temp_path = os.path.join(data_folder, 'Spectral_temp.data')

    if not os.path.exists(spectral_concat_path):
        return

    # One file per physically acquired B-scan: one for every (Y position, average).
    # Derived from the known scan geometry, NOT from Header.xml's SizeY, which the
    # SDK may report as either nYPixels or nYPixels*nBScanAvg with oversampling.
    total_bscans = int(nYPixels) * int(max(1, nBScanAvg))
    if total_bscans < 1:
        return

    try:
        # Rename concatenated file temporarily
        os.rename(spectral_concat_path, spectral_temp_path)

        # Read concatenated data
        with open(spectral_temp_path, 'rb') as f:
            concat_data = f.read()

        # Calculate bytes per B-scan
        total_bytes = len(concat_data)
        bytes_per_bscan = total_bytes // total_bscans

        # Split into individual files, preserving order (already matches MATLAB's
        # fileIndex = (y-1)*nBScanAvg + (avg-1) convention).
        for bscan_idx in range(total_bscans):
            start_byte = bscan_idx * bytes_per_bscan
            end_byte = start_byte + bytes_per_bscan
            bscan_data = concat_data[start_byte:end_byte]

            output_filename = f'Spectral{bscan_idx}.data'
            output_path = os.path.join(data_folder, output_filename)

            with open(output_path, 'wb') as f:
                f.write(bscan_data)

        # Remove temporary file
        os.remove(spectral_temp_path)

    except Exception:
        # If splitting fails, restore original file
        if os.path.exists(spectral_temp_path):
            os.rename(spectral_temp_path, spectral_concat_path)


def _fix_header_xml_for_matlab(outputFolder: str, raw_data: RawData, probe,
                               nYPixels: int = None, nBScanAvg: int = 1) -> None:
    """
    Fix Header.xml metadata for MATLAB compatibility.

    Crucially for B-scan averaging: the Y dimension (Image/SizePixel/SizeY) must be
    the number of DISTINCT Y positions (nYPixels), while the averaging count goes
    into Acquisition/SpeckleAveraging/SlowAxis. That is what MATLAB's header reader
    (yOCTLoadInterfFromFile_ThorlabsHeader) reads to know it should average the
    nBScanAvg repeats per Y position instead of treating them as extra B-scans
    (which is what produced the "N copies side-by-side in X" artifact).

        Args:
            outputFolder (str): Output directory containing Header.xml
            raw_data (RawData): Raw data object from the scan
            nYPixels (int): Number of distinct Y positions (B-scans in the volume)
            nBScanAvg (int): Number of averaged B-scans per Y position
        Returns:
            None
    """
    import xml.etree.ElementTree as ET

    header_path = os.path.join(outputFolder, 'Header.xml')
    if not os.path.exists(header_path):
        return

    navg = max(1, int(nBScanAvg))

    try:
        tree = ET.parse(header_path)
        root = tree.getroot()

        # Get dimensions from raw_data
        data_shape = raw_data.shape
        size_z = data_shape[0]  # Spectral points
        total_x = data_shape[1]  # Total width

        # Get apodization size
        apo_size = 25  # Default
        try:
            actual_apo_elem = root.find('.//Acquisition/ActualSizeOfApodization')
            if actual_apo_elem is not None and actual_apo_elem.text:
                apo_size = int(actual_apo_elem.text)
        except:
            pass

        # Single-B-scan width from one split file. After the split each
        # Spectral{i}.data holds exactly one B-scan, so this is the true width.
        spectral_0_path = os.path.join(outputFolder, 'data', 'Spectral0.data')
        if os.path.exists(spectral_0_path):
            file_size_bytes = os.path.getsize(spectral_0_path)
            elements_per_file = file_size_bytes // 2  # 2 bytes per uint16
            interf_size = elements_per_file // size_z
        else:
            interf_size = total_x

        # Count the split B-scan files. Total = (Y positions) * (averages), so the
        # number of distinct Y positions is that divided by the averaging count.
        data_folder = os.path.join(outputFolder, 'data')
        actual_bscans = 0
        if os.path.exists(data_folder):
            spectral_files = [f for f in os.listdir(data_folder)
                            if f.startswith('Spectral') and f.endswith('.data')]
            actual_bscans = len(spectral_files)

        if actual_bscans > 0:
            final_size_y = actual_bscans // navg
        elif nYPixels is not None:
            final_size_y = int(nYPixels)
        else:
            final_size_y = 1

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

        # Record B-scan averaging so MATLAB averages the repeats. MATLAB reads
        # Acquisition/SpeckleAveraging/SlowAxis; create the nodes if missing.
        if navg > 1:
            acquisition_elem = root.find('.//Acquisition')
            if acquisition_elem is not None:
                speckle_elem = acquisition_elem.find('SpeckleAveraging')
                if speckle_elem is None:
                    speckle_elem = ET.SubElement(acquisition_elem, 'SpeckleAveraging')
                slowaxis_elem = speckle_elem.find('SlowAxis')
                if slowaxis_elem is None:
                    slowaxis_elem = ET.SubElement(speckle_elem, 'SlowAxis')
                slowaxis_elem.text = str(navg)

        tree.write(header_path, encoding='utf-8', xml_declaration=True)

    except:
        pass  # If fixing fails, continue anyway