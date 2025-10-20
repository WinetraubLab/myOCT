# Imager package initialization

# Import main OCT functions for easy access
from .thorlabs_imager_oct import (
    yOCTScannerInit,
    yOCTScannerClose,
    yOCTPhotobleachLine,
)

__all__ = [
    'yOCTScannerInit',
    'yOCTScannerClose',
    'yOCTPhotobleachLine',
]

__version__ = '0.1.0'
