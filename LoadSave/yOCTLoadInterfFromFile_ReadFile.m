function [data, isValid] = yOCTLoadInterfFromFile_ReadFile(filePath, expectedSize, readFunction, callerName)
% Helper function to safely read OCT data files with validation
% This function provides consistent error handling across all OCT file loaders
%
% INPUTS:
%   filePath     - Full path to the file to read
%   expectedSize - Expected size of data array [rows, cols] or total elements
%   readFunction - Function handle to read the file (e.g., ds.read))
%   callerName   - Name of calling function for warning messages (e.g., 'ThorlabsData')
%
% OUTPUTS:
%   data    - Data read from file, or NaN array of expectedSize if read failed
%   isValid - true if file read successfully, false if corrupted/missing
%
% VALIDATION CHECKS:
%   1. File existence (fast-fail before expensive read operations)
%   2. Read operation success (try/catch for unexpected errors)
%   3. Non-empty result (detect empty/corrupted reads)
%   4. Size validation (prevent reshape errors)

% Initialize output
data = [];
isValid = true;

% Convert expectedSize to total element count if given as array
if numel(expectedSize) > 1
    expectedSize = prod(expectedSize);
end

% Check 1: File existence (fast-fail)
if ~isfile(filePath)
    warning(['yOCTLoadInterfFromFile_' callerName ':FileMissing'], ...
        'File does not exist: %s. Replacing with NaN data.', filePath);
    data = nan(expectedSize, 1);
    isValid = false;
    return;
end

% Check 2: Attempt to read file with error handling
try
    data = readFunction();
catch ME
    % Unexpected read error (binary corruption, file locks, etc.)
    warning(['yOCTLoadInterfFromFile_' callerName ':ReadError'], ...
        'Unexpected error reading file: %s. Error: %s. Replacing with NaN data.', ...
        filePath, ME.message);
    data = nan(expectedSize, 1);
    isValid = false;
    return;
end

% Check 3: Validate read returned data
if isempty(data)
    warning(['yOCTLoadInterfFromFile_' callerName ':EmptyFile'], ...
        'File read returned empty data: %s. Replacing with NaN data.', filePath);
    data = nan(expectedSize, 1);
    isValid = false;
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
    return;
end

end
