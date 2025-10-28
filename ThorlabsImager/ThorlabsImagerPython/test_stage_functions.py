"""
Test script for Thorlabs stage functions using XA SDK
"""

from thorlabs_imager_oct import (
    yOCTStageInit_1axis,
    yOCTStageSetPosition_1axis,
    yOCTStageClose_1axis
)
import thorlabs_imager_oct as tmo
from xa_sdk.shared.tlmc_type_structures import TLMC_Wait, TLMC_ScaleType, TLMC_Unit

import time

def test_stage(axis, move_mm):
    print(f"\n--- Testing axis '{axis}' ---")
    try:
        # Initialize stage
        pos = yOCTStageInit_1axis(axis)
        print(f"Initial position (mm): {pos}")

        # Move stage (functions now raise RuntimeError on failure)
        try:
            yOCTStageSetPosition_1axis(axis, move_mm)
        except RuntimeError as move_err:
            # Surface move errors for diagnosis
            print(f"Move failed for axis '{axis}': {move_err}")

        # Wait a short time for the controller to update
        time.sleep(2)

        # Read current position directly from the live handle (if available)
        device = tmo._stage_handles.get(axis)
        if device is not None:
            counts = device.get_position_counter(TLMC_Wait.TLMC_InfiniteWait)
            conv = device.convert_from_device_units_to_physical(TLMC_ScaleType.TLMC_ScaleType_Distance, counts)
            new_pos = conv.converted_value
            print(f"New position (mm): {new_pos}")
        else:
            print(f"No live device handle for axis '{axis}' to read position.")

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
