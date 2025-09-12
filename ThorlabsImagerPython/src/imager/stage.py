"""
Stage movement module for Thorlabs OCT using pySpectralRadar SDK
"""

class ThorlabsOCTStage:
    def __init__(self, device):
        self.device = device

    def move_to(self, x, y, z):
        """Move stage to specified coordinates."""
        # TODO: Implement stage movemen