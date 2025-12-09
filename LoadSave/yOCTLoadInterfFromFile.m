function [interferogram, dimensions, apodization,prof] = yOCTLoadInterfFromFile(varargin)
%%This function loads an interferogram data from file and preforms initial
%interferogram preprocessing
%
%USAGE:
% [interferogram, dimensions, apodization] = 
%       yOCTLoadInterfFromFile(inputDataFolder,'param1',value1,'param2',value2,...)
%
% INPUTS:
%   - inputDataFolder - OCT data folder / AWS data folder (s3:\)
% LIST OF OPTIONAL PARAMETERS AND VALUES
% Parameter                 Default     Information & Values
% 'OCTSystem'               ''          OCT System Name, can be 'Ganymede', 'Telesto' or 'Wasatch'.
%                                       If loading SRR files use 'Ganymede_SRR' or 'Telesto_SRR'.
%                                       If set to '', will try to figure out system from the file type.
% 'BScanAvgFramesToProcess' all         What B-Scan Average frame indexies to process. 
%                                       Usefull in cases where scan size is too big to be stored in memory, thus only part of the scan is loaded    
%                                       Index starts at 1.
% 'YFramesToProcess'        all         What Y frames to process indexies (applicable only for 3D scans).
%                                       Usefull in cases where scan size is too big to be stored in memory, thus only part of the scan is loaded 
%                                       Index starts at 1.
% 'PeakOnly'                false       when set to true, this function will only read file header without reading all dataa
%                                       and return data dimensions without computing the interferogram
%                                       Usage: dimensions = yOCTLoadInterfFromFile(...)
% 'ApodizationCorrection'   'Subtract'  What kind apodization correction to do. Can be
%                                       'Subtract' - Subtract apodization signal from interferogram
%                                       'None' - No ApodizationCorrection. Raw data is loaded.
% 'Chirp'                   []          If you loaded chirpfile once andyou have the chirp data, just pass it along here. 
%                                       If not, this function will downoload it. 
%                                       Upplicable for thorlabs systems only.
% OUTPUTS:
%   - interferogram - interferogram data, apodization corrected. 
%   - dimensions - describing the interferogram matrix dimensions. 
%       Structure is:
%           dimensions.lambda
%           dimensions.x
%           dimensions.y
%           dimensions.AScanAvg - optional
%           dimensions.BScanAvg - optional
%       For example if user done a B Scan of 1mm, pixel size 10um, 10 B scan averages.
%       dimensions will have the following fields:
%         * dimensions.lambda.order = 1, dimensions.x.order = 2, dimensions.BScanAvg.order = 3
%           This means that interferogram has the following dimensions order interferogram(lambda,x,BScanAvg)
%         * dimensions.y.order = NaN specifing no volume was taken.
%         * dimensions.x.values = 0:10:1000, imensions.x.units = 'microns'
%           This means that pixels along x dimension are positioned at 0:10:1000 microns
%         * dimensions.lambda.values = chirp, imensions.lambda.units = 'nm'
%           This specifies best wavelength estimate for pixels along lambda dimension.
%         * dimensions.y.index - running index of the dimension, this helps track index
%           position when loading only part of the OCT volume.
%     NOTICE: If interferogram is a volume scan with AScan & BScan Averaging 
%       dimensions will be interferogram(lambda,x,y,AScanAvg,BScanAvg).
%       If dimension size (of one of the dimensions) is 1 it does not
%       appear at the final matrix.
%   - apodization - OCT baseline intensity, without the tissue scatterers.
%       Dimensions order (lambda,podization #,y,BScanAvg). 
%       If dimension size is 1 it does not appear at the final matrix
%   - prof - profiling data - for debug purposes 

%% Input Checks
if (iscell(varargin{1}))
    %the first varible contains a cell with the rest of the varibles, open it
    varargin = varargin{1};
end 

%Optional Parameters
OCTSystem = '';
apodizationCorrection = 'subtract';
peakOnly = false;
chirp = [];
for i=2:2:length(varargin)
    switch(lower(varargin{i}))
        case 'octsystem'
            OCTSystem = varargin{i+1};
        case 'dimensions'
            dimensions = varargin{i+1};
        case 'yframestoprocess'
            YFramesToProcess = varargin{i+1};
            YFramesToProcess = YFramesToProcess(:);
        case 'bscanavgframestoprocess'
            BScanAvgFramesToProcess = varargin{i+1};
            BScanAvgFramesToProcess = BScanAvgFramesToProcess(:);
        case 'peakonly'
            peakOnly = varargin{i+1};
        case 'apodizationcorrection'
            apodizationCorrection = lower(varargin{i+1});
        case 'chirp'
            chirp = (varargin{i+1});
    end
end

%% Fix input data folder if required
inputDataFolder = varargin{1};
inputDataFolder = awsModifyPathForCompetability([inputDataFolder '/']);

tt = tic;
%% Figure out OCT system manufacturer
if exist('dimensions','var') && isfield(dimensions,'aux') && isfield(dimensions.aux,'OCTSystem')
    OCTSystem = dimensions.aux.OCTSystem;
end

if isempty(OCTSystem)
    [OCTSystem,OCTSystemManufacturer] = yOCTLoadInterfFromFile_WhatOCTSystemIsIt(inputDataFolder);
else
    switch(OCTSystem)
        case {'Ganymede','Telesto'}
            OCTSystemManufacturer = 'Thorlabs';
        case {'Ganymede_SRR','Telesto_SRR'}
            OCTSystemManufacturer = 'Thorlabs_SRR';
        case {'Wasatch'}
            OCTSystemManufacturer = 'Wasatch';
        case {'Simulated Ganymede'}
            OCTSystemManufacturer = 'Simulated';
        otherwise
            error('ERROR: Wrong OCTSystem name! (yOCTLoadInterfFromFile)')
    end
end

%% Load Header file, get dimensions
if ~exist('dimensions','var')
    %Load header information
    switch(OCTSystemManufacturer)
        case {'Thorlabs'}
            dimensions = yOCTLoadInterfFromFile_ThorlabsHeader(inputDataFolder, OCTSystem, chirp);
        
        case {'Thorlabs_SRR'}
            dimensions = yOCTLoadInterfFromFile_ThorlabsSRRHeader(inputDataFolder, OCTSystem, chirp);
                
        case {'Wasatch'}
            dimensions = yOCTLoadInterfFromFile_WasatchHeader(inputDataFolder);
        
        case('Simulated')
            dimensions = load(fullfile(inputDataFolder,'data.mat'), 'dim').dim;
    end
    
    dimensions.aux.OCTSystem = OCTSystem; %Add the OCT system we just discovered
else
    %Header information given by user
end

%Correct dimensions according to what user asks to process
if exist('YFramesToProcess','var')
    if (any(length(dimensions.y.index) == [0,1]))
        % dimensions contains only one frame. Empty array means index=1.
        if isempty(dimensions.y.index) && YFramesToProcess ~= 1
            error('dimensions.y.index is empty which means only YFrame is in the file, YFramesToProcess must be 1');
        elseif (dimensions.y.index ~= YFramesToProcess)
            error('Asking to process non existant frame');
        else
            %We already have one frame to process, nothing to do..
        end
    else
        %Process only subset of Y frames. Find the right index
        yIToUse = sum(dimensions.y.index(:)'==YFramesToProcess(:),1)>0;
        if ~any(yIToUse)
            error('User requested to process y frames %s but none exist in volume "%s"',sprintf('%d,',YFramesToProcess),inputDataFolder);
        end
        dimensions.y.values = dimensions.y.values(yIToUse);
        dimensions.y.values = dimensions.y.values(:)';
        dimensions.y.index = dimensions.y.index(yIToUse);
        dimensions.y.index = dimensions.y.index(:)';

        if (length(YFramesToProcess)==1) %Practically, we don't have a Y dimenson
            dimensions.y.order = NaN;
            if isfield(dimensions,'AScanAvg')
                dimensions.AScanAvg.order = dimensions.AScanAvg.order - 1;
            end
            if isfield(dimensions,'BScanAvg')
                dimensions.BScanAvg.order = dimensions.BScanAvg.order - 1;
            end
        end
    end
end
if exist('BScanAvgFramesToProcess','var') && isfield(dimensions,'BScanAvg')
    %Process only subset of BScanAvgFramesToProcess frames
    dimensions.BScanAvg.index = dimensions.BScanAvg.index(BScanAvgFramesToProcess);
    dimensions.BScanAvg.index = dimensions.BScanAvg.index(:)';
end

headerLoadTimeSec = toc(tt);
 
if (peakOnly == true)
    %We are done!
    interferogram = dimensions;
    apodization = dimensions;
    prof.headerLoadTimeSec = headerLoadTimeSec;
    return;
end

%% Load Data - System Specific Configuration
switch(OCTSystemManufacturer)
    case {'Thorlabs'}
        [interferogram, apodization, prof] = yOCTLoadInterfFromFile_ThorlabsData([varargin {'dimensions'} {dimensions}]);
    case {'Thorlabs_SRR'}
        [interferogram, apodization, prof] = yOCTLoadInterfFromFile_ThorlabsSRRData([varargin {'dimensions'} {dimensions}]);
    case {'Wasatch'}
        [interferogram, apodization, prof] = yOCTLoadInterfFromFile_WasatchData([varargin {'dimensions'} {dimensions}]);
    case('Simulated')
        [interferogram, apodization, prof] = yOCTLoadInterfFromFile_SimulatedData([varargin {'dimensions'} {dimensions}]);
end

%% Correct For Apodization
switch (apodizationCorrection)
    case 'subtract'
        % Check if apodization array contains NaN values from corrupted/missing files FIRST
        % This must be checked before the scalar NaN check
        if ~isscalar(apodization) && any(isnan(apodization(:)))
            % Skip correction: interferogram already contains NaN and will propagate through processing
        elseif isnan(apodization)
            % This catches the scalar NaN case
            error('No Apodization Data, Cannot Correct. Please set ''ApodizationCorrection'' to ''None''');
        else
            % Normal case where we perform apodization correction
            [~, sizeX, sizeY, AScanAvgN, BScanAvgN] = yOCTLoadInterfFromFile_DataSizing(dimensions);   
            apod = mean(apodization,2); %Mean across x axis
            s = size(apod);
            s = [s 1 1 1 1 1]; %Pad with ones

            interferogram = interferogram - repmat(apod,[1 sizeX sizeY/s(3) AScanAvgN BScanAvgN/s(5)]);
        end
    case 'none'
        %No correction required
    otherwise
        error(['No such Apodization Correction Method Implemented: ' apodizationCorrection]);
end

%% Finish
interferogram = squeeze(interferogram);
apodization = squeeze(apodization);
prof.headerLoadTimeSec = headerLoadTimeSec;