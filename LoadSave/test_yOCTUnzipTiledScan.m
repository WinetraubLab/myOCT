classdef test_yOCTUnzipTiledScan < matlab.unittest.TestCase
    % Test yOCTUnzipTiledScan functionality with various edge cases
    
    properties
        testDir          % Temporary directory for test files
        dummyOctContent  % Simulated .oct file content
        headerXmlContent % Sample Header.xml content
        dummyDataContent % Sample Spectral data file content
    end
    
    methods(TestMethodSetup)
        function createTestEnvironment(testCase)
            % Create a temporary test directory
            testCase.testDir = fullfile(tempdir, ['test_yOCTUnzip_' datestr(now, 'yyyymmdd_HHMMSS')]);
            mkdir(testCase.testDir);
            
            % Create dummy content for files
            % .oct files are just compressed archives, we'll create a minimal dummy
            testCase.dummyOctContent = uint8(randi([0 255], 1, 1000)); % Random bytes
            
            % Create a minimal but valid Header.xml
            testCase.headerXmlContent = sprintf(...
                ['<?xml version="1.0" encoding="UTF-8"?>\n' ...
                 '<Ocity version="1.0">\n' ...
                 '    <DataFiles>\n' ...
                 '        <DataFile Type="Raw" SizeZ="2048" SizeX="10" RangeZ="2.0" RangeX="0.5" RangeY="0.5" BytesPerPixel="2">data\\Spectral0.data</DataFile>\n' ...
                 '    </DataFiles>\n' ...
                 '</Ocity>\n']);
            
            % Create dummy spectral data
            testCase.dummyDataContent = uint16(randi([0 65535], 500, 10)); % 500 x 10 pixels
        end
    end
    
    methods(TestMethodTeardown)
        function cleanupTestEnvironment(testCase)
            % Remove the temporary test directory
            if exist(testCase.testDir, 'dir')
                rmdir(testCase.testDir, 's');
            end
        end
    end
    
    methods(Test)
        function testAllScenarios(testCase)
            % Main test that verifies:
            % - Data01: Intentionally skipped (not in filesystem, but in JSON list)
            % - Data02: Normal case: it has .oct file so it should unzip successfully
            % - Data03: This has .oct + incomplete data folder (no Header.xml): should alert missing header
            % - Data04: Already fully unzipped: this should skip
            % - Data05: Only unzipped data and no .oct: this should be marked as already unzipped
            
            % Create ScanInfo.json
            scanInfo = struct();
            scanInfo.octFolders = {'Data01', 'Data02', 'Data03', 'Data04', 'Data05'};
            scanInfo.octSystem = 'Ganymede';
            scanInfo.nXPixelsInEachTile = 10;
            scanInfo.nYPixelsInEachTile = 10;
            
            jsonPath = fullfile(testCase.testDir, 'ScanInfo.json');
            jsonText = jsonencode(scanInfo);
            fid = fopen(jsonPath, 'w');
            fprintf(fid, '%s', jsonText);
            fclose(fid);
            
            % Data01: This is intentually NOT created to test missing folder handling
            
            % Data02: Normal .oct file only
            data02Path = fullfile(testCase.testDir, 'Data02');
            mkdir(data02Path);
            octFile = fullfile(data02Path, 'VolumeGanymedeOCTFile.oct');
            testCase.createMockOctFile(octFile);
            
            % Data03: .oct file + incomplete data folder (no Header.xml)
            data03Path = fullfile(testCase.testDir, 'Data03');
            mkdir(data03Path);
            octFile03 = fullfile(data03Path, 'VolumeGanymedeOCTFile.oct');
            testCase.createMockOctFile(octFile03, false); % Create .oct without valid header
            mkdir(fullfile(data03Path, 'data')); % Also create partial data folder
            testCase.createDummySpectralFiles(fullfile(data03Path, 'data'), 3);
            
            % Data04: Fully unzipped (has Header.xml + data folder + .oct file)
            data04Path = fullfile(testCase.testDir, 'Data04');
            mkdir(data04Path);
            mkdir(fullfile(data04Path, 'data'));
            % Create Header.xml
            headerPath = fullfile(data04Path, 'Header.xml');
            fid = fopen(headerPath, 'w');
            fprintf(fid, '%s', testCase.headerXmlContent);
            fclose(fid);
            % Create some spectral data files
            testCase.createDummySpectralFiles(fullfile(data04Path, 'data'), 10);
            % Also include the .oct file simulating scenario where it wasn't deleted
            octFile04 = fullfile(data04Path, 'VolumeGanymedeOCTFile.oct');
            fid = fopen(octFile04, 'wb');
            fwrite(fid, testCase.dummyOctContent, 'uint8');
            fclose(fid);
            
            % Data05: Only unzipped data (no .oct file)
            data05Path = fullfile(testCase.testDir, 'Data05');
            mkdir(data05Path);
            mkdir(fullfile(data05Path, 'data'));
            % Create Header.xml
            headerPath05 = fullfile(data05Path, 'Header.xml');
            fid = fopen(headerPath05, 'w');
            fprintf(fid, '%s', testCase.headerXmlContent);
            fclose(fid);
            % Create spectral data
            testCase.createDummySpectralFiles(fullfile(data05Path, 'data'), 10);
            
            % Run yOCTUnzipTiledScan with verbose mode to test output
            results = yOCTUnzipTiledScan(testCase.testDir, ...
                'deleteCompressedAfterUnzip', false, ...
                'v', true);
            
            % Verify results
            testCase.verifyEqual(results.totalFolders, 5, ...
                'Should detect 5 total folders from ScanInfo.json');
            
            % Data04 and Data05 should be already unzipped
            testCase.verifyEqual(length(results.alreadyUnzipped), 2, ...
                'Should have 2 already unzipped folders');
            testCase.verifyTrue(ismember('Data04', results.alreadyUnzipped), ...
                'Data04 should be already unzipped');
            testCase.verifyTrue(ismember('Data05', results.alreadyUnzipped), ...
                'Data05 should be already unzipped');
            
            % Data02 should be successfully unzipped
            testCase.verifyEqual(length(results.successfullyUnzipped), 1, ...
                'Should have 1 newly unzipped folder');
            testCase.verifyTrue(ismember('Data02', results.successfullyUnzipped), ...
                'Data02 should be successfully unzipped');
            
            % Data01 and Data03 should fail
            testCase.verifyEqual(length(results.failed), 2, ...
                'Should have 2 failed folders');
            testCase.verifyTrue(ismember('Data01', results.failed), ...
                'Data01 should fail (not found)');
            testCase.verifyTrue(ismember('Data03', results.failed), ...
                'Data03 should fail (missing header after unzip)');
            
            % Verify error messages
            testCase.verifyEqual(length(results.errorMessages), 2, ...
                'Should have 2 error messages');
            
            % Check that warning was issued for failed folders
            testCase.verifyWarning(...
                @() yOCTUnzipTiledScan(testCase.testDir, 'deleteCompressedAfterUnzip', false, 'v', false), ...
                'yOCTUnzipTiledScan:FailedToUnzip');
        end
        
        function testEmptyOctFoldersList(testCase)
            % Test behavior when octFolders list is empty
            
            scanInfo = struct();
            scanInfo.octFolders = {};
            scanInfo.octSystem = 'Ganymede';
            
            jsonPath = fullfile(testCase.testDir, 'ScanInfo.json');
            jsonText = jsonencode(scanInfo);
            fid = fopen(jsonPath, 'w');
            fprintf(fid, '%s', jsonText);
            fclose(fid);
            
            % Should throw an error
            errorThrown = false;
            try
                yOCTUnzipTiledScan(testCase.testDir);
            catch
                errorThrown = true;
            end
            testCase.verifyTrue(errorThrown, 'Expected an error to be thrown for empty octFolders list');
        end
        
        function testMissingScanInfoJson(testCase)
            % Test behavior when ScanInfo.json doesn't exist
            % Don't create any files, just use empty testDir
            
            % Thus should throw an error
            errorThrown = false;
            try
                yOCTUnzipTiledScan(testCase.testDir);
            catch
                errorThrown = true;
            end
            testCase.verifyTrue(errorThrown, 'Expected an error to be thrown when ScanInfo.json is missing');
        end
        
        function testSingleFolderAlreadyUnzipped(testCase)
            % Test with a single folder that's already unzipped
            
            scanInfo = struct();
            scanInfo.octFolders = {'DataA'};
            scanInfo.octSystem = 'Ganymede';
            
            jsonPath = fullfile(testCase.testDir, 'ScanInfo.json');
            jsonText = jsonencode(scanInfo);
            fid = fopen(jsonPath, 'w');
            fprintf(fid, '%s', jsonText);
            fclose(fid);
            
            % Create already unzipped folder
            dataPath = fullfile(testCase.testDir, 'DataA');
            mkdir(dataPath);
            mkdir(fullfile(dataPath, 'data'));
            headerPath = fullfile(dataPath, 'Header.xml');
            fid = fopen(headerPath, 'w');
            fprintf(fid, '%s', testCase.headerXmlContent);
            fclose(fid);
            testCase.createDummySpectralFiles(fullfile(dataPath, 'data'), 5);
            
            results = yOCTUnzipTiledScan(testCase.testDir, 'v', false);
            
            testCase.verifyEqual(results.totalFolders, 1);
            testCase.verifyEqual(length(results.alreadyUnzipped), 1);
            testCase.verifyEqual(length(results.successfullyUnzipped), 0);
            testCase.verifyEqual(length(results.failed), 0);
        end
        
        function testSingleFolderNeedsUnzip(testCase)
            % Test with a single folder that needs to be unzipped
            
            scanInfo = struct();
            scanInfo.octFolders = {'DataB'};
            scanInfo.octSystem = 'Ganymede';
            
            jsonPath = fullfile(testCase.testDir, 'ScanInfo.json');
            jsonText = jsonencode(scanInfo);
            fid = fopen(jsonPath, 'w');
            fprintf(fid, '%s', jsonText);
            fclose(fid);
            
            % Create folder with .oct file
            dataPath = fullfile(testCase.testDir, 'DataB');
            mkdir(dataPath);
            octFile = fullfile(dataPath, 'VolumeGanymedeOCTFile.oct');
            testCase.createMockOctFile(octFile);
            
            results = yOCTUnzipTiledScan(testCase.testDir, ...
                'deleteCompressedAfterUnzip', false, ...
                'v', false);
            
            testCase.verifyEqual(results.totalFolders, 1);
            testCase.verifyEqual(length(results.alreadyUnzipped), 0);
            testCase.verifyEqual(length(results.successfullyUnzipped), 1);
            testCase.verifyEqual(length(results.failed), 0);
            
            % Verify Header.xml was created
            headerPath = fullfile(dataPath, 'Header.xml');
            testCase.verifyTrue(exist(headerPath, 'file') == 2, ...
                'Header.xml should exist after unzip');
        end
        
        function testVerboseOutput(testCase)
            % Test that verbose mode produces output the right way
            
            scanInfo = struct();
            scanInfo.octFolders = {'DataC'};
            scanInfo.octSystem = 'Ganymede';
            
            jsonPath = fullfile(testCase.testDir, 'ScanInfo.json');
            jsonText = jsonencode(scanInfo);
            fid = fopen(jsonPath, 'w');
            fprintf(fid, '%s', jsonText);
            fclose(fid);
            
            % Create already unzipped folder
            dataPath = fullfile(testCase.testDir, 'DataC');
            mkdir(dataPath);
            mkdir(fullfile(dataPath, 'data'));
            headerPath = fullfile(dataPath, 'Header.xml');
            fid = fopen(headerPath, 'w');
            fprintf(fid, '%s', testCase.headerXmlContent);
            fclose(fid);
            
            % This should not throw any errors
            results = yOCTUnzipTiledScan(testCase.testDir, 'v', true);
            
            testCase.verifyEqual(results.totalFolders, 1);
        end
        
        function testDeleteCompressedAfterUnzip(testCase)
            % Test that .oct files are deleted after successful unzip when requested
            
            scanInfo = struct();
            scanInfo.octFolders = {'DataDelete'};
            scanInfo.octSystem = 'Ganymede';
            
            jsonPath = fullfile(testCase.testDir, 'ScanInfo.json');
            jsonText = jsonencode(scanInfo);
            fid = fopen(jsonPath, 'w');
            fprintf(fid, '%s', jsonText);
            fclose(fid);
            
            % Create folder with .oct file
            dataPath = fullfile(testCase.testDir, 'DataDelete');
            mkdir(dataPath);
            octFile = fullfile(dataPath, 'VolumeGanymedeOCTFile.oct');
            testCase.createMockOctFile(octFile);
            
            % Verify .oct exists before unzip
            testCase.verifyTrue(exist(octFile, 'file') == 2, ...
                '.oct file should exist before unzip');
            
            % Run with deleteCompressedAfterUnzip = true
            results = yOCTUnzipTiledScan(testCase.testDir, ...
                'deleteCompressedAfterUnzip', true, ...
                'v', false);
            
            % Verify results
            testCase.verifyEqual(results.totalFolders, 1);
            testCase.verifyEqual(length(results.successfullyUnzipped), 1);
            
            % Verify .oct was deleted after successful unzip
            testCase.verifyFalse(exist(octFile, 'file') == 2, ...
                '.oct file should be deleted after successful unzip');
            
            % Verify Header.xml still exists (unzip was successful)
            headerPath = fullfile(dataPath, 'Header.xml');
            testCase.verifyTrue(exist(headerPath, 'file') == 2, ...
                'Header.xml should exist after unzip');
        end
        
        function testMalformedDataFolderStructure(testCase)
            % Test handling of malformed .oct files where 7Zip creates
            % files like "data·Spectral0.data" instead of "data\Spectral0.data"
            % This happens with some 7Zip versions when the file has
            % special directory separators (like a middle dot: ·)
            
            scanInfo = struct();
            scanInfo.octFolders = {'DataMalformed'};
            scanInfo.octSystem = 'Ganymede';
            
            jsonPath = fullfile(testCase.testDir, 'ScanInfo.json');
            jsonText = jsonencode(scanInfo);
            fid = fopen(jsonPath, 'w');
            fprintf(fid, '%s', jsonText);
            fclose(fid);
            
            % Create folder with malformed .oct file
            dataPath = fullfile(testCase.testDir, 'DataMalformed');
            mkdir(dataPath);
            octFile = fullfile(dataPath, 'VolumeGanymedeOCTFile.oct');
            testCase.createMalformedOctFile(octFile);
            
            % Run unzip
            results = yOCTUnzipTiledScan(testCase.testDir, ...
                'deleteCompressedAfterUnzip', false, ...
                'v', false);
            
            % Verify results
            testCase.verifyEqual(results.totalFolders, 1);
            testCase.verifyEqual(length(results.successfullyUnzipped), 1, ...
                'This should successfully unzip and fix malformed structure');
            
            % Verify proper data folder structure was created
            dataFolder = fullfile(dataPath, 'data');
            testCase.verifyTrue(exist(dataFolder, 'dir') == 7, ...
                'data folder should be created from malformed files');
            
            % Verify Header.xml is in correct location
            headerPath = fullfile(dataPath, 'Header.xml');
            testCase.verifyTrue(exist(headerPath, 'file') == 2, ...
                'Header.xml should exist in root folder');
            
            % Verify spectral files were moved into data folder
            spectralFile = fullfile(dataFolder, 'Spectral0.data');
            testCase.verifyTrue(exist(spectralFile, 'file') == 2, ...
                'Spectral files should be in data folder');
            
            % Verify no malformed files remain in root
            files = dir(dataPath);
            for i = 1:length(files)
                fname = files(i).name;
                % Check that no file starts with "data" followed by non-standard character
                if ~files(i).isdir && length(fname) > 4 && strcmp(fname(1:4), 'data')
                    if fname(5) ~= '.' && fname(5) ~= '_' && fname(5) ~= '-'
                        testCase.verifyFail(sprintf('Malformed file still exists: %s', fname));
                    end
                end
            end
        end
        
        function testParallelProcessingMultipleFolders(testCase)
            % Test that multiple folders can be processed in paralell
            % without conflicts or race conditions
            
            scanInfo = struct();
            scanInfo.octFolders = {'DataP1', 'DataP2', 'DataP3', 'DataP4', 'DataP5'};
            scanInfo.octSystem = 'Ganymede';
            
            jsonPath = fullfile(testCase.testDir, 'ScanInfo.json');
            jsonText = jsonencode(scanInfo);
            fid = fopen(jsonPath, 'w');
            fprintf(fid, '%s', jsonText);
            fclose(fid);
            
            % Create multiple folders, mix of states
            % DataP1: needs unzip
            dataP1Path = fullfile(testCase.testDir, 'DataP1');
            mkdir(dataP1Path);
            testCase.createMockOctFile(fullfile(dataP1Path, 'VolumeGanymedeOCTFile.oct'));
            
            % DataP2: already unzipped
            dataP2Path = fullfile(testCase.testDir, 'DataP2');
            mkdir(dataP2Path);
            mkdir(fullfile(dataP2Path, 'data'));
            fid = fopen(fullfile(dataP2Path, 'Header.xml'), 'w');
            fprintf(fid, '%s', testCase.headerXmlContent);
            fclose(fid);
            testCase.createDummySpectralFiles(fullfile(dataP2Path, 'data'), 3);
            
            % DataP3: needs unzip
            dataP3Path = fullfile(testCase.testDir, 'DataP3');
            mkdir(dataP3Path);
            testCase.createMockOctFile(fullfile(dataP3Path, 'VolumeGanymedeOCTFile.oct'));
            
            % DataP4: already unzipped
            dataP4Path = fullfile(testCase.testDir, 'DataP4');
            mkdir(dataP4Path);
            mkdir(fullfile(dataP4Path, 'data'));
            fid = fopen(fullfile(dataP4Path, 'Header.xml'), 'w');
            fprintf(fid, '%s', testCase.headerXmlContent);
            fclose(fid);
            testCase.createDummySpectralFiles(fullfile(dataP4Path, 'data'), 3);
            
            % DataP5: needs unzip
            dataP5Path = fullfile(testCase.testDir, 'DataP5');
            mkdir(dataP5Path);
            testCase.createMockOctFile(fullfile(dataP5Path, 'VolumeGanymedeOCTFile.oct'));
            
            % Run unzip
            results = yOCTUnzipTiledScan(testCase.testDir, ...
                'deleteCompressedAfterUnzip', false, ...
                'v', false);
            
            % Verify results
            testCase.verifyEqual(results.totalFolders, 5);
            testCase.verifyEqual(length(results.alreadyUnzipped), 2, ...
                'This should have 2 already unzipped folders');
            testCase.verifyEqual(length(results.successfullyUnzipped), 3, ...
                'This should have 3 newly unzipped folders');
            testCase.verifyEqual(length(results.failed), 0, ...
                'This should have no failures');
            
            % Verify all folders now have Header.xml
            for i = 1:length(scanInfo.octFolders)
                headerPath = fullfile(testCase.testDir, scanInfo.octFolders{i}, 'Header.xml');
                testCase.verifyTrue(exist(headerPath, 'file') == 2, ...
                    sprintf('Header.xml should exist for %s', scanInfo.octFolders{i}));
            end
        end
        
        function testMissingFolderOnly(testCase)
            % Test specific case where folder is in JSON but doesn't exist in filesystem
            
            scanInfo = struct();
            scanInfo.octFolders = {'DataMissing'};
            scanInfo.octSystem = 'Ganymede';
            
            jsonPath = fullfile(testCase.testDir, 'ScanInfo.json');
            jsonText = jsonencode(scanInfo);
            fid = fopen(jsonPath, 'w');
            fprintf(fid, '%s', jsonText);
            fclose(fid);
            
            % Intentionally don't create DataMissing folder
            
            % Run unzip
            testCase.verifyWarning(...
                @() yOCTUnzipTiledScan(testCase.testDir, 'v', false), ...
                'yOCTUnzipTiledScan:FailedToUnzip');
            
            results = yOCTUnzipTiledScan(testCase.testDir, 'v', false);
            
            % Verify results
            testCase.verifyEqual(results.totalFolders, 1);
            testCase.verifyEqual(length(results.failed), 1);
            testCase.verifyTrue(ismember('DataMissing', results.failed));
            
            % Verify error message
            testCase.verifyTrue(contains(results.errorMessages{1}, ...
                'Neither Header.xml nor VolumeGanymedeOCTFile.oct found'));
        end
    end
    
    methods(Access = private)
        function createMockOctFile(testCase, octFilePath, includeValidHeader)
            % Creates a mock .oct file that can be "unzipped" by yOCTUnzipOCTFolder
            % Since we're testing the logic, we'll create a minimal structure
            % includeValidHeader: if true, creates Header.xml inside archive (default: true)
            
            if nargin < 3
                includeValidHeader = true;
            end
            
            % Create a temporary folder to build the archive contents
            tempFolder = fullfile(tempdir, ['oct_temp_' datestr(now, 'yyyymmdd_HHMMSS_FFF')]);
            mkdir(tempFolder);
            mkdir(fullfile(tempFolder, 'data'));
            
            % Create Header.xml if requested
            if includeValidHeader
                headerPath = fullfile(tempFolder, 'Header.xml');
                fid = fopen(headerPath, 'w');
                fprintf(fid, '%s', testCase.headerXmlContent);
                fclose(fid);
            end
            
            % Create some dummy spectral data files
            testCase.createDummySpectralFiles(fullfile(tempFolder, 'data'), 5);
            
            % Create a zip file (7 Zip can extract .zip files too)
            % MATLAB's zip function creates a valid archive
            zipFile = [octFilePath '.zip'];
            zip(zipFile, '*', tempFolder);
            
            % Rename .zip to .oct
            if exist(octFilePath, 'file')
                delete(octFilePath);
            end
            movefile(zipFile, octFilePath);
            
            % Clean up temp folder
            rmdir(tempFolder, 's');
        end
        
        function createMalformedOctFile(testCase, octFilePath)
            % Creates a mock .oct file with malformed structure where files are named
            % like "dataSpectral0.data" (with middle dot ·) instead of being in "data\Spectral0.data"
            % This simulates older 7 Zip behavior or files with special directory separators
            
            % Create a temporary folder to build the archive contents
            tempFolder = fullfile(tempdir, ['oct_malformed_' datestr(now, 'yyyymmdd_HHMMSS_FFF')]);
            mkdir(tempFolder);
            
            % Create Header.xml in root (this is correct)
            headerPath = fullfile(tempFolder, 'Header.xml');
            fid = fopen(headerPath, 'w');
            fprintf(fid, '%s', testCase.headerXmlContent);
            fclose(fid);
            
            % Create files with malformed names using middle dot (·) character
            % Instead of: data\Chirp.data, data\Spectral0.data, etc.
            % Create: data·Chirp.data, data·Spectral0.data, etc.
            middleDot = char(183);  % Middle dot character: ·
            
            % Create malformed Chirp.data
            malformedChirpName = fullfile(tempFolder, ['data' middleDot 'Chirp.data']);
            fid = fopen(malformedChirpName, 'wb');
            fwrite(fid, testCase.dummyDataContent, 'uint16');
            fclose(fid);
            
            % Create malformed OffsetErrors.data
            malformedOffsetName = fullfile(tempFolder, ['data' middleDot 'OffsetErrors.data']);
            fid = fopen(malformedOffsetName, 'wb');
            fwrite(fid, testCase.dummyDataContent, 'uint16');
            fclose(fid);
            
            % Create malformed Spectral files
            for i = 0:4
                malformedSpectralName = fullfile(tempFolder, ...
                    ['data' middleDot sprintf('Spectral%d.data', i)]);
                fid = fopen(malformedSpectralName, 'wb');
                fwrite(fid, testCase.dummyDataContent, 'uint16');
                fclose(fid);
            end
            
            % Create a zip file
            zipFile = [octFilePath '.zip'];
            zip(zipFile, '*', tempFolder);
            
            % Rename .zip to .oct
            if exist(octFilePath, 'file')
                delete(octFilePath);
            end
            movefile(zipFile, octFilePath);
            
            % Clean up temp folder
            rmdir(tempFolder, 's');
        end
        
        function createDummySpectralFiles(testCase, dataFolder, numFiles)
            % Creates dummy Spectral*.data files in the specified folder
            % Always create Chirp.data and OffsetErrors.data
            chirpPath = fullfile(dataFolder, 'Chirp.data');
            fid = fopen(chirpPath, 'wb');
            fwrite(fid, testCase.dummyDataContent, 'uint16');
            fclose(fid);
            
            offsetPath = fullfile(dataFolder, 'OffsetErrors.data');
            fid = fopen(offsetPath, 'wb');
            fwrite(fid, testCase.dummyDataContent, 'uint16');
            fclose(fid);
            
            % Create Spectral data files
            for i = 0:(numFiles-1)
                spectralPath = fullfile(dataFolder, sprintf('Spectral%d.data', i));
                fid = fopen(spectralPath, 'wb');
                fwrite(fid, testCase.dummyDataContent, 'uint16');
                fclose(fid);
            end
        end
    end
end
