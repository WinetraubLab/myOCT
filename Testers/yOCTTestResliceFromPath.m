% Prompt for a tif file or tif stack folder and reslice it.
% This script keeps the chosen output path as-is and does not clear or
% delete existing output files or folders.

inputPath = input('Enter the path to a yOCT tif file or tif stack folder: ', 's');
inputPath = strtrim(inputPath);
if numel(inputPath) >= 2 && ((inputPath(1) == '"' && inputPath(end) == '"') || (inputPath(1) == '''' && inputPath(end) == ''''))
    inputPath = inputPath(2:end-1);
end

outputPath = input('Enter output file or folder path, or leave empty to keep the result in memory: ', 's');
outputPath = strtrim(outputPath);
if numel(outputPath) >= 2 && ((outputPath(1) == '"' && outputPath(end) == '"') || (outputPath(1) == '''' && outputPath(end) == ''''))
    outputPath = outputPath(2:end-1);
end

if isempty(inputPath)
    error('No input path provided.');
end

if ~isfolder(inputPath) && ~isfile(inputPath)
    error('Path does not exist: %s', inputPath);
end

if ~isempty(outputPath) && (isfolder(outputPath) || isfile(outputPath))
    error('Output path already exists. Choose a new output file or folder: %s', outputPath);
end

[~, dimensions] = yOCTFromTif(inputPath, 'isLoadMetadataOnly', true);

if isempty(dimensions) || ~isfield(dimensions, 'x') || ~isfield(dimensions, 'y') || ~isfield(dimensions, 'z')
    error('Unable to read dimensions metadata from: %s', inputPath);
end

x1_n = dimensions.x.values;
y1_n = dimensions.y.values;
z1_n = dimensions.z.values;

% Use the volume's native orientation so the output should match the input shape.
resliceNormal = [0; 1; 0];

resliceArgs = {'dimensions', dimensions, 'verbose', true, 'clearOutputFileOrFolderIfExists', false};
if ~isempty(outputPath)
    resliceArgs = [resliceArgs, {'outputFileOrFolder', outputPath}];
end

[reslicedVolume, xyzNew2Original, dimensions_n] = yOCTReslice(...
    inputPath, ...
    resliceNormal, ...
    x1_n, ...
    y1_n, ...
    z1_n, ...
    resliceArgs{:});

fprintf('Reslice completed successfully.\n');
fprintf('Input path: %s\n', inputPath);
if isempty(outputPath)
    fprintf('Output size: [%s]\n', num2str(size(reslicedVolume)));
else
    fprintf('Output saved to: %s\n', outputPath);
end
fprintf('Output x/y/z lengths: %d / %d / %d\n', ...
    length(dimensions_n.x.values), length(dimensions_n.y.values), length(dimensions_n.z.values));

samplePoint = xyzNew2Original(0, 0, 0);
fprintf('Center maps to original coordinates: [%g %g %g]\n', samplePoint(1), samplePoint(2), samplePoint(3));