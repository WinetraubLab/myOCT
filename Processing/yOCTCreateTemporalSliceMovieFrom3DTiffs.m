function allData = yOCTCreateTemporalSliceMovieFrom3DTiffs(...
    tiffFilePaths, timePoints_min, outputFilePath, ...
    sliceNumber, slicePlane, ...
    projectionMethod, projectionMethodNSlices, colorLim, addScalebar)
% Generate a movie from a slice of a series of 3D TIFF images obtained at
% different time points.
%
% INPUTS:
%   tiffFilePaths: List of file paths to the 3D TIFF images. Each file 
%       represent a different time point.
%   timePoints_min: a list of time points in which the tiff was captured
%   outputFilePath: file path to output.
%   sliceNumber: which slice of the tiff should we capture in the movie.
%       default: 1
%   slicePlane: can be 'xz', or 'xy'. Default 'xz'.
%   projectionMethod: can be 'average', or 'minProjection'. Default is
%       'averege'.
%   projectionMethodNSlices: how many slices to average (default: 2)
%   colorLim: contrast scaling. Default [-5 6].
%   addScalebar: default: true
%
% OUTPUT:
%   allData - the raw data (z,x,time) or (y,x,time)
%   outputFile

%% Input checks

gifSpeed = 5;

if length(tiffFilePaths) ~= length(timePoints_min)
    error('Number of files doesn''t match time points');
end

if ~exist('sliceNumber','var')
    sliceNumber = 1 + projectionMethodNSlices;
end
if ~exist('slicePlane','var')
    slicePlane = 'xz';
end

if ~exist('addScalebar','var')
    addScalebar = true;
end

if ~exist('projectionMethod','var')
    projectionMethod = 'average';
end
if ~exist('projectionMethodNSlices','var')
    projectionMethodNSlices = 2;
end

if ~exist('colorLim','var')
    colorLim = [-5 6];
end

if strcmpi(slicePlane,'xz')
    sliceDir = 'yI';
elseif strcmpi(slicePlane,'xy')
    sliceDir = 'zI';
else
    error(['Unknown sliceDir: ' sliceDir]);
end

%% Load slices from tiffs
[~,dim] = yOCTFromTif(tiffFilePaths{1},'isLoadMetadataOnly',true);
switch(sliceDir)
    case 'yI'
        allData = zeros(length(dim.z.values),length(dim.x.values),length(timePoints_min));
    case 'zI'
        allData = zeros(length(dim.y.values),length(dim.x.values),length(timePoints_min));
end

% Loop over all time points and load the data
for timeI = 1:length(timePoints_min)
    switch(sliceDir)
        case 'yI'
            data = yOCTFromTif(tiffFilePaths{timeI},'yI', ...
                sliceNumber + (-projectionMethodNSlices:projectionMethodNSlices));
        case 'zI'
            data = yOCTFromTif(tiffFilePaths{timeI},'zI', ...
                sliceNumber + (-projectionMethodNSlices:projectionMethodNSlices), ...
                'xI',dim.x.index);
    end

    % Projection
    switch(lower(projectionMethod))
        case 'average'
            switch(sliceDir)
                case 'yI'
                    data = squeeze(mean(data,3));
                case 'zI'
                    data = squeeze(mean(data,1))';
            end
        case 'minprojection'
            switch(sliceDir)
                case 'yI'
                    data = squeeze(min(data,[],3));
                case 'zI'
                    data = squeeze(min(data,[],1))';
            end
        otherwise
            error(['Don''t know projectionMethod: ' projectionMethod])
    end

    allData(:,:,timeI) = data;
end

%% Save data to gif
dim=yOCTChangeDimensionsStructureUnits(dim,'um');
for tI = 1:size(allData, 3)
    frameData = squeeze(allData(:,:,tI)); % Extract data
    frameData = min(max((frameData - colorLim(1)) / diff(colorLim), 0), 1);
    frameData = uint8(255 * mat2gray(frameData)); % Scale to 0-255
    rgbImage = cat(3, frameData, frameData, frameData); % Convert to RGB
    
    barHeight = 20; % Height of the scale bar

    % Add text to the image
    rgbImage = insertText(rgbImage, [10, size(frameData, 1) - 10 - barHeight], ...
        sprintf('t+%.0f Hours', timePoints_min(tI)/60), 'TextColor', 'white', 'FontSize', 14, 'BoxOpacity', 0);
    
    if addScalebar
        % Add a scale bar at the bottom right
        scaleBarLength = 100; % Length of the scale bar in pixels
        xStart = size(frameData, 2) - scaleBarLength - 10;
        yStart = size(frameData, 1) - barHeight - 10;
        rgbImage(yStart:yStart + barHeight - 1, xStart:xStart + scaleBarLength - 1, :) = 255;
    end
    
    % Scalebar size indication
    xCenter = xStart + scaleBarLength / 2;
    yCenter = yStart + barHeight / 2;
    rgbImage = insertText(rgbImage, [xCenter, yCenter], ...
        sprintf('%.0f%s',100*diff(dim.x.values(1:2)),dim.x.units),...
        'TextColor', 'black', 'FontSize', 14, 'BoxOpacity', 0, 'AnchorPoint', 'Center');

    % Convert to indexed image suitable for GIF
    [img, cmap] = rgb2ind(rgbImage, 256);
    
    % Write to GIF file
    if tI == 1
        imwrite(img, cmap, outputFilePath, 'gif', 'LoopCount', Inf, 'DelayTime', gifSpeed/100);
    else
        imwrite(img, cmap, outputFilePath, 'gif', 'WriteMode', 'append', 'DelayTime', gifSpeed/100);
    end
end