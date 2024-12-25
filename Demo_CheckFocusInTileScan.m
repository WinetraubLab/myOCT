% Run this demo to load a TileScan and check focus was done correctly.
% It will create an output XY file showing where the focus is for each
% depth.

%% Inputs

% Input folder
tiledScanInputFolder = './';

% Processing parameters
dispersionQuadraticTerm=-2.059e8;
focusSigma = 20; % When stitching along Z axis (multiple focus points), what is the size of each focus in z [pixels]. OBJECTIVE_DEPENDENT: for 10x use 20, for 40x use 20 or 1
focusPositionInImageZpix = 380;
applyPathLengthCorrection = true;

% Output
numberOfZScansToOutput = 20; % Set to 1e5 to output all scans
output_figure = 'out.tif';


%% Preprocess
if exist(output_figure,'file')
    delete(output_figure);
end

% Get a gird of depths
json = awsReadJSON([tiledScanInputFolder 'ScanInfo.json']);
scanZs = unique(json.gridZcc);
scanZs = scanZs(unique(round(linspace(1,length(scanZs),numberOfZScansToOutput))));

volumeIs = zeros(size(scanZs));
for i=1:length(volumeIs)
    j = find(scanZs(i)==json.gridZcc,1,'first');
    volumeIs(i) = j;
end

% Optical path correction text
if applyPathLengthCorrection
    opticalPathCorrectionTxt = 'Optical Path Corrected';
else
    opticalPathCorrectionTxt = 'No Optical Path Correction';
end

%% Loop over all volumes
for volumeIi = 1:length(volumeIs)
    volumeI = volumeIs(volumeIi);
    %% Load volume
    filePath = [tiledScanInputFolder json.octFolders{volumeI}];
    [meanAbs,dimensions] = yOCTProcessScan(filePath, ...
        {'meanAbs'}, ... Which functions would you like to process. Option exist for function hendel
        'dispersionQuadraticTerm', dispersionQuadraticTerm, ...
        'interpMethod', 'sinc5');
    zI = (1:length(dimensions.z.values))';
    if (applyPathLengthCorrection)
        meanAbs = yOCTOpticalPathCorrection(meanAbs, dimensions, json);
    end
    logMeanAbs = log(meanAbs);
    
    %% Plot a few slides around focus
    factorZ = yOCTProcessTiledScan_factorZ(zI, focusPositionInImageZpix, focusSigma);
    
    for zToPlot = focusPositionInImageZpix + ...
            unique(round(linspace(-focusSigma*2,focusSigma*2,15)))
        % OCT XY view 
        figure(1);
        subplot(1,5,1:4)
        imagesc( ...
            dimensions.x.values, ...
            dimensions.y.values, ...
            squeeze(logMeanAbs(zToPlot,:,:))');
        clim([-5 +6]);
        colormap gray;
        xlabel(['X [' dimensions.x.units ']']);
        ylabel(['Y [' dimensions.y.units ']']);
        title(sprintf('Scan Depth %.3f [mm]', ...
            json.gridZcc(volumeI)));
        axis equal;
        
        % Factor map
        subplot(1,5,5);
        plot(factorZ,zI,'b');
        hold on;
        plot([0,1],zToPlot*[1 1],'r--')
        hold off;
        xlabel('Factor');
        ylabel(sprintf('Within Scan Depth [pix] (%s)',...
            opticalPathCorrectionTxt))
        ylim(focusPositionInImageZpix+focusSigma*[-3 3]);
        axis ij
        grid on;
        
        % Capture frame and save it
        frame = getframe(gcf); % Capture the frame of the figure
        im = frame2im(frame); % Convert the frame to image data
        imwrite(im, output_figure, 'WriteMode', 'append');
    end
end % End volumeI loop