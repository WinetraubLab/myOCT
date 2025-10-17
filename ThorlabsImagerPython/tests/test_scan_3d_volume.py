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
    probe_path = r"C:\Program Files\Thorlabs\SpectralRadar\Config\Probe - Olympus 40x.ini"
    output_folder = r"C:\Users\OCT User\Desktop\TestD"
    
    # Test scan parameters - typical case with no B-scan averaging
    
    center_x = 0.0      # mm - centered
    center_y = 0.0      # mm - centered
    range_x = 1       # mm - 1mm scan range
    range_y = 1       # mm - 1mm scan range
    rotation = 0.0      # degrees - no rotation
    n_x_pixels = 1000     # Small number for quick test (vs 100 in demo)
    n_y_pixels = 6      # 6 B-scans (6 Y positions)
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
        oct_file_path = os.path.join(output_folder, 'scan.oct')
        
        if os.path.exists(output_folder):
            print(f"      ✓ Output folder created: {output_folder}")
        else:
            print(f"      ✗ Output folder NOT created!")
            raise FileNotFoundError(f"Output folder not found: {output_folder}")
        
        if os.path.exists(oct_file_path):
            file_size = os.path.getsize(oct_file_path)
            print(f"      ✓ scan.oct created ({file_size:,} bytes)")
        else:
            print(f"      ✗ scan.oct NOT created!")
            raise FileNotFoundError(f"scan.oct not found: {oct_file_path}")
        
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
        
        # Validate file size (basic sanity check)
        # Expected size depends on: spectral points × A-scans × B-scans × 2 bytes + overhead
        # Rough estimate for test scan: ~2-10 MB
        if file_size < 100000:  # Less than 100 KB seems too small
            print(f"      ⚠ Warning: scan.oct seems small ({file_size:,} bytes)")
            print(f"      Expected: at least 100 KB for typical OCT data")
        else:
            print(f"      ✓ scan.oct size is reasonable")
        
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
        print("\nOutput format:")
        print("- scan.oct: Complete OCT file (OCITY format) containing:")
        print("  • Header.xml: Scan metadata and parameters")
        print("  • Spectral data: Raw spectral/interferogram data")
        print("  • Image data: Processed intensity (amplitude in dB)")
        print("  • Chirp.data: Spectral calibration")
        print("  • Offset.data: Offset calibration")
        print("  • Apodization.data: Window function")
        print("\nYou can now:")
        print("1. Open in ThorImage OCT software")
        print("2. Extract with unzip tool or Python: zipfile.ZipFile('scan.oct').extractall()")
        print("3. Load with myOCT MATLAB after extracting")
        
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
