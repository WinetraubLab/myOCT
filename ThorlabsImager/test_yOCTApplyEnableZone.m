classdef test_yOCTApplyEnableZone < matlab.unittest.TestCase

    properties
        
    end
    
    methods(Test)
        function testSquare2D(testCase) 
            % Basic, most common functionality
            % Keep only positive x,y values
            [ptStart, ptEnd] = yOCTApplyEnableZone(...
                [-1 -1; -1  1], ...
                [ 1  1;  1 -1], ...
                @(x,y)( x>0 & y>0 ));

            assert(size(ptStart,1) == 2, "Results should be 2D")
            assert(size(ptStart,2) == 1, ["Second line has negative "...
                "x,y values and should have been descarted"]);
            assert(all(ptStart>0));
            assert(all(ptEnd>0));
        end

        function testSquare3D(testCase) 
            % Basic, most common functionality but in 3D

            % Keep only positive x,y values
            [ptStart, ptEnd] = yOCTApplyEnableZone(...
                [-1 -1; -1  1; 0 0], ...
                [ 1  1;  1 -1; 0 0], ...
                @(x,y,z)( x>0 & y>0 & z==0));
            
            assert(size(ptStart,1) == 3, "Results should be 3D")
            assert(size(ptStart,2) == 1, ["Second line has negative "...
                "x,y values and should have been descarted"]);
            assert(all(ptStart(1:2,:)>0));
            assert(all(ptEnd(1:2,:)>0));

            % Keep only positive z values
            [ptStart, ptEnd] = yOCTApplyEnableZone(...
                [-1 -1; -1  1; 1 0], ...
                [ 1  1;  1 -1; 1 0], ...
                @(x,y,z)(z>0));
            
            assert(size(ptStart,2) == 1, ["Second line has negative "...
                "x,y values and should have been descarted"]);
            assert(ptStart(2,1) == -1)
            assert(ptEnd(2,1) == 1)
        end

        function testFancyShape(testCase)
            % Keep only positive x,y values
            [ptStart, ptEnd] = yOCTApplyEnableZone(...
                [-1 -1; -1  1], ...
                [ 1  1;  1 -1], ...
                @(x,y)(x.^2+y.^2<=0.5^2 | x.^2+y.^2>1^2), ...
                1e-3);
            
            % Plot results
            for i=1:size(ptStart,2)
                plot([ptStart(1,i) ptEnd(1,i)],[ptStart(2,i) ptEnd(2,i)]);
                if (i==1)
                    hold on;
                end
            end
            hold off
            title('Confirm thath you see an x at the center and some x on the corners');
        end
    end
end