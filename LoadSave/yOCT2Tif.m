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
    metaJson = GenerateMetaData(metadata,c);
    
    if isOutputFile
        t = Tiff(outputFilePaths{1}, 'w');  % Open Tiff file
    end

    for yI=1:size(data,3)
        bits = yOCT2Tif_ConvertBitsData(data(:,:,yI),c,false);
        
        % Save file
        if isOutputFile
            if yI > 1
                t.writeDirectory();
            end

            % Set resolution pixel sizes (in microns)
            meta_um = yOCTChangeDimensionsStructureUnits(metadata,'microns');
            pixelSizeX_um = abs(meta_um.x.values(2) - meta_um.x.values(1));
            pixelSizeZ_um = abs(meta_um.z.values(2) - meta_um.z.values(1));
            
            % Build and set the tag struct
            tagstruct.ImageLength         = size(bits, 1);
            tagstruct.ImageWidth          = size(bits, 2);
            tagstruct.Photometric         = Tiff.Photometric.MinIsBlack;
            tagstruct.BitsPerSample       = 16;                            
            tagstruct.ResolutionUnit      = Tiff.ResolutionUnit.Centimeter; % Inch also possible
            tagstruct.XResolution         = 1/(pixelSizeX_um*1e-4); % Resolution in microns
            tagstruct.YResolution         = 1/(pixelSizeZ_um*1e-4); % Z is Y in ImageJ/Fiji
            tagstruct.Compression         = Tiff.Compression.PackBits;
            tagstruct.SamplesPerPixel     = 1;
            tagstruct.RowsPerStrip        = size(bits, 1);
            tagstruct.Orientation         = Tiff.Orientation.TopLeft;
            % Sets ImageDescription for ImageJ compatibility, specifying units in microns
            tagstruct.ImageDescription    = sprintf('ImageJ=1.53\nunit=um\nspacing=1.00\nimages=%d\n', size(data,3));
            tagstruct.Software            = jsonencode(metaJson);  % Saves our metadata in the TIFF 'Software' Tag

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
    
    % Files should be in the folder
    whereAreMyFiles = outputFilePaths{3};

%% Actual writing of data, partial file mode (loop part)
elseif mode == 2    
    
    % clim
    if isempty(c)
        c = [min(data(:)) max(data(:))];
    end
    
    for yI=1:size(data,3)
        bits = yOCT2Tif_ConvertBitsData(data(:,:,yI),c,false);
        
        p = yScanPath(outputFilePaths{3},in.partialFileModeIndex(yI));
        
        % Save Tif stack file
        tn1 = [tempname '.tif'];
        imwrite(bits,tn1);
        awsCopyFile_MW1(tn1,p); ...
        delete(tn1); % Cleanup   
    
        % Save C as a temp json
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
    % Finish WM work
    awsCopyFile_MW2(outputFilePaths{3});

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
        cJsons = dsJsons.readall();
        cFrameMins = cellfun(@(x)(min(x.c)),cJsons);
        cFrameMaxs = cellfun(@(x)(max(x.c)),cJsons);
        
        numberOfYPlanes(parforI) = length(cJsons);
        cOut(parforI,:) = [min(cFrameMins) max(cFrameMaxs)];
        if isempty(c) %Set the internal value
            cStack = cOut(parforI,:); % Use the value from the worker
        else
            cStack = c;
        end

        % Rewrite individual slides with the same c boundray for all
        for frameI = 1:numberOfYPlanes(parforI)
            % Read frame
            fpIn = yScanPath(outputFilePaths{3},frameI);
            fpOut = yScanPath(outputFilePaths{2},frameI);
            
            % Any fileDatastore request to AWS S3 is limited to 1000 files in 
            % MATLAB 2021a. Due to this bug, we have replaced all calls to 
            % fileDatastore with imageDatastore since the bug does not affect imageDatastore. 
            % 'https://www.mathworks.com/matlabcentral/answers/502559-filedatastore-request-to-aws-s3-limited-to-1000-files'
            ds = imageDatastore(fpIn,'readFcn',@imread);
            bits = ds.read();
            
            % Write a new frame
            tn = [tempname '.tif'];
            
            data = yOCT2Tif_ConvertBitsData(bits,...
                [cFrameMins(frameI) cFrameMaxs(frameI)],true);
            newBits = yOCT2Tif_ConvertBitsData(data,cStack,false);

            imwrite(newBits,tn);
            awsCopyFile_MW1(tn,fpOut); %Matlab worker version of copy files
            delete(tn);
        end 
    end %Run once but on a worker
    if isempty(c)
        c = cOut; % Use the value from the worker
    end
    
    % Remove partial tifs
    awsRmDir(outputFilePaths{3});

    % Finish up copying files
    awsCopyFile_MW2(outputFilePaths{2});
    
    % Finish generating a folder by placing metadata
    metaJson = GenerateMetaData(metadata,c);
    awsWriteJSON(metaJson, ...
                [outputFilePaths{2} '/TifMetadata.json']);
    
    % Generate a single file if required
    if isOutputFile
        outputFileTmpPath = awsModifyPathForCompetability([outputFilePaths{3} '\all.tif']);
        %for parforI=1:1
        parfor(parforI=1:1,1) %Run once but on a worker
            % Load data
            dat = yOCTFromTif(outputFilePaths{2},'yI',1:numberOfYPlanes,'isCheckMetadata',false);
            
            % Save it as a single file
            tn = [tempname '.tif'];
            yOCT2Tif(dat,tn,'clim',c,'metadata',metadata);
            awsCopyFile_MW1(tn,outputFileTmpPath); %Matlab worker version of copy files
            delete(tn);

        end
        awsCopyFile_MW2(outputFilePaths{3});
        awsCopyFileFolder(outputFileTmpPath,outputFilePaths{1});
        
        % Remove leftovers
        awsRmDir(outputFilePaths{3});
    end
    
    % If output folder is not required, delete it
    if ~isOutputFolder
        awsRmDir(outputFilePaths{2});
    end 
end

function p = yScanPath(outputFilePaths,yIndex)
p = awsModifyPathForCompetability(... 
    sprintf('%s/y%04d.tif', outputFilePaths,yIndex));

function metaJson = GenerateMetaData(metadata,c)
meta.metadata = metadata;
meta.clim = c;
meta.version = 3;
metaJson = meta;