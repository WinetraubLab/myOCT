classdef test_yOCTProcessTiledScan < matlab.unittest.TestCase

    methods(TestClassSetup)
        function setupHardwareLib(~)
            yOCTHardware('init', 'OCTSystem', 'Ganymede', 'skipHardware', true);
        end
    end
    
    properties (Access = private)
        CropTestFolder
        CropTestCommonParams
    end
    
    methods (Access = private)
        function [scanFolder, outFile] = makeResumeFixture(testCase, suffix)
            % Helper: build a fresh simulated scan + output paths inside a
            % unique tmp directory and register cleanup so leftovers never
            % pollute the workspace if a test fails mid-way.
            stamp = datestr(now, 'yyyymmdd_HHMMSSFFF');
            scanFolder = ['tmp_resume_' suffix '_' stamp '/'];
            outFile    = ['tmp_resume_' suffix '_' stamp '.tif'];

            dummyData = zeros(400,200,2)+1;
            dummyData([50,150],:,:) = 100;
            octProbePath = yOCTGetProbeIniPath('40x', 'OCTP900', 'SUMMER');

            yOCTSimulateTileScan(dummyData, scanFolder, ...
                'pixelSize_um', 1, ...
                'zDepths', 0, ...
                'focusPositionInImageZpix', 1, ...
                'focusSigma', 1000, ...
                'octProbePath', octProbePath);

            companion = [outFile '.fldr'];
            testCase.addTeardown(@() testCase.cleanupResumeFixture( ...
                scanFolder, outFile, companion));
        end

        function cleanupResumeFixture(~, scanFolder, outFile, companion)
            if exist(scanFolder,'dir');  rmdir(scanFolder,'s');  end
            if exist(outFile,'file');    delete(outFile);        end
            if exist(companion,'dir');   rmdir(companion,'s');   end
            % Also delete any stray inProgress sibling
            [folder, base, ext] = fileparts(outFile);
            if isempty(folder); folder = pwd; end
            stale = fullfile(folder, [base '_inProgress' ext]);
            if exist(stale,'file'); delete(stale); end
        end

        function setupCropSimulation(testCase)
            % Shared simulation setup for cropZRange tests.
            % This creates simulated scan data that all crop tests reuse.
            testCase.CropTestFolder = 'tmp_crop_test/';
            
            if exist(testCase.CropTestFolder, 'dir')
                rmdir(testCase.CropTestFolder, 's');
            end
            
            dummyData = zeros(512, 200, 2) + 1;
            dummyData([50, 150, 300], :, :) = 100;
            octProbePath = yOCTGetProbeIniPath('40x', 'OCTP900', 'SUMMER');
            focusPositionInImageZpix = 256;
            focusSigma = 1000;
            
            yOCTSimulateTileScan(dummyData, testCase.CropTestFolder, ...
                'pixelSize_um', 1, ...
                'zDepths', 0, ...
                'focusPositionInImageZpix', focusPositionInImageZpix, ...
                'focusSigma', focusSigma, ...
                'octProbePath', octProbePath);
            
            testCase.CropTestCommonParams = { ...
                'focusPositionInImageZpix', focusPositionInImageZpix, ...
                'focusSigma', focusSigma, ...
                'dispersionQuadraticTerm', 0, ...
                'v', false};
            
            testCase.addTeardown(@() testCase.cleanupCropTest()); % cleanup guard: this runs after test ends whether it passes or fails
        end
        
        function cleanupCropTest(testCase)
            if exist(testCase.CropTestFolder, 'dir')
                rmdir(testCase.CropTestFolder, 's');
            end
        end
    end
    
    methods(Test)
        function testLoadSaveNoStitchingNoFocus(testCase)
            % Confirm that yOCTProcessTiledScan works when:
            %   outputFilePixelSize_um = [] -> keeps native spacing
            %   outputFilePixelSize_um omitted (default 1 micron isotropic)
            %   And that the Z-dimension length scales as expected.

            % Generate Data
            dummyData = zeros(1000,500,2)+1;
            pixelSize_um = 1; 
            outputFolder = 'tmp/';
            octProbePath = yOCTGetProbeIniPath('40x', 'OCTP900', 'SUMMER');
            focusPositionInImageZpix = 1;
            focusSigma = 1000;
            dummyData([100, 200, 300],:,:) = 100;

            % Generate simulated data
            json = yOCTSimulateTileScan(dummyData,outputFolder,...
                        'pixelSize_um', pixelSize_um, ...
                        'zDepths',      0, ...
                        'focusPositionInImageZpix', focusPositionInImageZpix,... % No Z scan filtering
                        'focusSigma',focusSigma, ...
                        'octProbePath', octProbePath ...
                        );

            % Process with [] (Empty outputFilePixelSize_um)
            yOCTProcessTiledScan(...
                outputFolder, ... % Input
                {'temp.tif'},...  % Output
                'focusPositionInImageZpix', focusPositionInImageZpix,...
                'focusSigma',focusSigma, ...
                'dispersionQuadraticTerm',0, ...
                'interpMethod','sinc5', ...
                'outputFilePixelSize_um', []);
            [data, dim] = yOCTFromTif('temp.tif');

            % Process with the default (1 um - not passing anything)
            yOCTProcessTiledScan(...
                outputFolder, ... % Input (same simulated folder)
                {'temp2.tif'},... % New output
                'focusPositionInImageZpix', focusPositionInImageZpix,...
                'focusSigma',focusSigma, ...
                'dispersionQuadraticTerm',0, ...
                'interpMethod','sinc5' ... % outputFilePixelSize_um omitted: default 1 micron
                );
            [data2, dim2] = yOCTFromTif('temp2.tif');

            % Validation
            % Native pixel-size along Z (microns) used as reference
            pixelSizeZ_native_um = mean(diff(dim.z.values))*1e3;

            % Verify isotropic stack indeed has 1 micron per pixel in Z
            pixelSizeZ_um = diff(dim2.z.values)*1e3; % in microns
            testCase.verifyLessThan(max(abs(pixelSizeZ_um - 1)), 1e-3, ...
                'dim2.z spacing is not 1 um per pixel');
            
            % Verify X and Y spacing are also 1 micron (full isotropy)
            pixelSizeX_um = mean(diff(dim2.x.values))*1e3;
            pixelSizeY_um = mean(diff(dim2.y.values))*1e3;
            testCase.verifyLessThan(abs(pixelSizeX_um - 1), 1e-3, ...
                'dim2.x spacing is not 1 um per pixel');
            testCase.verifyLessThan(abs(pixelSizeY_um - 1), 1e-3, ...
                'dim2.y spacing is not 1 um per pixel');

            % Check total number of Z samples scales as expected
            expectedLength = round(length(dim.z.values) * pixelSizeZ_native_um / 1);
            testCase.verifyEqual(length(dim2.z.values), expectedLength, ...
                'AbsTol',1, ...
                'Z-dimension length after isotropic resampling is not as expected');

            % Clean Up
            rmdir(outputFolder, 's');
            delete temp.tif temp2.tif;
        end
        
        function testSystemNameCompatibility(testCase)
            % Verify that octSystem field works correctly in ScanInfo.json
            % Test both exact case and case-insensitive matching
            
            octProbePath = yOCTGetProbeIniPath('40x', 'OCTP900', 'SUMMER');
            dummyData = zeros(1000,500,2)+1;
            dummyData([100, 200, 300],:,:) = 100;
            pixelSize_um = 1;
            focusPositionInImageZpix = 1;
            focusSigma = 1;
            outputFolder = 'tmp_compatibility/';
            
            % Clean folder
            if exist(outputFolder, 'dir')
                rmdir(outputFolder, 's');
            end
            
            % Create scan
            yOCTSimulateTileScan(dummyData, outputFolder,...
                'pixelSize_um', pixelSize_um, ...
                'zDepths', 0, ...
                'focusPositionInImageZpix', focusPositionInImageZpix,...
                'focusSigma', focusSigma, ...
                'octProbePath', octProbePath);
            
            scanInfoPath = fullfile(outputFolder, 'ScanInfo.json');
            
            % Test octSystem = 'Simulated Ganymede' (exact case)
            json = awsReadJSON(scanInfoPath);
            json.octSystem = 'Simulated Ganymede';
            if isfield(json, 'OCTSystem'), json = rmfield(json, 'OCTSystem'); end
            awsWriteJSON(json, scanInfoPath);
            try
                yOCTProcessTiledScan(outputFolder, {'test1.tif'}, ...
                    'focusPositionInImageZpix', focusPositionInImageZpix,...
                    'focusSigma', focusSigma, ...
                    'dispersionQuadraticTerm', 0, ...
                    'v', false);
                test1Pass = true;
            catch ME
                test1Pass = false;
                fprintf('Test (octSystem=Simulated Ganymede) FAILED: %s\n', ME.message);
            end
            testCase.verifyTrue(test1Pass, 'Test octSystem with exact case should work');
            
            % Test octSystem = 'simulated ganymede' (lowercase - case insensitive)
            json = awsReadJSON(scanInfoPath);
            json.octSystem = 'simulated ganymede';
            if isfield(json, 'OCTSystem'), json = rmfield(json, 'OCTSystem'); end
            awsWriteJSON(json, scanInfoPath);
            try
                yOCTProcessTiledScan(outputFolder, {'test2.tif'}, ...
                    'focusPositionInImageZpix', focusPositionInImageZpix,...
                    'focusSigma', focusSigma, ...
                    'dispersionQuadraticTerm', 0, ...
                    'v', false);
                test2Pass = true;
            catch ME
                test2Pass = false;
                fprintf('Test (octSystem=simulated ganymede) FAILED: %s\n', ME.message);
            end
            testCase.verifyTrue(test2Pass, 'Test octSystem case insensitive should work');
            
            % Cleanup
            rmdir(outputFolder, 's');
            if exist('test1.tif', 'file'), delete('test1.tif'); end
            if exist('test2.tif', 'file'), delete('test2.tif'); end
        end
        
        function testCropZRange(testCase)
            % Test that cropZRange_mm correctly crops the Z dimension.
            %   1. no cropZRange_mm  -> full Z range (baseline)
            %   2. cropZRange_mm set -> output is trimmed to that range
            
            testCase.setupCropSimulation();
            
            %% 1. No cropZRange_mm (full Z range, baseline)
            yOCTProcessTiledScan(testCase.CropTestFolder, {'crop_full.tif'}, ...
                testCase.CropTestCommonParams{:}, 'outputFilePixelSize_um', []);
            [~, dimFull] = yOCTFromTif('crop_full.tif');
            testCase.addTeardown(@() delete('crop_full.tif'));
            
            nZFull = length(dimFull.z.values);
            testCase.verifyGreaterThan(nZFull, 1000, ...
                'Full Z range should have many pixels');
            
            %% 2. cropZRange_mm set (custom range, 10 pixels inside each edge)
            dz_mm = mean(diff(dimFull.z.values));
            nMarginPix = 10;
            cropRange = [dimFull.z.values(1 + nMarginPix), ...
                         dimFull.z.values(end - nMarginPix)];
            
            yOCTProcessTiledScan(testCase.CropTestFolder, {'crop_range.tif'}, ...
                testCase.CropTestCommonParams{:}, ...
                'cropZRange_mm', cropRange, 'outputFilePixelSize_um', []);
            [~, dimRange] = yOCTFromTif('crop_range.tif');
            testCase.addTeardown(@() delete('crop_range.tif'));
            
            nZRange = length(dimRange.z.values);
            
            % Output boundaries must match the requested range (within one pixel)
            testCase.verifyEqual(dimRange.z.values(1), cropRange(1), ...
                'AbsTol', abs(dz_mm), ...
                'First Z value should be approximately cropZRange_mm(1)');
            testCase.verifyEqual(dimRange.z.values(end), cropRange(2), ...
                'AbsTol', abs(dz_mm), ...
                'Last Z value should be approximately cropZRange_mm(2)');
            
            % dim.z.index must be 1:nZ
            testCase.verifyEqual(dimRange.z.index(:)', 1:nZRange, ...
                'dim.z.index should be 1:nZ after crop');
            
            % Z spacing should be uniform (same as original)
            if nZRange >= 2
                zSpacing = diff(dimRange.z.values);
                testCase.verifyLessThan(max(abs(zSpacing - dz_mm)), 1e-6, ...
                    'Z spacing should be uniform after cropZRange_mm');
            end
            
            % Pixel count must match grid positions within the range
            expectedNZ = sum(dimFull.z.values >= cropRange(1) & dimFull.z.values <= cropRange(2));
            testCase.verifyEqual(nZRange, expectedNZ, ...
                'Number of Z pixels should match grid positions within cropZRange_mm');
            
            % Cropped output must be strictly smaller than full range
            testCase.verifyLessThan(nZRange, nZFull, ...
                'cropZRange_mm output should have fewer Z pixels than no-crop baseline');
        end
        
        function testCropZRange_InvertedBoundaries(testCase)
            % Verify that an error is thrown when cropZRange_mm is
            % inverted (first element > second element).
            testCase.setupCropSimulation();
            
            errorOccurred = false;
            try
                yOCTProcessTiledScan(testCase.CropTestFolder, {'should_fail.tif'}, ...
                    testCase.CropTestCommonParams{:}, ...
                    'cropZRange_mm', [0.200, -0.050]);
            catch
                errorOccurred = true;
            end
            testCase.verifyTrue(errorOccurred, ...
                'Should throw error when cropZRange_mm is inverted (first > second)');
            if exist('should_fail.tif', 'file'), delete('should_fail.tif'); end
        end
        
        function testCropZRange_CompletelyOutsideRange(testCase)
            % Verify that an error is thrown when cropZRange_mm specifies
            % a range completely outside the available Z data.
            testCase.setupCropSimulation();
            
            errorOccurred = false;
            try
                yOCTProcessTiledScan(testCase.CropTestFolder, {'should_fail.tif'}, ...
                    testCase.CropTestCommonParams{:}, ...
                    'cropZRange_mm', [10 20]);
            catch
                errorOccurred = true;
            end
            testCase.verifyTrue(errorOccurred, ...
                'Should throw error when cropZRange_mm does not overlap with Z data');
            if exist('should_fail.tif', 'file'), delete('should_fail.tif'); end
        end
        
        function testCropZRange_PartialOverlap(testCase)
            % Verify that cropZRange_mm works when the requested range
            % extends beyond the available Z data on one or both sides.
            % The crop should succeed, selecting only the overlapping region.
            testCase.setupCropSimulation();
            
            % First get the full Z extent for reference
            yOCTProcessTiledScan(testCase.CropTestFolder, {'partial_ref.tif'}, ...
                testCase.CropTestCommonParams{:}, 'outputFilePixelSize_um', []);
            [~, dimFull] = yOCTFromTif('partial_ref.tif');
            testCase.addTeardown(@() delete('partial_ref.tif'));
            dz_mm = mean(diff(dimFull.z.values));
            
            % Case 1: Range extends past both sides (10 pixels beyond actual data)
            % All data should fit within range, so output should equal full range.
            wideMargin_mm = 10 * abs(dz_mm);
            wideRange = [dimFull.z.values(1) - wideMargin_mm, ...
                         dimFull.z.values(end) + wideMargin_mm];
            yOCTProcessTiledScan(testCase.CropTestFolder, {'partial_wide.tif'}, ...
                testCase.CropTestCommonParams{:}, ...
                'cropZRange_mm', wideRange, 'outputFilePixelSize_um', []);
            [~, dimWide] = yOCTFromTif('partial_wide.tif');
            testCase.addTeardown(@() delete('partial_wide.tif'));
            
            testCase.verifyEqual(length(dimWide.z.values), length(dimFull.z.values), ...
                'Wide range should keep all Z pixels');
            
            % Case 2: Range covers only the upper half of the Z data
            % Output should contain approximately half the Z pixels.
            zMid = (dimFull.z.values(1) + dimFull.z.values(end)) / 2;
            halfRange = [zMid, dimFull.z.values(end) + wideMargin_mm];
            yOCTProcessTiledScan(testCase.CropTestFolder, {'partial_half.tif'}, ...
                testCase.CropTestCommonParams{:}, ...
                'cropZRange_mm', halfRange, 'outputFilePixelSize_um', []);
            [~, dimHalf] = yOCTFromTif('partial_half.tif');
            testCase.addTeardown(@() delete('partial_half.tif'));
            
            % First Z value should be approximately zMid
            testCase.verifyEqual(dimHalf.z.values(1), zMid, ...
                'AbsTol', abs(dz_mm), ...
                'Partial overlap: first Z should be approximately midpoint');
            testCase.verifyLessThan(length(dimHalf.z.values), length(dimFull.z.values), ...
                'Partial overlap should have fewer Z pixels than full range');
            testCase.verifyGreaterThan(length(dimHalf.z.values), length(dimFull.z.values) * 0.3, ...
                'Partial overlap should have at least 30% of Z pixels (approximately half)');
        end

        function testResume_AfterInterruptedFinalize(testCase)
            % Resume after a crash that happened during the finalization
            % stage of a previous run. We simulate this by:
            %   1. Running a clean reference run.
            %   2. Running a second clean run, then deleting the final BigTIFF,
            %      half of the rewritten per-y slides, and TifMetadata.json.
            %      This is the on-disk state a crash mid-finalize would leave
            %      (parfor frames are still committed in partialMode/).
            %   3. Calling again with resume=true and verifying the recovered
            %      output is bit-for-bit identical to the reference.
            % NOTE: we cannot actually crash mid-parfor from a unit test, so
            % this test focuses on the steps that come AFTER parfor.

            [scanFolder, refOut] = testCase.makeResumeFixture('ref');
            [~,         resumeOut] = testCase.makeResumeFixture('out');

            commonArgs = { ...
                'focusPositionInImageZpix', 1, ...
                'focusSigma', 1000, ...
                'dispersionQuadraticTerm', 0, ...
                'v', false};

            % Reference (single-shot)
            yOCTProcessTiledScan(scanFolder, {refOut}, commonArgs{:}, 'resume', false);
            testCase.assertTrue(exist(refOut,'file') == 2, ...
                'Reference run must produce a final BigTIFF');
            [dataRef, ~] = yOCTFromTif(refOut);

            % Run #1 of the resume scenario (clean run that we will mutilate)
            yOCTProcessTiledScan(scanFolder, {resumeOut}, commonArgs{:}, 'resume', false);

            % Mutilate to mimic a crash that happened during finalize:
            %   - delete the final BigTIFF
            %   - delete TifMetadata.json
            %   - delete half of the rewritten per-y slides
            % Note we keep partialMode/ contents intact (parfor was finished).
            delete(resumeOut);
            companion = [resumeOut '.fldr'];
            metaFile = fullfile(companion, 'TifMetadata.json');
            if exist(metaFile,'file'); delete(metaFile); end
            slideFiles = dir(fullfile(companion, 'y*.tif'));
            for k = 1:floor(length(slideFiles)/2)
                delete(fullfile(companion, slideFiles(k).name));
            end

            % Resume must rebuild the deleted artifacts and produce a final
            % file numerically identical to the reference.
            yOCTProcessTiledScan(scanFolder, {resumeOut}, commonArgs{:}, 'resume', true);
            testCase.verifyTrue(exist(resumeOut,'file') == 2, ...
                'Resume must produce final BigTIFF');
            [dataResume, ~] = yOCTFromTif(resumeOut);

            testCase.verifyEqual(size(dataResume), size(dataRef), ...
                'Resumed output volume shape must match reference');
            testCase.verifyLessThan( ...
                max(abs(double(dataResume(:)) - double(dataRef(:)))), 1e-6, ...
                'Resumed output must be numerically identical to reference');
        end

        function testResume_StaleInProgressBigTIFF_IsCleared(testCase)
            % If a previous run crashed mid-write, an _inProgress.tif may
            % remain alongside the (missing) final file. The next resume
            % must delete it and produce a complete final BigTIFF.

            [scanFolder, outFile] = testCase.makeResumeFixture('stale');
            commonArgs = { ...
                'focusPositionInImageZpix', 1, ...
                'focusSigma', 1000, ...
                'dispersionQuadraticTerm', 0, ...
                'v', false};

            % Build a complete output first
            yOCTProcessTiledScan(scanFolder, {outFile}, commonArgs{:}, 'resume', false);

            % Simulate crash mid-BigTIFF: delete final file, keep slides in
            % the companion folder, plant a stale _inProgress sibling.
            delete(outFile);
            [folder, base, ext] = fileparts(outFile);
            if isempty(folder); folder = pwd; end
            stale = fullfile(folder, [base '_inProgress' ext]);
            fid = fopen(stale,'w'); fwrite(fid,'corrupt'); fclose(fid);
            testCase.assertTrue(exist(stale,'file') == 2);

            % Resume must clear the stale file and produce a valid final.
            yOCTProcessTiledScan(scanFolder, {outFile}, commonArgs{:}, 'resume', true);
            testCase.verifyTrue(exist(outFile,'file') == 2, ...
                'Final BigTIFF must exist after resume');
            testCase.verifyFalse(exist(stale,'file') == 2, ...
                'Stale _inProgress sibling must be removed after resume');
        end

        function testResume_ClimIsReused(testCase)
            % The clim used to rewrite slides + assemble the BigTIFF is
            % saved as _clim.json in partialMode/. A resume must reuse it
            % so that the final output is deterministic across runs.
            %
            % Strategy: plant a sentinel _clim.json BEFORE the first run so
            % that partialMode/ already has it when mode 3 runs.
            % The parfor (mode 2) still executes fresh (no committed .tif.json),
            % but mode 3 Honours the pre-existing _clim.json instead of
            % recomputing from per-frame data.
            %
            % Note: after mode 3, the companion *.tif.fldr/ folder is
            % deleted. The sentinel clim is verified by reading
            % it back from the TIFF's embedded Software tag via yOCTFromTif.

            [scanFolder, outFile] = testCase.makeResumeFixture('clim');
            commonArgs = { ...
                'focusPositionInImageZpix', 1, ...
                'focusSigma', 1000, ...
                'dispersionQuadraticTerm', 0, ...
                'v', false};

            % Pre-plant a sentinel _clim.json so mode 3 uses it.
            % (partialMode/ does not exist yet; create it before the run.)
            companion = [outFile '.fldr'];
            partialFolder = fullfile(companion, 'partialMode');
            mkdir(partialFolder);
            sentinelClim = [-12345.5, 12345.5];
            climPayload = struct(); climPayload.c = sentinelClim;
            awsWriteJSON(climPayload, fullfile(partialFolder, '_clim.json'));

            % Run with resume=true: parfor runs fresh (no committed .tif.json),
            % then mode 3 picks up the sentinel clim and embeds it in the BigTIFF.
            yOCTProcessTiledScan(scanFolder, {outFile}, commonArgs{:}, 'resume', true);
            testCase.assertTrue(exist(outFile,'file') == 2, ...
                'Final BigTIFF must exist after resume run');

            % The clim is embedded in the BigTIFF's Software TIFF tag as JSON;
            % yOCTFromTif's third output returns it directly.
            [~, ~, climOut] = yOCTFromTif(outFile);
            testCase.verifyEqual(climOut(:)', sentinelClim, 'AbsTol', 1e-9, ...
                'Resume must honour the cached _clim.json instead of recomputing');
        end

        function testResume_ConfigMismatch_FocusSigma(testCase)
            % Changing focusSigma between runs must abort with a precise error.
            testCase.verifyConfigMismatchError('focusSigma', 1000, 500);
        end

        function testResume_ConfigMismatch_DispersionQuadraticTerm(testCase)
            testCase.verifyConfigMismatchError('dispersionQuadraticTerm', 0, 79430000);
        end

        function testResume_ConfigMismatch_FocusPosition(testCase)
            testCase.verifyConfigMismatchError('focusPositionInImageZpix', 1, 100);
        end

        function testResume_SkipsWhenFullyDone(testCase)
            % Calling yOCTProcessTiledScan on an already-complete output is
            % a no-op: it must emit the dedicated warning and leave the
            % file untouched (same size, same mtime).

            [scanFolder, outFile] = testCase.makeResumeFixture('done');
            commonArgs = { ...
                'focusPositionInImageZpix', 1, ...
                'focusSigma', 1000, ...
                'dispersionQuadraticTerm', 0, ...
                'v', false};

            yOCTProcessTiledScan(scanFolder, {outFile}, commonArgs{:});
            testCase.assertTrue(exist(outFile,'file') == 2, ...
                'First run must produce final file');
            info1 = dir(outFile);

            companion = [outFile '.fldr'];
            partialPath = fullfile(companion, 'partialMode');
            testCase.verifyFalse(exist(partialPath,'dir') == 7, ...
                'partialMode/ must be removed after a clean run');

            pause(1.1); % allow mtime resolution to detect any change
            testCase.verifyWarning( ...
                @() yOCTProcessTiledScan(scanFolder, {outFile}, ...
                    commonArgs{:}, 'resume', true), ...
                'yOCTProcessTiledScan:outputAlreadyDone');

            info2 = dir(outFile);
            testCase.verifyEqual(info2.bytes, info1.bytes, ...
                'File size must not change on a no-op resume');
            testCase.verifyEqual(info2.datenum, info1.datenum, ...
                'File mtime must not change on a no-op resume');
        end

        function testResume_HalfCommittedFrame_IsRedone(testCase)
            % Crash between writing y####.tif and writing y####.tif.json:
            % only the .tif is on disk. The resume must NOT treat that as
            % "done" (the .json is the completion marker); it must redo
            % that frame so the final output matches a clean run.

            [scanFolder, outFile] = testCase.makeResumeFixture('half');
            commonArgs = { ...
                'focusPositionInImageZpix', 1, ...
                'focusSigma', 1000, ...
                'dispersionQuadraticTerm', 0, ...
                'v', false};

            % Reference: clean single-shot run
            [~, refOut] = testCase.makeResumeFixture('half_ref');
            yOCTProcessTiledScan(scanFolder, {refOut}, commonArgs{:}, 'resume', false);
            [dataRef, ~] = yOCTFromTif(refOut);

            % Plant a lone y0001.tif in partialMode/ without its .json sibling,
            % then run with resume=true and verify output matches the reference.
            companion = [outFile '.fldr'];
            partialFolder = fullfile(companion, 'partialMode');
            mkdir(partialFolder);
            fid = fopen(fullfile(partialFolder,'y0001.tif'),'w');
            fwrite(fid, uint8(zeros(100,1))); fclose(fid);

            yOCTProcessTiledScan(scanFolder, {outFile}, commonArgs{:}, 'resume', true);
            [dataResume, ~] = yOCTFromTif(outFile);
            testCase.verifyLessThan( ...
                max(abs(double(dataResume(:)) - double(dataRef(:)))), 1e-6, ...
                'Half-committed frame must be redone, not skipped');
        end

        function testResume_StaleInProgressSidecars_AreOverwritten(testCase)
            % Any crash can leave stale _inProgress sidecars on disk
            % (_clim_inProgress.json, TifMetadata_inProgress.json,
            % reconstructConfig_inProgress.json). A resume must ignore
            % their stale content and still produce a valid final file.

            [scanFolder, outFile] = testCase.makeResumeFixture('sidecars');
            commonArgs = { ...
                'focusPositionInImageZpix', 1, ...
                'focusSigma', 1000, ...
                'dispersionQuadraticTerm', 0, ...
                'v', false};

            companion = [outFile '.fldr'];
            partialFolder = fullfile(companion, 'partialMode');
            mkdir(partialFolder);

            % Plant the three stale _inProgress sidecars with garbage.
            staleFiles = { ...
                fullfile(partialFolder, '_clim_inProgress.json'), ...
                fullfile(partialFolder, 'reconstructConfig_inProgress.json'), ...
                fullfile(companion,    'TifMetadata_inProgress.json')};
            for k = 1:length(staleFiles)
                fid = fopen(staleFiles{k},'w'); fwrite(fid,'corrupt'); fclose(fid);
            end

            yOCTProcessTiledScan(scanFolder, {outFile}, commonArgs{:}, 'resume', true);
            testCase.verifyTrue(exist(outFile,'file') == 2, ...
                'Resume must still produce the final file despite stale sidecars');
        end

        function testResume_CorruptedClimCache_IsRecomputed(testCase)
            % A corrupted _clim.json (invalid JSON from an interrupted write)
            % must not abort the run. Mode 3 wraps the read in try/catch and
            % falls back to recomputing clim from the per-frame sidecars.

            [scanFolder, outFile] = testCase.makeResumeFixture('bad_clim');
            commonArgs = { ...
                'focusPositionInImageZpix', 1, ...
                'focusSigma', 1000, ...
                'dispersionQuadraticTerm', 0, ...
                'v', false};

            % Reference clim from a clean run.
            [~, refOut] = testCase.makeResumeFixture('bad_clim_ref');
            yOCTProcessTiledScan(scanFolder, {refOut}, commonArgs{:}, 'resume', false);
            [~, ~, climRef] = yOCTFromTif(refOut);

            % Plant an invalid _clim.json, then run.
            companion = [outFile '.fldr'];
            partialFolder = fullfile(companion, 'partialMode');
            mkdir(partialFolder);
            fid = fopen(fullfile(partialFolder,'_clim.json'),'w');
            fwrite(fid, 'this is not valid json {{{'); fclose(fid);

            yOCTProcessTiledScan(scanFolder, {outFile}, commonArgs{:}, 'resume', true);
            [~, ~, climOut] = yOCTFromTif(outFile);
            testCase.verifyEqual(climOut(:)', climRef(:)', 'AbsTol', 1e-6, ...
                'Corrupted clim must be recomputed, matching a clean run');
        end

        function testResume_OrphanStageDirInOutputFolder_IsCleaned(testCase)
            % If MATLAB is interrupted mid-write, a y####.tif/ directory can remain in
            % the output folder instead of a file. imageDatastore crashes on it.
            % Step 1b sweeps those orphans before the BigTIFF build.
            % Test that resume completes successfully and output matches a clean run.

            [scanFolder, outFile] = testCase.makeResumeFixture('orphan_out');
            commonArgs = { ...
                'focusPositionInImageZpix', 1, ...
                'focusSigma', 1000, ...
                'dispersionQuadraticTerm', 0, ...
                'v', false};

            % Reference: clean run
            [~, refOut] = testCase.makeResumeFixture('orphan_out_ref');
            yOCTProcessTiledScan(scanFolder, {refOut}, commonArgs{:}, 'resume', false);
            [dataRef, ~] = yOCTFromTif(refOut);

            % First clean run to get a complete partialMode/ with per-frame
            % .tif.json sidecars (so mode 2 is a no-op on the next resume).
            yOCTProcessTiledScan(scanFolder, {outFile}, commonArgs{:}, 'resume', false);

            % Simulate a crash mid-Step 3: delete the final BigTIFF and plant
            % an orphan y0001.tif/ directory in the output folder where the
            % slide file would be.
            delete(outFile);
            companion = [outFile '.fldr'];
            slidePath = fullfile(companion, 'y0001.tif');
            if exist(slidePath,'file'); delete(slidePath); end
            mkdir(slidePath); % orphan directory where a file is expected

            % Resume must sweep the orphan, rebuild the slide + BigTIFF,
            % and produce output identical to the reference.
            yOCTProcessTiledScan(scanFolder, {outFile}, commonArgs{:}, 'resume', true);
            testCase.verifyTrue(exist(outFile,'file') == 2, ...
                'Final BigTIFF must exist after resume');
            testCase.verifyFalse(exist(slidePath,'dir') == 7, ...
                'Orphan y####.tif/ directory must be removed');
            [dataResume, ~] = yOCTFromTif(outFile);
            testCase.verifyLessThan( ...
                max(abs(double(dataResume(:)) - double(dataRef(:)))), 1e-6, ...
                'Output must match the clean reference after orphan sweep');
        end

        function testResume_OrphanStageDirInPartialMode_IsCleaned(testCase)
            % Same bug as above but the orphan y####.tif/ lives in partialMode/.
            % Mode 1 resume sweeps it so mode 2 can re-stage that frame.
            % Test that resume completes successfully and output matches a clean run.

            [scanFolder, outFile] = testCase.makeResumeFixture('orphan_partial');
            commonArgs = { ...
                'focusPositionInImageZpix', 1, ...
                'focusSigma', 1000, ...
                'dispersionQuadraticTerm', 0, ...
                'v', false};

            % Reference: clean run
            [~, refOut] = testCase.makeResumeFixture('orphan_partial_ref');
            yOCTProcessTiledScan(scanFolder, {refOut}, commonArgs{:}, 'resume', false);
            [dataRef, ~] = yOCTFromTif(refOut);

            % Plant an orphan y0001.tif/ directory in partialMode/ BEFORE
            % any run (so mode 2 will have to redo that frame).
            companion = [outFile '.fldr'];
            partialFolder = fullfile(companion, 'partialMode');
            mkdir(partialFolder);
            orphanPath = fullfile(partialFolder, 'y0001.tif');
            mkdir(orphanPath);

            yOCTProcessTiledScan(scanFolder, {outFile}, commonArgs{:}, 'resume', true);
            testCase.verifyTrue(exist(outFile,'file') == 2, ...
                'Final BigTIFF must exist after resume');
            [dataResume, ~] = yOCTFromTif(outFile);
            testCase.verifyLessThan( ...
                max(abs(double(dataResume(:)) - double(dataRef(:)))), 1e-6, ...
                'Output must match the clean reference after orphan sweep in partialMode');
        end
    end

    methods (Access = private)
        function verifyConfigMismatchError(testCase, fieldName, prevValue, newValue)
            % Shared helper: write a config guard with prevValue and verify
            % that resuming with newValue throws resumeConfigMismatch.
            [scanFolder, outFile] = testCase.makeResumeFixture(['guard_' fieldName]);
            companion = [outFile '.fldr'];
            partialFolder = fullfile(companion, 'partialMode');
            mkdir(partialFolder);

            % Build a minimal but complete previous-config guard.
            guard = struct();
            guard.tiledScanInputFolder      = 'irrelevant';
            guard.dispersionQuadraticTerm   = 0;
            guard.focusSigma                = 1000;
            guard.focusPositionInImageZpix  = 1;
            guard.cropZRange_mm             = [];
            guard.outputFilePixelSize_um    = 1;
            guard.applyPathLengthCorrection = true;
            guard.reconstructConfig         = {};
            guard.(fieldName) = prevValue;
            awsWriteJSON(guard, fullfile(partialFolder,'reconstructConfig.json'));

            % Drop a dummy committed yI so partialMode is non-trivial.
            fid = fopen(fullfile(partialFolder,'y0001.tif'),'w'); fclose(fid);
            fid = fopen(fullfile(partialFolder,'y0001.tif.json'),'w');
            fprintf(fid,'{"c":[0,1]}'); fclose(fid);

            % Build the resume call args, replacing the field under test.
            args = { ...
                'focusPositionInImageZpix', 1, ...
                'focusSigma', 1000, ...
                'dispersionQuadraticTerm', 0, ...
                'v', false, ...
                'resume', true};
            for k = 1:2:length(args)
                if strcmp(args{k}, fieldName)
                    args{k+1} = newValue;
                end
            end

            % Use the fixture's scanFolder so ScanInfo.json is available;
            % the call should fail at the config-guard check long before
            % touching the actual scan data.
            testCase.verifyError( ...
                @() yOCTProcessTiledScan(scanFolder, {outFile}, args{:}), ...
                'yOCTProcessTiledScan:resumeConfigMismatch');
        end
    end
end
