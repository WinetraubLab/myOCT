from pyspectralradar import OCTSystem
from pyspectralradar.data.rawdata import RawData
from pyspectralradar.data.realdata import RealData

def main():
    print("Initializing Thorlabs Imager using pySpectralRadar SDK...")
    # Initialize OCT system and device
    oct_system = OCTSystem()
    device = oct_system.dev
    probe = oct_system.probe_factory.create_default()
    processing = oct_system.processing_factory.from_device()

    # Create a scan pattern (2mm range, 1024 A-scans)
    scan_pattern = probe.scan_pattern.create_bscan_pattern(2.0, 1024)

    # Prepare data objects
    raw = RawData()
    bscan = RealData()

    print("Starting acquisition...")
    device.acquisition.start(scan_pattern, "ASYNC_CONTINUOUS")
    for i in range(10):  # Example: grab 10 b-scans
        device.acquisition.get_raw_data(buffer=raw)
        processing.set_data_output(bscan)
        processing.execute(raw)
        # Convert to numpy array and print shape
        np_data = bscan.to_numpy()
        print(f"B-scan {i+1} shape: {np_data.shape}")
    device.acquisition.stop()
    print("Acquisition complete.")

    scan = ThorlabsOCTScan(device, probe, processing)

if __name__ == "__main__":
    main()