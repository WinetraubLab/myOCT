classdef test_yOCTScanTile_SkipHardware < matlab.unittest.TestCase
    % Test yOCTScanTile but while skipping hardware (test just the logic
    % part)
    
    methods(TestClassSetup)
        % Shared setup for the entire test class
    end
    
    methods(TestMethodSetup)
        function initCache(~)
            % Initialize SetUp cache with skipHardware=true so yOCTScanTile
            % reads the correct mode from cache without requiring real hardware.
            yOCTHardwareLibSetUp('Ganymede', true);
        end
    end

    methods(TestMethodTeardown)
        function clearCache(~)
            yOCTHardwareLibSetUp('reset');
        end
    end
    
    methods(Test)
        function testDefaultParameters3D(testCase)
            json = yOCTScanTile('test', ...
                [-0.25 0.25], ...
                [-0.25 0.25], ...
                'octProbePath', yOCTGetProbeIniPath('40x','OCTP900'));
        end

        function testDefaultParameters3DSetSmallerFOV(testCase)
            json = yOCTScanTile('test', ...
                [-0.25 0.25], ...
                [-0.25 0.25], ...
                'octProbePath', yOCTGetProbeIniPath('40x','OCTP900'),...
                'octProbeFOV_mm', 0.01);
            if length(json.xCenters_mm) < 10
                testCase.verifyFail('Expected to have a lot more centers')
            end

        end

        function testDefaultParameters2DSkipHardware(testCase)
            json = yOCTScanTile('test', ...
                [-0.25 0.25], 0, ...
                'octProbePath', yOCTGetProbeIniPath('40x','OCTP900'),...
                'octProbeFOV_mm', 0.01);
        end
    end
    
end