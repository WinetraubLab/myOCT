classdef test_yOCTSimulateTileScan < matlab.unittest.TestCase

    properties
        
    end
    
    methods(Test)
        function testLoadSaveNoStitchingNoFocus(testCase)
            % Confirm that with no focus, three peaks show up at the right positions
            dummyData = zeros(1000,100,5)+1;
            pixel_size_um = 1; 
            outputFolder = 'tmp/';
            octProbePath = yOCTGetProbeIniPath('40x','OCTP900');
            focusPositionInImageZpix = 1;
            focusSigma = 1000; % Very large focus, such that it has no effect
            dummyData([100, 200, 300],:,:) = 100;

            % Generate simulated data
            yOCTSimulateTileScan(dummyData,outputFolder,...
                'pixelSize_um', pixel_size_um, ...
                'zDepths',      0, ... [mm]
                'focusPositionInImageZpix', focusPositionInImageZpix,... No Z scan filtering
                'focusSigma',focusSigma, ...
                'octProbePath', octProbePath ...
                );

            % Make sure only one file exists
            assert(exist('tmp/Data01/data.mat','file'))
            assert(~exist('tmp/Data02/data.mat','file'))

            % Load the generated simulated data
            yOCTProcessTiledScan(...
                outputFolder, ... Input
                {'tmp2.tif'},... 
                'focusPositionInImageZpix', focusPositionInImageZpix,... No Z scan filtering
                'focusSigma',focusSigma, ...
                'dispersionQuadraticTerm',0, ... Use 0 as simulated data doesn't have dispersion
                'interpMethod','sinc5', ...
                'cropZAroundFocusArea',false ...
                );

            % Clean up
            rmdir(outputFolder, 's'); % Remove the folder and all its contents
            [dat, dim] = yOCTFromTif('tmp2.tif');
            delete tmp2.tif;

            % Verify three peaks are in the right position (intensity is
            % high)
            [~,i100] = min(abs(dim.z.values*1e3-100));
            fprintf('100 microns is at pixel %.0f\n',i100)
            [~,i200] = min(abs(dim.z.values*1e3-200));
            [~,i300] = min(abs(dim.z.values*1e3-300));
            flatDat1 = mean(dat,[2 3]);
            assert(flatDat1(i100) > prctile(flatDat1,80));
            assert(flatDat1(i200) > prctile(flatDat1,80));
            assert(flatDat1(i300) > prctile(flatDat1,80));
            %plot(dim.z.values*1e3,(mean(dat,[2 3])))
        end

        function testLoadSaveNoStitchingWithFocus(testCase)
            % Confirm that with focus (at 100um) we see one line
            dummyData = zeros(1000,100,5)+1;
            pixel_size_um = 1; 
            outputFolder = 'tmp/';
            octProbePath = yOCTGetProbeIniPath('40x','OCTP900');
            focusPositionInImageZpix = 69; % 69 pixels (corresponding to 100um).
            focusSigma = 10; % thighter focus 
            dummyData([100, 200, 300],:,:) = 100; % Three lines, but only 100um is in focus.

            % Generate simulated data
            yOCTSimulateTileScan(dummyData,outputFolder,...
                'pixelSize_um', pixel_size_um, ...
                'zDepths',      0, ... [mm]
                'focusPositionInImageZpix', focusPositionInImageZpix,... No Z scan filtering
                'focusSigma',focusSigma, ...
                'octProbePath', octProbePath ...
                );

            % Load the generated simulated data
            yOCTProcessTiledScan(...
                outputFolder, ... Input
                {'tmp2.tif'},... 
                'focusPositionInImageZpix', focusPositionInImageZpix,... No Z scan filtering
                'focusSigma',focusSigma, ...
                'dispersionQuadraticTerm',0, ... Use 0 as simulated data doesn't have dispersion
                'interpMethod','sinc5', ...
                'cropZAroundFocusArea',false ...
                );

            % Clean up
            [dat, dim] = yOCTFromTif('tmp2.tif');
            delete tmp2.tif;
            flatDat2 = mean(dat,[2 3]);
            
            % Verify that z=0 (which is the focus position), is indeed in
            % focus
            [~,i0] = min(abs(dim.z.values*1e3));
            assert(flatDat2(i0) > prctile(flatDat2,80), 'Verify z=0 is in focus');
            %plot(dim.z.values*1e3,(mean(dat,[2 3])))
        end

        function testLoadSaveNoStitchingWithWrongFocus(testCase)
            % Confirm that when selecting the wrong focus lines don't show
            % up in focus
            dummyData = zeros(1000,100,5)+1;
            pixel_size_um = 1; 
            outputFolder = 'tmp/';
            octProbePath = yOCTGetProbeIniPath('40x','OCTP900');
            focusPositionInImageZpix = 69; % 69 pixels (corresponding to 100um).
            focusSigma = 10; % thighter focus 
            dummyData([100, 200, 300],:,:) = 100; % Three lines, but only 100um is in focus.

            % Generate simulated data
            yOCTSimulateTileScan(dummyData,outputFolder,...
                'pixelSize_um', pixel_size_um, ...
                'zDepths',      0, ... [mm]
                'focusPositionInImageZpix', focusPositionInImageZpix,... No Z scan filtering
                'focusSigma',focusSigma, ...
                'octProbePath', octProbePath ...
                );

            % Load the generated simulated data - in focus
            yOCTProcessTiledScan(...
                outputFolder, ... Input
                {'tmp2.tif'},... 
                'focusPositionInImageZpix', focusPositionInImageZpix,...
                'focusSigma',focusSigma, ...
                'dispersionQuadraticTerm',0, ... Use 0 as simulated data doesn't have dispersion
                'interpMethod','sinc5', ...
                'cropZAroundFocusArea',true ...
                );
            [dat, ~] = yOCTFromTif('tmp2.tif');
            datInFocus = mean(dat(:));
            delete tmp2.tif;

            % Load the generated simulated data - out of focus
            yOCTProcessTiledScan(...
                outputFolder, ... Input
                {'tmp2.tif'},... 
                'focusPositionInImageZpix', focusPositionInImageZpix+10,...
                'focusSigma',focusSigma, ...
                'dispersionQuadraticTerm',0, ... Use 0 as simulated data doesn't have dispersion
                'interpMethod','sinc5', ...
                'cropZAroundFocusArea',true ...
                );
            [dat, ~] = yOCTFromTif('tmp2.tif');
            datOutFocus = mean(dat(:));
            delete tmp2.tif;

            % Clean up
            rmdir(outputFolder, 's'); % Remove the folder and all its contents

            assert(datInFocus > datOutFocus,'Focus position dose not work');
        end

        function testSimulatedDepths(testCase)

            % Generate dataset
            % Expectation, one line in depth 100mu, should show up in focus
            % when zDepth_mm is 0, not in focsus otherwise.
            % Focus is 100um below zDepth_mm = 0 which correspond to pixel
            % 100/n = 100/1.4 = 69 (approx)
            dummyData = zeros(1000,100,5)+1;
            pixel_size_um = 1; 
            outputFolder = 'tmp/';
            octProbePath = yOCTGetProbeIniPath('40x','OCTP900');
            focusPositionInImageZpix = 69;
            focusSigma = 10;
            dummyData(100,:,:) = 100;
            zDepths_mm = [-50 0 100]*1e-3; % mm

            % Generate simulated data
            yOCTSimulateTileScan(dummyData,outputFolder,...
                'pixelSize_um', pixel_size_um, ...
                'zDepths', zDepths_mm, ... 
                'focusPositionInImageZpix', focusPositionInImageZpix,...
                'focusSigma',focusSigma, ...
                'octProbePath', octProbePath ...
                );

            % Load Data01 (corresponding to zDepth = -0.05 mm)
            [interf, dim] = yOCTLoadInterfFromFile('tmp/Data01/', 'OCTSystem', 'Simulated Ganymede');
            [cpx, ~] = yOCTInterfToScanCpx(interf,dim,'dispersionQuadraticTerm', 0);
            dat = abs(cpx);
            assert(mean(dat(focusPositionInImageZpix,:,:),[2 3]) < 5, 'Intensity should be low');
            %figure(1); plot(dim.z.values,(mean(dat,[2 3])))

            % Load Data02 (corresponding to zDepth = 0 mm), we should see
            % something at the focus point
            [interf, dim] = yOCTLoadInterfFromFile('tmp/Data02/', 'OCTSystem', 'Simulated Ganymede');
            [cpx, ~] = yOCTInterfToScanCpx(interf,dim,'dispersionQuadraticTerm', 0);
            dat = abs(cpx);
            assert(mean(dat(focusPositionInImageZpix,:,:),[2 3]) > 5, 'Intensity should be high');
            %figure(1); plot(dim.z.values,(mean(dat,[2 3])))

            % Load Data03 (corresponding to zDepth = 0.1 mm)
            [interf, dim] = yOCTLoadInterfFromFile('tmp/Data03/', 'OCTSystem', 'Simulated Ganymede');
            [cpx, ~] = yOCTInterfToScanCpx(interf,dim,'dispersionQuadraticTerm', 0);
            dat = abs(cpx);
            assert(mean(dat(focusPositionInImageZpix,:,:),[2 3]) < 5, 'Intensity should be low');
            %figure(1); plot(dim.z.values,(mean(dat,[2 3])))
        end

        function testLoadSaveWithStitching(testCase)
            dummyData = zeros(1000,100,1)+1;
            pixel_size_um = 1; 
            outputFolder = 'tmp/';
            octProbePath = yOCTGetProbeIniPath('40x','OCTP900');
            focusPositionInImageZpix = 1;
            focusSigma = 1000; % Very large focus, such that it has no effect
            dummyData([100, 200, 300],:,:) = 100;
            zDepths_mm = (-5:5:400)*1e-3; % mm

            % Generate simulated data
            yOCTSimulateTileScan(dummyData,outputFolder,...
                'pixelSize_um', pixel_size_um, ...
                'zDepths', zDepths_mm, ... 
                'focusPositionInImageZpix', focusPositionInImageZpix,...
                'focusSigma',focusSigma, ...
                'octProbePath', octProbePath ...
                );

            % Load the generated simulated data
            yOCTProcessTiledScan(...
                outputFolder, ... Input
                {'tmp2.tif'},... 
                'focusPositionInImageZpix', focusPositionInImageZpix,...
                'focusSigma',focusSigma, ...
                'dispersionQuadraticTerm',0, ... Use 0 as simulated data doesn't have dispersion
                'interpMethod','sinc5', ...
                'cropZAroundFocusArea',true, ...
                'outputFilePixelSize_um',1 ...
                );
            [dat, dim] = yOCTFromTif('tmp2.tif');
            dat(isnan(dat))=0;
            datMean = mean(dat,[2 3]);
            delete tmp2.tif;
            rmdir(outputFolder, 's'); % Remove the folder and all its contents
            
            % Make sure the peaks show in the data
            dim = yOCTChangeDimensionsStructureUnits(dim,'um');
            [~, i100] = min(abs(dim.z.values-100));
            [~, i200] = min(abs(dim.z.values-200));
            [~, i300] = min(abs(dim.z.values-300));
            [~, i250] = min(abs(dim.z.values-250));
            assert(datMean(i100) > prctile(datMean,80), 'Value should be high')
            assert(datMean(i200) > prctile(datMean,80), 'Value should be high')
            assert(datMean(i300) > prctile(datMean,80), 'Value should be high')
            assert(datMean(i250) < prctile(datMean,60), 'Value should be low')
            %figure(1); plot(dim.z.values,mean(dat,[2 3]))

            % Check the dimensions size of the file
            assert(length(dim.x.values) == size(dummyData,2), 'X dimensions size is off')
            assert(length(dim.y.values) == size(dummyData,3), 'Y dimensions size is off')

            % Check start and finish of z dimensoin
            assert(abs(dim.z.values(1)-zDepths_mm(1)*1e3)<1,'Z start issue')
            assert(abs(dim.z.values(end)-zDepths_mm(end)*1e3)<1,'Z end issue')
            
            % Check pixel size
            assert(all(abs(diff(dim.x.values)-1)<0.01),'X dimension should be 1um')
            assert(all(abs(diff(dim.z.values)-1)<0.01),'Z dimension should be 1um')
        end
    end
    
end