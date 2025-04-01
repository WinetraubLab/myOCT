classdef test_yOCTTestLoadSaveTif < matlab.unittest.TestCase
    %======================================================================%
    %  test_yOCTTestLoadSaveTif class tests yOCT2Tif / yOCTFromTif
    %======================================================================%
    %
    %  This script tests loading and saving of TIF files. It does:
    %    - Bit-conversion
    %    - 2D, 3D data read/write
    %    - Partial file modes (initialize, iterative save, finalize)
    %    - Metadata handling
    %    - File/folder usage
    %
    %======================================================================%
    properties
        % Tester will store these for each test
        TestFolder   % temporary folder path
        LocalFile    % something like <TestFolder>/tmp.tif
        LocalFolder  % something like <TestFolder>/tmp_folder
        Data         % the 3D data for testing
        Meta         % the metadata
    end

    %======================================================================
    %   SETUP:  create data & define test folders/files (locally) --------
    %======================================================================
    methods(TestMethodSetup)
        function createDataAndFolders(testCase)
            % Define data for this plane
            data = rand(256,256,5);
            data(:,:,2) = data(:,:,2) + 2;
            data(:,:,3) = -data(:,:,3);
            data(:,:,4) = -data(:,:,4) - 2;
            data(:,:,5) = 10 * data(:,:,5);

            testCase.Data = data;
            meta.mymeta = (1:10)';
            testCase.Meta = meta;

            % Create fresh local test folder under current dir
            testCase.TestFolder = fullfile(pwd, 'load_save_tester');
            if exist(testCase.TestFolder, 'dir')
                rmdir(testCase.TestFolder, 's'); % remove old
            end
            mkdir(testCase.TestFolder);

            % Define local file & folder inside the test folder
            testCase.LocalFile   = fullfile(testCase.TestFolder, 'tmp.tif');
            testCase.LocalFolder = fullfile(testCase.TestFolder, 'tmp_folder');

            % Clean up if they exist
            if exist(testCase.LocalFile, 'file')
                delete(testCase.LocalFile);
            end
            if exist(testCase.LocalFolder, 'dir')
                rmdir(testCase.LocalFolder, 's');
            end
        end
    end

    methods(TestMethodTeardown)
        function removeTestFolder(testCase)
            % Always remove the test folder
            if exist(testCase.TestFolder, 'dir')
                rmdir(testCase.TestFolder, 's');
            end
        end
    end

    %======================================================================
    %   TEST METHODS
    %======================================================================
    methods(Test)

        function testBitConversion(testCase)
            fprintf('\nRunning testBitConversion...\n');

            % 1) Test bit conversion
            r1 = rand(10);
            c  = [0 1];
            r2 = yOCT2Tif_ConvertBitsData(...
                     yOCT2Tif_ConvertBitsData(r1, c, false), ...
                     c, true);
            testCase.assertLessThanOrEqual( ...
                max(abs(r1(:)-r2(:))), ...
                2^-14, ...
                'Bit conversion test #1 failed');

            % 2) Another check
            r1 = [0, 2, 2^(16-1)-1];
            c = [0, 2^(16-1)-1];
            r2 = yOCT2Tif_ConvertBitsData(...
                     yOCT2Tif_ConvertBitsData(r1, c, false), ...
                     c, true);
            testCase.assertEqual( ...
                max(abs(r2 - r1)), ...
                0, ...
                'Bit conversion test #2 failed');

            % 3) NaN check
            isNaNIn = isnan(yOCT2Tif_ConvertBitsData(NaN, c, false));
            isNaNOut = ~isnan(yOCT2Tif_ConvertBitsData( ...
                         yOCT2Tif_ConvertBitsData(NaN, c, false), c, true));
            testCase.assertFalse(isNaNIn,  'NaN conversion in-phase failed');
            testCase.assertFalse(isNaNOut, 'NaN re-conversion out-phase failed');

            fprintf('testBitConversion completed successfully.\n');
        end

        function testBasicTifWriteRead(testCase)
            fprintf('\nRunning testBasicTifWriteRead...\n');

            data = testCase.Data;
            fp_localFile = testCase.LocalFile;

            % Basic TIF write
            yOCT2Tif(data, fp_localFile);

            % Basic read subsets
            data_ = yOCTFromTif(fp_localFile, 'yI',1:2, 'xI',1:3, 'zI',1:4);
            testCase.assertLessThan( ...
                max(max(max(abs(data(1:4,1:3,1:2) - data_)))), ...
                1e-3, ...
                'From Tif test failed #1');

            data_ = yOCTFromTif(fp_localFile, 'yI',1:2, 'xI',3, 'zI',1:4);
            testCase.assertLessThan( ...
                max(max(max(abs(data(1:4,3,1:2) - data_)))), ...
                1e-3, ...
                'From Tif test failed #2');

            fprintf('testBasicTifWriteRead completed successfully.\n');
        end

        function testTifFile(testCase)
            fprintf('\nRunning testTifFile...\n');

            data = testCase.Data;
            meta = testCase.Meta;
            fp_localFile = testCase.LocalFile;

            % =============== 2D tests ===============
            testCase.LoadReadSeeItsTheSame(data(:,:,1), fp_localFile, [], [], 0, [], [], false);
            testCase.LoadReadSeeItsTheSame(data(:,:,1), fp_localFile);

            % =============== 3D tests ===============
            testCase.LoadReadSeeItsTheSame(data,         fp_localFile);
            testCase.LoadReadSeeItsTheSame(data,         fp_localFile, [], [], 0, 0, 2:3);

            % =============== 2D with metadata ===============
            testCase.LoadReadSeeItsTheSame(data(:,:,1),  fp_localFile, meta);

            fprintf('testTifFile completed successfully.\n');
        end

        function testTifFolder(testCase)
            fprintf('\nRunning testTifFolder...\n');

            data = testCase.Data;
            meta = testCase.Meta;
            fp_localFolder = testCase.LocalFolder;

            % =============== 3D tests ===============
            testCase.LoadReadSeeItsTheSame(data,         fp_localFolder, [], [], 0, [], [], false);
            testCase.LoadReadSeeItsTheSame(data,         fp_localFolder);
            testCase.LoadReadSeeItsTheSame(data,         fp_localFolder, [], [], 0, 0, 2:3);

            % =============== 2D with metadata ===============
            testCase.LoadReadSeeItsTheSame(data(:,:,1),  fp_localFolder, meta);

            fprintf('testTifFolder completed successfully.\n');
        end

        function testSaveBothOutputs(testCase)
            fprintf('\nRunning testSaveBothOutputs...\n');

            data = testCase.Data;
            fp_localFolder = testCase.LocalFolder;
            fp_localFile   = testCase.LocalFile;

            % Save 3D to both folder + file
            testCase.LoadReadSeeItsTheSame(data, {fp_localFolder, fp_localFile});

            fprintf('testSaveBothOutputs completed successfully.\n');
        end

        function testPartialSaveLocal(testCase)
            fprintf('\nRunning testPartialSaveLocal...\n');

            data = testCase.Data;
            fp_localFolder = testCase.LocalFolder;
            fp_localFile   = testCase.LocalFile;

            % 1) Partial save to a folder
            testCase.LoadReadSeeItsTheSame([], fp_localFolder, [], [], 1, []);
            testCase.LoadReadSeeItsTheSame(data(:,:,1), fp_localFolder, [], [], 2, 1);
            testCase.LoadReadSeeItsTheSame(data(:,:,2), fp_localFolder, [], [], 2, 2);
            testCase.LoadReadSeeItsTheSame(data(:,:,1:2), fp_localFolder, [], [], 3, [], []);

            % 2) Partial save to a single file
            testCase.LoadReadSeeItsTheSame([], fp_localFile, [], [], 1, []);
            testCase.LoadReadSeeItsTheSame(data(:,:,1), fp_localFile, [], [], 2, 1);
            testCase.LoadReadSeeItsTheSame(data(:,:,2), fp_localFile, [], [], 2, 2);
            testCase.LoadReadSeeItsTheSame(data(:,:,1:2), fp_localFile, [], [], 3, [], []);

            % 3) Partial save to both (folder + file)
            testCase.LoadReadSeeItsTheSame([], {fp_localFolder, fp_localFile}, [], [], 1, []);
            for i = 1:size(data,3)
                testCase.LoadReadSeeItsTheSame(data(:,:,i), {fp_localFolder, fp_localFile}, [], [], 2, i);
            end
            testCase.LoadReadSeeItsTheSame(data, {fp_localFolder, fp_localFile}, 3, []);

            fprintf('testPartialSaveLocal completed successfully.\n');
        end

    end  % methods(Test)

    %======================================================================
    %   PRIVATE HELPER METHODS
    %======================================================================
    methods(Access = private)
        function LoadReadSeeItsTheSame(testCase, data, filePath, meta, clim, ...
                                       partialFileMode, partialFileModeIndex, ...
                                       loadYIndex, isClearFilesWhenDone)
            % Utility function that saves data to TIF (yOCT2Tif),
            % loads it back (yOCTFromTif), and compares.

            if ~exist('meta','var') || isempty(meta),   meta = []; end
            if ~exist('clim','var') || isempty(clim),   clim = []; end
            if ~exist('partialFileMode','var'),         partialFileMode = 0; end
            if ~exist('partialFileModeIndex','var'),    partialFileModeIndex = 0; end
            if ~exist('loadYIndex','var'),              loadYIndex = []; end
            if ~exist('isClearFilesWhenDone','var') || isempty(isClearFilesWhenDone)
                isClearFilesWhenDone = true;
            end

            % Save
            yOCT2Tif(data, filePath, ...
                     'metadata',           meta, ...
                     'clim',               clim, ...
                     'partialFileMode',    partialFileMode, ...
                     'partialFileModeIndex', partialFileModeIndex);

            % If partial mode = 1 or 2, skip loading/comparing
            if partialFileMode == 1 || partialFileMode == 2
                return;
            end

            % Gather file paths in a cell array
            if ~iscell(filePath)
                filePaths = {filePath};
            else
                filePaths = filePath;
            end

            % Loop over each filePath to load & compare
            for i=1:length(filePaths)
                thisPath = filePaths{i};

                if isempty(loadYIndex)
                    [data_, meta_] = yOCTFromTif(thisPath);
                else
                    % Load only specified Y-planes
                    [data_, meta_] = yOCTFromTif(thisPath, 'yI', loadYIndex);
                    data = data(:,:,loadYIndex); 
                end

                % Compare data
                tolerance = 2^-(16-1-4);  % ~1/256
                diffVal = max(abs(data(:) - data_(:)));
                testCase.assertLessThanOrEqual( ...
                    diffVal, tolerance, ...
                    sprintf('Saving data not lossless! Path=%s', thisPath));

                % Compare metadata
                if ~isempty(meta)
                    testCase.assertEqual(meta_, meta, ...
                        'Metadata does not match the original!');
                end

                % Cleanup if needed
                if isClearFilesWhenDone
                    if exist(thisPath, 'file')
                        delete(thisPath);
                    elseif exist(thisPath, 'dir')
                        rmdir(thisPath, 's');
                    end
                else
                    fprintf('Not cleaning up after: %s\n', thisPath);
                end
            end
        end
    end

end
