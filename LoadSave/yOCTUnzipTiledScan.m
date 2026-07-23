function results = yOCTUnzipTiledScan(tiledScanInputFolder, varargin)
% Unzip compressed .oct files if they exist in the data folder. 
% This could happen if data acquisition was done with unzipOCTFile=false.
%
% INPUTS:
%   tiledScanInputFolder         - Path to tiled scan folder containing ScanInfo.json
%   'deleteCompressedAfterUnzip' - Delete .oct files after successful unzip (default: true)
%   'v'                          - Verbose mode with detailed progress reporting (default: false)
%
% OUTPUTS:
%   results - Structure with fields:
%       .alreadyUnzipped      - Folder names already unzipped
%       .successfullyUnzipped - Folders successfully unzipped in this run
%       .failed               - Folder names that failed to unzip
%       .errorMessages        - Error messages corresponding to failed folders
%       .totalFolders         - Total number of OCT folders found

%% Input parsing
p = inputParser;
addRequired(p, 'tiledScanInputFolder', @ischar);
addParameter(p, 'deleteCompressedAfterUnzip', true, @islogical);
addParameter(p, 'v', false, @islogical);
parse(p, tiledScanInputFolder, varargin{:});

in = p.Results;
v = in.v;

% Fix input path
tiledScanInputFolder = awsModifyPathForCompetability([in.tiledScanInputFolder '/']);

%% Load ScanInfo.json to get list of OCT folders
scanInfoPath = awsModifyPathForCompetability([tiledScanInputFolder 'ScanInfo.json']);
if ~awsExist(scanInfoPath, 'file')
    error('ScanInfo.json not found in: %s', tiledScanInputFolder);
end

% Read and parse JSON
json = awsReadJSON(scanInfoPath);

if ~isfield(json, 'octFolders') || isempty(json.octFolders)
    error('No OCT folders found in ScanInfo.json');
end

totalFolders = length(json.octFolders);


%% Check and unzip all folders
% Pre allocate result arrays for parfor
unzipStatus = cell(totalFolders, 1);      % 'already', 'success', 'failed', 'not_found'
errorMessages = cell(totalFolders, 1);    % Error message if failed
preservedOctFiles = cell(totalFolders, 1); % Path to preserved .oct files

% Process all folders in parallel
parfor i = 1:totalFolders
    octFolderPath = awsModifyPathForCompetability([tiledScanInputFolder json.octFolders{i} '/']);
    headerPath = awsModifyPathForCompetability([octFolderPath 'Header.xml']);
    
    if awsExist(headerPath, 'file')
        % Already unzipped: Header.xml exists
        unzipStatus{i} = 'already';
        
    else
        % Header.xml not found: check for compressed .oct file
        octFilePath = awsModifyPathForCompetability([octFolderPath 'VolumeGanymedeOCTFile.oct']);
        
        if awsExist(octFilePath, 'file')
            % Found compressed file: attempt to unzip
            try
                % Only delete compressed file if user requested it
                yOCTUnzipOCTFolder(octFilePath, octFolderPath, in.deleteCompressedAfterUnzip);
                
                % Verify unzip was successful by checking if Header.xml now exists
                if awsExist(headerPath, 'file')
                    unzipStatus{i} = 'success';
                else
                    unzipStatus{i} = 'failed';
                    errorMessages{i} = 'Header.xml not found after unzip attempt';
                    % Check if .oct was preserved for debugging
                    if awsExist(octFilePath, 'file')
                        preservedOctFiles{i} = octFilePath;
                    end
                end
                
            catch ME
                % Unzip failed: .oct should be preserved for debugging
                unzipStatus{i} = 'failed';
                errorMessages{i} = ME.message;
                % Verify .oct still exists
                if awsExist(octFilePath, 'file')
                    preservedOctFiles{i} = octFilePath;
                end
            end
            
        else
            % Neither Header.xml nor .oct file found
            unzipStatus{i} = 'not_found';
            errorMessages{i} = 'Neither Header.xml nor VolumeGanymedeOCTFile.oct found';
        end
    end
end

%% Collect and categorize results
alreadyUnzipped = {};
successfullyUnzipped = {};
failedToUnzip = {};
failedErrorMessages = {};
failedPreservedFiles = {};  % Track preserved .oct file paths for failed folders

for i = 1:totalFolders
    switch unzipStatus{i}
        case 'already'
            alreadyUnzipped{end+1} = json.octFolders{i}; %#ok<AGROW>
            
        case 'success'
            successfullyUnzipped{end+1} = json.octFolders{i}; %#ok<AGROW>
            
        case {'failed', 'not_found'}
            failedToUnzip{end+1} = json.octFolders{i}; %#ok<AGROW>
            failedErrorMessages{end+1} = errorMessages{i}; %#ok<AGROW>
            % Preserve the path even if empty, to maintain parallel indexing
            if ~isempty(preservedOctFiles{i})
                failedPreservedFiles{end+1} = preservedOctFiles{i}; %#ok<AGROW>
            else
                failedPreservedFiles{end+1} = ''; %#ok<AGROW>
            end
    end
end

%% Prepare output structure
results = struct();
results.alreadyUnzipped = alreadyUnzipped;
results.successfullyUnzipped = successfullyUnzipped;
results.failed = failedToUnzip;
results.errorMessages = failedErrorMessages;
results.totalFolders = totalFolders;

%% Print summary report
if v
    fprintf('\n%s Unzip Summary\n', datestr(datetime));
    fprintf('%s   Total folders:      %d\n', datestr(datetime), totalFolders);
    fprintf('%s   Already unzipped:   %d\n', datestr(datetime), length(alreadyUnzipped));
    fprintf('%s   Newly unzipped:     %d\n', datestr(datetime), length(successfullyUnzipped));
    fprintf('%s   Failed:             %d\n', datestr(datetime), length(failedToUnzip));
end

%% Show warning with failures (always shown, regardless of verbose)
if ~isempty(failedToUnzip)
    % Build detailed warning message
    warningMsg = [newline 'FAILED to unzip (' num2str(length(failedToUnzip)) ' folders):'];
    for i = 1:length(failedToUnzip)
        warningMsg = [warningMsg newline '  ' num2str(i) '. ' failedToUnzip{i}]; %#ok<AGROW>
        if ~isempty(failedErrorMessages{i})
            warningMsg = [warningMsg newline '     Error: ' failedErrorMessages{i}]; %#ok<AGROW>
        end
        % Add failed file path if available
        if ~isempty(failedPreservedFiles{i})
            warningMsg = [warningMsg newline '     ' failedPreservedFiles{i}]; %#ok<AGROW>
        end
    end
    warningMsg = [warningMsg newline newline];  % Add spacing at the end
    warning('yOCTUnzipTiledScan:FailedToUnzip', '%s', warningMsg);
end

end
