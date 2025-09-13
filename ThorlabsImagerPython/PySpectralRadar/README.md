Welcome to Thorlabs pySpectralRadar SDK! This SDK provides you with a robust set of tools to seamlessly integrate with
our
OCT systems. Whether you're a seasoned developer or just starting, our SDK is designed to help you get up and running
quickly.

# License

By using the Thorlabs pySpectralRadar SDK you agree to the terms and conditions detailed in the SDK license agreement
contained in the ThorImage OCT software manual. You can find this manual in Start Menu -> All Programs ->
Thorlabs -> ThorImage OCT -> ThorImage OCT Manual.

# Introduction

The pySpectralRadar SDK enables you to interact with our OCT systems using Python, providing a simplified interface to
leverage the full capabilities of our services. It supports a wide range of features, including data acquisition,
processing, and advanced analytics.

# Getting Started

## Prerequisites

Before you begin, ensure you have the following prerequisites:

* Installed ThorImage OCT v5.8 or later
* Installed python v3.11 or later

## Installation

Install the SDK using pip. After installation of ThorImageOCT, the wheel file is located
at ``C:\Program Files\Thorlabs\SpectralRadar\Python\PySpectralRadar\lib`` per default. Run the following command in your
terminal:

    pip install pyspectralradar-{VERSION}-py3-none-any.whl

# Basic Overview

The most important modules are given in the following sections.

## Data

Data acquired and used by the SDK is provided via data objects. A data object can contain

* floating point data (via :class:`~pyspectralradar.data.realdata.RealData`)
* complex floating point data (via :class:`~pyspectralradar.data.complexdata.ComplexData`)
* ARGB32 colored data (via :class:`~pyspectralradar.data.coloreddata.ColoredData`)
* unprocessed RAW data (via :class:`~pyspectralradar.data.rawdata.RawData`)

The data objects store all information belonging to them, such
as pixel data, spacing between pixels, comments attached to their data, etc. Data objects are automatically
resized if necessary and can contain 1-, 2- or 3-dimensional data. The dimensionality can be read by
:py:attr:`~pyspectralradar.data.utility.ishapeproperties.IShapeProperties.shape`, etc. Direct access to their memory is
possible via their method :func:`~.pointer`, etc. Data content can also be
converted into numpy arrays using th data classes method :func:`~.to_numpy`, etc. The Data attributes include sizes
along their first, second
and third axis, physical spacing between pixels, their total range, etc.

## OCTSystem

:class:`~pyspectralradar.octsystem.OCTSystem` class represents an optical coherence tomography (OCT) system.

This class initializes and manages the core components required for operating an OCT device, including the OCT
device itself (:class:`~pyspectralradar.octdevice.octdevice.OCTDevice`), a probe factory for creating probes
(:class:`~pyspectralradar.probe.probefactory.ProbeFactory`), and a processing factory for handling device-bound
processing tasks (:class:`~pyspectralradar.processing.processingfactory.DeviceBoundProcessingFactory`).

## OCTDevice

:class:`~pyspectralradar.octdevice.octdevice.OCTDevice` class specifies the OCT device (base unit) that is used. The
complete device will be initialized, the SLD will be switched on and all start-up dependent calibration will be
performed on construction.

## Processing

The numerics and processing routines required in order to create A-scans, B-scans and volumes out of directly
measured spectra can be accessed via the :class:`~pyspectralradar.processing.Processing`. When the
:class:`~pyspectralradar.processing.Processing` is created, all required temporary memory and routines are initialized
and prepared and several threads are started. In most cases the ideal way to create a processing object is to use the :
attr:`~processing_factory` of :class:`~pyspectralradar.octsystem.OCTSystem`, which creates optimized processing
algorithms for the :class:`~pyspectralradar.octdevice.OCTDevice` specified. If no device is available or the processing
routines are to be tweaked a :obj:`~pyspectralradar.processing.processing.Processing` must be instantiated.

## Probe

The probe is the hardware used for scanning the sample, usually with help of galvanometric scanners. The object
referenced by :class:`~pyspectralradar.probe.probe.Probe` is responsible for creating scan patterns and holds all
information and settings of the probe attached to the device. It needs to be calibrated to map suitable output voltage (
for analog galvo drivers) or digital values (for digital galvo drivers) to scanning angles, inches or millimeters. In
most cases this calibration data is provided by ``∗.ini`` files and the probe is, ideally, initialized by using
:class:`~pyspectralradar.octsystem.OCTSystem`'s :attr:`~probe_factory`. Probes calibrated at Thorlabs will usually come
with a factory-made probe configuration file which follows the nomenclature Probe + Objective Name.ini,
e.g. ``ProbeLSM03.ini``. If the probe is to be hardcoded into the software one can also provide an empty string as
parameter and provide the configuration manually using the Probes :attr:`~Probe.properties` functions. All actions that
depend on the probe configuration are nested as submodules of a :class:`~pyspectralradar.probe.probe.Probe` object to be
specified, such as:

* move galvo scanner to a specific position (:func:`~pyspectralradar.probe.submodules.scanner.Scanner.move`).
* create a scan pattern (
  :func:`~pyspectralradar.scanpattern.scanpatternfactory.ScanPatternFactory.create_bscan_pattern`), see also
  :class:`~pyspectralradar.scanpattern.scanpatternfactory.ScanPatternFactory` and
  :class:`~pyspectralradar.scanpattern.scanpattern.ScanPattern`.
* set calibration parameters for a specific probe

## ScanPattern

A scan pattern is used to specify the points on the probe to scan during data acquisition, and its information is
accessible via the :class:`~pyspectralradar.scanpattern.scanpattern.ScanPattern`. PySpectralRadar provides a
:class:`~pyspectralradar.scanpattern.scanpatternfactory.ScanPatternFactory` class that contains dedicated function can
be used to create a specific scan pattern, such
as :func:`~pyspectralradar.scanpattern.scanpatternfactory.ScanPatternFactory.create_bscan_pattern` for a simple B-scan
or :func:`~pyspectralradar.scanpattern.scanpatternfactory.ScanPatternFactory.create_volume_pattern` for a simple volume
scan.

## Logging
By default, pySpectralRadar will output diagnostic messages to `stdout`. The level of detail of these messages can be
adjusted by calling :func:`~pyspectralradar.base.logging.set_log_level`. This function also allows disabling the output
entirely.

To redirect the output into files (or to change the target back to `stdout`) use
:func:`~pyspectralradar.base.logging.set_log_output_file`, :func:`~pyspectralradar.base.logging.set_log_output_rotating_file` and
:func:`~pyspectralradar.base.logging.set_log_output_console`.
## Others

Other modules that are used in the pySpectralRadar SDK are

* :class:`~pyspectralradar.coloring.coloring.Coloring`: Handle to processing routines that can map floating point data
  to color data. In general this will 32-bit color data, such as RGBA or BGRA.
* :class:`~pyspectralradar.doppler.doppler.Doppler`: Class to Doppler processing routines that can be used to transform
  complex data to Doppler phase and amplitude signals.
* :class:`~pyspectralradar.polarization.polarization.Polarization`: A class for processing of polarization sensitive
  data.
* :class:`~pyspectralradar.settings.settings.SettingsFile`: Handle to an ``.ini`` file that can be read and written to
  without explicitly taking care of parsing the file.
* :class:`~pyspectralradar.specklevar.specklevar.SpeckleVariance`: Class containing Service functions for Speckle
  Variance Contrast Processing.

# Usage

The following section describes first steps that are needed to acquire data with the pySpectralRadar SDK.

## Initializing The Device

The easiest way to initialize the device is to use the :class:`~pyspectralradar.octsystem.OCTSystem` which initializes
and manages the core components required for operating an OCT device, including the OCT device itself, a probe factory
for creating probes, and a processing factory for handling device-bound processing tasks.

    from pyspectralradar import OCTSystem

    # initialization of device, default probe and device depending processing
    oct_system = OCTSystem()
    device = oct_system.dev
    probe = oct_system.probe_factory.create_default()
    processing = oct_system.processing_factory.from_device()
    #...

## Creating A Scan Pattern

In order to scan a sample and acquire B-scan OCT data one needs to specify a scan pattern that describes at
which point to acquire data. To get the data of a simple B-Scan one can simply use
:func:`~pyspectralradar.scanpattern.scanpatternfactory.ScanPatternFactory.create_bscan_pattern`:

    #...
    probe = oct_system.probe_factory.create_default()
    # define simple B-scan pattern with 2mm range and 1024 A-scans
    scan_pattern = probe.scan_pattern.create_bscan_pattern(2.0, 1024)
    #...

## Acquisition

The most convenient and fast way to acquire data is to acquire data asynchronously. For this one starts a measurement
using :func:`~pyspectralradar.octdevice.submodules.acquisition.acquisition.Acquisition.start` and retrieves the latest
available data via :func:`~pyspectralradar.octdevice.submodules.acquisition.acquisition.Acquisition.get_raw_data`. The
memory needed to store the data needs to be allocated first:

    #...
    # the :class:`~pyspectralradar.data.rawdata.RawData` object will be used to get the raw data handle and will
    # contain the data from the detector (e.g. line scan camera is SD-OCT systems) without any modification
    raw = RawData()
    # the :class:`~pyspectralradar.data.realdata.RealData` object will be used for the processed data and will
    # contain the OCT image
    bscan = RealData()

    # start the measurement to acquire the specified scan pattern continuously
    device.acquisition.start(scan_pattern, AcqType.ASYNC_CONTINUOUS)

    for i in range(0, 1000):    # grab 1000 b-scans
        # grabs the spectral data from the frame grabber and copies it to the :class:`~pyspectralradar.data.rawdata.RawData` object
        device.acquisition.get_raw_data(buffer=raw)
        # specifies the output of the processing routine and executes the processing
        processing.set_data_output(bscan)
        processing.execute(raw)
        # data is now in BScan...
        # do something with the data...

    # stop the measurement
    dev.acquisition.stop()
