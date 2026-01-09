function results = yOCTUnzipTiledScan(tiledScanInputFolder, varargin)
% Unzips all compressed .oct files in a tiled scan folder before processing.
% Useful when processing scans that were saved with unzipOCTFile=false during acquisition.
%
% This function:
%   1. Reads ScanInfo.json to find all OCT folders in the scan
%   2. Checks each folder for compressed .oct files
%   3. Unzips them in parallel using yOCTUnzipOCTFolder
%   4. Reports success/failure status for each folder
%   5. Only deletes compressed files that were successfully unzipped
%
% INPUTS:
%   tiledScanInputFolder         - Path to tiled scan folder containing ScanInfo.json
%   'deleteCompressedAfterUnzip' - Delete .oct files after successful unzip (default: true)
%   'v'                          - Verbose mode with detailed progress reporting (default: false)
%
% OUTPUTS:
%   results - Structure with fields:
%       .alreadyUnzipped      - Folder names already unzipped from previous runs
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
if ~strcmp(in.tiledScanInputFolder(end), '/') && ~strcmp(in.tiledScanInputFolder(end), '\')
    tiledScanInputFolder = awsModifyPathForCompetability([in.tiledScanInputFolder '/']);
else
    tiledScanInputFolder = awsModifyPathForCompetability(in.tiledScanInputFolder);
end

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
if v
    fprintf('  Found %d OCT folders to check for unzipping\n', totalFolders);
end

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
preservedFiles = {};  % Track preserved .oct file paths

for i = 1:totalFolders
    switch unzipStatus{i}
        case 'already'
            alreadyUnzipped{end+1} = json.octFolders{i}; %#ok<AGROW>
            
        case 'success'
            successfullyUnzipped{end+1} = json.octFolders{i}; %#ok<AGROW>
            
        case {'failed', 'not_found'}
            failedToUnzip{end+1} = json.octFolders{i}; %#ok<AGROW>
            failedErrorMessages{end+1} = errorMessages{i}; %#ok<AGROW>
            if ~isempty(preservedOctFiles{i})
                preservedFiles{end+1} = preservedOctFiles{i}; %#ok<AGROW>
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
    fprintf('\n========================================\n');
    fprintf('         UNZIP SUMMARY REPORT\n');
    fprintf('========================================\n');
    fprintf('Total OCT folders:       %d\n', totalFolders);
    fprintf('Already unzipped:        %d\n', length(alreadyUnzipped));
    fprintf('Successfully unzipped:   %d\n', length(successfullyUnzipped));
    fprintf('Failed to unzip:         %d\n', length(failedToUnzip));
    fprintf('========================================\n\n');
end

%% Show warning with failures (always shown, regardless of verbose)
if ~isempty(failedToUnzip)
    % Build detailed warning message using string concatenation to avoid sprintf escape issues
    warningMsg = [newline 'FAILED to unzip (' num2str(length(failedToUnzip)) ' folders):'];
    for i = 1:length(failedToUnzip)
        warningMsg = [warningMsg newline '  ' num2str(i) '. ' failedToUnzip{i}]; %#ok<AGROW>
        if ~isempty(failedErrorMessages{i})
            warningMsg = [warningMsg newline '     Error: ' failedErrorMessages{i}]; %#ok<AGROW>
        end
        % Add failed file path if available
        if ~isempty(preservedFiles) && i <= length(preservedFiles) && ~isempty(preservedFiles{i})
            warningMsg = [warningMsg newline '     ' preservedFiles{i}]; %#ok<AGROW>
        end
    end
    warningMsg = [warningMsg newline newline];  % Add spacing at the end
    warning('yOCTUnzipTiledScan:FailedToUnzip', '%s', warningMsg);
end

end
