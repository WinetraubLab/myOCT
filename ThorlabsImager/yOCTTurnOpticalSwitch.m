function yOCTTurnOpticalSwitch(newState)
% This script controls Agiltron Optical Switch. To select between
% photodiode path and OCT
% https://docs.google.com/document/d/110r7mnKVDM_gtPJmkoLcAxplEn8t0JWKQvdcDOx5qJA/edit
% INPUTS:
%   newState 
%       - set to 'photodiode' to connect photo diode fiber
%       - set to 'OCT' to connect OCT 
%       - set to 'init' to initialize com without turning anything. Note that all options will init before running.

tic
%% Input Processing
% Select COM, if doesn't exist use serialportlist to list all options
com_chanel = 'COM3';  

%% Store com for fast activation
persistent sp_structure;
if isempty(sp_structure)
    sp_structure.com_chanel = '';
    sp_structure.sp = [];
end

%% Connect to port if needed
if ~strcmp(sp_structure.com_chanel,com_chanel) % com chanel has changed, connect to Port
    sp_structure.com_chanel = com_chanel;
    sp_structure.sp=serialport(com_chanel,9600,'Timeout',5); %If that COM doesn't exist use serialportlist to list all options.
end
%delete(sp_structure.sp) % Disconnect from port

%% Convevert between state and the command to send to switch
switch(lower(newState))
    case 'photodiode'
        data = [1 18 0 1];
    case 'oct'
        data = [1 18 0 2];
    case 'init'
        return
    otherwise 
        error('Don''t know state %s',newState)
end

%% Execute command
write(sp_structure.sp,data,'uint8'); % Selects photobleach diode

%% Timing analysis
tt_ms=toc()*1e3;
if (tt_ms > 2)
    %warning("yOCTTurnOpticalSwitch('%s') took %.1fms, which is longer than expected",newState,tt_ms);
end
