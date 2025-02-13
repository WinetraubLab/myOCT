function [data, metadata, c] = yOCTFromTif (varargin)
% This function tiff file.
% USAGE: 
%   [data, metadata, clim] = yOCTFromTif (filepath [, parameters])
% INPUTS:
%   filpath - filepath to load. Can be a .tif file or a tif stack folder.
%       For each file in the tif stack, image dimensions are z-x.
%       Progressing along the stack is like moving along y axis.
%       Path can be local or s3 path.
% PARAMETERS:
%   'xI','yI','zI' - specify which index of area of the data to load. 
%       For example yOCTFromTif(filepath,'yI',1:10) will load first 10 frames. Default: load all.
%       Notice that if you would like par
%   'isLoadMetadataOnly' - when set to true will set data to [] and return
%       metadata only. Default: false.
%   'isCheckMetadata' - set to true if you would like to check header is good
%       (default) or false to skip this part. You might want to skip
%       checking header when running on aws as it requires using awsls
% OUTPUTS:
%   data - data saved from tif, dimensions are (z,x,y)
%   metaData - dimention structure, if present as meta data
%   c - limits used to create the file

%% Input Processing

p = inputParser;
addRequired(p,'filepath',@ischar);
addParameter(p,'xI',[])
addParameter(p,'yI',[]);
addParameter(p,'zI',[]);
addParameter(p,'isLoadMetadataOnly',false);
addParameter(p,'isCheckMetadata',true)

parse(p,varargin{:});
in = p.Results;

filepath = in.filepath;
filepathIn = in.filepath; %Record the oroginal file path
yI = in.yI;
xI = in.xI;
zI = in.zI;
isLoadMetadataOnly = in.isLoadMetadataOnly;
isCheckMetadata = in.isCheckMetadata;

%% Is AWS?
if (awsIsAWSPath(filepath))
    %Load Data from AWS
    isAWS = true;
    awsSetCredentials; %Use the advanced version as uploading is more challenging
    filepath = awsModifyPathForCompetability(filepath);
else
    isAWS = false;
end

%% Is Tif Folder or File
[~,~,f] = fileparts(filepath);
    
if (~isempty(f))
    isInputFile = true;
else
    isInputFile = false;
end

%% Copy file locally, if its at the cloud
if (isAWS && isInputFile)
    % Download file locally for easy access
    % Any fileDatastore request to AWS S3 is limited to 1000 files in 
    % MATLAB 2021a. Due to this bug, we have replaced all calls to 
    % fileDatastore with imageDatastore since the bug does not affect imageDatastore. 
    % 'https://www.mathworks.com/matlabcentral/answers/502559-filedatastore-request-to-aws-s3-limited-to-1000-files'
    ds=imageDatastore(filepath,'ReadFcn',@copyFileLocally);
    filepath=ds.read(); % Update file path
end

%% Run the job
try
    [data, metadata, c] = yOCTFromTif_MainFunction(filepath,isInputFile,xI,yI,zI,isLoadMetadataOnly,isCheckMetadata);
catch ME
    % Clean up before exiting
    if isAWS && isInputFile
        %Remove temporary file
        delete(filepath);
    end
    
    fprintf('\nError while yOCTFromTif reading "%s".\n',filepathIn);
    rethrow(ME);
end

% Clean up before exiting
if isAWS && isInputFile
    %Remove temporary file
    delete(filepath);
end

%% This is the main function that does the job
function [data, metadata, c] = yOCTFromTif_MainFunction(filepath,isInputFile,xI,yI,zI,isLoadMetadataOnly,isCheckMetadata)
%% Read Metadata
if (isInputFile)
    % Read meta from file
    info = imfinfo(filepath);

    % Get meta data
    if isfield(info(1), 'Software') && strncmp(info(1).Software, '{', 1)
        description = info(1).Software; % Use TIFF Tag "Software" so ImageJ/Fiji can read ImageDescription properly
    elseif isfield(info(1), 'ImageDescription') && strncmp(info(1).ImageDescription, '{', 1)
        description = info(1).ImageDescription;  % If 'Software' is not useful, check 'ImageDescription'
    else    
        description = '';  % No MetaData available
    end
    [c, metadata, maxbit] = intrpertDescription(description,filepath);
    
    if isempty(yI) || isCheckMetadata
        % Get avilable Ys
        yIAll=1:length(info);
        
        % If yI is not specified assume all
        if isempty(yI)
            yI = yIAll;
        end
    end
else
    % Read meta from JSON
    description = awsReadJSON([filepath '/TifMetadata.json']);
    
    [c, metadata, maxbit] = intrpertDescription(description,filepath);
    
    if isempty(yI) || isCheckMetadata
        % Get avilable Ys
        l = awsls(filepath);
        isTifFile = cellfun(@(x)(contains(x,'.tif')),l);
        yIAll=1:sum(isTifFile);

        % If yI is not specified assume all
        if isempty(yI)
            yI = yIAll;
        end
    end
end 

%No Scaling information, use default
if isempty(c) || length(c)~=2
    c(1) = maxbit;
    c(2) = 0;
end

if xor(isempty(xI),isempty(zI))
    error('If xI is defined than zI should be defined as well');
end
if ~isempty(xI)
    if (length(xI) == 1)
        xI = [xI xI];
    end
    if (length(zI) == 1)
        zI = [zI zI];
    end
    if (std(diff(xI))~=0 || std(diff(zI))~=0)
        error('xI, zI should be of the form start:jump:end');
    end

    pixRegionX = [xI(1) max(mean(diff(xI)),1) xI(end)];
    pixRegionY = [zI(1) max(mean(diff(zI)),1) zI(end)];
    imreadWrapper1 = @(filePath, frameIndex)(imreadWrapper(filePath, frameIndex, pixRegionX, pixRegionY));
else
    % Load all
    imreadWrapper1 = @(filePath, frameIndex)(imreadWrapper(filePath, frameIndex, [], []));
end

%% Check if metadata is consistent (if metadata exists)
if isCheckMetadata
    if isstruct(metadata) && isfield(metadata,'x') && isfield(metadata,'y')
        if (length(metadata.y.index) ~= length(metadata.y.values))
            error('File header is corupted. length(metadata.y.index)=%d while length(metadata.y.values) = %d',...
                length(metadata.y.index),length(metadata.y.values));
        end

        if (length(metadata.x.index) ~= length(metadata.x.values))
            error('File header is corupted. length(metadata.x.index)=%d while length(metadata.x.values) = %d',...
                length(metadata.x.index),length(metadata.x.values));
        end

        if (length(metadata.y.index) ~= length(yIAll))
            error('File is corupted. Header claims: length(metadata.y.index)=%d. Actual y plains in the file: %d',...
                length(metadata.y.index),length(yIAll));
        end
    end
end

%% If metadata only mode, we are done
if isLoadMetadataOnly
    data = [];
    return;
end

%% Get the data
for i=1:length(yI)
    
    %% Load data
    try
        if (isInputFile)
            % Single file mode
            bits = imreadWrapper1(filepath,yI(i));
        else
            % Folder mode
            % Any fileDatastore request to AWS S3 is limited to 1000 files in 
            % MATLAB 2021a. Due to this bug, we have replaced all calls to 
            % fileDatastore with imageDatastore since the bug does not affect imageDatastore. 
            % 'https://www.mathworks.com/matlabcentral/answers/502559-filedatastore-request-to-aws-s3-limited-to-1000-files'
            ds = imageDatastore(...
                awsModifyPathForCompetability(sprintf('%s/y%04d.tif',filepath,yI(i))), ...
                'ReadFcn',@(fp)(imreadWrapper1(fp,[])));
            bits = ds.read();
        end
    catch ME
        if isInputFile
            s = 'from a tif file';
        else
            s = 'from a tif folder';
        end
        fprintf('yOCTFromTif failed to load an image %s.\nslice %d.\n',...
            s,yI(i)); 
        for j=1:length(ME.stack) 
            ME.stack(j) 
        end 
        disp(ME.message); 
        error('Error in yOCTFrimTif, see information below');
    end

    %% Basic processing
    if (i==1)
        data = zeros(size(bits,1),size(bits,2),length(yI),'single');
    end
    
    data(:,:,i) = yOCT2Tif_ConvertBitsData(bits,c,true,maxbit); %Rescale to the original values
end
    
function out = copyFileLocally(filepath)
%Copy filename to other temp name
out = [tempname '.tif'];
copyfile(filepath,out);

function [c, metaData, maxbit] = intrpertDescription(description,filepath)

if isempty(description)
    c = [];
    metaData = [];
    maxbit = 2^8-1;
    return;
end

%% Read version
isDepricatedVersion = false;
if (~isstruct(description) && description(1) ~= '{')
    % Support for version 1, depriciated!
    c = sscanf(description,'min:%g,max:%g');
    isDepricatedVersion = true;
    metaData = [];
    maxbit = 2^8-1;
else
    if ~isstruct(description)
        jsn = jsondecode(description);
    else
        jsn = description;
    end
    
    if (jsn.version == 2)
        metaData = jsn.dim;
        c = jsn.c;
        isDepricatedVersion = true;
        maxbit = 2^8-1;
    elseif (jsn.version == 3)
        % Good version
        metaData = jsn.metadata;
        c = jsn.clim;
        maxbit = []; %Latest version
    end
end

%% Warning if needed
persistent timeOfLastWarningHappend; 
if isDepricatedVersion && (isempty(timeOfLastWarningHappend) || ...
        timeOfLastWarningHappend < now-1/86400) %Last warning is old by n seconds
    warning(['%s has a depriciated version of meta data, ' ...
        'update please by running this command:\n' ...
        'filePath = ''%s'';\n' ...
        '[data, meta] = yOCTFromTif(filePath);\n' ...
        'yOCT2Tif(data, filePath, ''metadata'', meta);'],filepath,filepath);
    
    timeOfLastWarningHappend = now;
end

function im = imreadWrapper(imagePath, frameIndex, pixRegionX, pixRegionY)

if isempty(frameIndex) && isempty(pixRegionX)
    %Simplest version of load
    im = imread(imagePath);
elseif ~isempty(frameIndex) && isempty(pixRegionX)
    %No pixel regions
    im = imread(imagePath,'index',frameIndex);
elseif isempty(frameIndex) && ~isempty(pixRegionX)
    %No frame index
    im = imread(imagePath,'PixelRegion',{pixRegionY pixRegionX});
else
    im = imread(imagePath,'index',frameIndex,'PixelRegion',{pixRegionY pixRegionX});
end