% Run this demo to use Thorlabs system to scan a 3D OCT Volume and process
% it. It will do so repeatedly for a time interval.

% The protocol for how to use this script can be found here:
% https://docs.google.com/document/d/1aMgy00HvxrOlTXRINk-SvcvQSMU1VzT0U60hdChUVa0/edit

% Before running this script, make sure myOCT folder is in path for example
% by running: addpath(genpath('F:\Jenkins\Scan OCTHist Dev\workspace\'))
yOCTSetLibraryPath(); % Set path

%% Inputs

% Define the 3D Volume
pixel_size_um = 1; % x-y Pixel size in microns
xOverall_mm = [-0.25 0.25]; % Define the overall volume you would like to scan [start, finish]. OBJECTIVE_DEPENDENT: For 10x use [-0.5 0.5], for 40x use [-0.25 0.25]
yOverall_mm = [-0.15 0.15]; % Define the overall volume you would like to scan [start, finish]. OBJECTIVE_DEPENDENT: For 10x use [-0.5 0.5], for 40x use [-0.25 0.25]
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
outputFolder = 'temp/';
if (outputFolder(end) ~= '\' || outputFolder(end) ~= '/')
    outputFolder(end+1) = '/';
end

% Set to true if you would like to process existing scan rather than scan a new one.
skipScanning = false;

% Time interval
scanTimeIntervals_min = (0:1:16)*60; % At what times to scan

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
fprintf('%s Please adjust the OCT focus such that it is precisely at the intersection of the tissue and the coverslip.\n', datestr(datetime));

% Quick pre-scan to identify tissue surface and verify it is at OCT focus
[surfacePosition_mm, x_mm, y_mm] = yOCTTissueSurfaceAutofocus(... 
        'xRange_mm', xOverall_mm,...
        'yRange_mm', yOverall_mm,...
        'octProbePath', octProbePath, ...
        'pixel_size_um', 25,...
        'focusPositionInImageZpix', focusPositionInImageZpix,...
        'dispersionQuadraticTerm', dispersionQuadraticTerm, ...
        'skipHardware',skipScanning);

%% Perform the scans

fprintf('First scan will be at t=%0.f Hr\nLast scan at t=%.1f Hr\n',...
    scanTimeIntervals_min(1)/60, ...
    scanTimeIntervals_min(end)/60);

tmpVolumeOutputFolder = [outputFolder '/OCTVolume/']; % This volume folder will be removed 
tStart = tic();

for scanI = 1:length(scanTimeIntervals_min)
    %% Wait until it's time to scan

    dt_min = toc(tStart)/60;
    timeRemainingToWait_min = scanTimeIntervals_min(scanI) - dt_min;
    timeRemainingToWait_sec = round(timeRemainingToWait_min*60+0.01);

    if (timeRemainingToWait_sec<0)
        warning('Interval too short!');
    else
        fprintf('%s Waiting for %.0f min to complete.\n', ...
            datestr(datetime), timeRemainingToWait_sec/60);

        if ~skipScanning % No need to wait if skipping scanning
            pause(timeRemainingToWait_sec);
        end
    end
    
    %% Scan
    scanName = strrep(datestr(datetime),':','_');

    fprintf('%s Scanning Volume\n',datestr(datetime));
    scanParameters = yOCTScanTile (...
        tmpVolumeOutputFolder, ...
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
	
    %% Process the scan
    fprintf('%s Processing\n',datestr(datetime));
    outputTiffFile = [outputFolder '/' scanName '.tiff'];
    if ~skipScanning
        yOCTProcessTiledScan(...
            tmpVolumeOutputFolder, ... Input
            {outputTiffFile},... Save only Tiff file as folder will be generated after smoothing
            'focusPositionInImageZpix', focusPositionInImageZpix,... No Z scan filtering
            'focusSigma',focusSigma,...
            'dispersionQuadraticTerm',dispersionQuadraticTerm,... Use default
            'interpMethod','sinc5', ...
            'v',true);
    end
end % Loop for the next scan

%% Load slices and generate projection

% List the files in the folder
filesInFolder = awsls(outputFolder(1:(end-1)));
filesInFolder = [...
    filesInFolder(endsWith(filesInFolder, '.tif', 'IgnoreCase', true)) ...
    filesInFolder(endsWith(filesInFolder, '.tiff', 'IgnoreCase', true)) ...
    ];
filesInFolder = cellfun(@(x)([outputFolder x]),filesInFolder,'UniformOutput',false);

% XZ slice of the center
data = yOCTCreateTemporalSliceMovieFrom3DTiffs(...
    filesInFolder,scanTimeIntervals_min, 'xz_middle.gif', ...
    round(diff(yOverall_mm)/pixel_size_um*1e3)/2, ... Middle slice
    'xz','minprojection', 5, [-24 14] ...
    );

zz = 600;
figure(1);
imagesc(squeeze(data(:,:,1)))
colormap gray;
hold on;
yline(zz, 'r');
hold off

% XY slice, relatively close to the center
yOCTCreateTemporalSliceMovieFrom3DTiffs(...
    filesInFolder,scanTimeIntervals_min, 'xy.gif', ...
    zz, ... some slice
    'xy','average', 5, [-24 14] ...
    );