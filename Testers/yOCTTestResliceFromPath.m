% Prompt for a tif file or tif stack folder and run yOCTReslice on it.
% This is meant as a quick verification script for path-based reslicing.

inputPath = input('Enter the path to a yOCT tif file or tif stack folder: ', 's');
inputPath = strtrim(inputPath);

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

[reslicedVolume, xyzNew2Original, dimensions_n] = yOCTReslice(...
    inputPath, ...
    resliceNormal, ...
    x1_n, ...
    y1_n, ...
    z1_n, ...
    'dimensions', dimensions, ...
    'verbose', true);

fprintf('Reslice completed successfully.\n');
fprintf('Input path: %s\n', inputPath);
fprintf('Output size: [%s]\n', num2str(size(reslicedVolume)));
fprintf('Output x/y/z lengths: %d / %d / %d\n', ...
    length(dimensions_n.x.values), length(dimensions_n.y.values), length(dimensions_n.z.values));

samplePoint = xyzNew2Original(0, 0, 0);
fprintf('Center maps to original coordinates: [%g %g %g]\n', samplePoint(1), samplePoint(2), samplePoint(3));