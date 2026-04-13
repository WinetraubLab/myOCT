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
                'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'oct2stageXYAngleDeg', 0);
            testCase.verifyEqual(name, 'gan632');
            testCase.verifyEmpty(module);
            testCase.verifyTrue(skip);
            testCase.verifyFalse(scanInit, ...
                'Scanner should not be initialized when skipHardware=true');
        end

        %% Init: early return with same args
        function testEarlyReturnWithSameArgs(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'oct2stageXYAngleDeg', 0);
            [module, name, skip, scanInit] = yOCTHardware('init', ...
                'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'oct2stageXYAngleDeg', 0);
            testCase.verifyEqual(name, 'gan632');
            testCase.verifyEmpty(module);
            testCase.verifyTrue(skip);
            testCase.verifyFalse(scanInit);
        end

        %% Status: returns cache with all outputs
        function testStatusReturnsCache(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'oct2stageXYAngleDeg', 0);
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
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'oct2stageXYAngleDeg', 0);
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
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'oct2stageXYAngleDeg', 0);
            [~, ~, ~, scanInit] = yOCTHardware('teardown');
            testCase.verifyFalse(scanInit, ...
                'Scanner state should be false after teardown');

            % Cache must be empty: status errors
            testCase.verifyError(@() yOCTHardware('status'), ...
                'myOCT:yOCTHardware:notInitialized');

            % Re-init with a different system must work
            [~, name, skip] = yOCTHardware('init', ...
                'OCTSystem', 'Ganymede', 'skipHardware', true, ...
                'oct2stageXYAngleDeg', 0);
            testCase.verifyEqual(name, 'ganymede');
            testCase.verifyTrue(skip);
        end

        %% System name change triggers re-init
        function testSystemNameChangeGan632ToGanymede(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'oct2stageXYAngleDeg', 0);
            [~, name, ~] = yOCTHardware('init', ...
                'OCTSystem', 'Ganymede', 'skipHardware', true, ...
                'oct2stageXYAngleDeg', 0);
            testCase.verifyEqual(name, 'ganymede');
        end

        function testSystemNameChangeGanymedeToGan632(testCase)
            yOCTHardware('init', 'OCTSystem', 'Ganymede', 'skipHardware', true, ...
                'oct2stageXYAngleDeg', 0);
            [~, name, ~] = yOCTHardware('init', ...
                'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'oct2stageXYAngleDeg', 0);
            testCase.verifyEqual(name, 'gan632');
        end

        %% Reset: clears cache and scanner state
        function testResetClearsCache(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'oct2stageXYAngleDeg', 0);
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

        %% Init errors without required params

        %% init errors without OCTSystem
        function testInitErrorsWithoutOCTSystem(testCase)
            testCase.verifyError(...
                @() yOCTHardware('init', 'oct2stageXYAngleDeg', 0), ...
                'myOCT:yOCTHardware:noSystemName');
        end

        %% Stage init: returns (0,0,0) when skipHardware is true
        function testInitStageReturnsOrigin(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'oct2stageXYAngleDeg', 0);
            [x0, y0, z0] = yOCTGetStagePosition();
            testCase.verifyEqual([x0; y0; z0], [0;0;0]);
        end

        %% yOCTStageMoveTo updates position, yOCTGetStagePosition reads it back
        function testMoveThenReadPosition(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'oct2stageXYAngleDeg', 0);
            yOCTStageMoveTo(1, 2, 3);
            [x0, y0, z0] = yOCTGetStagePosition();
            testCase.verifyEqual([x0; y0; z0], [1;2;3]);
        end

        %% yOCTGetStagePosition returns (0,0,0) after init with nonzero angle
        function testGetStagePositionWithAngle(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'oct2stageXYAngleDeg', 5);
            [x0, y0, z0] = yOCTGetStagePosition();
            testCase.verifyEqual([x0; y0; z0], [0;0;0]);
        end

        %% yOCTGetStagePosition errors if never initialized
        function testGetStagePositionErrorsAfterReset(testCase)
            testCase.verifyError(@() yOCTGetStagePosition(), ...
                'myOCT:yOCTHardware:stageNotInitialized');
        end

        %% yOCTStageMoveTo errors if never initialized
        function testMoveToErrorsAfterReset(testCase)
            testCase.verifyError(@() yOCTStageMoveTo(1, 2, 3), ...
                'myOCT:yOCTHardware:stageNotInitialized');
        end

        %% reset clears stage state
        function testResetClearsStageState(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'oct2stageXYAngleDeg', 0);
            yOCTHardware('reset');
            testCase.verifyError(@() yOCTGetStagePosition(), ...
                'myOCT:yOCTHardware:stageNotInitialized');
        end

        %% teardown clears stage state
        function testTeardownClearsStageState(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'oct2stageXYAngleDeg', 0);
            yOCTHardware('teardown');
            testCase.verifyError(@() yOCTGetStagePosition(), ...
                'myOCT:yOCTHardware:stageNotInitialized');
        end

        %% Changing OCT system auto-teardowns and clears stage state
        function testSystemChangeClearsStageState(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'oct2stageXYAngleDeg', 10);
            yOCTHardware('init', 'OCTSystem', 'Ganymede', 'skipHardware', true, ...
                'oct2stageXYAngleDeg', 0);
            % After system change, stage should be re-initialized at origin
            [x0, y0, z0] = yOCTGetStagePosition();
            testCase.verifyEqual([x0; y0; z0], [0;0;0]);
        end

    end
end
