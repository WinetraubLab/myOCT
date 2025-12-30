function [data, isValid, loadTime] = yOCTLoadInterfFromFile_ReadFile(filePath, expectedSize, readFunction, fileExtension, callerName)
% Helper function to safely read OCT data files with validation
% This function provides consistent error handling across all OCT file loaders
% Creates datastore internally and handles all file validation
%
% INPUTS:
%   filePath      - Full path to the file to read
%   expectedSize  - Expected size of data array [rows, cols] or total elements
%   readFunction  - ReadFcn for imageDatastore/fileDatastore (e.g., @(a)(double(DSRead(a,'short'))))
%   fileExtension - File extension for datastore (e.g., '.data', '.srr')
%   callerName    - Name of calling function for warning messages (e.g., 'ThorlabsData')
%
% OUTPUTS:
%   data      - Data read from file, or NaN array of expectedSize if read failed
%   isValid   - true if file read successfully, false if corrupted/missing
%   loadTime  - Time taken to perform read operation (seconds)
%
% VALIDATION CHECKS:
%   1. File existence (fast-fail before expensive datastore creation)
%   2. Datastore creation and read (try/catch for corruption/format errors)
%   3. Non-empty result (detect empty/corrupted reads)
%   4. Size validation (prevent reshape errors)

% Start timing
tic;

% Initialize output
data = [];
isValid = true;

% Convert expectedSize to total element count if given as array
if numel(expectedSize) > 1
    expectedSize = prod(expectedSize);
end

% Check 1: File existence (fast-fail before creating datastore)
if ~isfile(filePath)
    warning(['yOCTLoadInterfFromFile_' callerName ':FileMissing'], ...
        'File does not exist: %s. Replacing with NaN data.', filePath);
    data = nan(expectedSize, 1);
    isValid = false;
    loadTime = toc;
    return;
end

% Check 2: Create datastore and attempt read with error handling
try
    ds = imageDatastore(filePath, 'ReadFcn', readFunction, 'FileExtensions', fileExtension);
    data = ds.read();
catch ME
    % Datastore creation failed or read error (binary corruption, file locks, format errors, etc.)
    warning(['yOCTLoadInterfFromFile_' callerName ':ReadError'], ...
        'Error creating datastore or reading file: %s. Error: %s. Replacing with NaN data.', ...
        filePath, ME.message);
    data = nan(expectedSize, 1);
    isValid = false;
    loadTime = toc;
    return;
end

% Check 3: Validate read returned data
if isempty(data)
    warning(['yOCTLoadInterfFromFile_' callerName ':EmptyFile'], ...
        'File read returned empty data: %s. Replacing with NaN data.', filePath);
    data = nan(expectedSize, 1);
    isValid = false;
    loadTime = toc;
    return;
end

% Check 4: Validate file size matches expectations
actualSize = numel(data);
if actualSize ~= expectedSize
    warning(['yOCTLoadInterfFromFile_' callerName ':IncorrectSize'], ...
        'File has incorrect size: %s. Expected %d elements, got %d. Replacing with NaN data.', ...
        filePath, expectedSize, actualSize);
    data = nan(expectedSize, 1);
    isValid = false;
    loadTime = toc;
    return;
end

% All checks passed
loadTime = toc;

end
