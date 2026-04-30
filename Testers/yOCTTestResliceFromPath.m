% Prompt for a tif file or tif stack folder and run yOCTReslice on it.
% This is meant as a quick verification script for path-based reslicing.

inputPath = input('Enter the path to a yOCT tif file or tif stack folder: ', 's');
inputPath = strtrim(inputPath);

outputPath = input('Enter output file/folder (leave empty to keep in memory): ', 's');
outputPath = strtrim(outputPath);

if isempty(inputPath)
    error('No input path provided.');
end

if ~isfolder(inputPath) && ~isfile(inputPath)
    error('Path does not exist: %s', inputPath);
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

if isempty(outputPath)
    [reslicedVolume, xyzNew2Original, dimensions_n] = yOCTReslice(...
        inputPath, ...
        resliceNormal, ...
        x1_n, ...
        y1_n, ...
        z1_n, ...
        'dimensions', dimensions, ...
        'verbose', true);
else
    [reslicedVolume, xyzNew2Original, dimensions_n] = yOCTReslice(...
        inputPath, ...
        resliceNormal, ...
        x1_n, ...
        y1_n, ...
        z1_n, ...
        'dimensions', dimensions, ...
        'outputFileOrFolder', outputPath, ...
        'verbose', true);
end

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