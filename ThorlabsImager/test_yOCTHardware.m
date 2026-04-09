classdef test_yOCTHardware < matlab.unittest.TestCase
    % All tests use skipHardware=true so no real DLL or Python module is
    % needed. What we verify is pure cache and state logic.

    methods(TestMethodSetup)
        function resetCache(~)
            yOCTHardware('reset');
        end
    end

    methods(TestMethodTeardown)
        function cleanupCache(~)
            yOCTHardware('reset');
        end
    end

    methods(Test)

        %% Init: first call caches all outputs
        function testFirstCallCachesAllOutputs(testCase)
            [module, name, skip, scanInit] = yOCTHardware('init', ...
                'OCTSystem', 'Gan632', 'skipHardware', true);
            testCase.verifyEqual(name, 'gan632');
            testCase.verifyEmpty(module);
            testCase.verifyTrue(skip);
            testCase.verifyFalse(scanInit, ...
                'Scanner should not be initialized when skipHardware=true');
        end

        %% Init: early return with same args
        function testEarlyReturnWithSameArgs(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true);
            [module, name, skip, scanInit] = yOCTHardware('init', ...
                'OCTSystem', 'Gan632', 'skipHardware', true);
            testCase.verifyEqual(name, 'gan632');
            testCase.verifyEmpty(module);
            testCase.verifyTrue(skip);
            testCase.verifyFalse(scanInit);
        end

        %% Status: returns cache with all outputs
        function testStatusReturnsCache(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true);
            [module, name, skip, scanInit] = yOCTHardware('status');
            testCase.verifyEqual(name, 'gan632');
            testCase.verifyEmpty(module);
            testCase.verifyTrue(skip);
            testCase.verifyFalse(scanInit, ...
                'Scanner should not be initialized with skipHardware=true');
        end

        %% Status: errors when not initialized
        function testStatusErrorsWhenNotInitialized(testCase)
            testCase.verifyError(@() yOCTHardware('status'), ...
                'myOCT:yOCTHardware:notInitialized');
        end

        %% verifyInit: errors when not initialized
        function testVerifyInitErrorsWhenNotInitialized(testCase)
            testCase.verifyError(@() yOCTHardware('verifyInit'), ...
                'myOCT:yOCTHardware:notInitialized');
        end

        %% verifyInit: passes when skipHardware=true (scanner not needed)
        function testVerifyInitPassesWithSkipHardware(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true);
            [~, name, skip] = yOCTHardware('verifyInit');
            testCase.verifyEqual(name, 'gan632');
            testCase.verifyTrue(skip);
        end

        %% Teardown: safe when never initialized
        function testTeardownWithoutInitIsSafe(testCase)
            [~, ~, ~, scanInit] = yOCTHardware('teardown');
            testCase.verifyFalse(scanInit);
        end

        %% Teardown: clears cache and scanner state
        function testTeardownClearsCache(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true);
            [~, ~, ~, scanInit] = yOCTHardware('teardown');
            testCase.verifyFalse(scanInit, ...
                'Scanner state should be false after teardown');

            % Cache must be empty: status errors
            testCase.verifyError(@() yOCTHardware('status'), ...
                'myOCT:yOCTHardware:notInitialized');

            % Re-init with a different system must work
            [~, name, skip] = yOCTHardware('init', ...
                'OCTSystem', 'Ganymede', 'skipHardware', true);
            testCase.verifyEqual(name, 'ganymede');
            testCase.verifyTrue(skip);
        end

        %% System name change triggers re-init
        function testSystemNameChangeGan632ToGanymede(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true);
            [~, name, ~] = yOCTHardware('init', ...
                'OCTSystem', 'Ganymede', 'skipHardware', true);
            testCase.verifyEqual(name, 'ganymede');
        end

        function testSystemNameChangeGanymedeToGan632(testCase)
            yOCTHardware('init', 'OCTSystem', 'Ganymede', 'skipHardware', true);
            [~, name, ~] = yOCTHardware('init', ...
                'OCTSystem', 'Gan632', 'skipHardware', true);
            testCase.verifyEqual(name, 'gan632');
        end

        %% Reset: clears cache and scanner state
        function testResetClearsCache(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true);
            [~, ~, ~, scanInit] = yOCTHardware('reset');
            testCase.verifyFalse(scanInit, ...
                'Scanner state should be false after reset');
            testCase.verifyError(@() yOCTHardware('status'), ...
                'myOCT:yOCTHardware:notInitialized');
        end

        %% Invalid command errors
        function testInvalidCommandErrors(testCase)
            testCase.verifyError(@() yOCTHardware('bogus'), ...
                'myOCT:yOCTHardware:unknownCommand');
        end

        %% No command errors
        function testNoCommandErrors(testCase)
            testCase.verifyError(@() yOCTHardware(''), ...
                'myOCT:yOCTHardware:noCommand');
        end

        %% Stage init (via init with stage params)

        %% init with stage params returns (0,0,0) when skipHardware is true
        function testInitStageReturnsOrigin(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'oct2stageXYAngleDeg', 0);
            [x0, y0, z0] = yOCTHardware('getStagePosition');
            testCase.verifyEqual([x0; y0; z0], [0;0;0]);
        end

        %% init with stage params errors if OCT not initialized
        function testInitStageErrorsWithoutInit(testCase)
            testCase.verifyError(...
                @() yOCTHardware('init', 'oct2stageXYAngleDeg', 0), ...
                'myOCT:yOCTHardware:noSystemName');
        end

        %% init with stage angle 0: yOCTStageMoveTo updates position
        function testInitStageAngleZeroMoveTo(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'oct2stageXYAngleDeg', 0);
            yOCTStageMoveTo(3, 4, 5);
            [x0, y0, z0] = yOCTHardware('getStagePosition');
            testCase.verifyEqual([x0; y0; z0], [3;4;5]);
        end

        %% Calling init with stage params twice re-connects: tracked position resets
        function testInitStageTwiceResetsPosition(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'oct2stageXYAngleDeg', 0);
            yOCTStageMoveTo(5, 6, 7);
            % Second init with stage params re-connects — position resets
            yOCTHardware('init', 'oct2stageXYAngleDeg', 0);
            [x0, y0, z0] = yOCTHardware('getStagePosition');
            testCase.verifyEqual([x0; y0; z0], [0;0;0]);
        end

        %% getStagePosition

        %% getStagePosition returns position set by init
        function testGetStagePositionReturnsPosition(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'oct2stageXYAngleDeg', 5);
            [x0, y0, z0] = yOCTHardware('getStagePosition');
            testCase.verifyEqual([x0; y0; z0], [0;0;0]);
        end

        %% getStagePosition errors if stage was never initialized
        function testGetStagePositionErrorsWithoutStageInit(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true);
            testCase.verifyError(...
                @() yOCTHardware('getStagePosition'), ...
                'myOCT:yOCTHardware:stageNotInitialized');
        end

        %% yOCTStageMoveTo

        %% yOCTStageMoveTo writes position, getStagePosition reads it back
        function testMoveThenReadPosition(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'oct2stageXYAngleDeg', 0);
            yOCTStageMoveTo(1, 2, 3);
            [x0, y0, z0] = yOCTHardware('getStagePosition');
            testCase.verifyEqual([x0; y0; z0], [1;2;3]);
        end

        %% yOCTStageMoveTo errors if stage was never initialized
        function testMoveToErrorsWithoutStageInit(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true);
            testCase.verifyError(...
                @() yOCTStageMoveTo(1, 2, 3), ...
                'myOCT:yOCTHardware:stageNotInitialized');
        end

        %% Stage cleanup (reset / teardown / system change)

        %% reset clears stage state
        function testResetClearsStageState(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'oct2stageXYAngleDeg', 0);
            yOCTHardware('reset');
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true);
            testCase.verifyError(@() yOCTHardware('getStagePosition'), ...
                'myOCT:yOCTHardware:stageNotInitialized');
        end

        %% Teardown: clears stage state
        function testTeardownClearsStageState(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'oct2stageXYAngleDeg', 0);
            yOCTHardware('teardown');
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true);
            testCase.verifyError(@() yOCTHardware('getStagePosition'), ...
                'myOCT:yOCTHardware:stageNotInitialized');
        end

        %% Changing OCT system auto-teardowns and clears stage state
        function testSystemChangeClearsStageState(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'oct2stageXYAngleDeg', 10);
            yOCTHardware('init', 'OCTSystem', 'Ganymede', 'skipHardware', true);
            testCase.verifyError(@() yOCTHardware('getStagePosition'), ...
                'myOCT:yOCTHardware:stageNotInitialized');
        end

    end
end
