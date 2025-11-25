"""
Cleanup coordination for Thorlabs OCT and stage hardware.

This module provides a single unified cleanup function that coordinates
the shutdown of both OCT scanner and stage control hardware.
"""
import gc


def yOCTCloseAll():
    """Close all open hardware resources (stages and OCT scanner).

    This is the primary cleanup function that should be called at program exit.
    It coordinates cleanup of all resources in the correct order:
    1. Close all stage axes (disconnect → close each device)
    2. Close OCT scanner resources
    
    This function is idempotent - safe to call multiple times.
    It checks actual resource state and performs best-effort cleanup.
    
    Args:
        None
        
    Returns:
        None
    """
    # 1. Close all stage handles first (hardware before software SDK)
    try:
        from .thorlabs_imager_stage import yOCTCloseAllStages
        yOCTCloseAllStages()
    except Exception:
        # Best-effort fallback: ignore if stage module not available
        pass

    # 2. Close OCT scanner resources
    try:
        from .thorlabs_imager_oct import yOCTScannerClose, yOCTScannerIsInitialized
        if yOCTScannerIsInitialized():
            yOCTScannerClose()
    except Exception:
        pass  # Best effort

    # 3. Force final garbage collection to ensure all resources released
    gc.collect()


__all__ = ['yOCTCloseAll']
