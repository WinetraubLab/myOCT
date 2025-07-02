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

        function testSurfacePositionPixels(testCase)
            % This test verifies that yOCTFindTissueSurface is able to detect surface position of a simulated speckle field.
            % In this test, we use simplest speckle field without coverslip
            dim = yOCTChangeDimensionsStructureUnits(testCase.dimensions,'mm'); % Ensure it's in mm
            expectedSurfacePos_pix = dim.z.index(...
                testCase.simulatedSurfacePositionZ_pix);

            % Identify surface (always in mm)
            [surfacePosition_pix,x_pix,y_pix] = yOCTFindTissueSurface( ...
                testCase.logMeanAbs, dim, 'outputUnits', 'pix');
            
            % Check surface position
            assert(...
                abs(mean(mean(surfacePosition_pix)) - ...  Average surface position in mm
                expectedSurfacePos_pix) ...                Expected surface position in mm
                < 2, 'Expecting surface position within few pixels');

            % Check x,y
            assert(mean(abs(x_pix(:) - dim.x.index(:))) < 1);
            assert(mean(abs(y_pix(:) - dim.y.index(:))) < 1);
        end

        function testAssertTissueSurfaceInFocus(testCase)
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

            % This should fail, move 50um out of focus, in the other
            % direction sure that function returns an error.
            testCase.verifyError(...
                @()yOCTAssertTissueSurfaceIsInFocus(surfacePosition-surfaceZ-0.050,x,y),...
                'yOCT:SurfaceOutOfFocus');
        end

        function testOnlyPartOfTissueIsInFocus(testCase)

            % Where surface positoin should be (where we constructed it)
            surfacePosition = zeros(100,100);
            x = linspace(0,1,100);
            y = linspace(0,1,100);

            % Shift a small portion of the surface away from focus, make
            % sure assertion passes (as this is a small part)
            surfacePosition1 = surfacePosition;
            surfacePosition1(1:10,1:10) = 1000;
            yOCTAssertTissueSurfaceIsInFocus(surfacePosition1,x,y)

            % Shift a large portion of the surface away from focus, make
            % sure assertion fails
            surfacePosition1 = surfacePosition;
            surfacePosition1(1:50,:) = 1000;
            try
                yOCTAssertTissueSurfaceIsInFocus(surfacePosition1, x, y);
                testCase.verifyFail('Expected an error, but none was thrown.');
            catch ME
                validErrorIds = {'yOCT:SurfaceOutOfFocus', 'yOCT:SurfaceCannotBeInFocus'};
                testCase.verifyTrue(ismember(ME.identifier, validErrorIds), ...
                    sprintf('Unexpected error ID: %s', ME.identifier));
            end
        end
        
        function testNoEstimationYieldsAssertError(testCase)
            % Where surface positoin should be (where we constructed it)
            surfacePosition = zeros(100,100);
            x = linspace(0,1,100);
            y = linspace(0,1,100);

            % Make it such big potion of surface position is unknown
            surfacePosition(1:100,:) = NaN;

            testCase.verifyError(...
                @()yOCTAssertTissueSurfaceIsInFocus(surfacePosition,x,y),...
                'yOCT:SurfaceCannotBeEstimated');
        end

        function testUnevenSurfaceYieldsAssertError(testCase)
            % Create a surface that on average is in focus, but in practice
            % is very much out of focus
            x = linspace(0,1,100);
            y = linspace(0,1,100);
            surfacePosition = x'*y; 
            surfacePosition = surfacePosition - mean(surfacePosition);

            testCase.verifyError(...
                @()yOCTAssertTissueSurfaceIsInFocus(surfacePosition,x,y),...
                'yOCT:SurfaceCannotBeInFocus');
        end

        function testRealworldDataset(testCase)
            % This test loads a dataset from roboflow with real life cases
            % and tests that they pass

            % Load dataset
            rfFolder = rfDownloadDataset('tissue-surface','outputFolder','./temp/', 'version', 4);
            [imageFilePath, imageMaskPath, ~] = ...
                rfListImagesAndSegmentationsInDataset(rfFolder,'above-tissue');

            % Loop over all images and compare algorithm with ground truth
            for i=1:length(imageFilePath)
                % Load OCT image
                oct = rgb2gray(imread(imageFilePath{i}));

                % Create dimensions, assuming 1 micron per pixel
                dim.x.order = 2;
                dim.x.values = 1:size(oct,2);
                dim.x.units = 'microns';
                dim.x.index = 1:size(oct,2);
                dim.x.origin = 'unknown';
                dim.z.order = 1;
                dim.z.values = 1:size(oct,1);
                dim.z.units = 'microns';
                dim.z.index = 1:size(oct,1);
                dim.z.origin = 'unknown';
                dim.y.order = 3;
                dim.y.values = 1;
                dim.y.units = 'microns';
                dim.y.index = 1;
                dim.y.origin = 'unknown';

                % Get surface from algorithm
                surfacePosition_mm = yOCTFindTissueSurface( ...
                    oct, dim);

                % Convert surface position to pixel
                surfacePosition_pix = surfacePosition_mm*1e+3;

                % Load ground truth, surface is the bottom of the mask
                bMask = imread(imageMaskPath{i});
                surfacePositionGT_pix = zeros(size(surfacePosition_pix));
                for col = 1:length(surfacePosition_pix)
                    f = find(bMask(:, col), 1, 'last');
                    if ~isempty(f)
                        surfacePositionGT_pix(col) = f;
                    else
                        % Couldn't find ground truth for this column
                        surfacePositionGT_pix(col) = NaN;
                    end
                end

                % Compare 
                e_pix = abs(surfacePosition_pix - surfacePositionGT_pix);
                errorText = sprintf('Error too high for "%s"',imageFilePath{i});
                assert(sum(isnan(e_pix))/length(e_pix)<0.1, errorText); % Make sure not too many nans
                assert(mean(e_pix(~isnan(e_pix)))<10,errorText); % Make sure average error is not too high
                assert(prctile(e_pix(~isnan(e_pix)),90)<40,errorText); % Make sure max error is not too high
            end
        end
    end
end
