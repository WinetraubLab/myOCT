function [interferogram, apodization,prof] = yOCTLoadInterfFromFile_SimulatedData(varargin)
%Interface implementation of yOCTLoadInterfFromFile. See help yOCTLoadInterfFromFile
% OUTPUTS:
%   - interferogram - interferogram data, apodization corrected. 
%       Dimensions order (lambda,x,y,AScanAvg,BScanAvg). 
%       If dimension size is 1 it does not appear at the final matrix
%   - apodization - OCT baseline intensity, without the tissue scatterers.
%       Dimensions order (lambda,apodization #,y,BScanAvg). 
%       If dimension size is 1 it does not appear at the final matrix
%   - prof - profiling data - for debug purposes 

%% Input Checks
if (iscell(varargin{1}))
    %the first varible contains a cell with the rest of the varibles, open it
    varargin = varargin{1};
end 

inputDataFolder = varargin{1};
if (awsIsAWSPath(inputDataFolder))
    %Load Data from AWS
    awsSetCredentials;
    inputDataFolder = awsModifyPathForCompetability(inputDataFolder);
end

%Optional Parameters
for i=2:2:length(varargin)
    switch(lower(varargin{i}))
        case 'dimensions'
            dimensions = varargin{i+1};
        otherwise
            %error('Unknown parameter');
    end
end


%% Load data
interferogram = load(fullfile(inputDataFolder,'data.mat'), 'interf').interf;

%% Determine dimensions
[sizeLambda, sizeX, ~, AScanAvgN, BScanAvgN] = yOCTLoadInterfFromFile_DataSizing(dimensions);   
assert(size(interferogram,1) == sizeLambda);
assert(size(interferogram,2) == sizeX);
assert(size(interferogram,4) == AScanAvgN);
assert(size(interferogram,5) == BScanAvgN);

% Pull the relevant y
interferogram = interferogram(:,:,dimensions.y.index,:,:);

%% Finish
% Create apodization
apodization = zeros(size(interferogram));

% Empty profiling
prof = [];