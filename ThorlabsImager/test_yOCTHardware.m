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

        %% initStage: returns (0,0,0) with skipHardware=true
        function testInitStageReturnsOrigin(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true);
            [x0, y0, z0] = yOCTHardware('initStage');
            testCase.verifyEqual(x0, 0);
            testCase.verifyEqual(y0, 0);
            testCase.verifyEqual(z0, 0);
        end

        %% initStage: errors when hardware not initialized
        function testInitStageErrorsWithoutInit(testCase)
            testCase.verifyError(...
                @() yOCTHardware('initStage'), ...
                'myOCT:yOCTHardware:notInitialized');
        end

        %% stageStatus: returns state after initStage
        function testStageStatusAfterInit(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true);
            yOCTHardware('initStage', 'oct2stageXYAngleDeg', 5);
            [angle, posOCT, posStage] = yOCTHardware('stageStatus');
            testCase.verifyEqual(angle, 5);
            testCase.verifyEqual(posOCT, [0;0;0]);
            testCase.verifyEqual(posStage, [0;0;0]);
        end

        %% stageStatus: errors when stage not initialized
        function testStageStatusErrorsWithoutInitStage(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true);
            testCase.verifyError(...
                @() yOCTHardware('stageStatus'), ...
                'myOCT:yOCTHardware:stageNotInitialized');
        end

        %% updateStagePosition: updates tracked position
        function testUpdateStagePosition(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true);
            yOCTHardware('initStage');
            yOCTHardware('updateStagePosition', ...
                'posOCT', [1;2;3], 'posStage', [1.1;2.2;3.3]);
            [~, posOCT, posStage] = yOCTHardware('stageStatus');
            testCase.verifyEqual(posOCT, [1;2;3]);
            testCase.verifyEqual(posStage, [1.1;2.2;3.3]);
        end

        %% Reset: clears stage state
        function testResetClearsStageState(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true);
            yOCTHardware('initStage');
            yOCTHardware('reset');
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true);
            testCase.verifyError(@() yOCTHardware('stageStatus'), ...
                'myOCT:yOCTHardware:stageNotInitialized');
        end

        %% Teardown: clears stage state
        function testTeardownClearsStageState(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true);
            yOCTHardware('initStage');
            yOCTHardware('teardown');
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true);
            testCase.verifyError(@() yOCTHardware('stageStatus'), ...
                'myOCT:yOCTHardware:stageNotInitialized');
        end

    end
end
