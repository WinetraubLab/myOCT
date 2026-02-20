classdef test_yOCTEstimateScatteringCoefMuS < matlab.unittest.TestCase
    % Test yOCTEstimateScatteringCoefMuS function using simulated OCT data
    
    properties
        octData
        dimensions
        trueMuS  % Known ground truth mu_s
    end
    
    methods(TestMethodSetup)
        function createTestData(testCase)
            % Create  OCT volume with known scattering coefficient

            % Volume parameters
            zSize = 512;  % pixels in depth
            xSize = 100;  % a-scans in x
            ySize = 100;  % a-scans in y
            
            % Physical dimensions
            pixelSize_um = 2.5;  % um per pixel
            testCase.dimensions.x.values = (0:xSize-1) * pixelSize_um;
            testCase.dimensions.y.values = (0:ySize-1) * pixelSize_um;
            testCase.dimensions.z.values = (0:zSize-1) * pixelSize_um;
            testCase.dimensions.x.index = 1:xSize;
            testCase.dimensions.y.index = 1:ySize;
            testCase.dimensions.z.index = 1:zSize;
            testCase.dimensions.x.units = 'microns';  % Required for yOCTChangeDimensionsStructureUnits
            testCase.dimensions.y.units = 'microns';
            testCase.dimensions.z.units = 'microns';
            
            % Simulate known mu_s
            testCase.trueMuS = 12.0;  % mm^-1 (ground truth)
            
            % Create synthetic OCT data
            testCase.octData = createSyntheticOCTVolume(...
                zSize, xSize, ySize, ...
                pixelSize_um, testCase.trueMuS);
        end
    end
    
    methods(Test)
        function testBasicFunctionality(testCase)
            % Test that function runs without error and outputs are valid
            [mu_s, noiseFloor_dB] = yOCTEstimateScatteringCoefMuS(...
                testCase.octData, testCase.dimensions);

            % Type checks
            testCase.verifyClass(mu_s, 'double', 'mu_s should be double');
            testCase.verifyClass(noiseFloor_dB, 'double', 'noiseFloor_dB should be double');
            
            % Size checks
            testCase.verifySize(mu_s, [1 1], 'mu_s should be scalar');
            testCase.verifySize(noiseFloor_dB, [1 1], 'noiseFloor_dB should be scalar');
            
            % Value checks
            testCase.verifyTrue(isfinite(mu_s), 'mu_s should be finite');
            testCase.verifyTrue(isfinite(noiseFloor_dB), 'noiseFloor_dB should be finite');
            
            % Range checks
            testCase.verifyGreaterThan(mu_s, 0, 'mu_s should be positive');
            testCase.verifyLessThan(mu_s, 15, 'mu_s should be reasonable (<15 mm^-1)');  % CI observed ~12.001, using 15 as upper bound
            testCase.verifyLessThan(noiseFloor_dB, 0, 'noiseFloor_dB should be negative (in dB)');
        end
        
        function testMuSAccuracy(testCase)
            % Test that estimated mu_s matches ground truth within tolerance
            [mu_s, ~] = yOCTEstimateScatteringCoefMuS(...
                testCase.octData, testCase.dimensions);
            
            % Allow 0.05% error
            tolerance = testCase.trueMuS * 0.0005;
            testCase.verifyEqual(mu_s, testCase.trueMuS, ...
                'AbsTol', tolerance, ...
                sprintf('mu_s should be close to ground truth %.2f mm^-1', testCase.trueMuS));
        end
        
        function testDifferentMuSValues(testCase)
            % Test with different known mu_s values
            trueMuSValues = [5, 10, 15, 20];  % mm^-1
            
            for trueMuS = trueMuSValues
                % Create synthetic data with this mu_s
                octData = createSyntheticOCTVolume(...
                    512, 100, 100, 2.5, trueMuS);
                
                % Estimate mu_s
                [estimatedMuS, ~] = yOCTEstimateScatteringCoefMuS(...
                    octData, testCase.dimensions);
                
                % Allow 0.05% error
                tolerance = trueMuS * 0.0005;
                testCase.verifyEqual(estimatedMuS, trueMuS, ...
                    'AbsTol', tolerance, ...
                    sprintf('Estimated mu_s should match true value %.2f mm^-1', trueMuS));
            end
        end
        
        function testWithFlatSurface(testCase)
            % Test with perfectly flat tissue surface
            octData = createSyntheticOCTVolume(...
                512, 100, 100, 2.5, testCase.trueMuS, ...
                'surfaceVariation', 0);  % No surface variation
            
            [mu_s, ~] = yOCTEstimateScatteringCoefMuS(...
                octData, testCase.dimensions);
            
            % Flat surface should give most accurate result
            tolerance = testCase.trueMuS * 0.0005;
            testCase.verifyEqual(mu_s, testCase.trueMuS, ...
                'AbsTol', tolerance, ...
                'Flat surface should give accurate mu_s estimate');
        end
        
        function testWithIrregularSurface(testCase)
            % Test with highly irregular tissue surface
            octData = createSyntheticOCTVolume(...
                512, 100, 100, 2.5, testCase.trueMuS, ...
                'surfaceVariation', 50);  % 50 um variation
            
            [mu_s, ~] = yOCTEstimateScatteringCoefMuS(...
                octData, testCase.dimensions);
            
            % This should still work
            tolerance = testCase.trueMuS * 0.0005;
            testCase.verifyEqual(mu_s, testCase.trueMuS, ...
                'AbsTol', tolerance, ...
                'Irregular surface should still give reasonable mu_s estimate');
        end
        
        function testVerboseMode(testCase)
            % Test that verbose mode saves figure correctly
            
            % Use temporary folder for test
            tempFolder = fullfile(pwd, 'TmpTest_MuS');
            figPath = fullfile(tempFolder, 'scattering_coefficient_mu_s.png');
            
            % Run with verbose mode
            [mu_s, noiseFloor_dB] = yOCTEstimateScatteringCoefMuS(...
                testCase.octData, testCase.dimensions, 'v', true, ...
                'tempFolder', tempFolder);
            
            % Verify outputs are valid
            testCase.verifyTrue(isfinite(mu_s), 'mu_s should be valid in v mode');
            testCase.verifyTrue(isfinite(noiseFloor_dB), 'noiseFloor_dB should be valid in v mode');
            
            % Verify figure was saved
            testCase.verifyTrue(isfile(figPath), 'Figure should be saved in tempFolder');
            
            % Clean up
            close all;  % Close figures
            if isfile(figPath)
                delete(figPath);  % Delete test figure
            end
            if isfolder(tempFolder)
                rmdir(tempFolder);  % Remove temp folder
            end
        end
    end
end

%% Helper function to create a synthetic OCT volume
function octData = createSyntheticOCTVolume(zSize, xSize, ySize, pixelSize_um, trueMuS, varargin)
    % Create a synthetic OCT volume with known Scattering Coef (mu_s)
    %
    % INPUTS:
    %   zSize, xSize, ySize - volume dimensions in pixels
    %   pixelSize_um - pixel size in microns
    %   trueMuS - ground true Scattering Coef in mm^-1
    %
    % OPTIONAL PARAMETERS:
    %   'surfaceVariation' - surface variation in um (default: 20)
    %   'noiseLevel' - Gaussian noise std deviation in dB (default: 2)
    
    % Parse optional inputs
    p = inputParser;
    addParameter(p, 'surfaceVariation', 20, @isnumeric);  % um
    addParameter(p, 'noiseLevel', 2, @isnumeric);  % dB (random variation)
    parse(p, varargin{:});
    
    surfaceVariation_um = p.Results.surfaceVariation;
    noiseLevel_dB = p.Results.noiseLevel;
    
    % Create depth vector in um
    depth_um = (0:zSize-1)' * pixelSize_um;
    
    % Generate tissue surface (wavy surface)
    [X, Y] = meshgrid(1:xSize, 1:ySize);
    surfaceDepth_um = 100 + surfaceVariation_um * ...
        (sin(2*pi*X/30) + cos(2*pi*Y/40));  % Wavy surface at ~100 um
    surfaceDepth_pix = round(surfaceDepth_um / pixelSize_um);
    
    % Initialize volume with background noise
    octData = zeros(zSize, xSize, ySize, 'single');
    
    % Model parameters
    amplitude = 100;     % Arbitrary amplitude
    noiseFloor_dB = -20; % Background noise level
    
    % Generate OCT signal for each A-scan
    for xi = 1:xSize
        for yi = 1:ySize
            % Get surface position for this pixel
            surfIdx = surfaceDepth_pix(yi, xi);
            
            % Initialize A-scan with noise
            aScan = db2mag(noiseFloor_dB) * ones(zSize, 1);
            
            % Add exponential decay signal starting from surface
            if surfIdx > 0 && surfIdx < zSize
                % Depth relative to surface (in um)
                depthFromSurface_um = depth_um(surfIdx:end) - depth_um(surfIdx);
                
                % Exponential decay model: I(z) = A * exp(-2*mu_s*z) + noise
                depthFromSurface_mm = depthFromSurface_um / 1000;
                signal = amplitude * exp(-2 * trueMuS * depthFromSurface_mm);
                
                % Add to A-scan
                aScan(surfIdx:end) = signal + db2mag(noiseFloor_dB);
            end
            
            % Convert to dB scale
            aScan_dB = mag2db(aScan);
            
            % Add realistic noise
            aScan_dB = aScan_dB + noiseLevel_dB * randn(zSize, 1);
            
            % Store in volume
            octData(:, xi, yi) = aScan_dB;
        end
    end
end
