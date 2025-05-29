function [json] = yOCTSimulateTileScan(varargin)
% This function generates a synthetic 3D  interferogram that matches the 3D volume provided as input
% INPUTS:
%   data: a 3D matrix (z,x,y) or a 2D matrix (z,x)
%   octFolder: folder to save all output information
%   pixelSize_um: What is the pixel size (in all directions). Default: 1.
%       Units: um.
%   
%   See other parameters in: yOCTSimulateInterferogram and yOCTScanTile.
%   These are valid here.
%
% OUTPUTS:
%   json - config file

%% Input Parameters
p = inputParser;

% Output folder
addRequired(p,'data')
addRequired(p,'octFolder',@ischar);
addParameter(p,'pixelSize_um',1)

listOfParametersToKeep_yOCTScanTile={...
    'xRange_mm','yRange_mm','zDepths','pixelSize_um', 'octProbePath', ...
    'octProbeFOV_mm', 'oct2stageXYAngleDeg', 'isVerifyMotionRange', ...
    'xOffset','yOffset','tissueRefractiveIndex','nBScanAvg','unzipOCTFile','skipHardware'};

listOfParametersToKeep_yOCTSimulateInterferogram={...
    'pixelSize_um','tissueRefractiveIndex', ...
    'lambdaRange','numberOfSpectralBands','dispersionQuadraticTerm',...
    'referenceArmZOffset_um','focusSigma', 'focusPositionInImageZpix'};

listOfParametersToRemove_yOCTScanTile = setdiff(listOfParametersToKeep_yOCTSimulateInterferogram, listOfParametersToKeep_yOCTScanTile);
listOfParametersToRemove_yOCTSimulateInterferogram = setdiff(listOfParametersToKeep_yOCTScanTile, listOfParametersToKeep_yOCTSimulateInterferogram);

p.KeepUnmatched = true;
parse(p,varargin{:});
in = p.Results;
data = in.data;
pixelSize_um = in.pixelSize_um;

% There are two ways to define index of refraction, use
% tissueRefractiveIndex instead of 'n'
if isfield(in,'n')
    error('yOCTSimulateTileScan:n','Instead of providing n, provide tissueRefractiveIndex');
end

if isfield(in,'referenceArmZOffset_um')
    error('yOCTSimulateTileScan:referenceArmZOffset_um','Not implemented');
end

% Fix folder path
in.octFolder = awsModifyPathForCompetability([fileparts(in.octFolder) '/']);

%% Run yOCTScanTile to get the json

% Create parameters list
paramToKeep = ones(size(varargin),'logical');
paramToKeep(1) = 0; % Remove data
paramToKeep = myRMAll(varargin,listOfParametersToRemove_yOCTScanTile,paramToKeep);
paramToKeep = myRM(varargin,'skipHardware', paramToKeep); % Also remove Skip Hardware as we set it to true
pr = [varargin(paramToKeep) {'skipHardware',true}];

% Add xRange_mm, yRange_mm
xRange_mm = pixelSize_um*size(data,2)/1e3/2*[-1 1];
yRange_mm = pixelSize_um*size(data,3)/1e3/2*[-1 1]; 

pr = [pr(1) {xRange_mm}, {yRange_mm} pr(2:end)];
json = yOCTScanTile(pr{:});
json.OCTSystem = 'Simulated Ganymede';

% Make folder, place Json
if exist(in.octFolder, 'dir')
    rmdir(in.octFolder, 's'); % Remove the folder and all its contents
end
mkdir(in.octFolder); % Recreate the folder
awsWriteJSON(json, [in.octFolder '\ScanInfo.json']);


%% Check Json to see what is implemented
assert(isscalar(json.xCenters_mm),'multiple xy positions, not implemented')
assert(isscalar(json.yCenters_mm),'multiple xy positions, not implemented')
assert(size(data,2)*pixelSize_um/1e3 < json.octProbeFOV_mm, 'multiple xy positions, not implemented')
assert(size(data,3)*pixelSize_um/1e3 < json.octProbeFOV_mm, 'multiple xy positions, not implemented')

%% Generate the simulated data

% Create parameters list
paramToKeep = ones(size(varargin),'logical');
paramToKeep(2) = 0; % Remove OCT folder
paramToKeep = myRMAll(varargin,listOfParametersToRemove_yOCTSimulateInterferogram,paramToKeep);
pr = [varargin(paramToKeep) {'n', json.tissueRefractiveIndex}]; % Apply n from tissue refractive index

% Loop over all depth and similate data
for zI = 1:length(json.zDepths)
    pr1 = [pr {'referenceArmZOffset_um'}, {json.zDepths(zI)*1e3}];

    % Generate interferogram
    [interf, dim] = yOCTSimulateInterferogram(pr1{:});
    interf = single(interf);

    % Place it in folder
    outputFileDir = fullfile(in.octFolder, json.octFolders{zI});
    mkdir(outputFileDir);
    save(fullfile(outputFileDir, 'data.mat'),'interf','dim');
end

end

function paramToKeep = myRMAll(v,fieldNames,paramToKeep)
for i=1:length(fieldNames)
    paramToKeep = myRM(v,fieldNames{i}, paramToKeep);
end
end

function paramToKeep = myRM(v,fieldName,paramToKeep)
i = find(cellfun(@(x)strcmp(x,fieldName),v),1);
if ~isempty(i)
    paramToKeep(i) = 0;
    paramToKeep(i+1) = 0;
end
end