function Demo_DispersionCorrectionManual
%Run this demo to find dispersionParameter, manually

close all;

%% Inputs
%Ganymede
filePath = [''];

%% Pre-Process
%Load Intef From file
[interf,dimensions] = yOCTLoadInterfFromFile(filePath ...
    ,'BScanAvgFramesToProcess', 1 ... To compute dispersion correction only 1 frame is required
    ,'YFramesToProcess',1         ... To compute dispersion correction only 1 frame is required
    );

%Equispace interferogram to save computation time while re-processing
[interfe,dimensionse] = yOCTEquispaceInterf(interf,dimensions);

txt = uicontrol('Style','text',...
        'Position',[100 45 400 20],...
        'String','log10(dispersionQuadraticTerm)');
initialGuess = log10(100);
sld = uicontrol('Style', 'slider',...
        'Min',-10,'Max',10,'Value',initialGuess,...
        'Position', [100 20 400 20],...
        'SliderStep',[0.0005 0.1],... %[minor step, major step]
        'Callback', @(source,event)(SliderCallback(source,event,interfe,dimensionse))); 
    
%Present first image
SliderCallback(initialGuess,[],interfe,dimensionse)
end
    
function SliderCallback(source,event,interfe,dimensionse)
if ~isnumeric(source)
    val = source.Value;
else
    val = source;
end

dispersionQuadraticTerm = sign(val)*10^(abs(val));
scanCpxe = yOCTInterfToScanCpx( interfe ,dimensionse ...
    ,'dispersionQuadraticTerm', dispersionQuadraticTerm );
lg = log(abs(scanCpxe));
imagesc(lg);
caxis([-5 6]);
colormap gray;
title(sprintf('dispersionQuadraticTerm=%.3e [nm^2/rad]',dispersionQuadraticTerm));
end