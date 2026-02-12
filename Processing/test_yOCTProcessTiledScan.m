classdef test_yOCTProcessTiledScan < matlab.unittest.TestCase

    methods(TestClassSetup)
        function setupHardwareLib(~)
            yOCTHardwareLibSetUp('Ganymede');
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
            octProbePath = yOCTGetProbeIniPath('40x','OCTP900');
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
                'cropZAroundFocusArea',false, ...
                'outputFilePixelSize_um', []);
            [data, dim] = yOCTFromTif('temp.tif');

            % Process with the default (1 um - not passing anything)
            yOCTProcessTiledScan(...
                outputFolder, ... % Input (same simulated folder)
                {'temp2.tif'},... % New output
                'focusPositionInImageZpix', focusPositionInImageZpix,...
                'focusSigma',focusSigma, ...
                'dispersionQuadraticTerm',0, ...
                'interpMethod','sinc5', ...
                'cropZAroundFocusArea',false ... % outputFilePixelSize_um omitted: default 1 micron
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
            
            octProbePath = yOCTGetProbeIniPath('40x','OCTP900');
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
                    'cropZAroundFocusArea', false, ...
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
                    'cropZAroundFocusArea', false, ...
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
            % We simulate one scan, then process with 4 crop configurations:
            %   1. crop = false                 -> full Z range (baseline)
            %   2. crop = true                  -> focus-based crop (~1 pixel with 1 zDepth)
            %   3. crop = true + cropZRange_mm  -> custom range
            %   4. crop = false + cropZRange_mm -> crop=false prevails (no crop, warning issued for passing both)
            
            %% Setup: simulate a single depth scan
            dummyData = zeros(512, 200, 2) + 1;
            dummyData([50, 150, 300], :, :) = 100;
            pixelSize_um = 1;
            outputFolder = 'tmp_crop_range/';
            octProbePath = yOCTGetProbeIniPath('40x','OCTP900');
            focusPositionInImageZpix = 256; % Focus in the middle
            focusSigma = 1000; % Very wide sigma to avoid NaN issues during this test
            
            if exist(outputFolder, 'dir')
                rmdir(outputFolder, 's');
            end
            
            yOCTSimulateTileScan(dummyData, outputFolder, ...
                'pixelSize_um', pixelSize_um, ...
                'zDepths', 0, ...
                'focusPositionInImageZpix', focusPositionInImageZpix, ...
                'focusSigma', focusSigma, ...
                'octProbePath', octProbePath);
            
            commonParams = { ...
                'focusPositionInImageZpix', focusPositionInImageZpix, ...
                'focusSigma', focusSigma, ...
                'dispersionQuadraticTerm', 0, ...
                'v', false};
            
            %% 1. crop = false (full Z range, baseline)
            yOCTProcessTiledScan(outputFolder, {'crop_false.tif'}, ...
                commonParams{:}, 'cropZAroundFocusArea', false, ...
                'outputFilePixelSize_um', []);
            [dataFull, dimFull] = yOCTFromTif('crop_false.tif');
            
            nZFull = length(dimFull.z.values);
            testCase.verifyGreaterThan(nZFull, 1000, ...
                'Full Z range should have many pixels');
            testCase.verifyEqual(size(dataFull,1), nZFull, ...
                'Data Z size should match dim.z for crop=false');
            
            %% 2. crop = true (with 1 zDepth -> 1 Z pixels)
            yOCTProcessTiledScan(outputFolder, {'crop_true.tif'}, ...
                commonParams{:}, 'cropZAroundFocusArea', true, ...
                'outputFilePixelSize_um', []);
            [dataCropTrue, dimCropTrue] = yOCTFromTif('crop_true.tif');
            
            nZCropTrue = length(dimCropTrue.z.values);
            testCase.verifyLessThanOrEqual(nZCropTrue, 2, ...
                'crop=true with 1 zDepth should produce very few Z pixels');
            testCase.verifyEqual(size(dataCropTrue,1), nZCropTrue, ...
                'Data Z size should match dim.z for crop=true');
            testCase.verifyLessThan(nZCropTrue, nZFull, ...
                'crop=true should have fewer Z pixels than crop=false');
            
            %% 3. crop = true + cropZRange_mm (custom range)
            % Use a range well within the full Z extent
            dz_mm = mean(diff(dimFull.z.values));
            cropRange = [-0.050 0.200]; % 50um above surface to 200um below
            
            % Verify the crop range is within the data
            testCase.assumeGreaterThanOrEqual(dimFull.z.values(end), cropRange(2), ...
                'Test assumption: full Z range must extend past cropRange max');
            testCase.assumeLessThanOrEqual(dimFull.z.values(1), cropRange(1), ...
                'Test assumption: full Z range must start before cropRange min');
            
            yOCTProcessTiledScan(outputFolder, {'crop_range.tif'}, ...
                commonParams{:}, 'cropZAroundFocusArea', true, ...
                'cropZRange_mm', cropRange, 'outputFilePixelSize_um', []);
            [dataRange, dimRange] = yOCTFromTif('crop_range.tif');
            
            nZRange = length(dimRange.z.values);
            
            % Z values must be within the requested range
            testCase.verifyGreaterThanOrEqual(dimRange.z.values(1), cropRange(1), ...
                'First Z value should be >= cropZRange_mm(1)');
            testCase.verifyLessThanOrEqual(dimRange.z.values(end), cropRange(2), ...
                'Last Z value should be <= cropZRange_mm(2)');
            
            % Data matrix size must match dim
            testCase.verifyEqual(size(dataRange,1), nZRange, ...
                'Data Z size should match dim.z for cropZRange_mm');
            testCase.verifyEqual(size(dataRange,2), length(dimRange.x.values), ...
                'Data X size should match dim.x for cropZRange_mm');
            
            % dim.z.index must be 1:nZ
            testCase.verifyEqual(dimRange.z.index(:)', 1:nZRange, ...
                'dim.z.index should be 1:nZ after crop');
            
            % Z spacing should be uniform (same as original)
            if nZRange >= 2
                zSpacing = diff(dimRange.z.values);
                testCase.verifyLessThan(max(abs(zSpacing - dz_mm)), 1e-6, ...
                    'Z spacing should be uniform after cropZRange_mm');
            end
            
            % Pixel count must match expected from range and pixel size
            expectedNZ = sum(dimFull.z.values >= cropRange(1) & dimFull.z.values <= cropRange(2));
            testCase.verifyEqual(nZRange, expectedNZ, ...
                'Number of Z pixels should match grid positions within cropZRange_mm');
            
            % Must be between crop=true (small) and crop=false (full)
            testCase.verifyGreaterThan(nZRange, nZCropTrue, ...
                'cropZRange should have more Z pixels than crop=true');
            testCase.verifyLessThan(nZRange, nZFull, ...
                'cropZRange should have fewer Z pixels than crop=false');
            
            %% 4. crop = false + cropZRange_mm (crop = false wins, no crop happens)
            yOCTProcessTiledScan(outputFolder, {'crop_false_with_range.tif'}, ...
                commonParams{:}, 'cropZAroundFocusArea', false, ...
                'cropZRange_mm', cropRange, 'outputFilePixelSize_um', []);
            [~, dimFalseRange] = yOCTFromTif('crop_false_with_range.tif');
            
            nZFalseRange = length(dimFalseRange.z.values);
            testCase.verifyEqual(nZFalseRange, nZFull, ...
                'crop=false should disable cropping even when cropZRange_mm is provided');
            testCase.verifyEqual(dimFalseRange.z.values, dimFull.z.values, ...
                'Z values should be identical to crop=false case (range ignored)');
            
            %% Cleanup
            rmdir(outputFolder, 's');
            delete crop_false.tif crop_true.tif crop_range.tif crop_false_with_range.tif;
        end
        
        function testCropZRangeInvalidRangeErrors(testCase)
            % Verify that an error is thrown when cropZRange_mm specifies
            % a range completely outside the available Z data.
            
            dummyData = zeros(512, 200, 2) + 1;
            pixelSize_um = 1;
            outputFolder = 'tmp_crop_error/';
            octProbePath = yOCTGetProbeIniPath('40x','OCTP900');
            focusPositionInImageZpix = 256;
            focusSigma = 1000;
            
            if exist(outputFolder, 'dir')
                rmdir(outputFolder, 's');
            end
            
            yOCTSimulateTileScan(dummyData, outputFolder, ...
                'pixelSize_um', pixelSize_um, ...
                'zDepths', 0, ...
                'focusPositionInImageZpix', focusPositionInImageZpix, ...
                'focusSigma', focusSigma, ...
                'octProbePath', octProbePath);
            
            % Range completely outside the data (10mm to 20mm away)
            errorOccurred = false;
            try
                yOCTProcessTiledScan(outputFolder, {'should_fail.tif'}, ...
                    'focusPositionInImageZpix', focusPositionInImageZpix, ...
                    'focusSigma', focusSigma, ...
                    'dispersionQuadraticTerm', 0, ...
                    'cropZRange_mm', [10 20], ...
                    'v', false);
            catch
                errorOccurred = true;
            end
            testCase.verifyTrue(errorOccurred, ...
                'Should throw error when cropZRange_mm does not overlap with Z data');
            
            % Test inverted range (max < min)
            errorOccurred = false;
            try
                yOCTProcessTiledScan(outputFolder, {'should_fail2.tif'}, ...
                    'focusPositionInImageZpix', focusPositionInImageZpix, ...
                    'focusSigma', focusSigma, ...
                    'dispersionQuadraticTerm', 0, ...
                    'cropZRange_mm', [0.200, -0.050], ...
                    'v', false);
            catch
                errorOccurred = true;
            end
            testCase.verifyTrue(errorOccurred, ...
                'Should throw error when cropZRange_mm is inverted (first > second)');
            
            % Cleanup
            rmdir(outputFolder, 's');
            if exist('should_fail.tif', 'file'), delete('should_fail.tif'); end
            if exist('should_fail2.tif', 'file'), delete('should_fail2.tif'); end
        end
    end
end
