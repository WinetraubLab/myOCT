function roboflowDatasetFolder = rfLoadDataset(varargin)
% This function connects to Roboflow and downloads dataset locally.
%
% INPUTS:
%   projectName: name of the project.
%   workspace: workspace name, default is 'yolab'.
%   version: dataset version, default is 1.
%   format: data format, default is 'coco'.
%   outputFolder: where to place data. Default is projectName.
%
% OUTPUT:
%   roboflow folder path

%% Check API Key
if ~exist('yOCTRoboflowAPIKey','file')
    error([ ...
        'Please create /_private/yOCTRoboflowAPIKey.m that contains ' ...
        'Roboflow API key. Function should look like this:' newline newline ...
        'function apiKey = yOCTRoboflowAPIKey()' newline ...
        'apiKey = "key_value";'])
end
apiKey = yOCTRoboflowAPIKey();

%% Input check

p = inputParser;
addRequired(p,'projectName');
addParameter(p,'workspace','yolab');
addParameter(p,'version',1,@isnumeric);
addParameter(p,'format','coco');
addParameter(p,'outputFolder','');

parse(p,varargin{:});
in = p.Results;
in.apiKey = apiKey;

if isempty(in.outputFolder)
    in.outputFolder = ['./' in.projectName];
end

%% Fetch data

apiURL = ...
    "https://api.roboflow.com/" + in.workspace + "/" + ...
    in.projectName + "/" + string(in.version) + "/" + ...
    in.format + "?api_key=" + in.apiKey;

% Fetch dataset export info (JSON) from Roboflow
options = weboptions('ContentType','json');
data = webread(apiURL, options);

% Retrieve the direct download link from the JSON response
downloadURL = data.export.link;

% Download the dataset zip file to disk
outputFile = "roboflow_dataset.zip";
websave(outputFile, downloadURL);

% Unzip the dataset into a folder
unzip(outputFile, in.outputFolder);

% Cleanup
delete(outputFile)
roboflowDatasetFolder = in.outputFolder;
