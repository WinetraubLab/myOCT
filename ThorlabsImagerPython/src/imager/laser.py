"""
Laser control module for Thorlabs OCT using pySpectralRadar SDK
"""

class ThorlabsOCTLaser:
    def __init__(self, device):
        self.device = device

    def set_laser_state(self, state):
        """Turn laser on or off."""
        # TODO: Impl