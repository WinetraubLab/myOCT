% This script runs all tests in this library

% Get the path of the current script
currentScriptPath = fileparts(mfilename('fullpath'));

% Create a test suite including all tests except "test_all" in the current folder and its subfolders
testSuite = matlab.unittest.TestSuite.fromFolder(currentScriptPath, 'IncludingSubfolders', true);

% Remove 'test_all' tests from the suite
testFilter = @(test) ~strcmp(test.ProcedureName, 'test_all');
testSuite = testSuite(arrayfun(testFilter, testSuite));

% Get the number of tests
numTests = numel(testSuite);

% Initialize an array to store the results
results(numTests) = matlab.unittest.TestResult;

% Initialize the progress character bar
progressChar = repelem(' ', 50);  % Adjustable length of progress bar
fprintf('Progress: [%s]', progressChar);
backspace = repmat('\b', 1, length(progressChar) + 1);

% Loop over the test suite and run each test while updating the text progress bar
for k = 1:numTests
    % Update the progress bar
    progress = floor(k / numTests * length(progressChar));
    progressChar(1:progress) = '#';
    fprintf([backspace, progressChar]);
    
    % Run the next test
    results(k) = run(testSuite(k));
end

% Complete the progress bar
fprintf('\nDone!\n');

% Display the results
disp(results);
assert(all([results.Passed]),'Some test failed');