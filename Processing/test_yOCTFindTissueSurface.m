classdef test_yOCTFindTissueSurface < matlab.unittest.TestCase
    % Test yOCTScanTile but while skipping hardware (test just the logic
    % part)

    properties
        logMeanAbs
        dimensions
        simulatedSurfacePositionZ_pix
    end
    
    methods(TestMethodSetup) % Setup for each test

        function createDummyDataset(testCase)
            % Create a dummy dataset with a scattering interface
            testCase.simulatedSurfacePositionZ_pix = 500;
            speckleField = zeros(1024,100,200)+10; %z,x,y
            rng(1);
            speckleField(testCase.simulatedSurfacePositionZ_pix:end, :, :) = ...
                10 + 990 * abs(randn(1024 - testCase.simulatedSurfacePositionZ_pix + 1, 100, 200));
        
            [interf, dim] = yOCTSimulateInterferogram_core(speckleField);
            [cpx, dim] = yOCTInterfToScanCpx(interf, dim);
            logMeanAbs_tmp = log(abs(cpx));
            testCase.logMeanAbs = logMeanAbs_tmp;
            testCase.dimensions  = dim;
        end
    end
    
    methods(Test)
        function testDimensions(testCase)
            % This test verifies that output's size matches expectation. 
            [surfacePosition,x,y] = yOCTFindTissueSurface( ...
                testCase.logMeanAbs, ...
                testCase.dimensions);
            
            % Make sure x and y are unit vectors
            assert(size(x,2) == 1);
            assert(size(y,2) == 1);

            % Make sure x and y dimensions match surfacePosition
            assert(size(surfacePosition,1) == length(y))
            assert(size(surfacePosition,2) == length(x))

            % Make sure that size matches logMeanAbs
            assert(size(surfacePosition,2) == size(testCase.logMeanAbs,2)); % x direction
            assert(size(surfacePosition,1) == size(testCase.logMeanAbs,3)); % y direction
        end

        function testSurfacePositionValue(testCase)
            % This test verifies that surfacePosition matches speckle
            % field.

            %% Microns units
            dim = yOCTChangeDimensionsStructureUnits(testCase.dimensions,'microns');
            expectedSurfacePos = dim.z.values(...
                testCase.simulatedSurfacePositionZ_pix);
            [surfacePosition,x,y] = yOCTFindTissueSurface( ...
                testCase.logMeanAbs, dim);
            
            % Check surface position
            assert(...
                abs(mean(mean(surfacePosition)) - ... Average surface position
                expectedSurfacePos) ... Expected surface position
                <2);

            % Check x,y
            assert(mean(abs(x(:) - dim.x.values(:))) < 1);
            assert(mean(abs(y(:) - dim.y.values(:))) < 1);

            %% Milimeter units
            dim = yOCTChangeDimensionsStructureUnits(testCase.dimensions,'mm');
            expectedSurfacePos = dim.z.values(...
                testCase.simulatedSurfacePositionZ_pix);
            [surfacePosition,x,y] = yOCTFindTissueSurface( ...
                testCase.logMeanAbs, dim);
            
            % Check surface position
            assert(...
                abs(mean(mean(surfacePosition)) - ... Average surface position
                expectedSurfacePos) ... Expected surface position
                <2e-3);

            % Check x,y
            assert(mean(abs(x(:) - dim.x.values(:))) < 1e-3);
            assert(mean(abs(y(:) - dim.y.values(:))) < 1e-3);

            %% Ofset dim x,y,z by a small ammount. Verify that surface position oved as well
            dim = yOCTChangeDimensionsStructureUnits(testCase.dimensions,'microns');
            dim.z.values = dim.z.values+100; % Shift by 100 microns
            dim.x.values = dim.x.values+100; % Shift by 100 microns
            dim.y.values = dim.y.values+100; % Shift by 100 microns
            expectedSurfacePos = dim.z.values(...
                testCase.simulatedSurfacePositionZ_pix);
            [surfacePosition,x,y] = yOCTFindTissueSurface( ...
                testCase.logMeanAbs, dim);
            
            % Check surface position
            assert(...
                abs(mean(mean(surfacePosition)) - ... Average surface position
                expectedSurfacePos) ... Expected surface position
                <2);

            % Check x,y
            assert(mean(abs(x(:) - dim.x.values(:))) < 1);
            assert(mean(abs(y(:) - dim.y.values(:))) < 1);
            
        end

        function testSAssertTissueSurfaceInFocus(testCase)
            % This test verifies the assertion functionality

            % Convert to mm to make calculations below easier
            dim = yOCTChangeDimensionsStructureUnits(testCase.dimensions,'mm');
            
            % Compute surface position
            [surfacePosition,x,y] = yOCTFindTissueSurface( ...
                testCase.logMeanAbs, ...
                dim);

            % Where surface positoin should be (where we constructed it)
            surfaceZ = dim.z.values(testCase.simulatedSurfacePositionZ_pix);

            % Artificially move surface position such that focus is at
            % surface, this function should pass:
            yOCTAssertTissueSurfaceIsInFocus(surfacePosition-surfaceZ,x,y);

            % This should fail, move 50um out of focus, make sure that
            % function returns an error.
            testCase.verifyError(...
                @()yOCTAssertTissueSurfaceIsInFocus(surfacePosition-surfaceZ+0.050,x,y),...
                'yOCT:SurfaceOutOfFocus');
        end
    end
    
end