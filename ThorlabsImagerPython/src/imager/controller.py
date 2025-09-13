"""
Device controller for Thorlabs OCT using pySpectralRadar SDK
"""

import pyspectralradar

class ThorlabsOCTController:
    def __init__(self):
        self.device = None
        self.probe = None
        self.oct_probe_name = None
        self.oct_scan_speed = None

    def init_scanner(self, probe_file_path):
        """
        Initialize OCT Scanner with the given probe ini file path.
        """
        try:
            # Turn verbose off (if supported by SDK)
            # pyspectralradar.set_log_output('none')  # Example, depends on SDK

            self.device = pyspectralradar.Device()
            self.probe = self.device.init_probe(probe_file_path)

            if self.device is None:
                print("Device handle is invalid.")
                # If SDK provides error details:
                # print(self.device.get_error())
                return False

            dev_name = self.device.get_property('Device_Type')
            if dev_name == "Ganymede":
                self.oct_probe_name = "Ganymede"
                self.oct_scan_speed = 28000
            elif dev_name == "Telesto":
                self.oct_probe_name = "Telesto"
                self.oct_scan_speed = 28000
            else:
                print(f"Unknown device: {dev_name}")
            print(f"Initialized device: {dev_name}")
            return True
        except Exception as e:
            print(f"Failed to initialize scanner: {e}")
            return False

    def get_device_info(self):
        """Return device information if connected."""
        if self.device:
            return self.device.get_info()
        else:
            return None
        
    def close_scanner(self):
        if self.probe:
            self.probe.close()
        if self.device:
            self.device.close()
