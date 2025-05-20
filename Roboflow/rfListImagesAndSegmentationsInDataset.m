function [imageFilePath, imageMaskPath, imagePhase] = ...
    rfListImagesAndSegmentationsInDataset(roboflowDatasetFolder, maskLabel)
% This function loads the dataset that was downloaded using
% rfDownloadDataset, lists all the image paths and creates a label mask
%
% INPUTS:
%   roboflowDatasetFolder: see rfDownloadDataset.
%   maskLabel: name of the label to create a mask for.
%
% OUTPUT:
%   imageFilePath: path to the image.
%   imageMaskPath: path to the label (white - label, black - no label).
%   imagePhase: 0 - train, 1 - test, 2 - validate.


%% Get category ID from maskLabel
function categoryId = getCategoryIdFromMask( ...
    roboflowDatasetFolder, maskLabel)

    annotations_file = fullfile(roboflowDatasetFolder, 'train', '_annotations.coco.json');
    annotations_data = jsondecode(fileread(annotations_file));
    
    % Identify the category ID for the "above-tissue" label
    categoryId = -1;  % initialize
    for i = 1:length(annotations_data.categories)
        if strcmp(annotations_data.categories(i).name, maskLabel)
            categoryId = annotations_data.categories(i).id;
            break;
        end
    end
    
    if categoryId == -1
        error('Category "%s" not found!',maskLabel);
    end
end
categoryId = getCategoryIdFromMask(roboflowDatasetFolder, maskLabel);

%% Create data structures to output
imageFilePath = {};
imageMaskPath = {};
imagePhase = [];

%% Loop over all images in training

function processPhase(phaseName)
    annotations_file = fullfile(roboflowDatasetFolder, phaseName, '_annotations.coco.json');
    annotations_data = jsondecode(fileread(annotations_file));
    
    for j = 1:length(annotations_data.images)
        imageInfo = annotations_data.images(j);
        binaryMask = createBinaryMask(imageInfo, annotations_data.annotations, categoryId);
    
        % Save binary mask
        [~, imageName, ~] = fileparts(imageInfo.file_name);
        maskFilename = fullfile(roboflowDatasetFolder, phaseName, [imageName, '_mask.png']);
        imwrite(binaryMask, maskFilename);
    
        imageFilePath{end+1} = fullfile(...
            roboflowDatasetFolder, phaseName, imageInfo.file_name); %#ok<*AGROW>
        imageMaskPath{end+1} = fullfile(...
            roboflowDatasetFolder, phaseName, [imageName, '_mask.png']);
        switch(phaseName)
            case 'train'
                imagePhase(end+1)=0;
            case 'test'
                imagePhase(end+1)=1;
            case 'validate'
                imagePhase(end+1)=2;
        end
    
    end
end
processPhase('train');

end
%% Helper function to create a mask from categoryID
function binary_mask = createBinaryMask(imageInfo, annotations, categoryId)
    img_height = imageInfo.height;
    img_width = imageInfo.width;

    binary_mask = false(img_height, img_width);

    % Find annotations that belong to this image and specified category
    for k = 1:length(annotations)
        ann = annotations(k);
        if ann.image_id == imageInfo.id && ann.category_id == categoryId
            if ~iscell(ann.segmentation)
                ann.segmentation = {ann.segmentation}; % One class case
            end
            for seg = ann.segmentation
                coords = reshape(seg{:}, 2, [])';
                mask = poly2mask(coords(:,1), coords(:,2), img_height, img_width);
                binary_mask = binary_mask | mask; % combine masks
            end
        end
    end
end
