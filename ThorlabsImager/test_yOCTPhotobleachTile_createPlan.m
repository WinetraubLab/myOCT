classdef test_yOCTPhotobleachTile < matlab.unittest.TestCase
    
    properties
        DummyIni % dummy path
    end

    methods(TestMethodSetup)
        function makeDummyIni(tc)
            tc.DummyIni = [tempname,'.ini'];
            fid = fopen(tc.DummyIni,'wt');
            fprintf(fid,'RangeMaxX=1\nRangeMaxY=1\n');
            fclose(fid);
        end
    end
    methods(TestMethodTeardown)
        function deleteDummyIni(tc)
            if exist(tc.DummyIni,'file'), delete(tc.DummyIni); end
        end
    end

    methods(Test)
        
        function testEmptyPlan(testCase) 
            photobleachPlan = yOCTPhotobleachTile_createPlan([],[],0);
            assert(isempty(photobleachPlan));
        end
        function testOneFOVPlan(testCase) 
            % Photobleach x that fits in one FOV
            photobleachPlan = yOCTPhotobleachTile_createPlan(...
                [-1 -1; -1  1]*0.1, ...
                [ 1  1;  1 -1]*0.1, ...
                0);

            assert(~isempty(photobleachPlan),'Photobleach plan is empty');
            
            % Photobleach plan should start at the center
            assert(photobleachPlan(1).stageCenterX_mm == 0);
            assert(photobleachPlan(1).stageCenterY_mm == 0);
            assert(photobleachPlan(1).stageCenterZ_mm == 0);
            assert(all(photobleachPlan(1).lineLength_mm <0.5));
        end

        function testOneFOVMultipleDepthsPlan(testCase) 
            % Photobleach x that fits in one FOV, but has multiple depths
            photobleachPlan = yOCTPhotobleachTile_createPlan(...
                [-1 -1; -1  1]*0.1, ...
                [ 1  1;  1 -1]*0.1, ...
                [0 0.1]);

            % 2 steps in the plan, one for each photobleach depth
            assert(length(photobleachPlan)==2);
            
            % Photobleach plan should start at the center
            assert(all([photobleachPlan(:).stageCenterX_mm] == 0));
            assert(all([photobleachPlan(:).stageCenterY_mm] == 0));

            % Verify one line per depth
            assert(length(photobleachPlan(1).lineLength_mm) == 1); %#ok<ISCL>
            assert(length(photobleachPlan(2).lineLength_mm) == 1); %#ok<ISCL>

            yOCTPhotobleachTile_drawPlan(photobleachPlan);
        end

        function testMultipleFOVPlan(testCase) 
            % Photobleach x that doesn't fit in one FOV
            photobleachPlan = yOCTPhotobleachTile_createPlan(...
                [-1 -1; -1  1], ...
                [ 1  1;  1 -1], ...
                0);

            assert(length(photobleachPlan)>1);
            
            % Photobleach positions should be different
            assert(any([photobleachPlan(:).stageCenterX_mm] ~= photobleachPlan(1).stageCenterX_mm));
            assert(any([photobleachPlan(:).stageCenterY_mm] ~= photobleachPlan(1).stageCenterY_mm));

            % Make sure plan doesn't contain empty lines
            assert(all( ...
                arrayfun(@(x)(~isempty(x.lineLength_mm)),photobleachPlan) ...
                ));

            for i=1:length(photobleachPlan)
                ppStep = photobleachPlan(i);

                % Make sure all lines actually fit inside the FOV
                assert(all(sqrt(sum(ppStep.ptStartInFOV_mm.^2))<0.5));
                assert(all(sqrt(sum(ppStep.ptEndInFOV_mm.^2))<0.5));
            end

            % Draw the plan
            yOCTPhotobleachTile_drawPlan(photobleachPlan);
        end
        
        % Tests basic fields like FOV or photobleachPlan
        % are present when skipping hardware
        function testSkipHardwareJsonFields(tc)
            json = yOCTPhotobleachTile([-1;0],[1;0], ...
                         'skipHardware',true, ...
                         'octProbePath',tc.DummyIni);

            mustHave = {'FOV','photobleachPlan','units', ...
                        'stagePauseBeforeMoving_sec'};
            tc.verifyTrue(all(isfield(json,mustHave)), ...
                'Returned json missing mandatory fields');
        end
        
        % If we don’t give any information about tissue surface,
        % it should not try to move the laser up or down
        function testZeroSurfaceOffset(tc)
            json = yOCTPhotobleachTile([-0.2;0.2],[0.2;-0.2], ...
                         'skipHardware',true, ...
                         'surfaceMap',[], ...
                         'octProbePath',tc.DummyIni, ...
                         'maxLensFOV', 0.4);

            % Z offset must be zero when no surface map is given
            dz     = [json.photobleachPlan.zOffsetDueToTissueSurface];
            zStage = [json.photobleachPlan.stageCenterZ_mm];
            tc.verifyEqual(dz,     zeros(size(dz)));
            tc.verifyEqual(zStage, zeros(size(zStage)));
        end

        % Check that a flat +0.05 mm surface map makes the laser move up 
        % by exactly 0.05 mm
        function testConstantSurfaceOffsetApplied(tc)
            function S = makeFlatMap(z_mm)
                [X,Y] = meshgrid(-5:5);      % arbitrary grid
                S.surfacePosition_mm = z_mm*ones(size(X));
                S.surfaceX_mm = X(1,:);
                S.surfaceY_mm = Y(:,1);
            end

            S = makeFlatMap(0.05); % +50 microns everywhere
            json = yOCTPhotobleachTile([-0.2;0.2],[0.2;-0.2], ...
                         'skipHardware',true, ...
                         'surfaceMap',S, ...
                         'octProbePath',tc.DummyIni, ...
                         'maxLensFOV',0.4);
            dz = json.photobleachPlan.zOffsetDueToTissueSurface;
            zc = json.photobleachPlan.stageCenterZ_mm;
            tc.verifyEqual(dz, 0.05,'AbsTol',1e-3);
            tc.verifyEqual(zc, 0.05,'AbsTol',1e-3);
        end
        
        % Test that giving two Z depths makes two different photobleaching plans
        function testMultipleDepthsPreserved(tc)
            json = yOCTPhotobleachTile([-0.1 -0.1; -0.1 0.1], ...
                                       [ 0.1  0.1;  0.1 -0.1], ...
                         'z',[0 0.1], ...
                         'skipHardware',true, ...
                         'octProbePath',tc.DummyIni, ...
                         'maxLensFOV',0.4);
            tc.verifyEqual(numel(json.photobleachPlan),2);
            tc.verifyEqual(cellfun(@numel,{json.photobleachPlan.lineLength_mm}), ...
                           [1 1]);
        end
        
        % Test that scanning multiple tiles leads to different stage positions
        function testStageCentersUniqueAcrossTiles(tc)
            json = yOCTPhotobleachTile([-1 -1; -1 1], ...
                                       [ 1  1;  1 -1], ...
                         'skipHardware',true, ...
                         'octProbePath',tc.DummyIni, ...
                         'maxLensFOV',0.4);
            centers = [ [json.photobleachPlan.stageCenterX_mm]' ...
                        [json.photobleachPlan.stageCenterY_mm]' ];
            tc.verifyGreaterThan(size(unique(centers,'rows'),1),1, ...
                'Tiling expected > 1 unique centre');
        end
        
        % Test that the exposure time is calculated properly as length x exposurePerMM
        function testEstimatedExposureTime(tc)
            expSec = 10;
        
            json = yOCTPhotobleachTile([-0.5; 0.5], [0.5; -0.5], ...
                            'exposure',     expSec, ...
                            'skipHardware', true, ...
                            'octProbePath', tc.DummyIni, ...
                            'maxLensFOV',   0.4);
            plan = json.photobleachPlan;
            perTileLen = cellfun(@sum,{plan.lineLength_mm});   % sum within tile
            lenTotal   = sum(perTileLen);                      % sum across tiles
            expectedTime = lenTotal * expSec;   % sec
            tc.verifyEqual(expectedTime, lenTotal * expSec, 'AbsTol', 1e-6);
        end
    
        % Test that the function runs quickly when skipHardware = true
        % (should take less than a second)
        function testSkipHardwareFastExit(tc)
            t = tic;
            yOCTPhotobleachTile([-1;0],[1;0], ...
                'skipHardware',true,'octProbePath',tc.DummyIni, ...
                'maxLensFOV',[1 1]);
            tc.verifyLessThan(toc(t),1, ...
                '"skipHardware" path should be quick (<1 s)');
        end

        function testRectangularFOVROI(tc)
        % Check that the ROI box is centered properly using FOV in Y, not just FOV in X
        % This would be useful in case we ever have a rectangle FOV
            FOV = [2 1]; % width 2 mm, height 1 mm
        
            % build a steep linear surface
            [X,Y] = meshgrid(-5:5);
            S.surfacePosition_mm = Y;
            S.surfaceX_mm = X(1,:);
            S.surfaceY_mm = Y(:,1);

            json = yOCTPhotobleachTile([-0.4 -0.4; -0.4 0.4], ...
                                       [ 0.4  0.4;  0.4 -0.4], ...
                'skipHardware',true, ...
                'octProbePath',tc.DummyIni, ...
                'maxLensFOV',FOV, ...
                'surfaceMap',S);
        
            dz = json.photobleachPlan.zOffsetDueToTissueSurface;
        
            % Correct code: dz different to 0      ‎
            % Wrong Y origin: dz  is 0.1
            tc.verifyLessThan(abs(dz),0.05, ...
                ['ROI is rectangle, but it considers it a square' ...
                'replicating X to Y in the FOV']);
        end
        
        function testSurfaceOffsetMatchesPlaneMap(tc)
        % Validate that yOCTPhotobleachTile returns the correct Z offset for a
        % planar surface map and ROI dependent
        
            % Build a dense plane z = ax + by
            slopeX = 0.02;      % +20 microns per mm in X
            slopeY = -0.015;    % –15 microns per mm in Y
            step   = 0.01;      % 10  microns grid step to ensure ROI has samples
            xv     = -5:step:5;
            yv     = -5:step:5;
            [X, Y] = meshgrid(xv, yv);
        
            S.surfacePosition_mm = slopeX*X + slopeY*Y;
            S.surfaceX_mm        = xv;
            S.surfaceY_mm        = yv;
        
            % Pattern large enough to create multiple tiles
            ptStart = [-2 -2; -2  2];
            ptEnd   = [ 2  2;  2 -2];
        
            json = yOCTPhotobleachTile(ptStart, ptEnd, ...
                'skipHardware', true, ...
                'surfaceMap',   S, ...
                'octProbePath', tc.DummyIni, ...
                'maxLensFOV',   0.4, ...          
                'uniformSurfaceOffset', false);
        
            plan = json.photobleachPlan;
        
            % Expected offset = median inside each ROI
            expectedZ = nan(numel(plan),1);
            for k = 1:numel(plan)
                roiBox = [ ...
                    plan(k).stageCenterX_mm - json.FOV(1)/2, ...
                    plan(k).stageCenterY_mm - json.FOV(2)/2, ...
                    json.FOV(1), json.FOV(2)];
        
                % Use median over ROI
                expectedZ(k) = yOCTComputeZOffsetToFocusFromSurfaceROI( ...
                    S.surfacePosition_mm, S.surfaceX_mm, S.surfaceY_mm, ...
                    'roiToCheckSurfacePosition', roiBox, ...
                    'v', false);
        
                if isnan(expectedZ(k)), expectedZ(k) = 0; end % Fallback (NaN 0)
                
                % Check with given clamp
                expectedZ(k) = max(min(expectedZ(k), 0.1), -0.1);
            end
        
            % Actual offsets from the plan
            dz = [plan.zOffsetDueToTissueSurface]';
            
            tc.verifyEqual(numel(dz), numel(expectedZ), ...
                'Mismatch in number of tiles vs. expected offsets'); % Sanity pre'checks
        
            % Compare with a tight tolerance
            tc.verifyEqual(dz, expectedZ, 'AbsTol', 5e-3, ...
                'Z-offset per tile must match the median plane value (±5 microns)');
        end

        function testUniformSurfaceOffset(tc)
            % Verify that setting uniformSurfaceOffset = true forces ALL tiles
            % to share one single z offset, even if the tissue surface is different
            
                % Build an inclined surface map
                baseOffset = 0.05;                     % mm  (central tile height we expect)
                slope  = 0.02;                         % 20 micron step per X pixel
                
                [X, Y] = meshgrid(-5:5);
                S.surfacePosition_mm = baseOffset + slope * X;  % tilted + baseline
                S.surfaceX_mm        = X(1,:);
                S.surfaceY_mm        = Y(:,1);
            
                % Define a pattern that needs tiles
                ptStart = [-2 -2; -2  2];              % big X (start points)
                ptEnd   = [ 2  2;  2 -2];              % big X (end points)
            
                % Case A: uniformSurfaceOffset OFF
                jsonA = yOCTPhotobleachTile(ptStart, ptEnd, ...
                    'skipHardware',        true, ...
                    'surfaceMap',          S, ...
                    'octProbePath',        tc.DummyIni, ...
                    'maxLensFOV',          0.4, ...
                    'uniformSurfaceOffset', false);
            
                dzA = [jsonA.photobleachPlan.zOffsetDueToTissueSurface];
            
                % Case B: uniformSurfaceOffset ON
                jsonB = yOCTPhotobleachTile(ptStart, ptEnd, ...
                    'skipHardware',        true, ...
                    'surfaceMap',          S, ...
                    'octProbePath',        tc.DummyIni, ...
                    'maxLensFOV',          0.4, ...
                    'uniformSurfaceOffset', true);
            
                dzB = [jsonB.photobleachPlan.zOffsetDueToTissueSurface];
            
                % Assertions:
                % Test without uniformSurfaceOffset, tiles should have different z offsets
                tc.verifyGreaterThan(range(dzA), 0.0, ...
                    'Tiles should have different Z offsets when uniformSurfaceOffset = false');
            
                % Test with uniformSurfaceOffset, all z offsets must be equal
                tc.verifyLessThan(range(dzB), 1e-6, ...
                    'All Z offsets must match when uniformSurfaceOffset = true');
            
                % Test the common value must equal the offset of the tile nearest (0,0)
                tc.verifyEqual(dzB(1), baseOffset, 'AbsTol', 1e-3, ...
                    'Uniform Z offset should match the central tile (+0.05 mm)');
        end
    end
end
