"""
Demo script for testing yOCTPhotobleachLine function.

This script demonstrates how to:
1. Initialize the OCT scanner
2. Turn on the laser
3. Photobleach a line
4. Turn off the laser
5. Close the scanner

Equivalent to DemoNet1.m
"""

from thorlabs_imager_oct import yOCTScannerInit, yOCTScannerClose, yOCTPhotobleachLine


def main():
    # Path to your probe configuration file
    # Adjust this path to match your probe file location
    probe_path = r"C:\path\to\your\probe.ini"
    
    try:
        # Initialize the OCT scanner
        print("Initializing OCT Scanner...")
        yOCTScannerInit(probe_path)
        
        # TODO: Turn on laser (requires yOCTTurnLaser implementation)
        # yOCTTurnLaser(True)
        print("WARNING: Laser control not yet implemented!")
        print("Please turn on laser manually before photobleaching.")
        input("Press Enter when laser is ready...")
        
        # Photobleach a line from (-1, 0) to (1, 0) mm
        print("Photobleaching line...")
        yOCTPhotobleachLine(
            startX=-1.0,    # Start X position [mm]
            startY=0.0,     # Start Y position [mm]
            endX=1.0,       # End X position [mm]
            endY=0.0,       # End Y position [mm]
            duration=10.0,  # Total duration [seconds]
            nPasses=10      # Number of passes
        )
        print("Photobleaching complete!")
        
        # TODO: Turn off laser (requires yOCTTurnLaser implementation)
        # yOCTTurnLaser(False)
        print("Please turn off laser manually.")
        input("Press Enter to continue...")
        
    except Exception as e:
        print(f"Error: {e}")
        
    finally:
        # Always close the scanner
        print("Closing scanner...")
        yOCTScannerClose()
        print("Done!")


if __name__ == "__main__":
    main()
