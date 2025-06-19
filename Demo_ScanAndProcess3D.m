% Run this demo to use Thorlabs system to scan a 3D OCT Volume and process
% it.

% The protocol for how to use this script can be found here:
% https://docs.google.com/document/d/1aMgy00HvxrOlTXRINk-SvcvQSMU1VzT0U60hdChUVa0/edit

% Before running this script, make sure myOCT folder is in path for example
% by running: addpath(genpath('F:\Jenkins\Scan OCTHist Dev\workspace\'))
yOCTSetLibraryPath(); % Set path

%% Inputs

% Define the 3D Volume
pixelSize_um = 1; % x-y Pixel size in microns
xOverall_mm = [-0.25 0.25]; % Define the overall volume you would like to scan [start, finish]. OBJECTIVE_DEPENDENT: For 10x use [-0.5 0.5], for 40x use [-0.25 0.25]
yOverall_mm = [-0.25 0.25]; % Define the overall volume you would like to scan [start, finish]. OBJECTIVE_DEPENDENT: For 10x use [-0.5 0.5], for 40x use [-0.25 0.25]
% Uncomment below to scan one B-Scan.
% yOverall_mm = 0;

% Define probe 
octProbePath = yOCTGetProbeIniPath('40x','OCTP900'); % Inputs to the function are OBJECTIVE_DEPENDENT: '10x' or '40x', and scanning system dependent 'OCTP900' or ''
octProbeFOV_mm = 0.5; % How much of the field of view to use from the probe. OBJECTIVE_DEPENDENT: For 10x use 1, for 40x use 0.5
oct2stageXYAngleDeg = 0; % Angle between x axis of the motor and the Galvo's x axis

% Define z stack and z-stitching
scanZJump_um = 5; % microns. OBJECTIVE_DEPENDENT: For 10x use 15, for 40x use 5
zToScan_mm = unique([-100 (-30:scanZJump_um:400), 0])*1e-3; %[mm]
focusSigma = 10; % When stitching along Z axis (multiple focus points), what is the size of each focus in z [pixels]. OBJECTIVE_DEPENDENT: for 10x use 20, for 40x use 10 or 1

% Other scanning parameters
tissueRefractiveIndex = 1.33; % Use either 1.33 or 1.4 depending on the results. Use 1.4 for brain.

% Where to save scan files
output_folder = '\';

% Set to true if you would like to process existing scan rather than scan a new one.
skipScanning = false;

%% Compute scanning parameters

% Check that sufficient ammount of gel is above the tissue for proper focus
if (min(zToScan_mm)) > -100e-3
    warning('Because we use gel above tissue to find focus position. It is important to have at least one of the z-stacks in the gel. Consider having the minimum zToScan_mm to be -100e-3[mm]')
end

fprintf('%s Please adjust the OCT focus such that it is precisely at the intersection of the tissue and the coverslip.\n', datestr(datetime));

% Estimate dispersionQuadraticTerm and focusPositionInImageZpix using the
% glass slide.
% dispersionQuadraticTerm: makes the image sharp. You can set it manually
%   by running Demo_DispersionCorrectionManual.m
% focusPositionInImageZpix: is the z pixel that the focus is in
[dispersionQuadraticTerm, focusPositionInImageZpix] = ...
    yOCTScanGlassSlideToFindFocusAndDispersionQuadraticTerm( ...
    'octProbePath',octProbePath, ...
    'tissueRefractiveIndex',tissueRefractiveIndex, ...
    'skipHardware',skipScanning);

% Uncomment below to set manually
% dispersionQuadraticTerm=-1.549e08;
% focusPositionInImageZpix = 200; % 
% focusPositionInImageZpix = yOCTFindFocusTilledScan(volumeOutputFolder,...
%   'reconstructConfig',{'dispersionQuadraticTerm',dispersionQuadraticTerm},'verbose',true);

%% Focus check

% Quick pre-scan to identify tissue surface and verify it is at OCT focus
[surfacePosition_mm, x_mm, y_mm] = yOCTScanTissueSurfaceAndAutoAdjustFocusViaZStage(... 
        'xRange_mm', xOverall_mm,...
        'yRange_mm', yOverall_mm,...
        'octProbeFOV_mm', octProbeFOV_mm, ...
        'octProbePath', octProbePath, ...
        'pixelSize_um', 25,...
        'focusPositionInImageZpix', focusPositionInImageZpix,...
        'dispersionQuadraticTerm', dispersionQuadraticTerm, ...
        'skipHardware',skipScanning);

%% Perform the scan
volumeOutputFolder = [output_folder '/OCTVolume/'];

fprintf('%s Scanning Volume\n',datestr(datetime));
scanParameters = yOCTScanTile (...
    volumeOutputFolder, ...
    xOverall_mm, ...
    yOverall_mm, ...
    'octProbePath', octProbePath, ...
    'tissueRefractiveIndex', tissueRefractiveIndex, ...
    'octProbeFOV_mm', octProbeFOV_mm, ...
    'pixelSize_um', pixelSize_um, ...
    'xOffset',   0, ...
    'yOffset',   0, ... 
    'zDepths',   zToScan_mm, ... [mm]
    'oct2stageXYAngleDeg', oct2stageXYAngleDeg, ...
    'skipHardware',skipScanning, ...
    'v',true  ...
    );
	
%% Process the scan
fprintf('%s Processing\n',datestr(datetime));
outputTiffFile = [output_folder '/Image.tiff'];
yOCTProcessTiledScan(...
    volumeOutputFolder, ... Input
    {outputTiffFile},... Save only Tiff file as folder will be generated after smoothing
    'focusPositionInImageZpix', focusPositionInImageZpix,... No Z scan filtering
    'focusSigma',focusSigma,...
    'dispersionQuadraticTerm',dispersionQuadraticTerm,... Use default
    'outputFilePixelSize_um', pixelSize_um,...
    'interpMethod','sinc5', ...
    'v',true);
