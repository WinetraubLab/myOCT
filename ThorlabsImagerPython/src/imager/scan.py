"""
Scan module for Thorlabs OCT using pySpectralRadar SDK
"""

import pyspectralradar

class ThorlabsOCTScan:
    def __init__(self, device):
        self.device = device

    def perform_scan(self, params):
        """Perform a scan with given parameters."""
        # TODO: Implement scan logic using pyspectralradar
        pass