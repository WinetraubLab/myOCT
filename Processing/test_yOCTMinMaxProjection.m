classdef test_yOCTMinMaxProjection < matlab.unittest.TestCase

    properties
        
    end
    
    methods(Test)
        function testAxisProjectionZ(testCase)
            data = zeros(10,20,30); % (z,x,y)
            data(5,:,:) = -1; % Set the middle z as different value

            dataProjected = yOCTMinMaxProjection(data,'min',5,1);

            % Validate size
            assert(size(dataProjected,1) == size(data,1))
            assert(size(dataProjected,2) == size(data,2))
            assert(size(dataProjected,3) == size(data,3))

            % Project to z and confirm the z above did change
            assert(all(dataProjected(4,:,:) == -1,[1,2,3]))

            % Project to x,y and confirm the z above didn't change
            dataProjected = yOCTMinMaxProjection(data,'min',5,2);
            assert(~any(dataProjected(4,:,:) == -1,[1,2,3]))
            dataProjected = yOCTMinMaxProjection(data,'min',5,3);
            assert(~any(dataProjected(4,:,:) == -1,[1,2,3]))
        end
        function testAxisProjectionX(testCase)
            data = zeros(10,20,30); % (z,x,y)
            data(:,10,:) = -1; % Set the middle z as different value

            dataProjected = yOCTMinMaxProjection(data,'min',5,2);

            % Validate size
            assert(size(dataProjected,1) == size(data,1))
            assert(size(dataProjected,2) == size(data,2))
            assert(size(dataProjected,3) == size(data,3))

            % Project to z and confirm the x above did change
            assert(all(dataProjected(:,9,:) == -1,[1,2,3]))

            % Project to x,y and confirm the x above didn't change
            dataProjected = yOCTMinMaxProjection(data,'min',5,1);
            assert(~any(dataProjected(:,9,:) == -1,[1,2,3]))
            dataProjected = yOCTMinMaxProjection(data,'min',5,3);
            assert(~any(dataProjected(:,9,:) == -1,[1,2,3]))
        end
        function testAxisProjectionY(testCase)
            data = zeros(10,20,30); % (z,x,y)
            data(:,:,15) = -1; % Set the middle z as different value

            dataProjected = yOCTMinMaxProjection(data,'min',5,3);

            % Validate size
            assert(size(dataProjected,1) == size(data,1))
            assert(size(dataProjected,2) == size(data,2))
            assert(size(dataProjected,3) == size(data,3))

            % Project to z and confirm the x above did change
            assert(all(dataProjected(:,:,14) == -1,[1,2,3]))

            % Project to x,y and confirm the x above didn't change
            dataProjected = yOCTMinMaxProjection(data,'min',5,1);
            assert(~any(dataProjected(:,:,14) == -1,[1,2,3]))
            dataProjected = yOCTMinMaxProjection(data,'min',5,2);
            assert(~any(dataProjected(:,:,14) == -1,[1,2,3]))
        end
        function testMinMax(testCase)
            data = zeros(10,20,30); % (z,x,y)
            data(5,:,:) = -1; % Set the middle z as different value
            data(6,:,:) = 1; % Set the middle z as different value
            
            dataProjected = yOCTMinMaxProjection(data,'min',5,1);
            assert(all(dataProjected(4:6,:,:) == -1,[1,2,3]),'Problem in specify min projection')

            dataProjected = yOCTMinMaxProjection(data,'max',5,1);
            assert(all(dataProjected(4:6,:,:) == +1,[1,2,3]),'Problem in specify max projection')
        end

        function testWindow(testCase)
            data = zeros(10,20,30); % (z,x,y)
            data(5,:,:) = -1; % Set the middle z as different value
            
            dataProjected = yOCTMinMaxProjection(data,'min',5,1);
            assert(all(dataProjected(3:7,:,:) == -1,[1,2,3]),'Problem in window application of projection')

            dataProjected = yOCTMinMaxProjection(data,'min',3,1);
            assert(any(dataProjected(3:7,:,:) == 0,[1,2,3]),'Changing window doesn''t impact projection')
            assert(all(dataProjected(4:6,:,:) == -1,[1,2,3]),'Problem in window application of projection')
        end

        function testOutputClass(testCase)
            data = zeros(10,20,30); % (z,x,y)
            data(5,:,:) = -1; % Set the middle z as different value
            
            dataProjected = yOCTMinMaxProjection(data,'min',5,1);
            assert(isa(data, class(dataProjected)), 'Test failed: dataProjected is not the same class as data (no class)');

            dataProjected = yOCTMinMaxProjection(int8(data),'min',5,1);
            assert(isa(int8(data), class(dataProjected)), 'Test failed: dataProjected is not the same class as data (int8)');
        end
    end
    
end