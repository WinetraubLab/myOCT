function whereAreMyFiles = yOCT2Tif (varargin)
% This function saves a grayscale version of data to a Tiff stack file.
% There are a few options to save:
%   1) Save to a single large tif file, good for ImageJ viewing, less good
%       for parallel processing. To use this option filepath should end
%       with .tif
%   2) Save to a tif directory, where each y plane is a single plane,
%       creating smaller but many tif files.
%   2.1) Partial data mode
% Dimensions are (z,x) and each frame is y
% USAGE:
%   yOCT2Tif(data, filePath, [paramName, paramValue])
% INPUTS:
%   - data - 2D or 3D matrix to be saved to file. Dimensions of data are
%       (Z by X by Y). Each tif file will be Z by X and tiff stack will
%       will contain Y planes.
%   - filePath - where to save tiff file, this path can be:
%       1) Tif file path (ends with .tif) if you would like to save data to
%           a single tif file (or tif stack if 3D volume is provided)
%       2) Folder path. In this case, each Y plane will be saved as a
%           seperate file in the folder
%       3) Cell array with one tif file path and one tif folder path if you
%           would like to save both.
%           For example {'myfile.tif','myFolder\'} will generate both.
%       path can be local or AWS s3 path
% OPTINAL INPUTS: (entered as parameter name, value)  
%   'clim' - [min, max] of the grayscale, default will be minimum and
%       maximum of the data
%   'metadata' - i.e. dimention structure, to be saved alongside with the data
%       metadata is only valid at partialFileMode = 0 or 3
%   'partialFileMode' - can be 0 (not active), 1, 2 or 3. If partialFileMode
%       is 2, please set partialFileModeIndex. See partial mode below.
%       1 - initialize
%       2 - save each frame in partial mode
%       3 - cleanup
%   'partialFileModeIndex' - index along the y axis (each y is saved in a
%       different tif file) that data is assocated with.
%
% PARTIAL FILE MODE - EXPLENATION:
% In case we would like to process an OCT file which is much larger than 
% can be stored in memory, or we would like to process OCT file in parfor, 
% use this function. The general schematic for processing will be:
%   yOCT2Tif([],'C:\myOCTVolume\', 'partialFileMode',1); %Initialize
%   parfor bScanY=1:n %Loop over all B-Scans
%       resultScan = <Process B Scan> %Result scan dimensions are (y,x)
%       yOCT2Tif(resultScan,'C:\myOCTVolume\', ...
%           'partialFileMode',2,'partialFileModeIndex',bScanY); %Save a scan 
%   end
%   yOCT2Tif('C:\myOCTVolume\',[],'partialFileMode',3); % Finalize saving
%
% OUPTUTS:
%   whereAreMyFiles - path to file/folder where files are saved, very 
%       useful in partial file mode, to indicate to user where are the files.

%% Input Processing
p = inputParser;
addRequired(p,'data',@isnumeric);
addRequired(p,'filePath',@(x)(ischar(x) | iscell(x)));

addParameter(p,'clim',[])
addParameter(p,'metadata',[])
addParameter(p,'partialFileMode',0);
addParameter(p,'partialFileModeIndex',[]);
% If true, skip slides already committed and reuse saved clim (safe stop/resume)
addParameter(p,'resume',false,@islogical);

parse(p,varargin{:});
in = p.Results;
data = in.data;
filePath = in.filePath;
c = in.clim;
metadata = in.metadata;

% Partial Mode checks
mode = in.partialFileMode;
if (mode == 2)
    if (isempty(in.partialFileModeIndex))
        error('Please specify partialFileModeIndex when working in partialFileMode=2');
    elseif (length(in.partialFileModeIndex) ~= size(data,3))
        error('Please make sure partialFileModeIndex is the same as data''s 3rd axis');
    end
end

%% Figure out what the output format is
outputFilePaths = cell(2,1); %(1) - file path, (2) - folder path if needed

% What to output
if ischar(filePath)
    filePath = {filePath};
end
if (length(filePath)>2)
    error('Can output one file and or one folder but no more than that');
end

for i=1:length(filePath)
    [~,~,f] = fileparts(filePath{i});
    
    if (~isempty(f))
        %File
        if ~isempty(outputFilePaths{1})
            error('Can only output one file!');
        end
        outputFilePaths(1) = filePath(i);
    else
        %Folder
        if ~isempty(outputFilePaths{2})
            error('Can only output one folder!');
        end
        outputFilePaths{2} = awsModifyPathForCompetability([filePath{i} '/']);
    end
end

isOutputFile = ~isempty(outputFilePaths{1});
isOutputFolder = ~isempty(outputFilePaths{2});
whereAreMyFiles = outputFilePaths;

if ~isOutputFolder
    %Generate a folder path name from the file, just in case
    outputFilePaths{2} = awsModifyPathForCompetability([ ...
        outputFilePaths{1} '.fldr/']);
end

% For partial mode
outputFilePaths{3} = awsModifyPathForCompetability([outputFilePaths{2} '/partialMode/']);

%% If upload to AWS, make arrengements
if (awsIsAWSPath(filePath))
    isAWS = true;
    
    switch(mode)
        case {0,1,3}
            awsSetCredentials(1); %Use the advanced version as uploading is more challenging
        case {2}
            awsSetCredentials(0); %Use the advanced version as uploading is more challenging
    end
    
    %We will use this path for AWS CLI
    awsOutputFilePath = cell(size(outputFilePaths));
    for i=1:length(outputFilePaths)
        awsOutputFilePath{i} = awsModifyPathForCompetability(outputFilePaths{i},true); 
    end
    
    % Where to save data prior to upload
    if (mode == 0) % In mode=0 save data locally than upload
        outputFilePaths{1} = [tempname '.tif']; %Temporary local file path
        outputFilePaths{2} = [tempname '\']; %Temporary local file path
        outputFilePaths{3} = []; %No partial mode in mode 0
    else % In all other modes, you can upload directly
        outputFilePaths = awsOutputFilePath;
    end
else
    isAWS = false;
end

%% Actuall writing of data, regular mode
if mode == 0
    
    % Clear up if needed
    if isAWS
        if awsExist(awsOutputFilePath{1},'file') && isOutputFile
            awsRmFile(awsOutputFilePath{1}); %Clear file
        end
        if awsExist(awsOutputFilePath{2},'dir') && isOutputFolder
            awsRmDir(awsOutputFilePath{2}); %Clear dir
        end
    else
        if awsExist(outputFilePaths{1},'file') && isOutputFile
            awsRmFile(outputFilePaths{1}); %Clear file
        end
        if awsExist(outputFilePaths{2},'dir') && isOutputFolder
            awsRmDir(outputFilePaths{2}); %Clear dir
        end
    end
    
    % clim
    if isempty(c)
        c = [min(data(~isinf(data))) max(data(~isinf(data)))];
    end
    
    % encode meta data
    metaJson = buildTiffVolumeMetadata(metadata,c);
    
    if isOutputFile
        t = Tiff(outputFilePaths{1}, 'w8');  % Open Tiff file as BigTIFF
    end

    for yI=1:size(data,3)
        bits = yOCT2Tif_ConvertBitsData(data(:,:,yI),c,false);
        
        % Save file
        if isOutputFile
            if yI > 1
                t.writeDirectory();
            end

            tagstruct = buildTiffFrameTags(bits, metaJson, metadata, size(data,3));
            t.setTag(tagstruct);
            t.write(bits);
        end

        if isOutputFolder
            if (yI==1)
                awsWriteJSON(metaJson, ...
                    [outputFilePaths{2} '/TifMetadata.json']);
            end
            p = yScanPath(outputFilePaths{2},yI);
            imwrite(bits,p);
        end
    end

    if isOutputFile
        t.close();  % Close Tiff file
    end
    
    % At the end of the loop, upload to AWS if needed
    if (isAWS && isOutputFile)
        awsCopyFileFolder(outputFilePaths{1},awsOutputFilePath{1});
        delete(outputFilePaths{1}); %Cleanup
    end
    if (isAWS && isOutputFolder)
        awsCopyFileFolder(outputFilePaths{2},awsOutputFilePath{2});
        rmdir(outputFilePaths{2},'s'); %Cleanup
    end

%% Actual writing of data, partial file mode (initialization)
elseif mode == 1
    
    if in.resume
        % Resume mode: preserve existing partial/output data.
        if awsExist(outputFilePaths{3},'dir')
            try
                awsCopyFile_MW2(outputFilePaths{3});
            catch
                % No staged artifacts to commit, or commit already done. Safe to ignore.
            end
            % If MATLAB died after Mode 1 created the directory but before it finished
            % writing inside it, a leftover directory named y####.tif/ remains.
            % Remove those so mode 2 can re-write those frames cleanly.
            yOCT2Tif_cleanOrphanStages(outputFilePaths{3});
        else
            % Make sure the partial folder exists for the upcoming mode 2 writes
            if ~awsIsAWSPath(outputFilePaths{3}) && ~exist(outputFilePaths{3},'dir')
                mkdir(outputFilePaths{3});
            end
        end
    else
        % If output a file, clear it before writing
        if awsExist(outputFilePaths{1},'file') && isOutputFile
            awsRmFile(outputFilePaths{1}); %Clear file
        end

        % Always outputing a folder, clear it
        if awsExist(outputFilePaths{2},'dir')
            awsRmDir(outputFilePaths{2}); %Clear dir
        end
        
        % Clear the temporary folder as well
        if awsExist(outputFilePaths{3},'dir')
            awsRmDir(outputFilePaths{3});
        end
    end
    
    % Files should be in the folder
    whereAreMyFiles = outputFilePaths{3};

%% Actual writing of data, partial file mode (loop part)
elseif mode == 2    
    
    % clim
    if isempty(c)
        c = [min(data(:)) max(data(:))];
    end
    
    for yI=1:size(data,3)
        p = yScanPath(outputFilePaths{3},in.partialFileModeIndex(yI));

        % Skip frames already saved by a previous run (.json presence = complete)
        if in.resume && awsExist([p '.json'],'file') && awsExist(p,'file')
            continue;
        end

        % If a partial .tif exists without its .json (half-committed), delete it so
        % awsCopyFile_MW1 can create its staging subdirectory at that path
        if in.resume && awsExist(p,'file')
            awsRmFile(p);
        end

        % If an orphan staging directory exists because Mode 1 was interrupted before
        % writing .getmeout inside the uuid subfolder, nuke it so Mode 1 can start it fresh.
        if in.resume && awsExist(p,'dir')
            awsRmDir(p);
        end

        bits = yOCT2Tif_ConvertBitsData(data(:,:,yI),c,false);
        
        % Save Tif stack file
        tn1 = [tempname '.tif'];
        imwrite(bits,tn1);
        awsCopyFile_MW1(tn1,p); ...
        delete(tn1); % Cleanup   
    
        % Save C as a temp json (written last: acts as the completion marker)
        tn2 = [tempname '.json'];
        a.c = c;
        awsWriteJSON(a,tn2);
        awsCopyFile_MW1(tn2,[p '.json']); ...
        delete(tn2); % Cleanup   
    end
    
    % My files are actually only in the folder at this point.
    whereAreMyFiles = outputFilePaths{3};
    
%% Actual writing of data, partial file mode (finalization part)
else
    % Resume: The goal of this block is that every artifact produced here is either
    % fully committed under its final name or absent. We NEVER leave behind a
    % half-written file sharing the final name: an interrupted write stays
    % under an .inProgress sibling name (or as MW1-staged .getmeout folders)
    % so that a subsequent resume can redo only the steps that did not complete.
    % Order of operations:
    %   1. Commit MW1 staging in partialMode.
    %   2. Resolve/persist a stable global clim via _clim.json in partialMode.
    %      This prevents the clim used for rewriting slides from changing between
    %      runs, which would otherwise produce a different final BigTIFF.
    %   3. Rewrite each slide to the output folder, skipping slides whose final
    %      name already exists (they were committed by a prior run).
    %   4. Write TifMetadata.json atomically.
    %   5. Build BigTIFF into an .inProgress sibling, then rename to final name once complete.
    %   6. Remove partialMode only after the above are guaranteed on disk.
    
    % Step 1: commit anything left staged by MW1 in partialMode.
    try
        awsCopyFile_MW2(outputFilePaths{3});
    catch
        % No staged artifacts (full resume with no new work). Safe to skip.
    end

    % Step 1b: Clean up the output folder from a previous interrupted run.
    % Step 3 below also writes slides via Mode 1 (into the output folder). If MATLAB
    % died mid-write, the output folder may contain y####.tif/ directories instead
    % of y####.tif files. Mode 2 promotes any that finished writing; cleanOrphanStages
    % removes the rest. Without this, Step 5 (BigTIFF build) would crash when
    % imageDatastore encounters a directory where it expects a TIFF file.
    if in.resume && awsExist(outputFilePaths{2},'dir')
        try
            awsCopyFile_MW2(outputFilePaths{2});
        catch
            % no staged artifacts here, safe to skip
        end
        yOCT2Tif_cleanOrphanStages(outputFilePaths{2});
    end

    % Step 2: Resolve clim; reuse _clim.json if present so results are deterministic
    climCachePath = awsModifyPathForCompetability( ...
        [outputFilePaths{3} '/_clim.json']);
    cachedClim = [];
    if in.resume && awsExist(climCachePath,'file')
        try
            climStruct = awsReadJSON(climCachePath);
            if isfield(climStruct,'c') && numel(climStruct.c) == 2
                cachedClim = climStruct.c;
            end
        catch
            % Corrupted cache, recompute
            cachedClim = [];
        end
    end

    numberOfYPlanes=NaN;
    %for parforI=1:1
    parfor(parforI=1:1,1) %Run once but on a worker, to save trafic
        if isAWS
            % Make sure worker has the right credentials
            awsSetCredentials;
        end

        %Get all the JSON files, so we can read c
        % Any fileDatastore request to AWS S3 is limited to 1000 files in 
        % MATLAB 2021a. Due to this bug, we have replaced all calls to 
        % fileDatastore with imageDatastore since the bug does not affect imageDatastore. 
        % 'https://www.mathworks.com/matlabcentral/answers/502559-filedatastore-request-to-aws-s3-limited-to-1000-files'
        dsJsons = imageDatastore(outputFilePaths{3},'ReadFcn',@awsReadJSON, ...
            'FileExtensions','.json'); 
        % Exclude bookkeeping files (_clim.json, reconstructConfig.json) from per-frame list
        allJsonFiles = dsJsons.Files;
        keep = true(size(allJsonFiles));
        for k = 1:length(allJsonFiles)
            [~,bn,~] = fileparts(allJsonFiles{k});
            if startsWith(bn,'_') || strcmp(bn,'reconstructConfig') || strcmp(bn,'TifMetadata')
                keep(k) = false;
            end
        end
        dsJsons.Files = allJsonFiles(keep);

        cJsons = dsJsons.readall();
        cFrameMins = cellfun(@(x)(min(x.c)),cJsons);
        cFrameMaxs = cellfun(@(x)(max(x.c)),cJsons);

        numberOfYPlanes(parforI) = length(cJsons);

        if ~isempty(cachedClim)
            cOut(parforI,:) = cachedClim(:)';
        else
            cOut(parforI,:) = [min(cFrameMins) max(cFrameMaxs)];
        end

        if isempty(c) %Set the internal value
            cStack = cOut(parforI,:); % Use the value from the worker
        else
            cStack = c;
        end

        % Persist clim cache atomically so a future resume reuses the same value
        if isempty(cachedClim)
            climInProgress = awsModifyPathForCompetability( ...
                [outputFilePaths{3} '/_clim_inProgress.json']);
            a = struct();
            a.c = cStack;
            awsWriteJSON(a, climInProgress);
            if awsIsAWSPath(climCachePath)
                awsCopyFileFolder(climInProgress, climCachePath);
                try, delete(climInProgress); catch, end
            else
                if exist(climCachePath,'file'), delete(climCachePath); end
                movefile(climInProgress, climCachePath, 'f');
            end
        end

        % Step 3: Rewrite slides with unified clim; skip slides already committed
        for frameI = 1:numberOfYPlanes(parforI)
            fpOut = yScanPath(outputFilePaths{2},frameI);

            if awsExist(fpOut,'file'); continue; end % already committed

            fpIn = yScanPath(outputFilePaths{3},frameI);

            % Any fileDatastore request to AWS S3 is limited to 1000 files in
            % MATLAB 2021a. Due to this bug, we have replaced all calls to
            % fileDatastore with imageDatastore since the bug does not affect imageDatastore.
            % 'https://www.mathworks.com/matlabcentral/answers/502559-filedatastore-request-to-aws-s3-limited-to-1000-files'
            ds = imageDatastore(fpIn,'readFcn',@imread);
            bits = ds.read();

            % Write a new frame
            tn = [tempname '.tif'];

            dataConverted = yOCT2Tif_ConvertBitsData(bits,...
                [cFrameMins(frameI) cFrameMaxs(frameI)],true);
            newBits = yOCT2Tif_ConvertBitsData(dataConverted,cStack,false);

            imwrite(newBits,tn);
            awsCopyFile_MW1(tn,fpOut); %Matlab worker version of copy files
            delete(tn);
        end
    end %Run once but on a worker
    if isempty(c)
        c = cOut; % Use the value from the worker
    end

    % Commit rewritten slides
    try
        awsCopyFile_MW2(outputFilePaths{2});
    catch
        % No staged artifacts (full resume with all slides already committed).
    end

    % Step 4: Write TifMetadata.json atomically
    metaJson = buildTiffVolumeMetadata(metadata,c);
    metadataFinalPath = awsModifyPathForCompetability( ...
        [outputFilePaths{2} '/TifMetadata.json']);
    metadataInProgress = awsModifyPathForCompetability( ...
        [outputFilePaths{2} '/TifMetadata_inProgress.json']);
    awsWriteJSON(metaJson, metadataInProgress);
    if awsIsAWSPath(metadataFinalPath)
        awsCopyFileFolder(metadataInProgress, metadataFinalPath);
        try, delete(metadataInProgress); catch, end
    else
        if exist(metadataFinalPath,'file'), delete(metadataFinalPath); end
        movefile(metadataInProgress, metadataFinalPath, 'f');
    end

    % Step 5: Build BigTIFF atomically (_inProgress -> rename); skip if final already exists
    if isOutputFile
        metaJson = buildTiffVolumeMetadata(metadata, c);

        alreadyHaveFinal = in.resume && awsExist(outputFilePaths{1},'file');

        if ~alreadyHaveFinal
            % Write to _inProgress sibling; final name only appears after rename
            if isAWS
                tnLocal = [tempname '.tif'];
                finalDest = outputFilePaths{1};
            else
                [finalFolder, finalBase, finalExt] = fileparts(outputFilePaths{1});
                if isempty(finalFolder)
                    finalFolder = pwd;
                end
                tnLocal = fullfile(finalFolder, [finalBase '_inProgress' finalExt]);
                finalDest = outputFilePaths{1};
                % Clear any stale _inProgress from a prior crash
                if exist(tnLocal,'file')
                    delete(tnLocal);
                end
            end

            t = Tiff(tnLocal, 'w8');  % BigTIFF to support files > 4 GB

            for frameI = 1:numberOfYPlanes
                % Read one slide from the folder
                fpSlide = yScanPath(outputFilePaths{2}, frameI);
                ds = imageDatastore(fpSlide, 'readFcn', @imread);
                bits = ds.read();

                if frameI > 1
                    t.writeDirectory();
                end

                tagstruct = buildTiffFrameTags(bits, metaJson, metadata, numberOfYPlanes);
                t.setTag(tagstruct);
                t.write(uint16(bits));
            end
            t.close();

            % Atomic commit
            if isAWS
                awsCopyFileFolder(tnLocal, finalDest);
                delete(tnLocal);
            else
                if exist(finalDest,'file'), delete(finalDest); end
                movefile(tnLocal, finalDest, 'f');
            end
        end
    end

    % Step 6: All artifacts committed, safe to remove partialMode
    awsRmDir(outputFilePaths{3});

    % If output folder is not required, delete it
    if ~isOutputFolder
        awsRmDir(outputFilePaths{2});
    end
end

function p = yScanPath(outputFilePaths,yIndex)
p = awsModifyPathForCompetability(... 
    sprintf('%s/y%04d.tif', outputFilePaths,yIndex));

function metaJson = buildTiffVolumeMetadata(metadata,c)
%  This wrapper is called once per volume before the frame loop
meta.metadata = metadata;
meta.clim = c;
meta.version = 3;
metaJson = meta;

%% Build TIFF tags per frame (image dimensions, compression, ImageJ resolution)
%  This wrapper is called once per frame inside the write loop
%  It consumes the volume metadata produced by buildTiffVolumeMetadata
function tagstruct = buildTiffFrameTags(bits, metaJson, metadata, totalFrames)
tagstruct.ImageLength         = size(bits, 1);
tagstruct.ImageWidth          = size(bits, 2);
tagstruct.Photometric         = Tiff.Photometric.MinIsBlack;
tagstruct.PlanarConfiguration = Tiff.PlanarConfiguration.Chunky;
tagstruct.SampleFormat        = Tiff.SampleFormat.UInt;
tagstruct.BitsPerSample       = 16;
tagstruct.Compression         = Tiff.Compression.PackBits;
tagstruct.SamplesPerPixel     = 1;
tagstruct.RowsPerStrip        = size(bits, 1);
tagstruct.Orientation         = Tiff.Orientation.TopLeft;
tagstruct.Software            = jsonencode(metaJson);

if ~isempty(metadata) && ...
    isfield(metadata, 'x') && isfield(metadata.x, 'values') && ...
    isfield(metadata, 'z') && isfield(metadata.z, 'values') && ...
    numel(metadata.x.values) > 1 && numel(metadata.z.values) > 1

    meta_um = yOCTChangeDimensionsStructureUnits(metadata, 'microns');
    pixelSizeX_um = abs(meta_um.x.values(2) - meta_um.x.values(1));
    pixelSizeZ_um = abs(meta_um.z.values(2) - meta_um.z.values(1));

    if isfield(metadata, 'y') && isfield(metadata.y, 'values') && ...
            numel(metadata.y.values) > 1
        pixelSizeY_um = abs(meta_um.y.values(2) - meta_um.y.values(1));
    else
        pixelSizeY_um = pixelSizeX_um;
    end

    tagstruct.XResolution      = 1 / (pixelSizeX_um * 1e-4);
    tagstruct.YResolution      = 1 / (pixelSizeZ_um * 1e-4);
    tagstruct.ResolutionUnit   = Tiff.ResolutionUnit.Centimeter;
    tagstruct.ImageDescription = sprintf( ...
        ['ImageJ=1.53\n' ...
         'unit=um\n' ...
         'spacing=%g\n' ...
         'images=%d\n'], ...
         pixelSizeY_um, totalFrames);
else
    tagstruct.XResolution      = 1;
    tagstruct.YResolution      = 1;
    tagstruct.ResolutionUnit   = Tiff.ResolutionUnit.None;
    tagstruct.ImageDescription = sprintf('ImageJ=1.53\nspacing=1.00\nimages=%d\n', totalFrames);
end

function yOCT2Tif_cleanOrphanStages(partialFolder)
% Remove orphan staging directories left by an interrupted MW1 write.
% After a clean stage, MW2 promotes the contents into a FILE named y####.tif
% (or y####.tif.json). Anything still present as a DIRECTORY matching that
% pattern means MW1 crashed before writing its .getmeout marker, so MW2 had
% nothing to promote. We delete those dirs so the next parfor iteration
% re-stages from scratch.

fprintf('%s yOCT2Tif resume: scanning for orphan staging dirs in %s\n', ...
    datestr(datetime), partialFolder);
removed = {};
failed = {};

if awsIsAWSPath(partialFolder)
    entries = awsls(partialFolder);
    for k = 1:numel(entries)
        name = entries{k};
        % awsls returns folder entries with a trailing '/'; strip it for regex.
        if endsWith(name,'/')
            stripped = name(1:end-1);
        else
            continue; % not a directory, cannot be orphan stage
        end
        if ~isempty(regexp(stripped,'^y\d+\.tif(\.json)?$','once'))
            target = [partialFolder '/' stripped];
            try
                awsRmDir(target);
                removed{end+1} = stripped; %#ok<AGROW>
            catch err
                failed{end+1} = sprintf('%s (%s)', stripped, err.message); %#ok<AGROW>
            end
        end
    end
else
    listing = dir(partialFolder);
    for k = 1:numel(listing)
        if ~listing(k).isdir; continue; end
        name = listing(k).name;
        if strcmp(name,'.') || strcmp(name,'..'); continue; end
        if ~isempty(regexp(name,'^y\d+\.tif(\.json)?$','once'))
            target = fullfile(partialFolder,name);
            try
                rmdir(target,'s');
                removed{end+1} = name; %#ok<AGROW>
            catch err
                failed{end+1} = sprintf('%s (%s)', name, err.message); %#ok<AGROW>
            end
        end
    end
end

if isempty(removed) && isempty(failed)
    fprintf('%s yOCT2Tif resume: no orphan staging dirs found.\n', datestr(datetime));
else
    if ~isempty(removed)
        fprintf('%s yOCT2Tif resume: removed %d orphan staging dir(s): %s\n', ...
            datestr(datetime), numel(removed), strjoin(removed, ', '));
    end
    if ~isempty(failed)
        fprintf(2,'%s yOCT2Tif resume: FAILED to remove %d orphan dir(s): %s\n', ...
            datestr(datetime), numel(failed), strjoin(failed, ' | '));
    end
end
