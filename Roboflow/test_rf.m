classdef test_rf < matlab.unittest.TestCase

    methods (Test)

        function testLoadDatasetAndListImages(testCase)
            % Load a known dataset and get images

            rfFolder = rfDownloadDataset('tissue-surface','outputFolder','./temp/');
            [imageFilePath, imageMaskPath, imagePhase] = ...
                rfListImagesAndSegmentationsInDataset(rfFolder,'above-tissue');

            % Check output
            assert(~isempty(imageFilePath))
            assert(length(imageFilePath) == length(imageMaskPath));
            assert(length(imageFilePath) == length(imagePhase));
            assert(any(imagePhase==0)); % Make sure some training images exist
            assert(exist(imageFilePath{1},'file')); % Make sure files exist.
            assert(exist(imageMaskPath{1},'file')); % Make sure files exist.
        end
    end
end
