"""
Device controller for Thorlabs OCT using pySpectralRadar SDK
"""

import pyspectralradar

class ThorlabsOCTController:
    def __init__(self):
        self.device = None

    def connect(self):
        """Connect to the Thorlabs OCT device."""
        try:
            self.device = pyspectralradar.Device()
            print("Connected to Thorlabs OCT device.")
            return True
        except Exception as e:
            print(f"Failed to connect: {e}")
            return False

    def get_device_info(self):
        """Return device information if connected."""
        if self.device:
            return self.device.get_info()
        else:
            return None
