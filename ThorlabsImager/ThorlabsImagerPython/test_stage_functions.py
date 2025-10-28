"""
Test script for Thorlabs stage functions using XA SDK
"""

from thorlabs_imager_oct import (
    yOCTStageInit_1axis,
    yOCTStageSetPosition_1axis,
    yOCTStageClose_1axis
)

import time

def test_stage(axis, move_mm):
    print(f"\n--- Testing axis '{axis}' ---")
    try:
        # Initialize stage
        pos = yOCTStageInit_1axis(axis)
        print(f"Initial position (mm): {pos}")
        # Move stage
        print(f"Moving axis '{axis}' to {move_mm} mm...")
        yOCTStageSetPosition_1axis(axis, move_mm)
        print(f"Move command sent.")
        # Wait and read new position
        time.sleep(2)
        new_pos = yOCTStageInit_1axis(axis)
        print(f"New position (mm): {new_pos}")
    except Exception as e:
        print(f"Error with axis '{axis}': {e}")
    finally:
        # Close stage
        try:
            yOCTStageClose_1axis(axis)
            print(f"Closed axis '{axis}'")
        except Exception as close_e:
            print(f"Error closing axis '{axis}': {close_e}")

if __name__ == "__main__":
    # Test all axes
    for axis in ['x', 'y', 'z']:
        test_stage(axis, 10.0)
