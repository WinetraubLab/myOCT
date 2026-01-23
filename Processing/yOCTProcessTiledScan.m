function yOCTProcessTiledScan(varargin)
% This function Processes Tiled scan, my assumption is that scan size is
% very big, so the processed volume will not be returned directly to Matlab,
% but will be saved directly to disk (or cloud).
% For speed purposes, make sure that input and output folder are either both
% local or both on the cloud. In case, both are on the cloud - run using
% cluster. See output tiff file units under "OUTPUT".
% USAGE:
%   yOCTProcessTiledScan(tiledScanInputFolder,outputPath,[params])
%   yOCTProcessTiledScan({parameters})
% INPUTS:
%   - tiledScanInputFolder - where tiled scan is saved. Make sure the
%       ScanInfo.json is present in the folder
%   - outputPath - where products of the processing are saved. can be a
%       a string (path) to tif file or folder (for tif folder). If you
%       input a cell array with both file and folder, will save both
%   - params can be any processing parameters used by
%     yOCTLoadInterfFromFile or yOCTInterfToScanCpx or any of those below
% NAME VALUE INPUTS:
%   Parameter           Default Value   Notes
% Z position stitching:
%   focusSigma                  20      If stitching along Z axis (multiple focus points), what is the size of each focus in z [pixel]
%   focusPositionInImageZpix    NaN     For all B-Scans, this parameter defines the depth (Z, pixels) that the focus is located at. 
%                                       See yOCTFindFocusTilledScan for more details.
%   cropZAroundFocusArea        true    When set to true, will crop output processed scan around the area of z focus. 
% Save some Y planes in a debug folder:
%   yPlanesOutputFolder         ''      If set will save some y planes for debug purpose in that folder
%   howManyYPlanes              3       How many y planes to save (if yPlanesOutput folder is set)
% Other parameters:
%   applyPathLengthCorrection   true    Apply path link correction, if probe ini has the information.
%   outputFilePixelSize_um      1       Output file pixel size (isotropic).
%                                       Set to [] to keep input file
%                                       resolution though it may be non
%                                       isotropic resolution
%   v                           true    verbose mode  
%
%OUTPUT:
%   No output is returned. Will save mag2db(scan Abs) to outputPath, and
%   debugFolder

%% Parameters
% In case of using focusSigma, how far from focus to go before cutting off
% the signal, avoiding very low values (on log scale)
cuttoffSigma = 3; 

%% Input Processing
p = inputParser;
addRequired(p,'tiledScanInputFolder',@isstr);

% Define the outputs
addRequired(p,'outputPath');

% Z position stitching
addParameter(p,'dispersionQuadraticTerm',79430000,@isnumeric);
addParameter(p,'focusSigma',20,@isnumeric);
addParameter(p,'focusPositionInImageZpix',NaN,@isnumeric);
addParameter(p,'cropZAroundFocusArea',true);

% Save some Y planes in a debug folder
addParameter(p,'yPlanesOutputFolder','',@isstr);
addParameter(p,'howManyYPlanes',3,@isnumeric);

% Debug
addParameter(p,'v',true,@islogical);
addParameter(p,'applyPathLengthCorrection',true); %TODO(yonatan) shift this parameter to ProcessScanFunction

% Output file resolution
addParameter(p,'outputFilePixelSize_um',1,@(x)(isempty(x) || (isnumeric(x) && isscalar(x) && x>0)));

p.KeepUnmatched = true;
if (~iscell(varargin{1}))
    parse(p,varargin{:});
else
    parse(p,varargin{1}{:});
end

% Gather unmatched varibles, we will use them as passing inputs
vals = struct2cell(p.Unmatched);
nams = fieldnames(p.Unmatched);
tmp = [nams(:)'; vals(:)']; 
reconstructConfig = tmp(:)';

in = p.Results;
v = in.v;

% Fix input path
tiledScanInputFolder = awsModifyPathForCompetability([fileparts(in.tiledScanInputFolder) '/']);

% Fix output path
outputPath = in.outputPath;
if ischar(outputPath)
    outputPath = {outputPath};
end

% Set credentials
if any(cellfun(@(x)(awsIsAWSPath(x)),outputPath))
    % Any of the output folders is on the cloud
    awsSetCredentials(1);
elseif awsIsAWSPath(in.tiledScanInputFolder)
    % Input folder is on the cloud
    awsSetCredentials();
end

cropZAroundFocusArea = in.cropZAroundFocusArea;
if (cropZAroundFocusArea && isnan(in.focusPositionInImageZpix))
    warning('Because no focus position was set, cropZAroundFocusArea cannot be "true", changed to "false". See help of yOCTProcessTiledScan function.');
    cropZAroundFocusArea = false;
end

%% Load configuration file & set parameters
json = awsReadJSON([tiledScanInputFolder 'ScanInfo.json']);

%Figure out dispersion parameters
if isempty(in.dispersionQuadraticTerm)
    if isfield(json.octProbe,'DefaultDispersionParameterA')
        warning('octProbe has dispersionParameterA which is beeing depriciated in favor of dispersionQuadraticTerm. Please adjust probe.ini');
        in.dispersionParameterA = json.octProbe.DefaultDispersionParameterA;
        reconstructConfig = [reconstructConfig {'dispersionParameterA', in.dispersionParameterA}];
    else
        in.dispersionQuadraticTerm = json.octProbe.DefaultDispersionQuadraticTerm;
        reconstructConfig = [reconstructConfig {'dispersionQuadraticTerm', in.dispersionQuadraticTerm}];
        reconstructConfig = [reconstructConfig {'n', json.tissueRefractiveIndex}];
    end
else
    reconstructConfig = [reconstructConfig {'dispersionQuadraticTerm', in.dispersionQuadraticTerm}];
    reconstructConfig = [reconstructConfig {'n', json.tissueRefractiveIndex}];
end

focusPositionInImageZpix = in.focusPositionInImageZpix;
% If the focus position is the same for all volumes, create a vector that
% stores the focus position for each volume. This is mainly to enable
% compatbility with the upgraded yOCTFindFocus which returns a focus value
% for each volume 
if length(in.focusPositionInImageZpix) == 1 %#ok<ISCL>
    focusPositionInImageZpix = in.focusPositionInImageZpix * ones(1, length(json.zDepths));
end
focusSigma = in.focusSigma;

% Read OCT system name
if isfield(json, 'octSystem')
    octSystem = json.octSystem; % New format (lowercase)
elseif isfield(json, 'OCTSystem')
    octSystem = json.OCTSystem; % Old format (uppercase) for backward compatibility
else
    error('ScanInfo.json is missing required field "octSystem" (or legacy "OCTSystem"). Cannot determine OCT system type.');
end

%% z depth check
% A working assumption of yOCTProcessTiledScan is that when yOCTScanTile
% was called, zDepths list included "0". 
% The meaning of this constraint is that exists a scan in the stack in
% which the focus is at the tissue interface (according to the user's best
% guess). This constraint helps us align coordinate such that z=0 is at the
% surface of the tissue.
%
% In this section  we check that zDepths structure exists and that zdepth 0
% is included in the stack.

if isempty(json.zDepths) || ~isnumeric(json.zDepths) % Validate presence of z-depths data
    error("ScanInfo.json doesn't include valid zDepths.");
end

if min(abs(json.zDepths)) > 0.001 % 1um tolerance
    error( ...
        ['It seems that yOCTScanTile was executed without including ' ...
        'zDepth=0 in the list of depths which breaks our ability to ' ...
        'estimate dimension z coordinate, please scan again.' ...
        'See Demo_ScanAndProcess_3D.m for an example.'])
end

%% Extract some data (refactor candidate)
% Note this is a good place for future refactoring, where we create a
% function that for every yI index specifies which scans to load and where
% their XZ coordinates are compared to the larger grid.
% This is what these varibles are here to do

if ~isfield(json,'xCenters_mm')
    % Backward compatibility
    xCenters = json.xCenters;
else
    xCenters = json.xCenters_mm;
end
zDepths = json.zDepths;

%% Create dimensions structure for the entire tiled volume
[dimOneTile_mm, dimOutput_mm] = yOCTProcessTiledScan_createDimStructure(tiledScanInputFolder, focusPositionInImageZpix);

% Adjust output pixel size if needed
if ~isempty(in.outputFilePixelSize_um)
    pixelSizeX_um = round(mean(diff(dimOutput_mm.x.values))*1e3*100)/100;
    pixelSizeY_um = round(mean(diff(dimOutput_mm.y.values))*1e3*100)/100;

    % Check that x resolution matches y resolution
    if length(dimOutput_mm.y.values) >= 2
        assert(pixelSizeX_um == pixelSizeY_um,'X resolution should match Y resolution')
    else
        pixelSizeY_um = pixelSizeX_um;
    end

    % Check that X,Y resolution matches outputFilePixelSize_um otherwise,
    % we didn't implement yet.
    assert(in.outputFilePixelSize_um == pixelSizeX_um & in.outputFilePixelSize_um == pixelSizeY_um, ...
        ["pixelSizeX used for scanning is not the same as 'outputFilePixelSize_um', " ...
        "this is not implemented yet. Please specifiy outputFilePixelSize_um in function's input and make sure it matches scanning parameters."]);

    % Change Z resolution
    dimOutput_mm.z.values = ...
        (dimOutput_mm.z.values(1)): ...
        (in.outputFilePixelSize_um*1e-3): ...
        max(dimOutput_mm.z.values);
    dimOutput_mm.z.index = 1:length(dimOutput_mm.z.values);
end

if cropZAroundFocusArea
    % Remove Z positions that are way out of focus (if we are doing focus processing)

    zAll = dimOutput_mm.z.values;

    % Remove depths that are out of focus
    % Final crop is from first focus position to last focus position.
    zAll( ...
        ( zAll < min(zDepths) + dimOneTile_mm.z.values(round(focusPositionInImageZpix(1)  )) ) ...
        | ...
        ( zAll > max(zDepths) + dimOneTile_mm.z.values(round(focusPositionInImageZpix(end))) ) ...
        ) = []; 

    if isempty(zAll)
        % No zAll matches our criteria, find the closest one.
        [dist, i] = min(abs(dimOutput_mm.z.values - ...
            ( ...
            min(zDepths) + dimOneTile_mm.z.values(round(focusPositionInImageZpix(1))) ...
            ) ...
            ));
        assert(dist<1e-3,'Closest Z is >1um away from target, too far');
        zAll = dimOutput_mm.z.values(i);
    end

    dimOutput_mm.z.values = zAll(:)';
    dimOutput_mm.z.index = 1:length(zAll);
end

% Dimensions check
assert(length(dimOutput_mm.z.values) == length(dimOutput_mm.z.index));
assert(length(dimOutput_mm.x.values) == length(dimOutput_mm.x.index));

%% Save some Y planes in a debug folder if needed
if ~isempty(in.yPlanesOutputFolder) && in.howManyYPlanes > 0
    isSaveSomeYPlanes = true;
    yPlanesOutputFolder = awsModifyPathForCompetability([in.yPlanesOutputFolder '/']);
    
    % Clear folder if it exists
    if awsExist(yPlanesOutputFolder)
        awsRmDir(yPlanesOutputFolder);
    end
    
    %Save some stacks, which ones?
    yToSaveI = round(linspace(1,length(dimOutput_mm.y.values),in.howManyYPlanes));
else
    isSaveSomeYPlanes = false;
    yPlanesOutputFolder = '';
    yToSaveI = [];
end

%% Main loop
imOutSize = [...
    length(dimOutput_mm.z.values) ...
    length(dimOutput_mm.x.values) ...
    length(dimOutput_mm.y.values)];
printStatsEveryyI = max(floor(length(dimOutput_mm.y.values)/20),1);
ticBytes(gcp);
if(v)
    fprintf('%s Stitching ...\n',datestr(datetime)); tt=tic();
end
whereAreMyFiles = yOCT2Tif([], outputPath, 'partialFileMode', 1); %Init
parfor yI=1:length(dimOutput_mm.y.values) 
    try
        % Create a container for all data
        stack = zeros(imOutSize(1:2)); %z,x,zStach
        totalWeights = zeros(imOutSize(1:2)); %z,x
        
        % Relevant OCT tiles for this y, and what is the local y in the file
        [fps, yIInFile] = ...
            yOCTProcessTiledScan_getScansFromYFrame(yI, tiledScanInputFolder, focusPositionInImageZpix);
        
        % Loop over all x stacks
        fileI = 1;
        for xxI=1:length(xCenters)
            % Loop over depths stacks
            for zzI=1:length(zDepths)
                
                % Frame path
                fpTxt = fps{fileI};
                fileI = fileI+1;
                
                % Load interferogram and dim of the frame
                % Note that a frame is smaller than one tile as frame contains only one YFrameToPRocess, thus dim structure needs an update. 
                [intFrame, dimFrame] = ...
                    yOCTLoadInterfFromFile([{fpTxt}, reconstructConfig, ...
                    {'dimensions', dimOneTile_mm 'YFramesToProcess', yIInFile, 'OCTSystem', octSystem}]);
                [scan1,~] = yOCTInterfToScanCpx([{intFrame} {dimFrame} reconstructConfig]);
                intFrame = []; %#ok<NASGU> %Freeup some memory
                scan1 = abs(scan1);
                for i=length(size(scan1)):-1:3 %Average BScan Averages, A Scan etc
                    scan1 = squeeze(mean(scan1,i));
                end
                
                if (in.applyPathLengthCorrection && isfield(json.octProbe,'OpticalPathCorrectionPolynomial'))
                    [scan1, opticalPathCorrectionValidDataMap] = yOCTOpticalPathCorrection(scan1, dimFrame, json);
                else
                    % Optical path correction not applied, hence all pixels are "valud"
                    opticalPathCorrectionValidDataMap = logical(ones(size(scan1)));
                end
                
                % Filter around the focus
                zI = 1:length(dimFrame.z.values); zI = zI(:);
                if ~isnan(focusPositionInImageZpix(zzI))
                    factorZ = yOCTProcessTiledScan_factorZ( ...
                        zI, focusPositionInImageZpix(zzI), focusSigma);
                    factor = repmat(factorZ, [1 size(scan1,2)]);
                else
                    factor = ones(length(dimFrame.z.values),length(dimFrame.x.values)); %No focus gating
                end

                % When applying optical path correction, some values of scan1 are extrapolated to 0.
                % We shouldn't use extrapolated data in reconstructing the z-stack, hence we give those position factor=0.
                factor(~opticalPathCorrectionValidDataMap) = 0;
                
                % Figure out what is the x,z position of each pixel in this file
                x = dimFrame.x.values+xCenters(xxI);
                z = dimFrame.z.values+zDepths(zzI);
                
                % Helps with interpolation problems
                x(1) = x(1) - 1e-10; 
                x(end) = x(end) + 1e-10; 
                z(1) = z(1) - 1e-10; 
                z(end) = z(end) + 1e-10; 

              
                % Add to stack
                [xxAll,zzAll] = meshgrid(dimOutput_mm.x.values,dimOutput_mm.z.values);
                stack = stack + interp2(x,z,scan1.*factor,xxAll,zzAll,'linear',0);
                totalWeights = totalWeights + interp2(x,z,factor,xxAll,zzAll,'linear',0);
                
                % Save Stack, some files for future (debug)
                if (isSaveSomeYPlanes && sum(yI == yToSaveI)>0)
                    
                    tn = [tempname '.tif'];
                    im = mag2db(scan1);
                    if ~isnan(focusPositionInImageZpix(zzI))
                        im(focusPositionInImageZpix(zzI),1:20:end) = min(im(:)); % Mark focus position on sample
                    end
                    yOCT2Tif(im,tn);
                    awsCopyFile_MW1(tn, ...
                        awsModifyPathForCompetability(sprintf('%s/y%04d_xtile%04d_ztile%04d.tif',yPlanesOutputFolder,yI,xxI,zzI)) ...
                        );
                    delete(tn);
                    
                    if (xxI == length(xCenters) && zzI==length(zDepths))
                        % Save the last weight
                        tn = [tempname '.tif'];
                        yOCT2Tif(totalWeights,tn);
                        awsCopyFile_MW1(tn, ...
                            awsModifyPathForCompetability(sprintf('%s/y%04d_totalWeights.mat',yPlanesOutputFolder,yI)) ...
                            );
                        delete(tn);
                    end
                end
            end
        end
                      
        % Dont allow factor to get too small, it creates an unstable solution
        minFactor1 = exp(-cuttoffSigma^2/2);
        totalWeights(totalWeights<minFactor1) = NaN; 
            
        % Normalization
        stackmean = stack./totalWeights;
        
        % Save
        yOCT2Tif(mag2db(stackmean), outputPath, ...
            'partialFileMode', 2, 'partialFileModeIndex', yI); 
        
        % Is it time to print statistics?
        if mod(yI,printStatsEveryyI)==0 && v
            % Stats time!
            cnt = yOCTProcessTiledScan_AuxCountHowManyYFiles(whereAreMyFiles);
            fprintf('%s Completed yIs so far: %d/%d (%.1f%%)\n',datestr(datetime),cnt,length(dimOutput_mm.y.values),100*cnt/length(dimOutput_mm.y.values));
        end

    catch ME
        fprintf('Error happened in parfor, yI=%d:\n',yI); 
        disp(ME.message);
        for j=1:length(ME.stack) 
            ME.stack(j) 
        end  
        error('Error in parfor');
    end
end %parfor

if (v)
    fprintf('Done stitching, toatl time: %.0f[min]\n',toc(tt)/60);
    tocBytes(gcp)
end

%% Verify that all files are there
if (v)
    fprintf('%s Verifying all files are there ... ',datestr(datetime));
end

% Count how many files are in the library
cnt = yOCTProcessTiledScan_AuxCountHowManyYFiles(whereAreMyFiles);
    
if cnt ~= length(dimOutput_mm.y.values)
    % Some files are missing, print debug to help trubleshoot 
    fprintf('\nDebug Data:\n');
    fprintf('whereAreMyFiles = ''%s''\n',whereAreMyFiles);
    fprintf('Number of ds files: %d\n',cnt)
    
    % Use AWS ls
    l = awsls(whereAreMyFiles);
    isFileL = cellfun(@(x)(contains(lower(x),'.json')),l);
    cntL = sum(isFileL);
    fprintf('Number of awsls files: %d\n',cntL)
    
    if (cntL ~= length(yAll))
        % Throw an error
        error('Please review "%s". We expect to have %d y planes but see only %d in the folder.\nI didn''t delete folder to allow you to debug.\nPlease remove by running awsRmDir(''%s''); when done.',...
            whereAreMyFiles,length(yAll),cnt,whereAreMyFiles);
    else
        % This is probably a datastore issue
        warning('fileDatastore returned different number of files when compared to awsls. You might want to trubleshoot why this happend.\nFor background, see: %s',...
            'https://www.mathworks.com/matlabcentral/answers/502559-filedatastore-request-to-aws-s3-limited-to-1000-files');
    end
end

if (v)
    fprintf('Done!\n');
end

%% Reorganizing files
% Move files outside of their folder
if (v)
    fprintf('%s Finalizing saving tif file ... ',datestr(datetime));
    tt=tic;
end

% Get the main data out
yOCT2Tif([], outputPath, 'metadata', dimOutput_mm, 'partialFileMode', 3);

% Get saved y planes out
if isSaveSomeYPlanes
    if (v)
        fprintf('%s Reorg some y planes ... ',datestr(datetime));
    end
    awsCopyFile_MW2(yPlanesOutputFolder);
end
if (v)
    fprintf('Done! took %.1f[min]\n',toc(tt)/60);
end


function cnt = yOCTProcessTiledScan_AuxCountHowManyYFiles(whereAreMyFiles)
% This is an aux function that counts how many files yOCT2Tif saved 
% Any fileDatastore request to AWS S3 is limited to 1000 files in 
% MATLAB 2021a. Due to this bug, we have replaced all calls to 
% fileDatastore with imageDatastore since the bug does not affect imageDatastore. 
% 'https://www.mathworks.com/matlabcentral/answers/502559-filedatastore-request-to-aws-s3-limited-to-1000-files'
ds = imageDatastore(whereAreMyFiles,'ReadFcn',@(x)(x),'FileExtensions','.getmeout','IncludeSubfolders',true); %Count all artifacts
isFile = cellfun(@(x)(contains(lower(x),'.json')),ds.Files);
cnt = sum(isFile);

