classdef test_yOCTPhotobleachTile < matlab.unittest.TestCase

    properties
        
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
    end
end
