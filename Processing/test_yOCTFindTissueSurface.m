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
            % This test verifies that yOCTFindTissueSurface is able to detect surface position of a simulated speckle field.
            % In this test, we use simplest speckle field without coverslip
            dim = yOCTChangeDimensionsStructureUnits(testCase.dimensions,'mm'); % Ensure it's in mm
            expectedSurfacePos_mm = dim.z.values(...
                testCase.simulatedSurfacePositionZ_pix);

            % Identify surface (always in mm)
            [surfacePosition_mm,x_mm,y_mm] = yOCTFindTissueSurface( ...
                testCase.logMeanAbs, dim);
            
            % Check surface position
            assert(...
                abs(mean(mean(surfacePosition_mm)) - ...  Average surface position in mm
                expectedSurfacePos_mm) ...                Expected surface position in mm
                < 2e-3 );

            % Check x,y
            assert(mean(abs(x_mm(:) - dim.x.values(:))) < 1e-3);
            assert(mean(abs(y_mm(:) - dim.y.values(:))) < 1e-3);
        end

        function testSurfacePositionAfterOffset(testCase)
            % Offset dim x,y,z by a small amount. Verify that surface position moved as well
            dim = yOCTChangeDimensionsStructureUnits(testCase.dimensions,'mm'); % Ensure it's in mm
            dim.z.values = dim.z.values + 0.1; % Shift by 100 microns
            dim.x.values = dim.x.values + 0.1; % Shift by 100 microns
            dim.y.values = dim.y.values + 0.1; % Shift by 100 microns
            
            expectedSurfacePos_mm = dim.z.values(...
                testCase.simulatedSurfacePositionZ_pix);
            
            % Identify surface (always in mm)
            [surfacePosition_mm,x_mm,y_mm] = yOCTFindTissueSurface( ...
                testCase.logMeanAbs, dim);
            
            % Check surface position
            assert( ...
                abs(mean(mean(surfacePosition_mm)) - ...  Average surface position in mm
                expectedSurfacePos_mm) ...                Expected surface position in mm
                < 2e-3 );
            
            % Check x,y
            assert(mean(abs(x_mm(:) - dim.x.values(:))) < 1e-3);
            assert(mean(abs(y_mm(:) - dim.y.values(:))) < 1e-3);
        end

        function testChangingDimensionsShouldntChangeOutputs(testCase)
            
            % Compute surface position with mm inputs
            [surfacePosition1,x1,y1] = yOCTFindTissueSurface( ...
                testCase.logMeanAbs, ...
                yOCTChangeDimensionsStructureUnits(testCase.dimensions,'mm'));
 
            % Compute surface position with microns inputs
            [surfacePosition2,x2,y2] = yOCTFindTissueSurface( ...
                testCase.logMeanAbs, ...
                yOCTChangeDimensionsStructureUnits(testCase.dimensions,'microns'));
 
            % Make sure that changing the inputs doesn't impact the output
            % units. According to yOCTScanAndFindTissueSurface
            % documentation, output is allways in mm
            assert(...
                max(abs(surfacePosition1(:)-surfacePosition2(:)))==0, ... 
                "Input units impact surfacePosition")
            assert(max(abs(x1(:)-x2(:)))==0, "Input units impact x")
            assert(max(abs(y1(:)-y2(:)))==0, "Input units impact y")
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