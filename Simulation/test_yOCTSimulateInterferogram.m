classdef test_yOCTSimulateInterferogram < matlab.unittest.TestCase
    % Test generating interferograms
    
    methods(TestClassSetup)
        % Shared setup for the entire test class
    end
    
    methods(TestMethodSetup)
        % Setup for each testa
    end
    
    methods(Test)
        function testGenerateInterfAndReconstruct1D(testCase)
            % Generate a A scan, see that we can simulate it and then
            % reconstruct without loosing data
            data = zeros(1024,1);
            data(50) = 1;

            % Encode as interferogram
            [interf, dim] = yOCTSimulateInterferogram_core(data);

            % Reconstruct
            [scanCpx, ~] = yOCTInterfToScanCpx(interf, dim, 'dispersionQuadraticTerm',0);
            reconstructedData = abs(scanCpx);

            % Smooth data a bit, since yOCTInterfToScanCpx applies a filter
            filt = [0.5 1.1 0.5];
            dataSmooth = conv(data,filt*sqrt(mean(filt.^2)),'same');

            % Check size
            if (size(scanCpx,1) ~= size(data,1))
                testCase.verifyFail('Expected to preserve size')
            end

            % Check total energy
            eData = sqrt(sum(data.^2));
            eReconstructed = sqrt(sum(reconstructedData.^2));
            if abs( (eReconstructed-eData)/eData ) > 0.001
                testCase.verifyFail('Expected to preserve energy');
            end

            % Check match on a point by point bases
            if max(abs(dataSmooth-reconstructedData)) > 0.05
                testCase.verifyFail('Reconstruction failed');
            end
   
        end

        function testGenerateInterfAndReconstruct2D(testCase)
            % Generate a B scan, where for each x direction particle is
            % positioned in a different depth, see that x is reconstructed
            % correctly.

            % Generate B scan
            data = zeros(1024,100);
            particleDepths = (1:size(data,2))*2+50;
            for i=1:length(particleDepths)
                data(particleDepths(i),i) = 1;
            end

            % Encode as interferogram
            [interf, dim] = yOCTSimulateInterferogram_core(data);

            % Reconstruct
            [scanCpx, ~] = yOCTInterfToScanCpx(interf, dim, 'dispersionQuadraticTerm',0);
            reconstructedData = abs(scanCpx);

            % Check size
            if (size(scanCpx,1) ~= size(data,1) || size(scanCpx,2) ~= size(data,2))
                testCase.verifyFail('Expected to preserve size')
            end

            % Compare between each x position and the first one shifted
            for i=2:length(particleDepths)
                a = reconstructedData(:,1);
                b = reconstructedData(:,i);

                b(1:(particleDepths(i)-particleDepths(1)))=[];
                b(end:length(a)) = 0;

                % Check match
                if max(abs(a-b)) > 0.001
                    testCase.verifyFail(sprintf('Reconstruction failed index %d',i));
                end
            end
        end

        function testGenerateInterfAndReconstruct3D(testCase)
            % Generate a 3D volume with a plane, and see that
            % reconstruction works

            data = zeros(1024,100,50);
            data(50,:,:) = 1;

            % Encode as interferogram
            [interf, dim] = yOCTSimulateInterferogram_core(data);

            % Reconstruct
            [scanCpx, ~] = yOCTInterfToScanCpx(interf, dim, 'dispersionQuadraticTerm',0);
            reconstructedData = abs(scanCpx);

            % Check size
            if (size(scanCpx,1) ~= size(data,1) || size(scanCpx,2) ~= size(data,2) || size(scanCpx,3) ~= size(data,3))
                testCase.verifyFail('Expected to preserve size')
            end

            % Compare between each x position and the first see that they
            % all match
            d = reconstructedData - reconstructedData(:,1,1);

            % Check match
            if max(abs(d)) > 0.001
                testCase.verifyFail('Reconstruction failed');
            end
        end
        
        function testRealisticReconstruct1D(testCase)
            scattererIndex = [];
            for n=[1, 1.33] % Check both air and water
                % Generate a A scan of a known pixel size, verify that
                % reconstruction is the same
                data = zeros(1024,1);
                data(53) = 1; % Place a scatterer at 53 microns
    
                % Encode as interferogram
                [interf, dim] = yOCTSimulateInterferogram(data,'n',n);
    
                % Reconstruct
                [scanCpx, dim] = yOCTInterfToScanCpx(interf, dim, 'dispersionQuadraticTerm',0,'n',n);
                reconstructedData = abs(scanCpx);
    
                % Find scatterer
                [~, reconstructedDataI] = max(reconstructedData);
                scattererIndex(end+1) = reconstructedDataI;

                % Check position 
                if abs(dim.z.values(reconstructedDataI) - 53) > 1.5 % Threshold in microns
                    testCase.verifyFail(sprintf('Failed z depth, n=%.2f',n));
                end
            end

            if (scattererIndex(2) < scattererIndex(1))
                testCase.verifyFail(...
                    'Increasing index of refraction should shorten the distance');
            end
   
        end

    end
end