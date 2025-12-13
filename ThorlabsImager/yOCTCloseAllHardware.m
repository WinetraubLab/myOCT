function yOCTCloseAllHardware()
%yOCTCloseAllHardware Closes all hardware connections for the OCT system

    % Load library (should already be loaded to memory)
    [octSystemModule, octSystemName, skipHardware] = yOCTLoadHardwareLibSetUp();

    %% Close hardware based on system type
    if ~skipHardware
        switch(octSystemName)
            case 'ganymede'
                % Ganymede: C# DLL - close scanner only
                yOCTScannerClose();
                
            case 'gan632'
                % Gan632: Python SDK - close all hardware (stages + scanner)
                octSystemModule.cleanup.yOCTCloseAllHardware();
                
            otherwise
                error('Unknown OCT system: %s', octSystemName);
        end
    end