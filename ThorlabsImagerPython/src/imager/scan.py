"""
Scan module for Thorlabs OCT using pySpectralRadar SDK
"""

import pyspectralradar
import os
from datetime import datetime

class ThorlabsOCTScan:
    def __init__(self, device, probe, processing):
        self.device = device
        self.probe = probe
        self.processing = processing

    def scan_3d_volume(self, x_center, y_center, range_x, range_y, rotation_angle,
                   size_x, size_y, n_bscan_avg, output_directory, disp_a, is_save_processed):
        
        
        # Create output directory if it doesn't exist
        os.makedirs(output_directory, exist_ok=True)

        # Set B-scan averages and load calibration if needed
        self.device.set_probe_parameter('Probe_Oversampling_SlowAxis', n_bscan_avg)
        if is_save_processed:
            chirp_file = r"C:\Program Files\Thorlabs\SpectralRadar\Config\Chirp.dat"
            self.device.load_calibration('Calibration_Chirp', chirp_file)
            # TODO: Set dispersion parameters using disp_a

        # Create volume scan pattern using SDK
        scan_pattern = self.probe.scan_pattern.create_volume_pattern(
            range_x, size_x, range_y, size_y,
            "ApoEachBScan", "FrameByFrame"
        )
        # Apply rotation and shift if needed
        if rotation_angle != 0:
            scan_pattern.rotate(rotation_angle)
        if x_center != 0 or y_center != 0:
            scan_pattern.shift(x_center, y_center)

        # Optionally visualize scan pattern
        # scan_pattern.visualize_on_device()
        # scan_pattern.visualize_on_image()

        # Prepare data objects
        raw = pyspectralradar.data.rawdata.RawData()
        bscan = pyspectralradar.data.realdata.RealData()

        # Start acquisition
        self.device.acquisition.start(scan_pattern, "ASYNC_CONTINUOUS")
        for i in range(size_y):  # or desired number of scans
            self.device.acquisition.get_raw_data(buffer=raw)
            self.processing.set_data_output(bscan)
            self.processing.execute(raw)
            np_data = bscan.to_numpy()
            # Save or process np_data as needed

        # Stop measurement and cleanup
        self.device.acquisition.stop()
        scan_pattern.close()