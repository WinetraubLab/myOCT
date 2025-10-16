"""
Test script for yOCTScan3DVolume function.

This script tests the 3D volume scanning functionality with actual hardware.
It performs a small test scan to verify the complete workflow:
- Scanner initialization with probe file
- 3D volume scan execution
- Data acquisition and processing
- File output verification
- Scanner cleanup
"""

import sys
import os

# Add src to path so we can import imager
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from imager.oct_python_library_operations import yOCTScannerInit, yOCTScannerClose, yOCTScan3DVolume
import time
import shutil


def test_scan_3d_volume():
    """Test 3D volume scanning with small parameters."""
    
    print("=" * 70)
    print("Testing yOCTScan3DVolume")
    print("=" * 70)
    
    # Configuration
    probe_path = r"C:\Program Files\Thorlabs\SpectralRadar\Config\Probe - Olympus 10x.ini"
    output_folder = r"C:\Users\OCT User\Documents\GitHub\myOCT\ThorlabsImagerPython\tests\test_output_scan3d"
    
    # Test scan parameters - typical case with no B-scan averaging
    
    center_x = 0.0      # mm - centered
    center_y = 0.0      # mm - centered
    range_x = 1.0       # mm - 1mm scan range
    range_y = 1.0       # mm - 1mm scan range
    rotation = 0.0      # degrees - no rotation
    n_x_pixels = 50     # Small number for quick test (vs 100 in demo)
    n_y_pixels = 4      # 4 B-scans (4 Y positions)
    n_bscan_avg = 1     # No averaging (typical case) → 4 spectral files total
    
    try:
        # Clean up old test output if exists
        if os.path.exists(output_folder):
            print(f"\nCleaning up old test output: {output_folder}")
            shutil.rmtree(output_folder)
        
        # Step 1: Initialize scanner
        print(f"\n[1/4] Initializing scanner with probe: {probe_path}")
        print("      This may take a few seconds...")
        start_time = time.time()
        yOCTScannerInit(probe_path)
        init_time = time.time() - start_time
        print(f"      ✓ Scanner initialized successfully ({init_time:.2f}s)")
        
        # Step 2: Run 3D volume scan
        print(f"\n[2/4] Starting 3D volume scan")
        print(f"      Center: ({center_x}, {center_y}) mm")
        print(f"      Range: {range_x} x {range_y} mm")
        print(f"      Size: {n_x_pixels} x {n_y_pixels} pixels")
        print(f"      B-scan averaging: {n_bscan_avg}")
        print(f"      Rotation: {rotation}°")
        print(f"      Output: {output_folder}")
        print("      Scanning... (this will take some time)")
        
        scan_start = time.time()
        yOCTScan3DVolume(
            center_x, center_y,
            range_x, range_y,
            rotation,
            n_x_pixels, n_y_pixels,
            n_bscan_avg,
            output_folder
        )
        scan_time = time.time() - scan_start
        print(f"      ✓ Scan completed successfully ({scan_time:.2f}s)")
        
        # Step 3: Verify output
        print(f"\n[3/4] Verifying output files")
        header_file = os.path.join(output_folder, 'Header.xml')
        data_folder = os.path.join(output_folder, 'data')
        
        if os.path.exists(output_folder):
            print(f"      ✓ Output folder created: {output_folder}")
        else:
            print(f"      ✗ Output folder NOT created!")
            raise FileNotFoundError(f"Output folder not found: {output_folder}")
        
        if os.path.exists(header_file):
            file_size = os.path.getsize(header_file)
            print(f"      ✓ Header.xml created ({file_size:,} bytes)")
        else:
            print(f"      ✗ Header.xml NOT created!")
            raise FileNotFoundError(f"Header.xml not found: {header_file}")
        
        if os.path.exists(data_folder):
            print(f"      ✓ data/ folder created")
        else:
            print(f"      ✗ data/ folder NOT created!")
            raise FileNotFoundError(f"data folder not found: {data_folder}")
        
        # Check for Spectral data files
        # Python SDK saves all data as Spectral0.data, then splits it into:
        # Spectral0.data, Spectral1.data, Spectral2.data, ... (one per B-scan)
        # This matches the format expected by MATLAB's yOCTLoadInterfFromFile()
        spectral_files_found = []
        total_expected_files = n_y_pixels * n_bscan_avg
        
        for i in range(total_expected_files):
            spectral_file = os.path.join(data_folder, f'Spectral{i}.data')
            if os.path.exists(spectral_file):
                file_size = os.path.getsize(spectral_file)
                spectral_files_found.append((f'Spectral{i}.data', file_size))
        
        if len(spectral_files_found) > 0:
            print(f"      ✓ Spectral data files found ({len(spectral_files_found)} files):")
            for filename, fsize in spectral_files_found:
                print(f"          - {filename} ({fsize:,} bytes)")
        else:
            print(f"      ✗ No Spectral data files found!")
            raise FileNotFoundError(f"No Spectral.data files found in {data_folder}")
        
        # List all files in output folder
        files = os.listdir(output_folder)
        print(f"      Files in output folder ({len(files)}):")
        for f in files:
            fpath = os.path.join(output_folder, f)
            if os.path.isfile(fpath):
                fsize = os.path.getsize(fpath)
                print(f"        - {f} ({fsize:,} bytes)")
            else:
                print(f"        - {f}/ (folder)")
        
        # List files in data subfolder
        if os.path.exists(data_folder):
            data_files = os.listdir(data_folder)
            print(f"      Files in data/ folder ({len(data_files)}):")
            for f in data_files[:5]:  # Show first 5 files
                fpath = os.path.join(data_folder, f)
                fsize = os.path.getsize(fpath)
                print(f"        - {f} ({fsize:,} bytes)")
            if len(data_files) > 5:
                print(f"        ... and {len(data_files) - 5} more files")
        
        # Step 4: Close scanner
        print(f"\n[4/4] Closing scanner")
        yOCTScannerClose()
        print(f"      ✓ Scanner closed successfully")
        
        # Summary
        print("\n" + "=" * 70)
        print("TEST PASSED ✓")
        print("=" * 70)
        print(f"Total time: {time.time() - start_time:.2f}s")
        print(f"  - Initialization: {init_time:.2f}s")
        print(f"  - Scanning: {scan_time:.2f}s")
        print(f"Output saved to: {output_folder}")
        print("\nOutput format (MATLAB-compatible):")
        print("- Header.xml: Metadata and scan parameters")
        print(f"- data/Spectral0.data through Spectral{total_expected_files-1}.data: One file per B-scan")
        print("- data/Chirp.data: Calibration chirp")
        print("- data/OffsetErrors.data: Calibration offset")
        print("\nYou can now:")
        print("1. Load the data with myOCT MATLAB: yOCTLoadInterfFromFile('" + output_folder.replace('\\', '/') + "')")
        print("2. Open in ThorImage OCT software")
        print("3. Verify Header.xml contains correct scan parameters")
        
        return True
        
    except Exception as e:
        print(f"\n✗ TEST FAILED")
        print(f"Error: {e}")
        print(f"Error type: {type(e).__name__}")
        
        # Try to clean up
        try:
            print("\nAttempting cleanup...")
            yOCTScannerClose()
            print("Scanner closed")
        except:
            pass
        
        import traceback
        print("\nFull traceback:")
        traceback.print_exc()
        
        return False


if __name__ == "__main__":
    print("\n" + "=" * 70)
    print("3D Volume Scan Test")
    print("=" * 70)
    print("\nThis test will:")
    print("- Initialize the OCT scanner")
    print("- Perform a small 3D volume scan (50x3 pixels)")
    print("- Save the data to a .oct file")
    print("- Verify the output")
    print("- Clean up resources")
    print("\nMake sure the OCT device is:")
    print("✓ Connected via USB")
    print("✓ Powered on")
    print("✓ Sample is in position (or scanning air is OK for this test)")
    print("\nPress Ctrl+C to abort, or Enter to continue...")
    
    try:
        input()
    except KeyboardInterrupt:
        print("\n\nTest aborted by user")
        sys.exit(0)
    
    success = test_scan_3d_volume()
    sys.exit(0 if success else 1)
