import matplotlib.pyplot as plt

from pyspectralradar import Coloring, OCTSystem, RawData, RealData, set_log_level
from pyspectralradar.types import *

"""
The purpose of the simple examples is to demonstrate the usage of the basic building blocks of the SDK. Each code
snippet focuses on a single concept.
"""

ENABLE_EXPORTS = False
ENABLE_PLOTS = False


def simple_measurement():
    """
    Example on how to acquire a simple B-Scan measurement (1024 A-Scans distributed along a segment 2 millimeter long).

    Returns:
        None

    """

    # initialization of device, probe and processing handles
    sys = OCTSystem()
    dev = sys.dev
    probe = sys.probe_factory.create_default()
    proc = sys.processing_factory.from_device()

    # the :class:`~pyspectralradar.data.rawdata.RawData` object will be used to get the raw data handle and will
    # contain the data from the detector (e.g. line scan camera is SD-OCT systems) without any modification
    raw = RawData()
    # the :class:`~pyspectralradar.data.realdata.RealData` object will be used for the processed data and will
    # contain the OCT image
    bscan = RealData()

    # define simple B-scan pattern with 2mm range and 1024 A-scans
    pattern = probe.scan_pattern.create_bscan_pattern(2.0, 1024)

    # start the measurement to acquire the specified scan pattern once
    dev.acquisition.start(pattern, AcqType.ASYNC_FINITE)

    # grabs the spectral data from the frame grabber and copies it to the
    # :class:`~pyspectralradar.data.rawdata.RawData` object
    dev.acquisition.get_raw_data(buffer=raw)

    # specifies the output of the processing routine and executes the processing
    proc.set_data_output(bscan)
    proc.execute(raw)

    # stops the measurement
    dev.acquisition.stop()

    # clear up everything
    del pattern

    del bscan
    del raw
    del proc
    del probe
    del dev

    print('simple_measurement finished. ')


def simple_measurement_with_log():
    """
    Example on how to acquire a simple B-Scan measurement with logging enabled"

    Returns:
        None

    """
    set_log_level(LogLevel.INFO)
    simple_measurement()
    set_log_level(LogLevel.OFF)


def export_data_and_image():
    """
    After a simple B-Scan measurement has been acquired, data are stored (for future post-processing) and exported (
    for beautiful pictures).

    Returns:
        None
    """

    # Initialization of device, probe and processing handles.
    sys = OCTSystem()
    dev = sys.dev
    probe = sys.probe_factory.create_default()
    proc = sys.processing_factory.from_device()

    # The raw data handle will contain the unprocessed data from the detector
    # (e.g. line scan camera is SD-OCT systems) without any modification.
    raw = RawData()

    # The data handle will be used for the processed data and will contain the OCT image.
    bscan = RealData()

    # Define a horizontal B-scan pattern with 2mm range and 1024 A-scans.
    pattern = probe.scan_pattern.create_bscan_pattern(2.0, 1024)

    # Start the measurement to acquire the specified scan pattern once.
    dev.acquisition.start(pattern, AcqType.ASYNC_FINITE)

    # Grabs the spectral data from the frame grabber and copies it to the previously created raw data handle.
    dev.acquisition.get_raw_data(buffer=raw)

    # Specifies the output of the processing routine and executes the processing.
    proc.set_data_output(bscan)
    proc.execute(raw)

    # Stops the measurement.
    dev.acquisition.stop()

    # Exports the processed data to a csv-file to the specified folder. Several different export formats are
    # available, see :class:`~pyspectralradar.types.datatypes.DataExportFormat`
    if ENABLE_EXPORTS:
        bscan.export(DataExportFormat.CSV, 'pyspectralradar_export_data_and_image.csv')

    # The OCT image can be exported as an image in common image format as well. It needs to be colored for that,
    # e.g. the colormap and boundaries for the coloring need to be defined.
    # :class:`~pyspectralradar.coloring.coloring.Coloring` object with specified color scheme, here simple black and
    # white, and byte order
    coloring = Coloring(ColorScheme.BLACK_AND_WHITE, ByteOrder.RGBA)

    # set the boundaries for the colormap, 0.0 as lower and 70.0 as upper boundary are a good choice normally.
    coloring.set_boundaries(0.0, 70.0)

    # Exports the processed data to an image with the specified slice normal direction since this will result in
    # 2D-images. To get the B-scan in one image with depth and scan field as axes for a single B-scan
    # :class:`pyspectralradar.types.datatypes.DataDirection` DIR3, which is the y-axis, is chosen.
    if ENABLE_EXPORTS:
        bscan.export_data_as_image(coloring, ColoredDataExportFormat.JPG, DataDirection.DIR3,
                                   'pyspectralradar_export_data_and_image.jpg',
                                   ExportOptionMasks.DRAW_SCALEBAR or ExportOptionMasks.USE_PHYSICAL_ASPECT_RATIO)

    # Clean up everything.
    del pattern

    del bscan
    del raw
    del proc

    del probe
    del dev

    print('export_data_and_image finished. ')


def averaging_and_imaging_speed():
    """
    Example on how to adjust image quality by averaging and exposure time.

    Returns:
        None
    """

    sys = OCTSystem()
    dev = sys.dev
    probe = sys.probe_factory.create_default()
    proc = sys.processing_factory.from_device()

    raw = RawData()
    bscan = RealData()

    # The scan speed of SD-OCT systems can be changed. A better image quality can be obtained with a longer
    # integration time and therefore lower scan speed. Preset 0 is the default scan speed followed by the
    # highest. Please note to adjust the reference intensity on your scanner manually. The number and description
    # of available device presets can be obtained with
    # :func:`~pyspectralradar.octdevice.submodules.presets.devicepresets.Presets.get_presets_in_category`.
    device_presets = dev.presets.get_presets_in_category(0)
    print('Device presets:\n', device_presets)

    # Pick a device preset to use: (0 = default)
    chosen_preset = 0
    dev.presets.set_active_preset(0, chosen_preset, probe, proc)

    # Another possibility to modify the image quality is averaging. In the SDK is the data acquisition and
    # processing separated. Therefore, the adjustment of averaging parameters need to be done for both parts. With
    # the probe properties, the averaging for the data acquisition can be specified.
    ascan_averaging = 2
    bscan_averaging = 3
    probe.properties.set_oversampling(ascan_averaging)  # this results in a repetition of each scan point in the B-scan
    probe.properties.set_oversampling_slow_axis(
        bscan_averaging)  # this results in a repetition of each B-scan in the pattern

    # With the processing properties, the averaging parameter for the processing routine can be adjusted.
    # Please pay attention to match the averaging parameters for acquisition and processing!
    proc.properties.set_ascan_avg(ascan_averaging)
    proc.properties.set_bscan_avg(bscan_averaging)

    pattern = probe.scan_pattern.create_bscan_pattern(2.0, 1024)
    # Please see the documentation of :class:`~pyspectralradar.types.octdevicetypes.AcqType` to get more information
    # about the different acquisition types
    dev.acquisition.start(pattern, AcqType.ASYNC_FINITE)

    dev.acquisition.get_raw_data(buffer=raw)
    proc.set_data_output(bscan)
    proc.execute(raw)

    dev.acquisition.stop()

    coloring = Coloring(ColorScheme.BLACK_AND_WHITE, ByteOrder.RGBA)
    coloring.set_boundaries(0.0, 70.0)
    if ENABLE_EXPORTS:
        bscan.export_data_as_image(coloring, ColoredDataExportFormat.JPG, DataDirection.DIR3,
                                   'pyTest_averaging_and_imaging_speed.jpg')

    del pattern

    del bscan
    del raw

    del proc
    del probe
    del dev

    print('averaging_and_imaging_speed finished. ')


def volume_scan_pattern():
    """
    Example on how to acquire a volume pattern with averaging.

    Returns:
        None
    """

    sys = OCTSystem()
    dev = sys.dev
    probe = sys.probe_factory.create_default()
    proc = sys.processing_factory.from_device()

    raw_slice = RawData()
    raw_volume = RawData()
    bscan = RealData()
    volume = RealData()

    # Parameter for the volume pattern
    ascans_per_bscan = 10
    bscans_per_volume = 50

    # averaging parameter
    bscan_averaging = 3
    probe.properties.set_oversampling_slow_axis(bscan_averaging)
    proc.properties.set_bscan_avg(bscan_averaging)

    # Several different scan pattern, e.g. for multiple A-scans at one position, B-scans as a line or circle or
    # volumes can be created. For more information please see region #ScanPattern in the documentation. Creating
    # a volume scan pattern requires an additional input parameter for the type of the acquisition order which
    # specifies how to grab the raw data. With AcquisitionOrder.ACQ_ORDER_ALL the whole data of the
    # scan pattern will be returned by calling the function
    # :func:`~pyspectralradar.octdevice.submodules.acquisition.acquisition.Acquisition.get_raw_data` once.
    volume_pattern_aoa = probe.scan_pattern.create_volume_pattern(2.0, ascans_per_bscan, 2.0, bscans_per_volume,
                                                                  ApodizationType.EACH_BSCAN,
                                                                  AcquisitionOrder.ACQ_ORDER_ALL)
    dev.acquisition.start(volume_pattern_aoa, AcqType.ASYNC_FINITE)
    dev.acquisition.get_raw_data(buffer=raw_volume)

    proc.set_data_output(volume)
    proc.execute(raw_volume)

    dev.acquisition.stop()

    # With an acquisition order that captures frame by frame, the data of the scan pattern will be returned slice by
    # slice calling the function
    # :func:`~pyspectralradar.octdevice.submodules.acquisition.acquisition.Acquisition.get_raw_data`. To get the
    # data of the whole volume the function
    # :func:`~pyspectralradar.octdevice.submodules.acquisition.acquisition.Acquisition.get_raw_data` need to be
    # called (bscans per volume * oversampling of the slow scanning axis) times.
    volume_pattern_fbf = probe.scan_pattern.create_volume_pattern(2.0, ascans_per_bscan, 2.0, bscans_per_volume,
                                                                  ApodizationType.EACH_BSCAN,
                                                                  AcquisitionOrder.FRAME_BY_FRAME)
    dev.acquisition.start(volume_pattern_fbf, AcqType.ASYNC_FINITE)

    for i in range(0, (bscans_per_volume * bscan_averaging)):
        dev.acquisition.get_raw_data(buffer=raw_slice)

        proc.set_data_output(bscan)
        proc.execute(raw_slice)

        # To collect the data of the whole volume the data can be added slice by slice to one
        # :class:`~pyspectralradar.data.realdata.RealData` object
        volume.append(bscan, DataDirection.DIR3)

        # To collect the raw data of the whole volume the data can be added slice by slice to one
        # :class:`~pyspectralradar.data.rawdata.RawData` object
        raw_volume.append(raw_slice, DataDirection.DIR3)

    dev.acquisition.stop()

    del volume_pattern_aoa
    del volume_pattern_fbf

    del bscan
    del volume
    del raw_slice
    del raw_volume

    del proc
    del probe
    del dev

    print('averaging_and_imaging_speed finished. ')


def modify_scan_patterns():
    """
    Example on how to perform rotation, shifting and zooming of a scan pattern.

    Returns:
        None
    """

    sys = OCTSystem()
    dev = sys.dev
    probe = sys.probe_factory.create_default()
    proc = sys.processing_factory.from_device()

    raw = RawData()
    bscan = RealData()

    # All scan patterns are created as horizontal scans centered at (0.0, 0.0) normally. With the following
    # functions you can shift, rotate and zoom the specified pattern. The modifications of a scan pattern (
    # rotation and zoom) are all around the optical center which is (0,0) in mm. Therefore, the rotation and Zoom
    # should be applied before :func:`~pyspectralradar.scanpattern.scanpattern.ScanPattern.shift` is used.
    pattern = probe.scan_pattern.create_bscan_pattern(2.0, 1024)

    # Please note that the angle of :func:`~pyspectralradar.scanpattern.scanpattern.ScanPattern.rotate` is in radians
    angle_degree = 45
    pattern.rotate(angle_degree * 3.14159265 / 180)

    # Increases or decreases the size of the scan pattern around the specified scan pattern center
    zoom_factor = 1.5
    pattern.zoom(zoom_factor)

    # shifts the specified scan pattern relative to its original position, here (0.0, 0.0), by (shift_x, shift_y).
    shift_x = 1.0
    shift_y = 2.0
    pattern.shift(shift_x, shift_y)

    dev.acquisition.start(pattern, AcqType.ASYNC_FINITE)
    dev.acquisition.get_raw_data(buffer=raw)

    proc.set_data_output(bscan)
    proc.execute(raw)

    dev.acquisition.stop()

    del pattern
    del bscan
    del raw

    del proc
    del probe
    del dev

    print('modify_scan_patterns finished. ')


def get_data_content():
    """
    Example on how to get access to the data content from a data handle.

    Returns:
        None
    """

    # Initialize handles
    sys = OCTSystem()
    dev = sys.dev
    probe = sys.probe_factory.create_default()
    proc = sys.processing_factory.from_device()

    raw = RawData()
    bscan = RealData()

    # create scan pattern and start/stop a single measurement
    pattern = probe.scan_pattern.create_bscan_pattern(2.0, 1024)
    dev.acquisition.start(pattern, AcqType.ASYNC_FINITE)
    dev.acquisition.get_raw_data(buffer=raw)
    proc.set_data_output(bscan)
    proc.execute(raw)
    dev.acquisition.stop()

    # create 3-dim numpy array (YXZ ordered) and copy the data contents of the different data handles
    print('raw_size: ', *raw.shape)
    raw_numpy = raw.to_numpy()
    print('bscan_size: ', *bscan.shape)
    bscan_numpy = bscan.to_numpy()

    if ENABLE_PLOTS:
        plt.figure()
        plt.title('get_data_content(): Raw Content as Numpy Array')
        plt.imshow(raw_numpy.reshape(raw.shape[1],
                                     raw.shape[0]).T, cmap='gray')

        plt.figure()
        plt.title('get_data_content(): Data Content as Numpy Array')
        plt.imshow(bscan_numpy.reshape(bscan.shape[1],
                                       bscan.shape[0]).T, cmap='gray')
        plt.show()

    print('get_data_content finished.')


def continuous_measurement():
    """
    Example on how to perform a continuous acquisition of multiple B-scans.

    Returns:
        None
    """

    # initialization of device, probe and processing handles
    sys = OCTSystem()
    dev = sys.dev
    probe = sys.probe_factory.create_default()
    proc = sys.processing_factory.from_device()

    # the RawData() object will be used to get the raw data handle and will contain the data from the detector (
    # e.g. line scan camera is SD-OCT systems) without any modification
    raw = RawData()
    # the #Data() object will be used for the processed data and will contain the OCT image
    bscan = RealData()

    # define simple B-scan pattern with 2mm range and 1024 A-scans
    pattern = probe.scan_pattern.create_bscan_pattern(2.0, 1024)

    print('Performing continuous acquisition...\n')
    # start the measurement to acquire the specified scan continuously
    dev.acquisition.start(pattern, AcqType.ASYNC_CONTINUOUS)

    frame_count = 100
    for frame_index in range(0, frame_count + 1):
        # grabs the spectral data from the frame grabber and copies it to the #RawData() object
        dev.acquisition.get_raw_data(buffer=raw)

        # specifies the output of the processing routine and executes the processing
        proc.set_data_output(bscan)
        proc.execute(raw)

        # continuous acquisition may lose frames if getRawData is not called fast enough.
        lost_frames = raw.lost_frames
        print('Frame ', frame_index, '/', frame_count, ' (', lost_frames, ' frames lost)\n')

    # stops the measurement
    dev.acquisition.stop()

    del pattern

    del bscan
    del raw

    del proc
    del probe
    del dev

    print('continuous_measurement finished.')


if __name__ == '__main__':
    print("PySimpleSpectralRadarDemos started. \n")

    set_log_level(LogLevel.OFF)
    keep_going = True

    while keep_going:
        print("The following simple demonstration programs are available: \n")
        print("a: Single B-scan acquisition")
        print("b: Data export as csv and jpg format")
        print("c: Adjusting image quality by averaging")
        print("d: Acquisition of a volume pattern with averaging")
        print("e: Rotation, shifting and zooming of a scan pattern")
        print("f: Get access to the data content from a DataHandle")
        print("g: Continuous acquisition of multiple B-scans")
        print("h: Single B-scan acquisition with logging")
        print("x: Terminate")

        x = input('Select the program that shall be executed\n')
        print('Your selection: ', x, '\n')
        if x == 'a':
            simple_measurement()
        elif x == 'b':
            export_data_and_image()
        elif x == 'c':
            averaging_and_imaging_speed()
        elif x == 'd':
            volume_scan_pattern()
        elif x == 'e':
            modify_scan_patterns()
        elif x == 'f':
            get_data_content()
        elif x == 'g':
            continuous_measurement()
        elif x == 'h':
            simple_measurement_with_log()
        elif x == 'x':
            keep_going = False
        else:
            print('Invalid selection, try again.\n')
