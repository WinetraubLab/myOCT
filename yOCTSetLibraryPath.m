function yOCTSetLibraryPath(mode)
% Sets up library's path correctly.
% mode can be 
% 'simple' (default) where path head is just the folder above this file; or
% 'full' where path head is one folder above that and we include myOCT as
% well as hashtag alignment

%% Check if running this function is needed or path has been added

global yOCTSetLibraryPathRunOnce
if isempty(yOCTSetLibraryPathRunOnce)
    yOCTSetLibraryPathRunOnce = true;
else
    return; % This function ran before
end

%% Get this file's path
p = mfilename('fullpath');
pathparts = strsplit(p,filesep);
pathparts(end) = [];

% Generate myOCT/ folder path
myOCTFolder = assemblepath(pathparts(1:(end)));

% Generate parent path
parentFolder = assemblepath(pathparts(1:(end-1)));

%% Add to path as needed by user input
addpath(genpath(myOCTFolder));
if exist('mode','var') && strcmp(mode,'full')
    addpath(genpath(parentFolder));
end

function s = assemblepath(pathparts)
s = pathparts{1};
for i=2:length(pathparts)
    s = [s filesep pathparts{i}];
end
s = [s filesep];
