function yOCT2Dicom (data, filepath, dimensions, c)
%This function saves a grayscale version of data to a Dicom stack file.
%Dimensions are (z,x) and each frame is y
%INPUTS
%   data - scan data (dimensions are (z,x,y)
%   filpath - filepath of output Dicom file (including 'name.dcm')
%   dimensions - describing the interferogram matrix dimensions
%   c - [min, max] of the grayscale data

%% Input check
if ~exist('c','var') || isempty(c)
    c = [prctile(data(:),20), prctile(data(:),99.999)]; %min value is at percentile 20 because most of volume has no signals
end

if exist('dimensions','var')
    switch dimensions.x.units
        case 'microns'
            SizeX=0.001*(dimensions.x.values(2)-dimensions.x.values(1));
        case 'mm'
            SizeX=dimensions.x.values(2)-dimensions.x.values(1);
        case 'NA'
            SizeX=0;
            disp("Warning: couldn't assign X pixel size to Dicom file")
    end
    switch dimensions.z.units
        case 'microns [in medium]'
            SizeZ=0.001*(dimensions.z.values(2)-dimensions.z.values(1));
        case 'mm'
            SizeZ=dimensions.z.values(2)-dimensions.z.values(1);
        case 'NA'
            SizeZ=0;
            disp("Warning: couldn't assign Z pixel size to Dicom file")
    end
    if ~isnan(dimensions.y.order)
        switch dimensions.y.units
            case 'microns'
                SizeY=0.001*(dimensions.y.values(2)-dimensions.y.values(1));
            case 'mm'
                SizeY=dimensions.y.values(2)-dimensions.y.values(1);
            case 'NA'
                SizeY=0;
                disp("Warning: couldn't assign Y pixel size to Dicom file")
        end
    else
        SizeY=0;
        disp("2D Dicom file")
    end
else
    SizeX=0;
    SizeZ=0;
    SizeY=0;
    disp("Warning: no dimensions variable was attached, zero pixel size was assigned to Dicom file")  
end

if exist('dimensions','var')
    if ~isfield(dimensions.aux,'octSystem')
        dimensions.aux.octSystem = 'Unknown';
    end
else
    dimensions.aux.octSystem = 'Unknown';
end
    
%% Do we need AWS?
if awsIsAWSPath(filepath)
    %Load Data from AWS
    isAWS = true;
    awsSetCredentials(1); %Use the advanced version as uploading is more challenging
    awsFilePath = filepath;
    awsFilePath = awsModifyPathForCompetability(awsFilePath,true); %We will use this path for AWS CLI
    filepath = [tempname '.dcm'];
else
    isAWS = false;
end

%% Preform writing to the file

if (size(data,3) ~= 1) % Volume case 
    for yi=1:size(data,3)
        color(:,:,:) = uint16((squeeze(data(:,:,yi))-c(1))/(c(2)-c(1))*65535);
        color(color>65535) = 65535;
        color(color<0) = 0;
        color4D(:,:,:,yi)=color;
    end

    dicomwrite(color4D,filepath,'Modality',['OCT: ' dimensions.aux.octSystem], ...
        'ObjectType','Secondary Capture Image Storage')

    % add resolution parameters
    info=dicominfo(filepath);
    info.PixelSpacing = [SizeZ SizeX];
    info.SpacingBetweenSlices = SizeY;
    info.EchoTime = [c(1) c(2)]; %saves previous pixel values
    dicomwrite(color4D,filepath, info,'CreateMode','Copy')

else
    color(:,:) = uint16((squeeze(data(:,:,:))-c(1))/(c(2)-c(1))*65535);
    dicomwrite(color,filepath,'Modality',['OCT: ' dimensions.aux.octSystem], ...
        'ObjectType','Secondary Capture Image Storage')
    
    % add resolution parameters
    info=dicominfo(filepath);
    info.PixelSpacing = [SizeZ SizeX];
    info.SpacingBetweenSlices = SizeY;
    info.EchoTime = [c(1) c(2)]; %saves previous pixel values
    dicomwrite(color,filepath, info,'CreateMode','Copy')
end
    
%% Upload file to cloud if required
if (isAWS)
    awsCopyFileFolder(filepath,awsFilePath)
    delete(filepath); %Cleanup
end


