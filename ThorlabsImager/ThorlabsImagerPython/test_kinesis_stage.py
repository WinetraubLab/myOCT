"""
Test script for Thorlabs stage functions using Kinesis (.NET via pythonnet)

This script initializes each axis, moves to a target absolute position in mm,
then reads back the live position from the device and closes the connection.

Usage: run directly. Adjust TARGET_MM if desired.
"""

import time

from thorlabs_imager_oct import (
    yOCTStageInit_1axis,
    yOCTStageSetPosition_1axis,
    yOCTStageClose_1axis,
)
import thorlabs_imager_oct as tmo  # access module internals (_kinesis_devices)


TARGET_MM = 10.0  # absolute target position in mm for the test move


def test_stage(axis: str, target_mm: float) -> None:
    print(f"\n--- Testing axis '{axis}' ---")
    try:
        # Initialize stage (returns current position in mm)
        pos_mm = yOCTStageInit_1axis(axis)
        print(f"Initial position (mm): {pos_mm}")

        # Request absolute move to target_mm (function blocks until completion)
        try:
            print(f"Moving axis '{axis}' to {target_mm} mm (absolute)...")
            yOCTStageSetPosition_1axis(axis, target_mm)
        except RuntimeError as move_err:
            print(f"Move failed for axis '{axis}': {move_err}")

        # Give the controller a brief moment to update Position property
        time.sleep(1.0)

        # Read current position directly from the live device handle, if available
        dev = tmo._kinesis_devices.get(axis.lower())
        if dev is not None:
            try:
                new_pos_mm = float(dev.Position)
                print(f"New position (mm): {new_pos_mm}")
            except Exception as read_err:
                print(f"Could not read device position for axis '{axis}': {read_err}")
        else:
            print(f"No live Kinesis device handle for axis '{axis}'.")

    except Exception as e:
        print(f"Error with axis '{axis}': {e}")
    finally:
        # Close stage for this axis
        try:
            yOCTStageClose_1axis(axis)
            print(f"Closed axis '{axis}'")
        except Exception as close_err:
            print(f"Error closing axis '{axis}': {close_err}")


if __name__ == "__main__":
    # Test all axes with the same absolute target
    for axis in ['x', 'y', 'z']:
        test_stage(axis, TARGET_MM)
