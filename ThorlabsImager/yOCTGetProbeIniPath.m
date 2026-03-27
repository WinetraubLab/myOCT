function p = yOCTGetProbeIniPath(magnificationStr, otherKeyword)
% Returns probe ini absulte path for usage by this function
% Some options:
% 	p = yOCTGetProbeIniPath('10x'); 
%	p = yOCTGetProbeIniPath('40x')
%	p = yOCTGetProbeIniPath('10x','OCTP900')
%	p = yOCTGetProbeIniPath('20x','OCTP900')

%% Input checks
if ~exist('magnificationStr','var') || isempty(magnificationStr)
	magnificationStr = '10x';
end
if ~exist('otherKeyword','var') || isempty(otherKeyword)
	otherKeyword = '';
end

overallKeyword = lower([magnificationStr otherKeyword]);

%% Set name 
switch(overallKeyword)
	case '10x'
		probeName = 'Probe - Olympus 10x.ini';
	case '40x'
		probeName = 'Probe - Olympus 40x.ini';
	case '10xoctp900'
		probeName = 'Probe - Olympus 10x - OCTP900.ini';
	case '20xoctp900'
		probeName = 'Probe - Olympus 20x - OCTP900.ini';
	case '40xoctp900'
		probeName = 'Probe - Olympus 40x - OCTP900.ini';
	otherwise
		error('Can''t recognize which ini probe to use');
end

%% Path
currentFileFolder = [fileparts(mfilename('fullpath')) '\'];
p = awsModifyPathForCompetability(...
    [currentFileFolder '\' probeName]);
