# Imager package initialization

# Import low-level hardware functions for easy access
from .oct_python_library_operations import (
    # OCT Scanner functions
    yOCTScannerInit,
    yOCTScannerClose,
    yOCTScan3DVolume,
    yOCTPhotobleachLine,
    
    # Stage functions
    yOCTStageInit,
    yOCTStageMoveTo,
    yOCTStageSetPosition_1axis,
    
    # Laser and optical switch
    yOCTSetLaserPower,
    yOCTTurnOpticalSwitch,
    
    # Utility functions
    yOCTGetProbeConfig,
)

# Package metadata
__version__ = '0.1.0'
__author__ = 'WinetraubLab'

# Define what gets imported with "from imager import *"
__all__ = [
    # OCT functions
    'yOCTScannerInit',
    'yOCTScannerClose',
    'yOCTScan3DVolume',
    'yOCTPhotobleachLine',
    
    # Stage functions
    'yOCTStageInit',
    'yOCTStageMoveTo',
    'yOCTStageSetPosition_1axis',
    
    # Laser and optical switch
    'yOCTSetLaserPower',
    'yOCTTurnOpticalSwitch',
    
    # Utility
    'yOCTGetProbeConfig',
]