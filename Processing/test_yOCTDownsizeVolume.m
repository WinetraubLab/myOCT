classdef test_yOCTDownsizeVolume < matlab.unittest.TestCase
    properties
        TestFolder
        InputFile
        OutputFile
    end

    methods(TestMethodSetup)
        function createFolders(testCase)
            testCase.TestFolder = fullfile(pwd, 'downsize_volume_tester');
            if exist(testCase.TestFolder, 'dir')
                rmdir(testCase.TestFolder, 's');
            end
            mkdir(testCase.TestFolder);

            testCase.InputFile = fullfile(testCase.TestFolder, 'input.tif');
            testCase.OutputFile = fullfile(testCase.TestFolder, 'output.tif');
        end
    end

    methods(TestMethodTeardown)
        function removeTestFolder(testCase)
            if exist(testCase.TestFolder, 'dir')
                rmdir(testCase.TestFolder, 's');
            end
        end
    end

    methods(Test)
        function testDownsizeFactorTwo(testCase)
            % Create a small deterministic volume: (z,x,y)
            data = reshape(linspace(0, 1, 4 * 6 * 8), [4, 6, 8]);

            meta.x.values = (1:6) * 1e-6;
            meta.x.index = 1:6;
            meta.x.units = 'meters';
            meta.y.values = (1:8) * 1e-6;
            meta.y.index = 1:8;
            meta.y.units = 'meters';
            meta.z.values = (1:4) * 1e-6;
            meta.z.index = 1:4;
            meta.z.units = 'meters';

            yOCT2Tif(data, testCase.InputFile, 'metadata', meta);

            yOCTDownsizeVolume(testCase.InputFile, testCase.OutputFile, 2);

            xI = 1:2:6;
            yI = 1:2:8;
            zI = 1:2:4;

            expected = yOCTFromTif(testCase.InputFile, 'xI', xI, 'yI', yI, 'zI', zI);
            actual = yOCTFromTif(testCase.OutputFile);

            testCase.assertEqual(size(actual), size(expected), 'Output size mismatch');

            maxDiff = max(abs(actual(:) - expected(:)));
            testCase.assertLessThanOrEqual(maxDiff, 1 / 255, 'Downsized data mismatch');

            [~, metaOut] = yOCTFromTif(testCase.OutputFile, 'isLoadMetadataOnly', true);
            testCase.assertEqual(length(metaOut.x.index), numel(xI), 'x metadata size mismatch');
            testCase.assertEqual(length(metaOut.y.index), numel(yI), 'y metadata size mismatch');
            testCase.assertEqual(length(metaOut.z.index), numel(zI), 'z metadata size mismatch');
        end
    end
end
