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
%   cropZRange_mm               []      Custom Z crop range [zMin_mm, zMax_mm] in mm relative to tissue surface (z=0).
%                                       When empty ([]), no Z cropping is applied and the full scan range is kept.
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
addParameter(p,'cropZRange_mm',[],@(x)(isempty(x) || (isnumeric(x) && numel(x)==2 && x(1)<x(2))));

% Save some Y planes in a debug folder
addParameter(p,'yPlanesOutputFolder','',@isstr);
addParameter(p,'howManyYPlanes',3,@isnumeric);

% Debug
addParameter(p,'v',true,@islogical);
addParameter(p,'applyPathLengthCorrection',true); %TODO(yonatan) shift this parameter to ProcessScanFunction

% Output file resolution
addParameter(p,'outputFilePixelSize_um',1,@(x)(isempty(x) || (isnumeric(x) && isscalar(x) && x>0)));

% Safe stop/resume: if true, pick up where a previous run left off (skip frames
% and slides already committed, reuse saved clim). Set false to force a fresh run.
addParameter(p,'resume',true,@islogical);

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


%% Load configuration file & set parameters
json = awsReadJSON([tiledScanInputFolder 'ScanInfo.json']);

%% Unzip compressed .oct files if they exist in the data folder
unzipResults = yOCTUnzipTiledScan(tiledScanInputFolder, ...
    'deleteCompressedAfterUnzip', true, ...
    'v', v);

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
    warning("json contains 'OCTSystem' field instead of 'octSystem' field. Please make sure to replace field name by January 2027 as this name will be deprecated")
    octSystem = json.OCTSystem; % Old format (uppercase) for backward compatibility
else
    error('ScanInfo.json is missing required field "octSystem" (or legacy "OCTSystem"). Cannot determine OCT system type.');
end

if isempty(json.zDepths) || ~isnumeric(json.zDepths) % Validate presence of z-depths data
    error("ScanInfo.json doesn't include valid zDepths.");
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

if ~isempty(in.cropZRange_mm)
    % Crop Z to the requested range
    cropZMin_mm = in.cropZRange_mm(1);
    cropZMax_mm = in.cropZRange_mm(2);
    
    zAll = dimOutput_mm.z.values;
    zAll(zAll < cropZMin_mm | zAll > cropZMax_mm) = [];
    
    if isempty(zAll)
        error('cropZRange_mm [%.4f, %.4f] does not overlap with the available Z range [%.4f, %.4f]. Adjust cropZRange_mm or check scan parameters.', ...
            cropZMin_mm, cropZMax_mm, dimOutput_mm.z.values(1), dimOutput_mm.z.values(end));
    end
    
    dimOutput_mm.z.values = zAll(:)';
    dimOutput_mm.z.index = 1:length(zAll);
    
    if v
        fprintf('cropZRange_mm active: Z cropped to [%.3f, %.3f] mm (%d pixels)\n', ...
            zAll(1), zAll(end), length(zAll));
    end
else
    zAll = dimOutput_mm.z.values; % Keep full Z range, no crop

    dimOutput_mm.z.values = zAll(:)';
    dimOutput_mm.z.index = 1:length(zAll);
end

% Dimensions check
assert(length(dimOutput_mm.z.values) == length(dimOutput_mm.z.index));
assert(length(dimOutput_mm.x.values) == length(dimOutput_mm.x.index));

% Store z-depths used during scanning in the dimensions structure.
% Use length(metadata.scanZDepths_mm) > 1 to determine if the scan was a z-stack or a single depth scan.
dimOutput_mm.scanZDepths_mm = json.zDepths(:)'; % Row vector [mm]

%% Save some Y planes in a debug folder if needed
if ~isempty(in.yPlanesOutputFolder) && in.howManyYPlanes > 0
    isSaveSomeYPlanes = true;
    yPlanesOutputFolder = awsModifyPathForCompetability([in.yPlanesOutputFolder '/']);
    
    % On resume, keep existing debug snapshots; new ones will overwrite by name
    if ~in.resume && awsExist(yPlanesOutputFolder)
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

% If the output already exists and no partial work remains, nothing to do.
% Must be checked BEFORE yOCT2Tif mode 1 (which always creates partialMode/).
if in.resume
    % Locate where partialMode/ would be, matching yOCT2Tif's convention
    allFinalFilesExist = true;
    outputFolderForPartial = '';
    for kOut = 1:length(outputPath)
        op = outputPath{kOut};
        [~,~,ext] = fileparts(op);
        if ~isempty(ext)
            % File output
            if ~awsExist(op,'file')
                allFinalFilesExist = false;
            end
            if isempty(outputFolderForPartial)
                outputFolderForPartial = awsModifyPathForCompetability([op '.fldr/']);
            end
        else
            % Folder output
            folderPath = awsModifyPathForCompetability([op '/']);
            metaPath = awsModifyPathForCompetability([folderPath 'TifMetadata.json']);
            if ~awsExist(metaPath,'file')
                allFinalFilesExist = false;
            end
            outputFolderForPartial = folderPath; % prefer folder over .fldr sibling
        end
    end
    partialModePath = awsModifyPathForCompetability( ...
        [outputFolderForPartial 'partialMode/']);
    partialStillExists = awsExist(partialModePath,'dir');

    if allFinalFilesExist && ~partialStillExists
        warning('yOCTProcessTiledScan:outputAlreadyDone', ...
            ['Output already exists and no partial work remains. Nothing to do.\n' ...
            'To regenerate: delete the output files and re-run, ' ...
            'or pass ''resume'', false to force a fresh run.']);
        return;
    end
end

ticBytes(gcp);
if(v)
    fprintf('%s Stitching ...\n',datestr(datetime)); tt=tic();
end
whereAreMyFiles = yOCT2Tif([], outputPath, 'partialFileMode', 1, 'resume', in.resume); %Init

% Guard against resuming with different inputs: save the current config and
% compare against a previous run. Mismatch -> clear error, not silent corruption.
configGuardPath = awsModifyPathForCompetability( ...
    [whereAreMyFiles '/reconstructConfig.json']);
newConfig = struct();
newConfig.tiledScanInputFolder     = tiledScanInputFolder;
newConfig.dispersionQuadraticTerm  = in.dispersionQuadraticTerm;
newConfig.focusSigma               = in.focusSigma;
newConfig.focusPositionInImageZpix = in.focusPositionInImageZpix;
newConfig.cropZRange_mm            = in.cropZRange_mm;
newConfig.outputFilePixelSize_um   = in.outputFilePixelSize_um;
newConfig.applyPathLengthCorrection= in.applyPathLengthCorrection;
newConfig.reconstructConfig        = reconstructConfig;

if in.resume && awsExist(configGuardPath,'file')
    try
        prevConfig = awsReadJSON(configGuardPath);
    catch
        prevConfig = [];
    end
    if ~isempty(prevConfig)
        mismatchLines = {};
        % Paths (tiledScanInputFolder) are excluded from comparison: moving data
        % to a different drive or PC changes the path but not the reconstruction.
        fieldsToSkip = {'tiledScanInputFolder'};
        fn = fieldnames(newConfig);
        for k = 1:length(fn)
            f = fn{k};
            if any(strcmp(f, fieldsToSkip)), continue; end
            % Compare via JSON encoding: avoids false positives from floating-point
            % round-trips through JSON and cell/struct type differences.
            prevJson = ''; curJson = '';
            try, prevJson = jsonencode(prevConfig.(f)); catch, end
            try, curJson  = jsonencode(newConfig.(f));  catch, end
            if ~isfield(prevConfig,f) || ~strcmp(prevJson, curJson)
                prevStr = '<missing>';
                if isfield(prevConfig,f)
                    prevStr = yOCTProcessTiledScan_formatConfigValue(prevConfig.(f));
                end
                curStr = yOCTProcessTiledScan_formatConfigValue(newConfig.(f));
                mismatchLines{end+1} = sprintf('    %s: previous=%s, current=%s', f, prevStr, curStr); %#ok<AGROW>
            end
        end
        if ~isempty(mismatchLines)
            msg = sprintf(['Cannot resume: the following inputs differ from the previous run:\n%s\n\n'...
                'Partial data lives at:\n    %s\n\n'...
                'Options to resolve:\n'...
                '    1) Re-run with the previous input values.\n'...
                '    2) Delete the partial folder above and re-run to start fresh.\n'...
                '    3) Re-run passing ''resume'', false to force a fresh run.'], ...
                strjoin(mismatchLines, newline), whereAreMyFiles);
            error('yOCTProcessTiledScan:resumeConfigMismatch', '%s', msg);
        end
    end
end
% Always (re)write the guard to keep it in sync with the current inputs
configInProgress = awsModifyPathForCompetability( ...
    [whereAreMyFiles '/reconstructConfig_inProgress.json']);
awsWriteJSON(newConfig, configInProgress);
if awsIsAWSPath(configGuardPath)
    awsCopyFileFolder(configInProgress, configGuardPath);
    try, delete(configInProgress); catch, end
else
    if exist(configGuardPath,'file'), delete(configGuardPath); end
    movefile(configInProgress, configGuardPath, 'f');
end

% Find frames already done (y####.tif.json present = frame complete)
alreadyDoneYI = false(1,length(dimOutput_mm.y.values));
if in.resume
    for yI = 1:length(dimOutput_mm.y.values)
        finalJsonPath = awsModifyPathForCompetability( ...
            sprintf('%s/y%04d.tif.json', whereAreMyFiles, yI));
        if awsExist(finalJsonPath,'file')
            alreadyDoneYI(yI) = true;
        end
    end
end
numAlreadyDone = sum(alreadyDoneYI);
if v && numAlreadyDone > 0
    fprintf('%s Resume: %d / %d yI frames already committed, will be skipped.\n', ...
        datestr(datetime), numAlreadyDone, length(dimOutput_mm.y.values));
end

parfor yI=1:length(dimOutput_mm.y.values) 
    % Skip frames already done; re-check inside parfor in case of race
    if alreadyDoneYI(yI)
        continue;
    end
    finalJsonPath = awsModifyPathForCompetability( ...
        sprintf('%s/y%04d.tif.json', whereAreMyFiles, yI));
    if awsExist(finalJsonPath,'file')
        continue;
    end

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
                    {'dimensions', dimOneTile_mm 'YFramesToProcess', yIInFile, 'octSystem', octSystem}]);
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

                % Correct for focus drift: re-center this tile on its own
                % focus pixel so that the proper focus lands at absolute
                % depth zDepths(zzI). For a constant focus (single value), this
                % is a no-op because dimFrame.z.values is already 0 at the focus.
                % so behavior is unchanged for the single focus position.
                if ~isnan(focusPositionInImageZpix(zzI))
                    z = z - dimFrame.z.values(round(focusPositionInImageZpix(zzI)));
                end
                
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
            'partialFileMode', 2, 'partialFileModeIndex', yI, 'resume', in.resume); 
        
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

% Count how many files are in the library. On resume, the helper only sees
% staged (.getmeout) artifacts from this run; frames committed by previous
% runs live as y####.tif.json directly in whereAreMyFiles, so add them back.
cnt = yOCTProcessTiledScan_AuxCountHowManyYFiles(whereAreMyFiles) + numAlreadyDone;

if cnt ~= length(dimOutput_mm.y.values)
    % Some files are missing, print debug to help trubleshoot 
    fprintf('\nDebug Data:\n');
    fprintf('whereAreMyFiles = ''%s''\n',whereAreMyFiles);
    fprintf('Number of ds files: %d\n',cnt)
    
    % Use AWS ls. Match only per-frame jsons (y####.tif.json); exclude
    % bookkeeping files like _clim.json and reconstructConfig.json.
    l = awsls(whereAreMyFiles);
    isFileL = cellfun(@(x)(~isempty(regexp(lower(x),'y\d+\.tif\.json$','once'))),l);
    cntL = sum(isFileL);
    fprintf('Number of awsls files: %d\n',cntL)
    
    if (cntL ~= length(dimOutput_mm.y.values))
        % Throw an error
        error('Please review "%s". We expect to have %d y planes but see only %d in the folder.\nI didn''t delete folder to allow you to debug.\nPlease remove by running awsRmDir(''%s''); when done.',...
            whereAreMyFiles,length(dimOutput_mm.y.values),cnt,whereAreMyFiles);
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
yOCT2Tif([], outputPath, 'metadata', dimOutput_mm, 'partialFileMode', 3, 'resume', in.resume);

% Resume summary (same format as yOCTUnzipTiledScan)
if v
    nTotalYI = length(dimOutput_mm.y.values);
    nNewYI   = nTotalYI - numAlreadyDone;
    fprintf('\n%s Reconstruction Summary\n', datestr(datetime));
    fprintf('%s   Total y planes:         %d\n', datestr(datetime), nTotalYI);
    fprintf('%s   Already reconstructed:  %d\n', datestr(datetime), numAlreadyDone);
    fprintf('%s   Newly reconstructed:    %d\n', datestr(datetime), nNewYI);
end

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
try
    ds = imageDatastore(whereAreMyFiles,'ReadFcn',@(x)(x),'FileExtensions','.getmeout','IncludeSubfolders',true); %Count all artifacts
    isFile = cellfun(@(x)(contains(lower(x),'.json')),ds.Files);
    cnt = sum(isFile);
catch
    % No .getmeout staged files (e.g. full resume with no new work). Not an error.
    cnt = 0;
end


function s = yOCTProcessTiledScan_formatConfigValue(v)
% Format a config value as a short string for error messages
if isnumeric(v) || islogical(v)
    if isempty(v)
        s = '[]';
    elseif isscalar(v)
        s = mat2str(v);
    else
        s = ['[' strjoin(arrayfun(@mat2str, v(:)', 'UniformOutput', false), ' ') ']'];
    end
elseif ischar(v)
    s = ['"' v '"'];
elseif iscell(v)
    parts = cell(1, numel(v));
    for iii = 1:numel(v)
        parts{iii} = yOCTProcessTiledScan_formatConfigValue(v{iii});
    end
    s = ['{' strjoin(parts, ', ') '}'];
else
    try
        s = jsonencode(v);
    catch
        s = '<unprintable>';
    end
end

