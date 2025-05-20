% Run this demo to use Thorlabs system to scan a 3D OCT Volume and process
% it.

% The protocol for how to use this script can be found here:
% https://docs.google.com/document/d/1aMgy00HvxrOlTXRINk-SvcvQSMU1VzT0U60hdChUVa0/edit

% Before running this script, make sure myOCT folder is in path for example
% by running: addpath(genpath('F:\Jenkins\Scan OCTHist Dev\workspace\'))
yOCTSetLibraryPath(); % Set path

%% Inputs

% Define the 3D Volume
pixel_size_um = 1; % x-y Pixel size in microns
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
tissueRefractiveIndex = 1.4; % Use either 1.33 or 1.4 depending on the results. Use 1.4 for brain.
% dispersionQuadraticTerm is OBJECTIVE_DEPENDENT
%dispersionQuadraticTerm=6.539e07; % 10x
%dispersionQuadraticTerm=9.56e07;   % 40x
%dispersionQuadraticTerm=-2.059e08;  % 10x, OCTP900
dispersionQuadraticTerm=-1.549e08;  % 40x, OCTP900

% Where to save scan files
output_folder = '\';

% Set to true if you would like to process existing scan rather than scan a new one.
skipScanning = false;

% For all B-Scans, this parameter defines the depth (Z, pixels) that the focus is located at.
% If set to NaN, yOCTFindFocusTilledScan will be executed to request user to select focus position.
focusPositionInImageZpix = NaN;

%% Compute scanning parameters

% Check that sufficient ammount of gel is above the tissue for proper focus
if (min(zToScan_mm)) > -100e-3
    warning('Because we use gel above tissue to find focus position. It is important to have at least one of the z-stacks in the gel. Consider having the minimum zToScan_mm to be -100e-3[mm]')
end

%% Focus check
fprintf('%s Please adjust the OCT focus such that it is precisely at the intersection of the tissue and the coverslip.\n', datestr(datetime));

% Quick pre-scan to identify tissue surface and verify it is at OCT focus
[surfacePosition_mm, x_mm, y_mm] = yOCTScanAndFindTissueSurface(... 
        'xRange_mm', xOverall_mm,...
        'yRange_mm', yOverall_mm,...
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
    'pixelSize_um', pixel_size_um, ...
    'xOffset',   0, ...
    'yOffset',   0, ... 
    'zDepths',   zToScan_mm, ... [mm]
    'oct2stageXYAngleDeg', oct2stageXYAngleDeg, ...
    'skipHardware',skipScanning, ...
    'v',true  ...
    );

%% Find focus in the scan
if isnan(focusPositionInImageZpix)
    fprintf('%s Find focus position volume\n',datestr(datetime));
    focusPositionInImageZpix = yOCTFindFocusTilledScan(volumeOutputFolder,...
        'reconstructConfig',{'dispersionQuadraticTerm',dispersionQuadraticTerm},'verbose',true);
end
	
%% Process the scan
fprintf('%s Processing\n',datestr(datetime));
outputTiffFile = [output_folder '/Image.tiff'];
yOCTProcessTiledScan(...
    volumeOutputFolder, ... Input
    {outputTiffFile},... Save only Tiff file as folder will be generated after smoothing
    'focusPositionInImageZpix', focusPositionInImageZpix,... No Z scan filtering
    'focusSigma',focusSigma,...
    'dispersionQuadraticTerm',dispersionQuadraticTerm,... Use default
    'interpMethod','sinc5', ...
    'v',true);
