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
            % Verify compatibility for different combinations of octSystem / OCTSystem
            % in ScanInfo.json when processing tiled scans
            
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
            
            % Test octSystem = 'Simulated Ganymede'
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
            testCase.verifyTrue(test1Pass, 'This should work: octSystem=Simulated Ganymede');
            
            % Test OCTSystem = 'Simulated Ganymede'
            json = awsReadJSON(scanInfoPath);
            json.OCTSystem = 'Simulated Ganymede';
            if isfield(json, 'octSystem'), json = rmfield(json, 'octSystem'); end
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
                fprintf('Test (OCTSystem=Simulated Ganymede) FAILED: %s\n', ME.message);
            end
            testCase.verifyTrue(test2Pass, 'This should work: OCTSystem=Simulated Ganymede');
            
            % Test octSystem = 'simulated ganymede'
            json = awsReadJSON(scanInfoPath);
            json.octSystem = 'simulated ganymede';
            if isfield(json, 'OCTSystem'), json = rmfield(json, 'OCTSystem'); end
            awsWriteJSON(json, scanInfoPath);
            try
                yOCTProcessTiledScan(outputFolder, {'test3.tif'}, ...
                    'focusPositionInImageZpix', focusPositionInImageZpix,...
                    'focusSigma', focusSigma, ...
                    'dispersionQuadraticTerm', 0, ...
                    'cropZAroundFocusArea', false, ...
                    'v', false);
                test3Pass = true;
            catch ME
                test3Pass = false;
                fprintf('Test (octSystem=simulated ganymede) FAILED: %s\n', ME.message);
            end
            testCase.verifyTrue(test3Pass, 'This should work: octSystem=simulated ganymede');
            
            % Test OCTSystem = 'simulated ganymede'
            json = awsReadJSON(scanInfoPath);
            json.OCTSystem = 'simulated ganymede';
            if isfield(json, 'octSystem'), json = rmfield(json, 'octSystem'); end
            awsWriteJSON(json, scanInfoPath);
            try
                yOCTProcessTiledScan(outputFolder, {'test4.tif'}, ...
                    'focusPositionInImageZpix', focusPositionInImageZpix,...
                    'focusSigma', focusSigma, ...
                    'dispersionQuadraticTerm', 0, ...
                    'cropZAroundFocusArea', false, ...
                    'v', false);
                test4Pass = true;
            catch ME
                test4Pass = false;
                fprintf('Test (OCTSystem=simulated ganymede) FAILED: %s\n', ME.message);
            end
            testCase.verifyTrue(test4Pass, 'This should work: OCTSystem=simulated ganymede');
            
            % Cleanup
            rmdir(outputFolder, 's');
            for i = 1:4
                if exist(sprintf('test%d.tif', i), 'file'), delete(sprintf('test%d.tif', i)); end
            end
        end
    end
end
