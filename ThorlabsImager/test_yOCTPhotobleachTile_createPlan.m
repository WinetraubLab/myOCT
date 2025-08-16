classdef test_yOCTPhotobleachTile_createPlan < matlab.unittest.TestCase
    
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
        
        function testperformTilePhotobleaching(tc)
        % Verify that the Photobleach Plan correctly decides whether each ROI
        % should be photobleached, based on surface assertion results.
            
            % Pattern large enough to create multiple tiles
            ptStart = [-2 -2; -2  2];
            ptEnd   = [ 2  2;  2 -2];
            
            % Test data is designed so the left side passes (flat) and the right side fails.
            xv = -5:0.02:5;
            yv = -5:0.02:5;
            [X, ~] = meshgrid(xv, yv);
            S.surfacePosition_mm = zeros(size(X));
            S.surfacePosition_mm(X <  0) = 0.02;           % flat area (should pass and be photobleached)
            S.surfacePosition_mm(X >= 0) = 0.2 .* X(X>=0); % strong slope (should not pass or be photobleached)
            S.surfaceX_mm = xv;
            S.surfaceY_mm = yv;

            % Build photobleach plan
            json = yOCTPhotobleachTile(ptStart, ptEnd, ...
                'skipHardware', true, ...
                'surfaceMap',   S, ...
                'octProbePath', tc.DummyIni, ...
                'maxLensFOV',   0.4);

            plan  = json.photobleachPlan;    % Photobleach Plan
            tc.verifyGreaterThan(numel(plan), 20, 'Expected multiple tiles');
            tc.verifyTrue(all(arrayfun(@(p)isfield(p,'performTilePhotobleaching'), plan)), ...
                'Each tile must include performTilePhotobleaching');

            % Extract decisions
            flags     = [plan.performTilePhotobleaching]; % Decision to photobleach or skip
            leftOnly  = ([plan.stageCenterX_mm] <= -0.2); % This half must be photobleached
            rightOnly = ([plan.stageCenterX_mm] >=  0.2); % This half must NOT be photobleached
            
            % Test Expectations
            tc.verifyGreaterThan(nnz(leftOnly),  0, 'Need left-only tiles'); % Ensure both sides exist first
            tc.verifyGreaterThan(nnz(rightOnly), 0, 'Need right-only tiles');
            tc.verifyTrue(all(flags(leftOnly)), ...
                'Left half should be photobleached (all performTilePhotobleaching == true');
            tc.verifyTrue(all(~flags(rightOnly)), ...
                'Right half should be skipped (all performTilePhotobleaching == false)');
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
                'maxLensFOV',   0.4);
        
            plan = json.photobleachPlan;
        
            % Expected offset = median inside each ROI
            expectedZ = nan(numel(plan),1);
            for k = 1:numel(plan)
                roiBox = [ ...
                    plan(k).stageCenterX_mm - json.FOV(1)/2, ...
                    plan(k).stageCenterY_mm - json.FOV(2)/2, ...
                    json.FOV(1), json.FOV(2)];
        
                % Use median over ROI
                expectedZ(k) = yOCTAssertFocusAndComputeZOffset( ...
                    S.surfacePosition_mm, S.surfaceX_mm, S.surfaceY_mm, ...
                    'roiToCheckSurfacePosition', roiBox, ...
                    'throwErrorIfOutOfFocus', false, ... 
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

        function testSurfaceCorrectionModes(tc)
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
            
                % Case A: Per-tile (mode = 1)
                jsonA = yOCTPhotobleachTile(ptStart, ptEnd, ...
                    'skipHardware',        true, ...
                    'surfaceMap',          S, ...
                    'octProbePath',        tc.DummyIni, ...
                    'maxLensFOV',          0.4, ...
                    'surfaceCorrectionMode', 1);
            
                dzA = [jsonA.photobleachPlan.zOffsetDueToTissueSurface];

                % Tiles should have different offsets
                tc.verifyGreaterThan(range(dzA), 0.0, ...
                    'Tiles should have different Z offsets when surfaceCorrectionMode=1 (Per-tile).');

                % Case B: uniform from center (mode = 2)
                jsonB = yOCTPhotobleachTile(ptStart, ptEnd, ...
                    'skipHardware',        true, ...
                    'surfaceMap',          S, ...
                    'octProbePath',        tc.DummyIni, ...
                    'maxLensFOV',          0.4, ...
                    'surfaceCorrectionMode', 2);
            
                dzB = [jsonB.photobleachPlan.zOffsetDueToTissueSurface];

                % All offsets must be equal
                tc.verifyLessThan(range(dzB), 1e-6, ...
                    'All Z offsets must match when surfaceCorrectionMode=2 (uniform from center).');
                
                % Identify the centered tile to compare expected value
                distB = hypot([jsonB.photobleachPlan.stageCenterX_mm], ...
                              [jsonB.photobleachPlan.stageCenterY_mm]);
                [~, idx0_B] = min(distB);
                tc.verifyEqual(dzB(idx0_B), baseOffset, 'AbsTol', 1e-3, ...
                    'Uniform Z offset should match the centered tile (+0.05 mm).');
                
                % Case C: uniform mode with a NaN tile away from center
                % Make a NaN patch around (x,y) ≈ (2,2) so a non-center tile sees NaN
                S_nanNonCenter = S;
                nonCenterMask = (X > 1.7 & X < 2.3 & Y > 1.7 & Y < 2.3);
                S_nanNonCenter.surfacePosition_mm(nonCenterMask) = NaN;

                jsonC = yOCTPhotobleachTile(ptStart, ptEnd, ...
                    'skipHardware', true, ...
                    'surfaceMap',   S_nanNonCenter, ...
                    'octProbePath', tc.DummyIni, ...
                    'maxLensFOV',   0.4, ...
                    'surfaceCorrectionMode', 2);
            
                dzC = [jsonC.photobleachPlan.zOffsetDueToTissueSurface];
            
                % Still all equal and no NaNs (sanitization of oldOffset)
                tc.verifyTrue(all(~isnan(dzC)), ...
                    'Uniform mode should not leave NaNs in zOffsetDueToTissueSurface.');
                tc.verifyLessThan(range(dzC), 1e-6, ...
                    'All Z offsets must match in uniform mode, even with a NaN in a non-center tile.');

               % Case D: uniform mode with NaN at the center (reference invalid) must be zero offsets everywhere
                tol = 1e-9;
                
                % Make a NaN patch around (0,0) to break the reference tile
                S_nanCenter = S;
                centerMask = (abs(X) <= 0.3 & abs(Y) <= 0.3);
                S_nanCenter.surfacePosition_mm(centerMask) = NaN;
                
                jsonD = yOCTPhotobleachTile(ptStart, ptEnd, ...
                    'skipHardware', true, ...
                    'surfaceMap',   S_nanCenter, ...
                    'octProbePath', tc.DummyIni, ...
                    'maxLensFOV',   0.4, ...
                    'surfaceCorrectionMode', 2);
                
                dzD = [jsonD.photobleachPlan.zOffsetDueToTissueSurface];
                zD  = [jsonD.photobleachPlan.stageCenterZ_mm];
                
                % Expect: no NaNs in offsets and all exactly zero
                tc.verifyTrue(all(~isnan(dzD)), ...
                    'Case D: No NaNs expected in uniform fallback.');
                tc.verifyLessThan(range(dzD), tol, ...
                    'Case D: All Z offsets must be equal in uniform fallback.');
                tc.verifyTrue(all(abs(dzD) <= tol), ...
                    'Case D: All Z offsets must be zero when reference is invalid.');
                
                % Expect: stage Z unchanged from baseline (jsonD.z is the baseline depth)
                tc.verifyLessThan(range(zD), tol, ...
                    'Case D: stageCenterZ_mm should be identical across tiles in zero-offset fallback.');
                tc.verifyEqual(mean(zD), jsonD.z, 'AbsTol', tol, ...
                    'Case D: stageCenterZ_mm should remain at baseline (z).');

                % Case E: per-tile produces NaNs in a subset; uniform must lift them to zRef and move stage Z
                % This checks that there are no errors bringing previous invalid tiles from failed focus validations

                % Build a surface map that yields NaN only in two off center patches
                S_subset = S;
                patch1 = (X > 1.5 & X < 3.5 & Y > 1.5 & Y < 3.5);            % near (+2,+2)
                patch2 = (X < -1.5 & X > -3.5 & Y < -1.5 & Y > -3.5);        % near (-2,-2)
                S_subset.surfacePosition_mm(patch1 | patch2) = NaN;
                
                % First run per-tile (mode=1) to identify which tiles became NaN
                jsonE_per = yOCTPhotobleachTile(ptStart, ptEnd, ...
                    'skipHardware',        true, ...
                    'surfaceMap',          S_subset, ...
                    'octProbePath',        tc.DummyIni, ...
                    'maxLensFOV',          0.4, ...
                    'surfaceCorrectionMode', 1);
                
                dzE_per = [jsonE_per.photobleachPlan.zOffsetDueToTissueSurface];
                zE_per  = [jsonE_per.photobleachPlan.stageCenterZ_mm];
                nanIdx  = find(isnan(dzE_per));
                
                % We expect at least 2 tiles to have NaN offsets in per-tile mode
                tc.verifyGreaterThanOrEqual(numel(nanIdx), 2, ...
                    'Case E: Expected at least 2 tiles with NaN per-tile offsets.');
                
                % Now run uniform mode (mode=2) with the same map
                jsonE_uni = yOCTPhotobleachTile(ptStart, ptEnd, ...
                    'skipHardware',        true, ...
                    'surfaceMap',          S_subset, ...
                    'octProbePath',        tc.DummyIni, ...
                    'maxLensFOV',          0.4, ...
                    'surfaceCorrectionMode', 2);
                
                dzE_uni = [jsonE_uni.photobleachPlan.zOffsetDueToTissueSurface];
                zE_uni  = [jsonE_uni.photobleachPlan.stageCenterZ_mm];
                
                % Under uniform mode, no NaNs should remain and all offsets must be equal
                tc.verifyTrue(all(~isnan(dzE_uni)), ...
                    'Case E: Uniform mode must not leave NaNs in zOffsetDueToTissueSurface.');
                tc.verifyLessThan(range(dzE_uni), 1e-6, ...
                    'Case E: All Z offsets must match under uniform mode.');
                
                % Get the uniform reference offset (centered tile in the uniform result)
                distE = hypot([jsonE_uni.photobleachPlan.stageCenterX_mm], ...
                              [jsonE_uni.photobleachPlan.stageCenterY_mm]);
                [~, idx0_E] = min(distE);
                zRef_E = dzE_uni(idx0_E);
                
                % For tiles that were NaN in per-tile mode, uniform must add exactly zRef_E in stage Z
                tc.verifyEqual(zE_uni(nanIdx) - zE_per(nanIdx), zRef_E*ones(size(nanIdx)), ...
                    'AbsTol', 1e-9, ...
                    'Case E: Tiles with NaN per-tile offsets must gain exactly zRef_E in stageCenterZ_mm under uniform mode.');
                
                % And their offsets must now equal the reference
                tc.verifyTrue(all(abs(dzE_uni(nanIdx) - zRef_E) <= 1e-12), ...
                    'Case E: Tiles with prior NaN offsets must equal the uniform reference offset after correction.');
                
                % If the plan tracks this flag, all tiles should be photobleached in uniform mode
                if isfield(jsonE_uni.photobleachPlan,'performTilePhotobleaching')
                    tc.verifyTrue(all([jsonE_uni.photobleachPlan.performTilePhotobleaching]), ...
                        'Case E: performTilePhotobleaching should be true for all tiles in uniform mode.');
                end
        end
    end
end
