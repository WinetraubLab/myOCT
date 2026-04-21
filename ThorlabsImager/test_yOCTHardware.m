classdef test_yOCTHardware < matlab.unittest.TestCase
    % All tests use skipHardware=true so no real DLL or Python module is
    % needed. What we verify is pure cache and state logic.


    properties (Access = private)
        ProbeIni
    end
    % Use a probe file
    methods (TestClassSetup)
        function findProbeIni(testCase)
            thorlabsFolder = fileparts(which('yOCTHardware'));
            testCase.ProbeIni = fullfile(thorlabsFolder, ...
                'Probe Olympus - 10x - OCTP900.ini');
            assert(exist(testCase.ProbeIni, 'file') == 2, ...
                'Probe INI not found: %s', testCase.ProbeIni);
        end
    end

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
                'octProbePath', testCase.ProbeIni);
            testCase.verifyEqual(name, 'gan632');
            testCase.verifyEmpty(module);
            testCase.verifyTrue(skip);
            testCase.verifyFalse(scanInit, ...
                'Scanner should not be initialized when skipHardware=true');
        end

        %% Init: early return with same args
        function testEarlyReturnWithSameArgs(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'octProbePath', testCase.ProbeIni);
            [module, name, skip, scanInit] = yOCTHardware('init', ...
                'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'octProbePath', testCase.ProbeIni);
            testCase.verifyEqual(name, 'gan632');
            testCase.verifyEmpty(module);
            testCase.verifyTrue(skip);
            testCase.verifyFalse(scanInit);
        end

        %% Status: returns cache with all outputs
        function testStatusReturnsCache(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'octProbePath', testCase.ProbeIni);
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

        %% Status: passes when skipHardware=true (scanner not needed)
        function testStatusPassesWithSkipHardware(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'octProbePath', testCase.ProbeIni);
            [~, name, skip] = yOCTHardware('status');
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
                'octProbePath', testCase.ProbeIni);
            [~, ~, ~, scanInit] = yOCTHardware('teardown');
            testCase.verifyFalse(scanInit, ...
                'Scanner state should be false after teardown');

            % Cache must be empty: status errors
            testCase.verifyError(@() yOCTHardware('status'), ...
                'myOCT:yOCTHardware:notInitialized');

            % Re-init with a different system must work
            [~, name, skip] = yOCTHardware('init', ...
                'OCTSystem', 'Ganymede', 'skipHardware', true, ...
                'octProbePath', testCase.ProbeIni);
            testCase.verifyEqual(name, 'ganymede');
            testCase.verifyTrue(skip);
        end

        %% System name change triggers re-init
        function testSystemNameChangeGan632ToGanymede(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'octProbePath', testCase.ProbeIni);
            [~, name, ~] = yOCTHardware('init', ...
                'OCTSystem', 'Ganymede', 'skipHardware', true, ...
                'octProbePath', testCase.ProbeIni);
            testCase.verifyEqual(name, 'ganymede');
        end

        function testSystemNameChangeGanymedeToGan632(testCase)
            yOCTHardware('init', 'OCTSystem', 'Ganymede', 'skipHardware', true, ...
                'octProbePath', testCase.ProbeIni);
            [~, name, ~] = yOCTHardware('init', ...
                'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'octProbePath', testCase.ProbeIni);
            testCase.verifyEqual(name, 'gan632');
        end

        %% Reset: clears cache and scanner state
        function testResetClearsCache(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'octProbePath', testCase.ProbeIni);
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

        %% init errors without OCTSystem
        function testInitErrorsWithoutOCTSystem(testCase)
            testCase.verifyError(...
                @() yOCTHardware('init', 'skipHardware', true), ...
                'myOCT:yOCTHardware:noSystemName');
        end

        %% Stage init: returns (0,0,0) when skipHardware is true
        function testInitStageReturnsOrigin(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'octProbePath', testCase.ProbeIni);
            [x0, y0, z0] = yOCTGetStagePosition();
            testCase.verifyEqual([x0; y0; z0], [0;0;0]);
        end

        %% yOCTStageMoveTo updates position, yOCTGetStagePosition reads it back
        function testMoveThenReadPosition(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'octProbePath', testCase.ProbeIni);
            yOCTStageMoveTo(1, 2, 3);
            [x0, y0, z0] = yOCTGetStagePosition();
            testCase.verifyEqual([x0; y0; z0], [1;2;3]);
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
                'octProbePath', testCase.ProbeIni);
            yOCTHardware('reset');
            testCase.verifyError(@() yOCTGetStagePosition(), ...
                'myOCT:yOCTHardware:stageNotInitialized');
        end

        %% teardown clears stage state
        function testTeardownClearsStageState(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'octProbePath', testCase.ProbeIni);
            yOCTHardware('teardown');
            testCase.verifyError(@() yOCTGetStagePosition(), ...
                'myOCT:yOCTHardware:stageNotInitialized');
        end

        %% Changing OCT system auto-teardowns and clears stage state
        function testSystemChangeClearsStageState(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'octProbePath', testCase.ProbeIni);
            yOCTHardware('init', 'OCTSystem', 'Ganymede', 'skipHardware', true, ...
                'octProbePath', testCase.ProbeIni);
            % After system change, stage should be re-initialized at origin
            [x0, y0, z0] = yOCTGetStagePosition();
            testCase.verifyEqual([x0; y0; z0], [0;0;0]);
        end

        %% INI auto-read: when octProbePath is provided, init reads the
        %  stage rotation angle from the INI and initializes the stage.
        function testInitReadsAngleFromIni(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'octProbePath', testCase.ProbeIni);

            global goct2stageXYAngleDeg; %#ok<GVMIS>
            probe = yOCTReadProbeIniToStruct(testCase.ProbeIni);
            testCase.verifyEqual(goct2stageXYAngleDeg, probe.Oct2StageXYAngleDeg);
        end

        %% No probe path => stage NOT initialized (OCT-only mode)
        function testInitWithoutProbeSkipsStage(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true);
            testCase.verifyError(@() yOCTGetStagePosition(), ...
                'myOCT:yOCTHardware:stageNotInitialized');
        end

        %% yOCTVerifyMotionRange registers range in globals (skipHardware
        %  mode avoids any real motion).
        function testVerifyMotionRangeRegistersGlobals(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'octProbePath', testCase.ProbeIni);

            yOCTVerifyMotionRange([-1 -2 -3], [1 2 3]);

            global gRegisteredMotionRangeMin_OCT; %#ok<GVMIS>
            global gRegisteredMotionRangeMax_OCT; %#ok<GVMIS>
            testCase.verifyEqual(gRegisteredMotionRangeMin_OCT(:), [-1;-2;-3]);
            testCase.verifyEqual(gRegisteredMotionRangeMax_OCT(:), [ 1; 2; 3]);
        end

        %% Registered range always includes the origin so homing is allowed
        %  even when the scan's bounding box does not contain (0,0,0).
        function testVerifyMotionRangeIncludesOrigin(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'octProbePath', testCase.ProbeIni);

            % Scan bounding box entirely in z>0; origin (z=0) must still be allowed
            yOCTVerifyMotionRange([0 0 0.002], [0 0 0.020]);

            % Homing back to (0,0,0) must not error
            yOCTStageMoveTo(0, 0, 0);
            [x0, y0, z0] = yOCTGetStagePosition();
            testCase.verifyEqual([x0; y0; z0], [0; 0; 0]);
        end

        %% yOCTStageMoveTo: when a range is registered, targets inside are allowed
        function testMoveToAllowsWithinRegisteredRange(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'octProbePath', testCase.ProbeIni);
            yOCTVerifyMotionRange([-1 -1 -1], [1 1 1]);

            yOCTStageMoveTo(0.5, -0.5, 0);
            [x0, y0, z0] = yOCTGetStagePosition();
            testCase.verifyEqual([x0; y0; z0], [0.5; -0.5; 0]);
        end

        %% yOCTStageMoveTo: when a range is registered, targets outside error
        function testMoveToRejectsOutsideRegisteredRange(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'octProbePath', testCase.ProbeIni);
            yOCTVerifyMotionRange([-1 -1 -1], [1 1 1]);

            testCase.verifyError(@() yOCTStageMoveTo(2, 0, 0), ...
                'myOCT:yOCTHardware:positionOutOfRange');
        end

        %% reset clears registered motion range
        function testResetClearsRegisteredRange(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'octProbePath', testCase.ProbeIni);
            yOCTVerifyMotionRange([-1 -1 -1], [1 1 1]);

            yOCTHardware('reset');

            global gRegisteredMotionRangeMin_OCT; %#ok<GVMIS>
            global gRegisteredMotionRangeMax_OCT; %#ok<GVMIS>
            testCase.verifyEmpty(gRegisteredMotionRangeMin_OCT);
            testCase.verifyEmpty(gRegisteredMotionRangeMax_OCT);
        end

        %% teardown clears registered motion range
        function testTeardownClearsRegisteredRange(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true, ...
                'octProbePath', testCase.ProbeIni);
            yOCTVerifyMotionRange([-1 -1 -1], [1 1 1]);

            yOCTHardware('teardown');

            global gRegisteredMotionRangeMin_OCT; %#ok<GVMIS>
            global gRegisteredMotionRangeMax_OCT; %#ok<GVMIS>
            testCase.verifyEmpty(gRegisteredMotionRangeMin_OCT);
            testCase.verifyEmpty(gRegisteredMotionRangeMax_OCT);
        end

    end
end
