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
            data(10) = 1;

            % Encode as interferogram
            [interf, dim] = yOCTSimulateInterferogram(data);

            % Reconstruct
            [scanCpx, ~] = yOCTInterfToScanCpx(interf, dim, 'dispersionQuadraticTerm',0);
            reconstructedData = abs(scanCpx);

            % Smooth data a bit, since yOCTInterfToScanCpx applies a filter
            dataSmooth = conv(data,[0.5 1 0.5]/2,'same');

            % Check size
            if (size(scanCpx,1) ~= size(data,1))
                testCase.verifyFail('Expected to preserve size')
            end

            % Check total intensity
            if abs(sum(data) - sum(reconstructedData)) > 0.001
                testCase.verifyFail('Expected to preserve energy');
            end

            % Check match
            if max(abs(dataSmooth-reconstructedData)) > 0.001
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
            [interf, dim] = yOCTSimulateInterferogram(data);

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
            [interf, dim] = yOCTSimulateInterferogram(data);

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
    end
end