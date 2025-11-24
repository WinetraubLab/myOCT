"""
Stage control helper functions extracted from `thorlabs_imager_oct.py`.

This module provides: yOCTStageInit_1axis, yOCTStageSetPosition_1axis,
yOCTStageClose_1axis, and yOCTCloseAllStages. It isolates XA SDK usage so
the main OCT module can remain focused on OCT device functions.
"""
import os
import gc

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

# Axis to serial number mapping
_stage_serial_numbers = {
    'x': '26006464',
    'y': '26006471',
    'z': '26006482'
}

# Stage handles for each axis
_stage_handles = {}


def yOCTStageInit_1axis(axes: str) -> float:
    """Initialize stage for one axis and return current position in mm."""
    axis = axes.lower()
    actuator_model = "ZST225"
    if axis not in _stage_serial_numbers:
        raise ValueError(f"Invalid axis: {axes}")
    serial_no = _stage_serial_numbers[axis]

    # XA SDK startup
    if not hasattr(XASDK, '_oct_xa_started') or not XASDK._oct_xa_started:
        dll_path = os.path.abspath(os.path.dirname(__file__))
        if hasattr(os, 'add_dll_directory'):
            os.add_dll_directory(dll_path)
        original_cwd = os.getcwd()
        try:
            os.chdir(dll_path)
            XASDK.try_load_library(dll_path)
            XASDK.startup("")
            XASDK._oct_xa_started = True
        finally:
            os.chdir(original_cwd)

    device = None
    try:
        device = KST201(serial_no, "", TLMC_OperatingModes.Default)
        device.set_enable_state(TLMC_ChannelEnableStates.ChannelEnabled)
        device.set_connected_product(actuator_model)

        pos_counts = device.get_position_counter(TLMC_Wait.TLMC_InfiniteWait)
        pos_conv = device.convert_from_device_units_to_physical(
            TLMC_ScaleType.TLMC_ScaleType_Distance,
            pos_counts
        )
        pos_mm = pos_conv.converted_value

        _stage_handles[axis] = device
        return pos_mm

    except XADeviceException as e:
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
    """Move stage axis to position in mm using XA SDK."""
    axis = axis.lower()
    if axis not in _stage_handles:
        raise RuntimeError(f"Stage for axis {axis} not initialized.")
    device = _stage_handles[axis]
    try:
        abs_param = device.convert_from_physical_to_device(
            TLMC_ScaleType.TLMC_ScaleType_Distance,
            TLMC_Unit.TLMC_Unit_Millimetres,
            float(position_mm)
        )
        MOVE_TIMEOUT_MS = 120000
        device.move_absolute(
            TLMC_MoveModes.MoveMode_Absolute,
            abs_param,
            MOVE_TIMEOUT_MS
        )

    except XADeviceException as e:
        err_msg = getattr(e, 'message', None) or str(e)
        raise RuntimeError(f"XADeviceException during move: code={getattr(e,'error_code',None)} msg={err_msg}")
    except Exception as e:
        raise RuntimeError(f"Error during move for axis {axis}: {e}")


def yOCTStageClose_1axis(axis: str) -> None:
    """Close stage for one axis (disconnect -> close)."""
    axis = axis.lower()
    if axis in _stage_handles:
        device = _stage_handles[axis]
        error_occurred = None
        try:
            device.disconnect()
        except Exception as e:
            error_occurred = e
        try:
            device.close()
        except Exception as e:
            if error_occurred is None:
                error_occurred = e
        del _stage_handles[axis]
        if error_occurred is not None:
            raise RuntimeError(f"Error closing stage for axis {axis}: {error_occurred}")


def yOCTCloseAllStages():
    """Close all stage handles and leave XA SDK running (do not shutdown)."""
    global _stage_handles
    while _stage_handles:
        axis, dev = _stage_handles.popitem()
        try:
            dev.disconnect()
        except Exception:
            pass
        try:
            dev.close()
        except Exception:
            pass
    gc.collect()


__all__ = [
    'yOCTStageInit_1axis',
    'yOCTStageSetPosition_1axis',
    'yOCTStageClose_1axis',
    'yOCTCloseAllStages',
]
