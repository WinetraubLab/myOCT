% Run this demo to use Thorlabs system to scan an overview of a sample.
% This scritp should complete within a few minutes.

% Before running this script, make sure myOCT folder is in path for example
% by running: addpath(genpath('F:\Jenkins\Scan OCTHist Dev\workspace\'))
yOCTSetLibraryPath(); % Set path

%% Inputs
octSystem = 'Ganymede'; % Use either 'Ganymede' or 'Gan632' depending on your OCT system

% Define the scan
sampleSize_mm = 2; % Will scan from -sampleSize_mm to +sampleSize_mm

% Define probe 
octProbePath = yOCTGetProbeIniPath('40x','OCTP900'); % Inputs to the function are OBJECTIVE_DEPENDENT: '10x' or '40x', and scanning system dependent 'OCTP900' or ''

% Define the scan
pixelSize_um = 25; % x-y Pixel size in microns

% Other scanning parameters
tissueRefractiveIndex = 1.33; % Use either 1.33 or 1.4 depending on the results. Use 1.4 for brain.

% OCT System Selection
octSystem = 'Ganymede'; % Use either 'Ganymede' or 'Gan632' depending on your OCT system

% Set to true if you would like to process existing scan rather than scan a new one.
skipHardware = false;

%% Load hardware
yOCTHardwareLibSetUp(octSystem, skipHardware, true)

%% Compute scanning parameters

% Estimate dispersionQuadraticTerm and focusPositionInImageZpix using the
% glass slide.
% dispersionQuadraticTerm: makes the image sharp. You can set it manually
%   by running Demo_DispersionCorrectionManual.m
% focusPositionInImageZpix: is the z pixel that the focus is in
[dispersionQuadraticTerm, focusPositionInImageZpix] = ...
    yOCTScanGlassSlideToFindFocusAndDispersionQuadraticTerm( ...
    'octProbePath',octProbePath, ...
    'tissueRefractiveIndex',tissueRefractiveIndex, ...
    'skipHardware',skipHardware);

%% Scan Overview

% Quick pre-scan to identify tissue surface and verify it is at OCT focus
[surfacePosition_mm, x_mm, y_mm] = yOCTTissueSurfaceAutofocus(... 
        'xRange_mm', sampleSize_mm*[-1 1],...
        'yRange_mm', sampleSize_mm*[-1 1],...
        'octProbePath', octProbePath, ...
        'pixelSize_um', pixelSize_um,...
        'focusPositionInImageZpix', focusPositionInImageZpix,...
        'dispersionQuadraticTerm', dispersionQuadraticTerm, ...
        'skipHardware',skipHardware);

%% Plot results
figure(1)
imagesc(x_mm, y_mm, surfacePosition_mm);
xlabel('x [mm]');
ylabel('y [mm]');
title('Tissue Interface Depth [mm]');
colorbar;
grid on;

%% Cleanup for next run
yOCTHardwareLibTearDown(true);
