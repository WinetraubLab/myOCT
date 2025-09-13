import os
import time
from os.path import exists

import matplotlib.pyplot as plt
import numpy as np

import pyspectralradar.types as pt
from pyspectralradar import ColoredData, Coloring, ComplexData, Doppler, ImageField, OCTFile, OCTSystem, Polarization, \
    ProcessingFactory, RawData, RealData, ScanPointsFactory, SpeckleVariance, set_log_level

"""
The purpose of the advanced examples is to show
• practical combinations of the building blocks,
• auxiliary operations that complement the acquisition and processing routines.
"""

ENABLE_EXPORTS = False
ENABLE_PLOTS = False


def write_oct_file(file_format: pt.FileFormat = pt.FileFormat.OCITY) -> bool:
    """
    Example on how to write the results from a measurement to an OCT file.

    Returns:
        True
    """
    print('\n----------------------------------')
    print('Initialize Device and Handles...')
    print('----------------------------------\n')
    sys = OCTSystem()
    probe = sys.probe_factory.create_default()
    print('Currently used probe is: ', probe.display_name)

    print('\n----------------------------------')
    print('Set scan parameter...')
    print('----------------------------------\n')

    # set scan rate and activate extended adjust
    dev = sys.dev
    proc = sys.processing_factory.from_device()
    preset_category, preset = 0, 0
    dev.presets.set_active_preset(preset_category, preset, probe, proc)
    proc.properties.set_ext_adjust(1)

    # define simple B-scan pattern with 2mm range and 1024 A-scans
    scan_range = 2.0
    a_scans = 1024
    scan_pattern = probe.scan_pattern.create_bscan_pattern(scan_range, a_scans)

    print('\n----------------------------------')
    print('Run Acquisition...')
    print('----------------------------------\n')

    # acquire video camera image
    video_image = dev.camera.get_image()

    # start the measurement to acquire the specified scan pattern once
    time_start = time.time()
    dev.acquisition.start(scan_pattern, pt.AcqType.ASYNC_FINITE)

    # grabs the spectral data from the frame grabber and copies it to the #RawDataHandle
    raw = dev.acquisition.get_raw_data()
    # the raw data handle raw will contain the data from the detector (e.g. line scan camera is SD-OCT systems)
    # without any modification

    # the #data handle bscan will be used for the processed data and will contain the OCT image
    bscan = RealData()
    # specifies the output of the processing routine and executes the processing
    proc.set_data_output(bscan)
    proc.execute(raw)

    # stops the measurement
    dev.acquisition.stop()
    time_end = time.time()

    print('\n----------------------------------')
    print('Check properties...')
    print('----------------------------------\n')
    print('\n----------------------------------')
    print('Raw data dimension: ', )
    print(raw.shape)
    print('Real data number of elements:')
    print(raw.size)
    print('\n----------------------------------')
    print('Real data dimensions:')
    print(bscan.shape)
    print('Real data number of elements:')
    print(bscan.size)
    print('----------------------------------\n')

    print('----------------------------------\n')
    print('Export Data...\n')
    print('----------------------------------\n')

    # exports the processed data to a csv-file to the specified folder. For more information about the data
    # export see #ExportDataAndImage
    if ENABLE_EXPORTS:
        bscan.export(pt.DataExportFormat.CSV, 'pyTest_simple_measurement.csv')

    print('\n----------------------------------')
    print('Create new OCTFile...\n')
    print('----------------------------------\n')

    oct_file = OCTFile(filetype=file_format)

    print('\n----------------------------------')
    print('Store Data to OCTFile...\n')
    print('----------------------------------\n')

    if file_format == pt.FileFormat.OCITY:
        oct_file.save_calibration(proc, 0)
        # add en face video camera image of measurement to file
        oct_file.add_data(video_image, pt.FileNames.VIDEO_IMAGE)
        # color = Coloring(ColorScheme.BLACK_AND_WHITE, ByteOrder.RGBA)
        color = Coloring(pt.ColorScheme.BLACK_AND_RED_YELLOW, pt.ByteOrder.RGBA)
        color.set_boundaries(0.0, 70.0)
        # add bscan preview image
        preview_image = color.colorize(bscan, transpose=True)
        oct_file.add_data(preview_image, pt.FileNames.PREVIEW_IMAGE)

    oct_file.add_data(bscan, pt.FileNames.OCT_DATA)
    oct_file.add_data(raw, "data\\Spectral0.data")

    oct_file.properties.set_process_state = pt.ProcessingStates.RAW_AND_PROCESSED
    oct_file.properties.set_acquisition_mode("Mode2D")
    oct_file.properties.set_comment("Created using PySDK.")
    oct_file.properties.set_study("PySDK")

    oct_file.set_metadata(dev, proc, probe, scan_pattern)
    acq_time = time_end - time_start
    oct_file.properties.set_scan_time_sec(acq_time)
    current_time = np.int64(time.time())
    oct_file.timestamp = current_time
    if file_format == pt.FileFormat.OCITY:
        oct_file.save('PyDemoSDKCreatedFile.oct')
    if file_format == pt.FileFormat.SDR:
        oct_file.save('PyDemoSDKCreatedFile.sdr')

    print('\n----------------------------------')
    print('Clear objects from memory...')
    print('----------------------------------')

    del oct_file
    del video_image
    del preview_image

    del bscan
    del raw

    del scan_pattern
    del proc
    del probe
    del dev

    print('write_oct_file finished. ')
    return True


def read_oct_file() -> bool:
    """
    This example program shows how to read an oct-file with the SDK which has been acquired and saved with
    ThorImageOCT. To make sure the correct parameters will be used to modify the loaded data, e.g. the files for
    the processing from the dataset and not the current ones for an acquisition, it is necessary to use the
    functions specified for an OCTFile as in this example.

    Returns:
        True
    """
    # this calls the demo program from above and creates an .oct-file
    if not exists("PyDemoSDKCreatedFile.oct"):
        write_oct_file()

    # Please select an .oct-file you want to load
    oct_file = OCTFile("PyDemoSDKCreatedFile.oct")

    # with the getter functions, the metadata information from the dataset can be loaded
    print('Range X in mm: ', oct_file.properties.get_range_x())

    # load intensity data as numpy array from OCTFile
    intensity = oct_file.get_data_object("data\\Intensity.data")
    intensity_numpy = intensity.to_numpy()

    # load the 0-indexed spectral data as numpy array from OCTFile
    spectral_data = oct_file.get_data_object(oct_file.get_spectral_data_name(0))
    spectral_data_numpy = spectral_data.to_numpy()

    if ENABLE_PLOTS:
        plt.figure()
        plt.subplot(1, 2, 1)
        plt.title('pyDemo read_oct_file: Data Content as Numpy Array')
        plt.imshow(intensity_numpy[:, :, 0], cmap='gray')

        plt.subplot(1, 2, 2)
        plt.title('pyDemo read_oct_file: SpectralData Content as Numpy Array')
        plt.imshow(spectral_data_numpy[:, :, 0], cmap='gray')

        plt.show()

    print('read_oct_file finished. ')
    return True


def read_sdr_file() -> bool:
    """
    This example program shows how to read an oct-file of .sdr format with the SDK which has been acquired and saved
    with ThorImageOCT or using the SDK. To make sure the correct parameters will be used to modify the loaded data,
    e.g. the files for the processing from the dataset and not the current ones for an acquisition, it is necessary
    to use the functions specified for an OCTFile as in this example.

    Returns:
        True
    """
    try:
        # this calls the demo program from above and creates an .oct-file
        if not exists("PyDemoSDKCreatedFile.sdr"):
            write_oct_file(pt.FileFormat.SDR)

        # Please select an .oct-file you want to load
        sdr_file = OCTFile("PyDemoSDKCreatedFile.sdr", pt.FileFormat.SDR)

        index_count = len(sdr_file)
        print('Index count: ', index_count)

        file_data_names = [sdr_file.get_data_name(i) for i in range(index_count)]
        print(file_data_names)

        bscan = RealData()
        raw0 = sdr_file.get_data_object('Spectral0.data')
        chirp = sdr_file.get_data_object(sdr_file.find('Chirp.data'))
        offsets = sdr_file.get_data_object(sdr_file.find('OffsetErrors.data'))
        apo_spectra = sdr_file.get_data_object(sdr_file.find('ApodizationSpectrum.data'))

        proc = ProcessingFactory.create(1024, 2, False, 3.051758, 100, pt.FFTType.STANDARD_FFT, 0)
        proc.calibration.set(pt.CalibrationType.CHIRP, chirp)
        proc.calibration.set(pt.CalibrationType.APO_SPECTRUM, apo_spectra)
        proc.calibration.set(pt.CalibrationType.OFFSET_ERRORS, offsets)

        proc.set_data_output(bscan)
        proc.execute(raw0)

        print(raw0.shape)
        print(bscan.shape)

        bscan_numpy = bscan.to_numpy()

        if ENABLE_PLOTS:
            plt.figure()
            plt.title('pyDemo read_sdr_file: Data Content as Numpy Array')
            plt.imshow(bscan_numpy[:, :, 0], cmap='gray')
            plt.show()

        print('read_sdr_file finished. ')
        return True

    except Exception as e:
        print('read_sdr_file did not finish successful.', e)
        return False


def processing_chain() -> bool:
    """
    The processing chain consists out of several steps. With the SDK it is possible to get the processed data in
    between and not only at the end. This may be useful if you want to write your own processing routine and do not
    want ti reimplement all of it.

    Returns:
        True
    """
    sys = OCTSystem()
    dev = sys.dev
    probe = sys.probe_factory.create_default()
    proc = sys.processing_factory.from_device()

    raw = RawData()
    spectrum_offsets_removed = RealData()
    bscan = RealData()

    # Creating the pattern with no range in the second direction put all B-scans to the same position.
    pattern = probe.scan_pattern.create_bscan_pattern(2.0, 1024)

    dev.acquisition.start(pattern, pt.AcqType.ASYNC_FINITE)
    dev.acquisition.get_raw_data(buffer=raw)

    # The output from the processing routine can be set to different steps from the processing routine. Here the
    # offset corrected spectrum is chosen. Several others are available via
    # :func:`~pyspectralradar.processing.processing.Processing.set_spectrum_output`. Please see the chapter
    # Processing in the documentation for more information.

    # Spectrum after the offsets are removed only
    proc.set_spectrum_output(spectrum_offsets_removed, pt.SpectrumType.OFFSET_CORRECTED)
    # Processed data with the complete processing chain applied.
    proc.set_data_output(bscan)

    proc.execute(raw)

    dev.acquisition.stop()

    del pattern

    del bscan
    del spectrum_offsets_removed
    del raw

    del proc
    del probe
    del dev

    print('processing_chain finished. ')
    return True


def read_and_process_raw_data_from_file() -> bool:
    """
    Example on how to extract raw data from an existing .oct file and use the SDK to process the data.

    Returns:
        True
    """
    # this calls the demo program from above and creates an .oct-file
    if not exists("PyDemoSDKCreatedFile.oct"):
        write_oct_file()

    oct_file = OCTFile("PyDemoSDKCreatedFile.oct")

    proc = ProcessingFactory.from_oct_file(oct_file)

    post_proc_intensity = RealData()

    # load intensity data as numpy array from OCTFile
    intensity = oct_file.get_data_object("data\\Intensity.data")
    intensity_numpy = intensity.to_numpy()

    # load the 0-indexed spectral data as numpy array from OCTFile
    spectral_data = oct_file.get_data_object(oct_file.get_spectral_data_name(0))

    # specifies the output of the processing routine and executes the processing
    proc.set_data_output(post_proc_intensity)
    proc.execute(spectral_data)

    post_proc_intensity_numpy = post_proc_intensity.to_numpy()

    if ENABLE_PLOTS:
        plt.figure()
        plt.subplot(1, 2, 1)
        plt.title('pyDemo Data Content as Numpy Array from File')
        plt.imshow(intensity_numpy[:, :, 0], cmap='gray')

        plt.subplot(1, 2, 2)
        plt.title('pyDemo Post-Processed Data as Numpy Array')
        plt.imshow(post_proc_intensity_numpy[:, :, 0], cmap='gray')

        plt.show()

    del post_proc_intensity
    del intensity
    del spectral_data
    del proc
    del oct_file

    print('read_and_process_raw_data_from_file finished. ')
    return True


def advanced_modification_of_scan_pattern() -> bool:
    """
    With our SDK it is possible to create a scan pattern consisting out of several B-scans acquired after each other
    directly. All B-scans need to have the same number of A-scans. Therefore, it is possible to create a pattern of
    rotating B-scans.
    One way to create such a pattern is to create a volume pattern first and modify it with the functions
    :func:`~pyspectralradar.scanpattern.scanpattern.ScanPattern.shift` and
    :func:`~pyspectralradar.scanpattern.scanpattern.ScanPattern.rotate`.
    This two functions shifts/rotate a single B-scan out of the volume pattern.
    This example shows how to use
    :func:`~pyspectralradar.scanpattern.scanpattern.ScanPattern.rotate`, the use of
    :func:`~pyspectralradar.scanpattern.scanpattern.ScanPattern.shift` is analogous.

    Returns:
        True
    """
    sys = OCTSystem()
    dev = sys.dev
    probe = sys.probe_factory.from_gui_settings()
    proc = sys.processing_factory.from_device()

    raw = RawData()
    bscan = RealData()

    ascans_per_bscan = 1024
    length_of_bscan = 2.0
    number_of_bscans = 16

    # creating the pattern with no range in the second direction put all B-scans to the same position.
    pattern = probe.scan_pattern.create_volume_pattern(length_of_bscan, ascans_per_bscan, 0.0, number_of_bscans, 1,
                                                       1)

    # Rotating the 16 B-scans, the parameter for rotation is in radians and not degree
    step_size = 360 / number_of_bscans * (3.14159265 / 180)
    # the first B-scan will not be rotated
    for current_bscan in range(1, number_of_bscans):
        pattern.rotate(current_bscan * step_size, current_bscan)

    dev.acquisition.start(pattern, pt.AcqType.ASYNC_FINITE)

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

    print('advanced_modification_of_scan_pattern finished. ')
    return True


def freeform_scanpatterns() -> bool:
    """
    With the freeform scan pattern functions it is possible to create 2D and 3D scan patterns of arbitrary form.
    The points used to create the scan pattern can be either only edge points of the pattern and by using
    interpolation methods the real scan points will be created. The other possibility is that the user creates
    all scan positions which will be used "as is".

    Returns:
        True
    """

    sys = OCTSystem()
    dev = sys.dev

    probe = sys.probe_factory.from_gui_settings()
    proc = sys.processing_factory.from_device()

    # First two examples to define only the edge points of the scan pattern and let the real scan positions
    # created inside the SDK will be shown. Create points used for the scan pattern. These coordinates are in mm.
    posx = np.array([0.0, -1.0, 0.0, 1.0], dtype=np.double)
    posy = np.array([1.0, 0.0, -1.0, 0.0], dtype=np.double)
    scan_indices = np.array([0, 0, 0, 0], dtype=np.int32)

    ascans_in_bscan = 512
    pattern_2_d = probe.scan_pattern.create_freeform_pattern_2d(posx,
                                                                posy,
                                                                ascans_in_bscan,
                                                                pt.InterpolationMethod.SPLINE,
                                                                True)

    # save scan points from the scan pattern to a file
    if ENABLE_EXPORTS:
        pattern_2_d.scan_points_factory.save_to_file(scan_indices, "PyDemo_ScanPatternPoints",
                                                     pt.ScanPointsDataFormat.TXT)

    # To create a 3D-freeform scan pattern the "edge" points for both B-scans need to be defined and the
    # corresponding scan indices.
    posx_3_d = np.array([0, -1, 0, 1, 0, -2, 0, 2], dtype=np.double)
    posy_3_d = np.array([1, 0, -1, 0, 2, 0, -2, 0], dtype=np.double)
    scan_indices_3_d = np.array([0, 0, 0, 0, 1, 1, 1, 1], dtype=np.int32)
    pattern_3_d = probe.scan_pattern.create_freeform_pattern_3d(posx_3_d,
                                                                posy_3_d,
                                                                scan_indices_3_d,
                                                                len(scan_indices_3_d),
                                                                ascans_in_bscan,
                                                                pt.InterpolationMethod.SPLINE,
                                                                True,
                                                                pt.ApodizationType.EACH_BSCAN,
                                                                pt.AcquisitionOrder.ACQ_ORDER_ALL)

    # The following two examples create a scan pattern with defined scan points from the user directly.
    posx_2_d_lut = np.array([0, -1, 0, 1], dtype=np.double)
    posy_2_d_lut = np.array([1, 0, -1, 0], dtype=np.double)

    # using an interpolation function to create te scan points
    scan_posx_2_d_lut, scan_posy_2_d_lut = pattern_3_d.scan_points_factory.interpolate_2d(posx_2_d_lut,
                                                                                          posy_2_d_lut,
                                                                                          ascans_in_bscan,
                                                                                          pt.InterpolationMethod.SPLINE,
                                                                                          pt.BoundaryCondition.PERIODIC)

    pattern_2_d_lut = probe.scan_pattern.create_freeform_pattern_2d_from_LUT(scan_posx_2_d_lut,
                                                                             scan_posy_2_d_lut,
                                                                             True)

    number_of_bscans = 2
    range_y = 1.0
    scan_posx_3_d_lut, scan_posy_3_d_lut = pattern_2_d_lut.scan_points_factory.inflate(scan_posx_2_d_lut,
                                                                                       scan_posy_2_d_lut,
                                                                                       number_of_bscans,
                                                                                       range_y,
                                                                                       pt.InflationMethod.NORMAL_DIR)

    pattern_3_d_lut = probe.scan_pattern.create_freeform_pattern_3d_from_LUT(scan_posx_3_d_lut,
                                                                             scan_posy_3_d_lut,
                                                                             ascans_in_bscan,
                                                                             number_of_bscans,
                                                                             True,
                                                                             pt.ApodizationType.EACH_BSCAN,
                                                                             pt.AcquisitionOrder.ACQ_ORDER_ALL)

    # The points from the scan pattern can be read with the function
    # :func:`~pyspectralradar.scanpattern.submodules.lut.LUT.get`.
    # For this first the size of the pattern need to be known which is available with
    # :func:`~pyspectralradar.scanpattern.submodules.lut.LUT.size`
    scan_pattern_size_3_d_lut = pattern_3_d_lut.LUT.size()
    scan_indices_3_d_lut = np.zeros(scan_pattern_size_3_d_lut, dtype=np.int32)
    if ENABLE_EXPORTS:
        pattern_3_d_lut.LUT.save_to_file(scan_indices_3_d_lut,
                                         "PyDemo_ScanPoints3D_LUT",
                                         pt.ScanPointsDataFormat.TXT)  # stores applied voltages to disk

    # The created scan points can be loaded from a file with
    # :func:`~pyspectralradar.scanpattern.submodules.scanpointsfactory.ScanPointsFactory.load_from_file`
    # and saved to using :func:`~pyspectralradar.scanpattern.submodules.lut.LUT.save_to_file` in different formats,
    # see :class:`~pyspectralradar.types.scanpatterntypes.ScanPointsDataFormat`
    # Make sure to pass an arrays of appropriate size to
    # :func:`~pyspectralradar.scanpattern.submodules.scanpointsfactory.ScanPointsFactory.load_from_file` which can be
    # determined with # :func:`~pyspectralradar.scanpattern.ScanPattern.size`
    if ENABLE_EXPORTS:
        pattern_3_d_lut.scan_points_factory.save_to_file(scan_indices_3_d_lut,
                                                         "PyDemo_ScanPoints3D_LUT_mm",
                                                         pt.ScanPointsDataFormat.TXT)  # stores physical positions to
        # disk

    raw = RawData()
    bscan = RealData()

    dev.acquisition.start(pattern_3_d_lut, pt.AcqType.ASYNC_FINITE)

    dev.acquisition.get_raw_data(buffer=raw)

    proc.set_data_output(bscan)
    proc.execute(raw)

    dev.acquisition.stop()

    del raw
    del bscan

    del pattern_3_d_lut
    del pattern_3_d
    del pattern_2_d_lut
    del pattern_2_d

    del probe
    del proc
    del dev

    print('freeform_scanpatterns finished. ')
    return True


def removing_apo_from_scan_pattern():
    """
    Sometimes it can be useful to get rid of the acquisition of additional apodization spectra used in the processing
    routine to speed up the acquisition process. It is possible to perform the acquisition of those apodization
    spectra before the measurement is started and use those spectra in the processing chain.

    This example finishes the while loop acquisition via keyboard interrupt (`Ctrl+C` in terminal; `Ctrl+F2` in
    PyCharm).

    Returns:
        None
    """
    sys = OCTSystem()
    dev = sys.dev

    probe = sys.probe_factory.from_gui_settings()
    proc = sys.processing_factory.from_device()

    raw = RawData()
    bscan = RealData()

    # Sets the number of apodization spectra to zero and therefore no apodization is performed in the scan later.
    # Also, the time for the scanner to get to the starting position of each scan is reduced. Only once the flyback
    # time is needed instead of two.
    probe.properties.set_apodization_cycles(0)

    ascans_per_bscan = 1024
    length_of_bscan = 2.0

    pattern = probe.scan_pattern.create_bscan_pattern(length_of_bscan, ascans_per_bscan)

    # the apodization spectra are acquired now
    dev.acquisition.measure_apo_spectra(probe, proc)

    dev.acquisition.start(pattern, pt.AcqType.ASYNC_CONTINUOUS)

    try:
        while True:
            dev.acquisition.get_raw_data(buffer=raw)
            proc.set_data_output(bscan)
            proc.execute(raw)
    except KeyboardInterrupt:
        pass

    dev.acquisition.stop()

    del pattern
    del bscan
    del raw

    del proc
    del probe
    del dev

    print('removing_apo_from_scan_pattern finished. ')


def doppler_oct() -> bool:
    """
    This demo program shows how to perform the additional processing used for Doppler OCT imaging.

    Returns:
        True
    """

    sys = OCTSystem()
    dev = sys.dev

    probe = sys.probe_factory.from_gui_settings()
    proc = sys.processing_factory.from_device()

    # create additional processing handling for Doppler OCT
    doppler_proc = Doppler()

    raw = RawData()
    complex_bscan = ComplexData()

    amps = RealData()
    phases = RealData()

    ascans_per_bscan = 1024
    length_of_bscan = 2.0

    pattern = probe.scan_pattern.create_bscan_pattern(length_of_bscan, ascans_per_bscan)

    dev.acquisition.start(pattern, pt.AcqType.ASYNC_FINITE)

    dev.acquisition.get_raw_data(buffer=raw)
    # the required processing output for the standard processing routine is complex,
    # :func:`~pyspectralradar.processing.processing.Processing.set_data_output` checks the input object to be a class
    # object of :class:`~pyspectralradar.data.realdata.RealData` or
    # :class:`~pyspectralradar.data.complexdata.ComplexData`
    proc.set_data_output(complex_bscan)
    # the standard processing routines needs to be executed before
    proc.execute(raw)

    # specify the outputs for doppler processing
    doppler_proc.set_output(pt.DopplerOutput.AMPLITUDE, amps)
    doppler_proc.set_output(pt.DopplerOutput.PHASE, phases)
    # doppler_proc.set_phase_output(phases)

    # choose averaging parameter for the doppler processing routine
    doppler_proc.properties.set_averaging_1(3)
    doppler_proc.properties.set_averaging_2(3)

    # executes the doppler processing
    doppler_proc.execute(complex_bscan)

    dev.acquisition.stop()

    if ENABLE_PLOTS:
        plt.figure()
        plt.subplot(1, 2, 1)
        plt.title('Doppler Data \'amps\' as Numpy Array - EnFace')
        plt.imshow(amps.to_numpy()[:, :, 0], cmap='gray')

        plt.subplot(1, 2, 2)
        plt.title('Doppler Data \'phases\' as Numpy Array - EnFace')
        plt.imshow(phases.to_numpy()[:, :, 0], cmap='gray')

        plt.show()

    del pattern

    del amps
    del phases
    del complex_bscan
    del raw

    del proc
    del doppler_proc
    del probe
    del dev

    print('doppler_oct finished. ')
    return True


def speckle_variance_oct() -> bool:
    """
    This demo program shows how to perform the additional processing used for Speckle Variance imaging.

    Returns:
        True
    """
    sys = OCTSystem()
    dev = sys.dev

    probe = sys.probe_factory.from_gui_settings()
    proc = sys.processing_factory.from_device()

    # choose parameter for oversampling
    oversampling_slow_axis = 3
    probe.properties.set_oversampling(3)
    proc.properties.set_spectrum_avg(1)
    probe.properties.set_oversampling_slow_axis(oversampling_slow_axis)

    ascans_per_bscan = 512
    length_of_bscan = 10.0
    bscans_per_volume = 128
    width_of_volume = 10.0
    pattern = probe.scan_pattern.create_volume_pattern(length_of_bscan,
                                                       ascans_per_bscan,
                                                       width_of_volume,
                                                       bscans_per_volume,
                                                       pt.ApodizationType.EACH_BSCAN,
                                                       pt.AcquisitionOrder.ACQ_ORDER_ALL)

    raw = RawData()
    volume = ComplexData()
    volume.reserve(int(dev.properties.get_spectrum_elements() / 2), ascans_per_bscan, bscans_per_volume)

    dev.acquisition.start(pattern, pt.AcqType.ASYNC_FINITE)
    dev.acquisition.get_raw_data(buffer=raw)

    # the required processing output for the standard processing routine is complex
    proc.set_data_output(volume)

    # the standard processing routines needs to be executed before
    proc.execute(raw)
    dev.acquisition.stop()

    var = SpeckleVariance()
    # choose averaging parameter for speckle variance processing
    var.properties.set_averaging1(3)
    var.properties.set_averaging2(3)

    mean, variance = var.compute(volume)
    print('volume.shape: ', volume.shape)
    print('mean.shape: ', mean.shape)
    print('variance.shape: ', variance.shape)

    # export data
    if ENABLE_EXPORTS:
        variance.export(pt.DataExportFormat.CSV, "PyDemo_Variance_Export")

    if ENABLE_PLOTS:
        plt.figure()
        plt.subplot(4, 2, 1)
        plt.title('mean Data Content as Numpy Array - EnFace')
        plt.imshow(mean.to_numpy()[100, :, :], cmap='gray')

        plt.subplot(1, 2, 2)
        plt.title('variance Data Content as Numpy Array - EnFace')
        plt.imshow(variance.to_numpy()[100, :, :], cmap='gray')

        plt.show()

    del var

    del pattern

    del mean
    del variance
    del volume
    del raw

    del proc
    del probe
    del dev

    print('speckle_variance_oct finished. ')
    return True


# TODO: ToBeChecked with hardware
def external_trigger_modus():
    """
    Please read the software and hardware manual carefully before using the external trigger mode in software.
    This demo program makes clear when the external trigger needs to be applied and when it needs to be turned off.
    It is necessary to follow these instructions since additional measurements before the data acquisition itself need
    to be done without an underlying trigger signal and the synchronization between the mirror(s) and the camera
    cannot be initiated correctly with external trigger signal applied.

    This example finishes the while loop acquisition via keyboard interrupt (`Ctrl+C` in terminal; `Ctrl+F2` in
    PyCharm).

    Returns:
        None
    """
    print("Do not trigger externally until the measurement is started correctly")

    sys = OCTSystem()
    dev = sys.dev

    probe = sys.probe_factory.create_default()
    proc = sys.processing_factory.from_device()

    raw = RawData()
    bscan = RealData()

    ascans_per_bscan = 1024
    length_of_bscan = 2.0
    pattern = probe.scan_pattern.create_bscan_pattern(length_of_bscan, ascans_per_bscan)

    colored_bscan = ColoredData()
    coloring = Coloring(pt.ColorScheme.BLACK_AND_WHITE, pt.ByteOrder.RGBA)
    coloring.set_boundaries(0.0, 70.0)

    # setting the trigger mode to external and specify the timeout
    dev.trigger_mode.set(pt.TriggerMode.EXTERNAL_ASCAN)
    dev.trigger_mode.set_timeout(5)

    dev.acquisition.start(pattern, pt.AcqType.ASYNC_CONTINUOUS)
    print('External triggering possible as of now. \n')
    try:
        while True:
            dev.acquisition.get_raw_data(buffer=raw)
            proc.set_data_output(bscan)
            proc.execute(raw)
    except KeyboardInterrupt:
        pass

    coloring.colorize(bscan, False, colored_bscan)
    if ENABLE_EXPORTS:
        colored_bscan.export(pt.ColoredDataExportFormat.PNG, pt.DataDirection.DIR3, 'pyExtTriggerTestImg',
                             pt.ExportOptionMasks.NONE)
    dev.acquisition.stop()

    print(
        'Please stop the external trigger signal here to make sure that the next measurement can be started '
        'correctly.\n')

    del raw
    del bscan

    del pattern
    del probe
    del proc
    del dev

    print('external_trigger_modus finished. ')


# TODO: ToBeChecked with hardware
def batch_measurement_with_polarization_adjustment():
    """
    Some polarisation-sensitive OCT devices (at the time of writing only the VEGA 200 series) possess a motorized
    control stage which allows the modification of the sampled polarisation.
    This demo will capture a batch of B-Scans, each with a different setting of the polarisation control and export
    the resulting images to "C:/OCTExport/demo_batch_*.png".

    Returns:
        None
    """

    # Each polarization retarder will go through n polarization_steps, so overall n*n images will be captured
    polarization_steps = 4

    # initialization of device
    sys = OCTSystem()
    dev = sys.dev

    # Check if device actually supports polarization adjustment
    if not dev.polarization_adjustment.is_available():
        del dev
        del sys
        print("ERROR: Device does not support polarization adjustment")
        return

    # Ensure export directory exists
    export_folder = 'C:\\OCTExport'
    if not os.path.exists(export_folder):
        os.mkdir(export_folder)

    # initialization of probe and processing handles
    probe = sys.probe_factory.create_default()
    proc = sys.processing_factory.from_device()

    raw = RawData()
    bscan = RealData()

    coloring = Coloring(pt.ColorScheme.BLACK_AND_WHITE, pt.ByteOrder.RGBA)
    coloring.set_boundaries(0.0, 70.0)

    pattern = probe.scan_pattern.create_bscan_pattern(2.0, 1024)

    dev.acquisition.start(pattern, pt.AcqType.SYNC)
    for pol_half_wave in range(0, polarization_steps):
        try:
            dev.polarization_adjustment.set_retardation(pt.PolarizationRetarder.HALF_WAVE,
                                                        pol_half_wave / (polarization_steps - 1),
                                                        pt.WaitForCompletion.WAIT)
        except Exception as e:
            print(e)
            return
        for pol_quarter_wave in range(0, polarization_steps):
            print('Capturing image ', pol_half_wave, '_', pol_quarter_wave)
            # octdevice.pol_adjustment_retardation(OCTDevice.PolarizationRetarder.QUARTER_WAVE,
            #                                pol_quarter_wave / (polarization_steps - 1),
            #                                OCTDevice.WaitForCompletion.WAIT)

            # Workaround for ill-programmed servo in octdevice vega
            dev.polarization_adjustment.set_retardation(pt.PolarizationRetarder.QUARTER_WAVE,
                                                        pol_quarter_wave / (polarization_steps - 1),
                                                        pt.WaitForCompletion.WAIT)
            dev.acquisition.get_raw_data(buffer=raw)
            proc.set_data_output(bscan)
            proc.execute(raw)
            filename = os.path.join(export_folder, 'pyDemo_batch', str(pol_half_wave), '_', str(pol_quarter_wave),
                                    '.png')
            bscan.export_data_as_image(coloring, pt.ColoredDataExportFormat.PNG, pt.DataDirection.DIR3, filename)

    dev.acquisition.stop()

    del pattern

    del bscan
    del raw

    del proc
    del probe
    del dev

    print('batch_measurement_with_polarization_adjustment finished. ')


# TODO: ToBeChecked with hardware
def automatic_reference_and_amplification_adjustment():
    """
    Some OCT devices (at the time of writing only the VEGA 200 and ATR series) possess a motorized reference intensity
    control stage which allows the modification of the amount of reference light returned to the sensor. Additionally,
    the device may contain an amplification control stage, which determines by how much the analog output of the
    sensor is amplified before being sampled and digitized. Both amplification and reference light need to be adjusted
    together to ensure an optimal image.
    The goal is to have both the reference light and the amplification as high as possible without over-saturating the
    digitization stage. The following code attempts an automated adjustment of these two values. This highly depends
    on the concrete sample being imaged and may fail or yield suboptimal results. During the calibration process,
    a series of images will be written to "C:/OCTExport", allowing a visual understanding of the process.

    Returns:
        None
    """

    sys = OCTSystem()
    dev = sys.dev

    proc = sys.processing_factory.from_device()

    amplification = 0
    saturation = 0
    ref = 0

    # Check if device has required hardware
    if (not dev.amplification.is_available() or
            not dev.ref_intensity.is_available() or
            not proc.properties.get_saturation()):
        del proc
        del dev
        del sys
        print('"ERROR: Device does not have required controls."')
        return

    export_folder = 'C:\\OCTExport'
    # Ensure export directory exists
    if not os.path.exists(export_folder):
        os.mkdir(export_folder)

    # initialization of probe and processing handles
    probe = sys.probe_factory.from_gui_settings()

    raw = RawData()
    bscan = RealData()

    coloring = Coloring(pt.ColorScheme.BLACK_AND_WHITE, pt.ByteOrder.RGBA)
    coloring.set_boundaries(0.0, 70.0)

    pattern = probe.scan_pattern.create_bscan_pattern(2.0, 1024)

    dev.acquisition.start(pattern, pt.AcqType.SYNC)

    max_amp = dev.amplification.get_max() - 1
    # The processing step will calculate a saturation metric, which corresponds to the saturation of the sensor.
    # Ideally, this value should be around 80%
    # Amplification and Reference light intensity are the two parameters that this algorithm tries to optimize
    success = False

    # This is not actually used as a loop. The construct just allows us to use break to abort the execution and
    # jump to the cleanup stage.
    while not success:
        # Step 1: Set amplification and reference light to maximum (should over saturate)
        dev.amplification.set(max_amp)
        dev.ref_intensity.set_ctrl_value(1, pt.WaitForCompletion.WAIT)

        dev.acquisition.get_raw_data(buffer=raw)
        proc.set_data_output(bscan)
        proc.execute(raw)
        saturation = proc.get_relative_saturation()

        filename = os.path.join(export_folder, '\\pyDemo_auto_adjust_01_full_', str(saturation), '.png')
        bscan.export_data_as_image(coloring, pt.ColoredDataExportFormat.PNG, pt.DataDirection.DIR3, filename,
                                   pt.ExportOptionMasks.DRAW_SCALEBAR or
                                   pt.ExportOptionMasks.DRAW_MARKERS or
                                   pt.ExportOptionMasks.USE_PHYSICAL_ASPECT_RATIO)

        if saturation < 0.2:
            print('ERROR: Sensor did not reach saturation, even with full reference light and amplification. '
                  'Please choose a different sample. Saturation was ', saturation)
            break

        # Step 2: Reduce amplification until under-saturation is reached. Then increase amplification by one step
        amplification = max_amp

        while amplification > 0:
            amplification -= 1
            dev.amplification.set(amplification)

            dev.acquisition.get_raw_data(buffer=raw)
            proc.set_data_output(bscan)
            proc.execute(raw)
            saturation = proc.get_relative_saturation()

            filename = os.path.join(export_folder, '\\pyDemo_auto_adjust_02_reduced_', str(amplification + 1), '_',
                                    str(saturation), '.png')

            bscan.export_data_as_image(coloring, pt.ColoredDataExportFormat.PNG, pt.DataDirection.DIR3, filename,
                                       pt.ExportOptionMasks.DRAW_SCALEBAR or
                                       pt.ExportOptionMasks.DRAW_MARKERS or
                                       pt.ExportOptionMasks.USE_PHYSICAL_ASPECT_RATIO)
            if saturation < 0.9:
                amplification += 1
                break

        dev.amplification.set(amplification)

        # Step 3: Reduce reference light until proper saturation is reached. This algorithm uses a binary search
        # algorithm to find the optimum.
        ref_low = 0
        ref_high = 1

        while (ref_high - ref_low) > 0.01:
            ref = (ref_low + ref_high) / 2
            dev.ref_intensity.set_ctrl_value(ref, pt.WaitForCompletion.WAIT)

            dev.acquisition.get_raw_data(buffer=raw)
            proc.set_data_output(bscan)
            proc.execute(raw)
            saturation = proc.get_relative_saturation()

            filename = os.path.join(export_folder, '\\pyDemo_auto_adjust_03_set_int_ref_', str(ref), '_',
                                    str(saturation), '.png')

            bscan.export_data_as_image(coloring, pt.ColoredDataExportFormat.PNG, pt.DataDirection.DIR3, filename,
                                       pt.ExportOptionMasks.DRAW_SCALEBAR or
                                       pt.ExportOptionMasks.DRAW_MARKERS or
                                       pt.ExportOptionMasks.USE_PHYSICAL_ASPECT_RATIO)

            if saturation < 0.75:
                ref_low = ref
            elif saturation >= 0.8:
                ref_high = ref
            else:
                break

        success = True

    dev.acquisition.stop()

    del pattern

    del bscan
    del raw

    del proc
    del probe
    del dev

    if success:
        print('Algorithm complete. Final saturation: ', saturation, '. Parameters: Amplification: ',
              (amplification + 1), '/', (max_amp + 1), ' Reference Light Intensity: ', ref)

    print('automatic_reference_and_amplification_adjustment finished. ')


def image_field_calibration() -> bool:
    """
    Example on how to determine the image field correction for the given surface data, previously measured with the
    given scan pattern and how to set the specified image field to the specified Probe handle.

    Notice that no probe file will be automatically saved.

    Returns:
        True

    """
    sys = OCTSystem()
    dev = sys.dev

    probe = sys.probe_factory.from_gui_settings()
    proc = sys.processing_factory.from_device()

    raw = RawData()
    volume = RealData()
    image_field = ImageField()

    ascans_per_bscan = 256
    bscans_per_volume = 256
    ascan_averaging = 10

    max_range_x = probe.properties.get_range_max_x()
    max_range_y = probe.properties.get_range_max_y()
    probe.properties.set_oversampling(ascan_averaging)
    proc.properties.set_ascan_avg(ascan_averaging)

    pattern = probe.scan_pattern.create_volume_pattern(max_range_x,
                                                       ascans_per_bscan,
                                                       max_range_y,
                                                       bscans_per_volume,
                                                       pt.ApodizationType.EACH_BSCAN,
                                                       pt.AcquisitionOrder.ACQ_ORDER_ALL)

    dev.acquisition.start(pattern, pt.AcqType.ASYNC_FINITE)
    dev.acquisition.get_raw_data(buffer=raw)
    proc.set_data_output(volume)
    proc.execute(raw)
    dev.acquisition.stop()

    # image field correction
    surface = volume.analysis.determine_surface()
    image_field.determine(pattern, surface)
    image_field.set_in_probe(probe)
    if ENABLE_EXPORTS:
        probe.save('PyDemoProbe')

    del pattern

    del volume
    del surface
    del raw

    del image_field

    del proc
    del probe
    del dev

    print('image_field_calibration finished. ')
    return True


def write_oct_file_with_freeform_scan_pattern() -> bool:
    """
    This example program shows how to write data acquired with the SDK to an oct-file together with the used freeform
    scan pattern, which can be viewed with ThorImageOCT.

    Returns:
        True
    """

    sys = OCTSystem()
    dev = sys.dev

    probe = sys.probe_factory.create_default()
    proc = sys.processing_factory.from_device()

    raw = RawData()
    bscan = RealData()
    video_image = ColoredData()

    # Creating a circle freeform scan pattern with predefined points
    number_of_ascans = 1024
    scan_pattern_file = 'C:\\OCTScanPattern\\ScanPoints_Circle.txt'
    pattern = probe.scan_pattern.create_freeform_pattern_2d_from_file(scan_pattern_file,
                                                                      number_of_ascans,
                                                                      pt.ScanPointsDataFormat.TXT,
                                                                      pt.InterpolationMethod.SPLINE,
                                                                      True)

    dev.acquisition.start(pattern, pt.AcqType.ASYNC_FINITE)

    dev.camera.get_image(video_image)
    dev.acquisition.get_raw_data(buffer=raw)
    proc.set_data_output(bscan)
    proc.execute(raw)

    dev.acquisition.stop()

    # Creating the file in the correct data format for ThorImageOCT
    oct_file = OCTFile()

    # Adding the processed data to the file
    # To see what data types are used in standard .oct-files please see class "OCTFile.Names"
    oct_file.add_data(bscan, pt.FileNames.OCT_DATA)  # "data\\Intensity.data"
    oct_file.add_data(video_image, pt.FileNames.VIDEO_IMAGE)  # "data\\VideoImage.data"

    # A suitable mode need to be selected to view the data in ThorImageOCT.
    # All acquisition modes from ThorImageOCT are listed in "OCTFile.Modes".
    # Please note that the available acquisitions modes may depend on your hardware.
    oct_file.properties.set_acquisition_mode(pt.Modes.m2d)
    oct_file.properties.set_process_state(pt.ProcessingStates.PROCESSED_INTENSITY)

    # The data from the device, probe, processing and scan pattern will be saved as well
    oct_file.set_metadata(dev, proc, probe, pattern)

    # save freeform points
    scan_posx, scan_posy, scan_indices = ScanPointsFactory.load_from_file(scan_pattern_file,
                                                                          pt.ScanPointsDataFormat.TXT)
    scan_points = RealData.from_scan_points(scan_posx, scan_posy, scan_indices)
    oct_file.add_data(scan_points, pt.FileNames.FREEFORM_SCAN_POINTS)

    scan_posx_interp, scan_posy_interp = pattern.scan_points()
    scan_points_size_interp = pattern.size()
    scan_points_indices_interp = np.empty(scan_points_size_interp, dtype=np.int32)
    scan_points_interp = RealData.from_scan_points(scan_posx_interp,
                                                   scan_posy_interp,
                                                   scan_points_indices_interp)
    oct_file.add_data(scan_points_interp, pt.FileNames.FREEFORM_SCAN_POINTS_INTERP)
    if ENABLE_EXPORTS:
        oct_file.save('PyDemoCreatedFile.oct')

    del oct_file
    del pattern

    del video_image
    del bscan
    del raw

    del proc
    del probe
    del dev

    print('write_oct_with_freeform_scan_pattern finished. ')
    return True


def ring_light_adjustment():
    """
    Example on how to control the scan heads illumination ring.

    Returns:
        None

    """
    sys = OCTSystem()
    dev = sys.dev

    print('(output value, unit): ', dev.output_device.get_names_and_units)

    # define device output, in this case the ring light was chosen
    output_name = 'Ring Light'
    lower_ring_light_limit, upper_ring_light_limit = dev.output_device.get_value_range_by_name(output_name)

    print("The lower ring light intensity value is : ", lower_ring_light_limit)
    print("The upper ring light intensity value is : ", upper_ring_light_limit)
    input_txt = "Set the desired ring light intensity. The value [type: double] must be between " + str(
        lower_ring_light_limit) + " and " + str(upper_ring_light_limit) + ". "
    ring_light_intensity = input(input_txt)

    # set ring light intensity
    dev.output_device.set_value_by_name(output_name, float(ring_light_intensity))
    print("The ring light intensity was set to ", ring_light_intensity, ". ")

    del dev

    print('\nring_light_adjustment finished.\n')


def write_ps_oct_file():
    """
    This example program shows how to write PS data acquired with the SDK to an oct-file which can be viewed with
    ThorImageOCT.

    Notice: This example requires a PS-OCT system (e.g. TEL221PS) to work.

    Returns:
        None
    """

    sys = OCTSystem()
    dev = sys.dev

    probe = sys.probe_factory.from_gui_settings()

    # In systems containing several cameras, there should be one set of processing routines for each camera. The
    # reason is that each camera has its own calibration, and the calibration is an integral part of the
    # computations. The function below creates and returns a handle only for the first camera. Thus,
    # the next function is needed to handle signals from the second camera.
    proc_0 = sys.processing_factory.from_device()
    proc_1 = sys.processing_factory.from_device(1)
    pol_proc = Polarization()

    # the #RawData() object) will be used to get the raw data handle and will contain the data from the detector
    # (e.g. line scan camera is SD-OCT systems) without any modification
    raw_0 = RawData()
    raw_1 = RawData()

    # The #ComplexData() object will be used for the processed data and will contain the reflexion coefficients.
    # They are not just real numbers because each reflexion partially changes the phase.
    complex_0 = ComplexData()
    complex_1 = ComplexData()

    # initialize preview and video image, to be visualized in GUI
    preview_image = ColoredData()
    video_image = ColoredData()
    color = Coloring(pt.ColorScheme.BLACK_AND_WHITE, pt.ByteOrder.RGBA)
    color.set_boundaries(0.0, 70.0)

    # The byproducts of the polarization processing.
    stokes_param_i = RealData()  # Total intensity.
    # stokes_param_q = RealData()
    # stokes_param_u = RealData()
    # stokes_param_v = RealData()
    # retardation = RealData()
    # optical_axis = RealData()
    # dopu = RealData()           # Degree of polarization uniformity.

    # Values that determine the behaviour of the Polarization processing routines.
    pol_proc.properties.set_bscan_averaging(1)  # Number of frames for averaging.
    pol_proc.properties.set_averaging_z(1)  # Number of pixels for averaging along the z-axis.
    pol_proc.properties.set_averaging_x(1)  # Number of pixels for averaging along the x-axis.
    pol_proc.properties.set_averaging_y(1)  # Number of pixels for averaging along the y-axis.
    pol_proc.properties.set_ascan_averaging(1)  # A-Scan averaging. This parameter influences the
    # way data get acquired, it cannot be changed for offline processing.

    # define simple B-scan pattern with 2mm range and 1024 A-scans
    pattern = probe.scan_pattern.create_bscan_pattern(2.0, 1024)

    dev.camera.get_image(video_image)

    dev.acquisition.start(pattern, pt.AcqType.ASYNC_FINITE)

    # grabs the spectral data from the frame grabber and copies it to the #RawData objects handle
    dev.acquisition.get_raw_data(buffer=raw_0)
    dev.acquisition.get_raw_data(1, raw_1)

    # Specifies the output of the processing routine and executes the processing
    proc_0.set_data_output(complex_0)
    proc_1.set_data_output(complex_1)

    # Now executing to get the complex data: these are the reflections coefficients at each depth.
    proc_0.execute(raw_0)
    proc_1.execute(raw_1)

    # Beware that each of the following means extra load for the CPU. Those parameters not needed should be left
    # out. Those left in will be computed right below.
    pol_proc.set_data_output(stokes_param_i,
                             pt.PolarizationOutput.INTENSITY)  # Total intensity.
    # pol_proc.set_data_output(stokes_param_q, Polarization.PolarizationOutput.STOKES_Q)
    # pol_proc.set_data_output(stokes_param_u, Polarization.PolarizationOutput.STOKES_U)
    # pol_proc.set_data_output(stokes_param_v, Polarization.PolarizationOutput.STOKES_V)
    # pol_proc.set_data_output(dopu, Polarization.PolarizationOutput.DOPU)   # Degree of polarization uniformity.
    # pol_proc.set_data_output(retardation, Polarization.PolarizationOutput.RETARDATION)
    # pol_proc.set_data_output(optical_axis, Polarization.PolarizationOutput.OPTIC_AXIS)

    # The analysis of the polarization will be done here. Only those parameters set above will be computed.
    pol_proc.execute(complex_1, complex_0)

    dev.acquisition.stop()
    print('Data is now available for use. Display, store, whatever.')

    # Creating the file in the correct data format for ThorImageOCT
    oct_file = OCTFile()

    # Optional: adding the raw (unprocessed) data to the file.
    oct_file.add_data(raw_0, 'data\\Spectral0.data')
    oct_file.add_data(raw_1, 'data\\Spectral0_Cam1.data')

    # Optional: adding processed data to the file
    oct_file.add_data(complex_0, 'data\\Complex.data')
    oct_file.add_data(complex_1, 'data\\Complex_Cam1.data')

    # save used Probe.ini: please adjust if necessary
    probe_path = 'C:\\Program Files\\Thorlabs\\SpectralRadar\\config\\' + probe.properties.get_name()
    oct_file.add_text(probe_path, 'data\\Probe.ini')

    # add preview image
    color.colorize(stokes_param_i, True, preview_image)
    oct_file.add_data(preview_image, pt.FileNames.PREVIEW_IMAGE)

    # If nothing else is specified about the data saved with the function
    # :func:`~pyspectralradar.octfile.octfile.OCTFile.add_data`, the function
    # :func:`~pyspectralradar.octfile.octfile.OCTFile.set_metadata` below will assume that the number of pixels along
    # the Z-direction and the z-range are those that characterize the device. If the data had been cropped along the
    # z-axis, or any other modification has been made that deviates from the standard properties of the device,
    # it should be explicit. Whether :func:`~pyspectralradar.octfile.octfile.OCTFile.set_metadata` is invoked before
    # or after, is irrelevant.

    # Adding the processed data to the file To see what data types are used in standard .oct-files please see
    # variables "DataObjectName_" in "SpectralRadar.h"
    oct_file.add_data(stokes_param_i, pt.FileNames.OCT_DATA)
    # oct_file.add_data(stokes_param_q, "data\\PolQ.data")
    # oct_file.add_data(stokes_param_u, "data\\PolU.data")
    # oct_file.add_data(stokes_param_v, "data\\PolV.data")
    # oct_file.add_data(retardation, "data\\Retardation.data")
    # oct_file.add_data(optical_axis, "data\\OpticalAxis.data")
    # oct_file.add_data(dopu, "data\\DOPU.data")

    oct_file.save_calibration(proc_1, 1)
    oct_file.save_calibration(proc_0, 0)

    # A suitable mode need to be selected to view the data in ThorImageOCT. All acquisition modes from
    # ThorImageOCT are listed in :class:`~pyspectralradar.types.octfiletypes.Modes`. Please note that the
    # available acquisitions modes may depend on your hardware.
    oct_file.properties.set_acquisition_mode(pt.Modes.POLARIZATION_SENSITIVE)

    # Specify that the file is read as raw and/or processed data in the GUI.
    oct_file.properties.set_process_state(pt.ProcessingStates.RAW_AND_PROCESSED_AND_PHASE)
    # oct_file.properties.int.set_process_state(pt.ProcessingStates.RAW_SPECTRA)
    # oct_file.properties.int.set_process_state(pt.ProcessingStates.PROCESSED_INTENSITY)

    oct_file.study = 'pyDemo PS_OCT'
    oct_file.scan_line_shown = True
    oct_file.add_data(video_image, pt.FileNames.VIDEO_IMAGE)

    # The data from the device, probe, processing and scan pattern will be saved as well
    oct_file.set_polarization_metadata(pol_proc)
    oct_file.set_metadata(dev, proc_1, probe, pattern)
    oct_file.set_metadata(dev, proc_0, probe, pattern)

    # save file
    if ENABLE_EXPORTS:
        oct_file.save('pyDemo_PS_OCT.oct')

    del oct_file

    del pattern
    del preview_image

    del stokes_param_i
    # del stokes_param_q
    # del stokes_param_u
    # del stokes_param_v
    # del retardation
    # del optical_axis
    # del dopu

    del complex_0
    del complex_1
    del raw_0
    del raw_1

    del pol_proc
    del proc_0
    del proc_1

    del probe
    del dev

    print('write_ps_oct_file finished. ')


if __name__ == '__main__':
    print("PyAdvancedSpectralRadarDemos started. \n")

    set_log_level(pt.LogLevel.OFF)
    keep_going = True

    while keep_going:
        print("The following simple demonstration programs are available: \n")
        print("a: How to write an .oct-file")
        print("b: How to read an .oct-file")
        print("c: How to read an .sdr-file")
        print("d: Single steps of the processing chain")
        print("e: Read and process data from_file")
        print("f: Creating one scan pattern out of several B-scans, e.g. rotating B-scans around the center")
        print("g: Handling of freeform scan patterns")
        print("h: Speed up the acquisition by modifying the scan pattern")
        print("i: Doppler OCT with the SDK")
        print("j: Speckle variance OCT with the SDK")
        print("k: External A-scan trigger (requires additional hardware)")
        print("l: Capture batch of images and adjust polarization retardation (requires supported device)")
        print("m: Auto-set amplification and reference light intensity (requires supported device)")
        print("n: Performs image field calibration")
        print("o: How to write an .oct-file containing a freeform scan pattern")
        print("p: How to adjust the ring light intensity")
        print("q: Polarization sensitive OCT with the SDK")
        print("x: Terminate")

        x = input('Select the program that shall be executed\n')
        print('Your selection: ', x, '\n')
        if x == 'a':
            write_oct_file()
        elif x == 'b':
            read_oct_file()
        elif x == 'c':
            read_sdr_file()
        elif x == 'd':
            processing_chain()
        elif x == 'e':
            read_and_process_raw_data_from_file()
        elif x == 'f':
            advanced_modification_of_scan_pattern()
        elif x == 'g':
            freeform_scanpatterns()
        elif x == 'h':
            removing_apo_from_scan_pattern()
        elif x == 'i':
            doppler_oct()
        elif x == 'j':
            speckle_variance_oct()
        elif x == 'k':
            external_trigger_modus()
        elif x == 'l':
            batch_measurement_with_polarization_adjustment()
        elif x == 'm':
            automatic_reference_and_amplification_adjustment()
        elif x == 'n':
            image_field_calibration()
        elif x == 'o':
            write_oct_file_with_freeform_scan_pattern()
        elif x == 'p':
            ring_light_adjustment()
        elif x == 'q':
            write_ps_oct_file()
        elif x == 'x':
            keep_going = False
        else:
            print('Invalid selection, try again.\n')
