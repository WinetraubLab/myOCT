classdef test_yOCTProcessTiledScan < matlab.unittest.TestCase

    methods(TestClassSetup)
        function setupHardwareLib(~)
            yOCTHardware('init', 'OCTSystem', 'Ganymede', 'skipHardware', true);
        end
    end
    
    properties (Access = private)
        CropTestFolder
        CropTestCommonParams
        SvTestFolder
        SvProcessingParams
        SvVesselColumns
        SvStaticTissueColumns
    end
    
    methods (Access = private)
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

        function setupSpeckleVarianceTestData(testCase)
            % Create simulated OCT data for speckle-variance tests.
            % Each Y position contains 5 repeated Bscans.
            % Vessel columns change strongly between repeats to simulate flow,
            % while static tissue columns remain nearly unchanged.
            testCase.SvTestFolder = 'tmp_sv_test/';

            if exist(testCase.SvTestFolder, 'dir')
                rmdir(testCase.SvTestFolder, 's');
            end

            dummyData = ones(512, 100, 4);
            dummyData([100, 200, 300], :, :) = 100;
            octProbePath = yOCTGetProbeIniPath('40x', 'OCTP900', 'SUMMER');
            focusPositionInImageZpix = 256;
            focusSigma = 1000;
            nReps = 5;
            testCase.SvVesselColumns = 40:60;
            testCase.SvStaticTissueColumns = [10:30, 70:90];

            yOCTSimulateTileScan(dummyData, testCase.SvTestFolder, ...
                'pixelSize_um', 1, ...
                'zDepths', 0, ...
                'focusPositionInImageZpix', focusPositionInImageZpix, ...
                'focusSigma', focusSigma, ...
                'octProbePath', octProbePath);

            % Add 5 repeated B-scans with simulated motion.
            % Static tissue changes by only 0.5% between repeats,
            % while vessel columns change by 60% to simulate blood flow:
            d = load(fullfile(testCase.SvTestFolder, 'Data01', 'data.mat'));
            interf = repmat(d.interf, [1 1 1 1 nReps]); % (lambda,x,y,AScanAvg,BScanAvg)
            rng(1);
            fluctAmp = 0.005*ones(1, size(interf,2));
            fluctAmp(testCase.SvVesselColumns) = 0.6;
            interf = interf .* (1 + fluctAmp .* ...
                randn([1, size(interf,2), size(interf,3), 1, nReps], 'like', interf));
            dim = d.dim;
            dim.BScanAvg.order = 4; % lambda=1, x=2, y=3, BScanAvg=4
            dim.BScanAvg.index = 1:nReps;
            dim.BScanAvg.indexMax = nReps;
            save(fullfile(testCase.SvTestFolder, 'Data01', 'data.mat'), 'interf', 'dim');

            testCase.SvProcessingParams = { ...
                'focusPositionInImageZpix', focusPositionInImageZpix, ...
                'focusSigma', focusSigma, ...
                'dispersionQuadraticTerm', 0, ...
                'v', false};

            testCase.addTeardown(@() testCase.cleanupSvTest()); % cleanup guard: this runs after test ends whether it passes or fails
        end

        function cleanupSvTest(testCase)
            if exist(testCase.SvTestFolder, 'dir')
                rmdir(testCase.SvTestFolder, 's');
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

        function testInputFolderTrailingSlash(testCase)
            % Verify the input folder is read the same with and without a trailing slash (/)
            testCase.setupCropSimulation();

            folderWithSlash = testCase.CropTestFolder;
            folderNoSlash = folderWithSlash(1:(end-1));

            yOCTProcessTiledScan(folderWithSlash, {'slash_yes.tif'}, ...
                testCase.CropTestCommonParams{:}, 'outputFilePixelSize_um', []);
            [dataWithSlash, dimWithSlash] = yOCTFromTif('slash_yes.tif');
            testCase.addTeardown(@() delete('slash_yes.tif'));

            yOCTProcessTiledScan(folderNoSlash, {'slash_no.tif'}, ...
                testCase.CropTestCommonParams{:}, 'outputFilePixelSize_um', []);
            [dataNoSlash, dimNoSlash] = yOCTFromTif('slash_no.tif');
            testCase.addTeardown(@() delete('slash_no.tif'));

            % Both paths point at the same folder, so both outputs match:
            testCase.verifyEqual(size(dataNoSlash), size(dataWithSlash), ...
                'Output size should not depend on a trailing slash');
            testCase.verifyEqual(dataNoSlash, dataWithSlash, ...
                'Output data should not depend on a trailing slash');
            testCase.verifyEqual(dimNoSlash.z.values, dimWithSlash.z.values, ...
                'AbsTol', 1e-9, ...
                'Z values should not depend on a trailing slash');
        end

        function testSpeckleVarianceOutput(testCase)
            % Verify that speckleVarianceOutputPath produces an angiography
            % volume where simulated blood-flow regions appear bright,
            % while the structural output remains unchanged.
            testCase.setupSpeckleVarianceTestData();

            % Process with both structural and speckle variance outputs
            yOCTProcessTiledScan(testCase.SvTestFolder, {'sv_struct.tif'}, ...
                testCase.SvProcessingParams{:}, ...
                'speckleVarianceOutputPath', 'sv_angio.tif');
            testCase.addTeardown(@() delete('sv_struct.tif'));
            testCase.addTeardown(@() delete('sv_angio.tif'));
            structuralVolume = yOCTFromTif('sv_struct.tif');
            angioVolume = yOCTFromTif('sv_angio.tif');

            testCase.verifyEqual(size(angioVolume), size(structuralVolume), ...
                'Angiography and structural volumes should have the same size');
            testCase.verifyTrue(any(~isnan(angioVolume(:))), ...
                'Angiography output should not be all NaN');

            % Compare the simulated vessel region with static tissue.
            % The vessel should be much brighter in the angiography volume,
            % but should have little contrast in the structural volume.
            vesselColumns = testCase.SvVesselColumns;
            staticTissueColumns = testCase.SvStaticTissueColumns;
            angioContrast_dB = mean(angioVolume(:,vesselColumns,:), 'all', 'omitnan') ...
                - mean(angioVolume(:,staticTissueColumns,:), 'all', 'omitnan');
            structuralContrast_dB = mean(structuralVolume(:,vesselColumns,:), 'all', 'omitnan') ...
                - mean(structuralVolume(:,staticTissueColumns,:), 'all', 'omitnan');
            testCase.verifyGreaterThan(angioContrast_dB, 20, ...
                'Vessel columns should be >20dB brighter in the angiography volume');
            testCase.verifyLessThan(abs(structuralContrast_dB), 3, ...
                'Structural volume should barely change in vessel columns');

            % Structural output must not change when the option is enabled
            yOCTProcessTiledScan(testCase.SvTestFolder, {'sv_struct_only.tif'}, ...
                testCase.SvProcessingParams{:});
            testCase.addTeardown(@() delete('sv_struct_only.tif'));
            structuralOnlyVolume = yOCTFromTif('sv_struct_only.tif');
            testCase.verifyEqual(structuralVolume, structuralOnlyVolume, 'AbsTol', 1e-6, ...
                'Structural output should be identical with and without speckleVarianceOutputPath');
        end

        function testSpeckleVarianceRequiresRepeatedBScans(testCase)
            % Verify that requesting angiography without repeated B-scans
            % (nBScanAvg = 1) produces a clear error.
            testCase.setupCropSimulation(); % Scan with no repeated B-scans

            testCase.verifyError(@() yOCTProcessTiledScan( ...
                testCase.CropTestFolder, {'should_fail.tif'}, ...
                testCase.CropTestCommonParams{:}, ...
                'speckleVarianceOutputPath', 'should_fail_angio.tif'), ...
                'yOCTProcessTiledScan:SpeckleVarianceRequiresRepeats', ...
                'Angiography should require repeated B-scans');
        end

        function testSpeckleVarianceSameOutputPathError(testCase)
            % Verify that using the same path for structural and angiography
            % outputs produces an error.
            testCase.setupSpeckleVarianceTestData();

            testCase.verifyError(@() yOCTProcessTiledScan( ...
                testCase.SvTestFolder, {'sv_struct.tif'}, ...
                testCase.SvProcessingParams{:}, ...
                'speckleVarianceOutputPath', 'sv_struct.tif'), ...
                'yOCTProcessTiledScan:SameOutputPath', ...
                'Structural and angiography outputs should require different paths');
        end
    end
end
