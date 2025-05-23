function [ptStartO, ptEndO] = yOCTApplyEnableZone(...
    ptStart, ptEnd, enableZone, enableZoneRes)
% This function takes a collection of lines (and returns a collection of
% lines) after trimming the enable zone, to prevent photobleaching in the
% disabled zone.
% This function works on 2D lines (x,y) and 3D lines (x,y,z)
%
% INPUTS:
%   ptStart: line start coordinate (dim,n). Where dim=1 is x coordinate,
%       dim=2 is the y coordinate etc. n is number of lines. 
%       Values are in mm.
%       If lines are 2D, ptStart is expected to have size (2,n), if lines
%       are 3D, ptStart is expected to have size (3,n).
%   ptEnd: corresponding line end point in mm (dim,n).
%   enableZone: a function handle returning 1 if we can photobleach in
%       that coordinate, 0 otherwise. For example, this function will allow 
%       photobleaching only in a circle:
%           @(x,y)(x^2+y^2 < 2^2)
%       If ptStart and ptEnd are 3D then function should have @(x,y,z)
%       handle. For example:
%           @(x,y,z)(x^2+y^2 < 2^2)
%   enableZoneRes - resolution / accuracy of enable zone (mm). Default
%       0.010mm
% OUTPUTS:
%   ptStartO, ptEndO - start and end positions of the remaning lines.

%% Input checks

if ~exist('enableZoneRes','var')
    enableZoneRes = 0.010; %mm
end

assert(all(size(ptStart)==size(ptEnd)),'Size of ptStart and ptEnd should be the same');
dim = size(ptStart,1);
assert(dim>1 && dim<=3);

if dim == 3
    assert(all(ptStart(3,:)==ptEnd(3,:)),'Different z for start and end points is not implemented');
    enableZone1 = enableZone;
else
    % Add a 3rd dimension
    ptStart(3,:) = 0;
    ptEnd(3,:) = 0;
    enableZone1 = @(x,y,z)(enableZone(x,y));
end

%% Preform work
ptStartO = [];
ptEndO = [];
for i=1:size(ptStart,2) % Loop over all points
    pt1 = ptStart(:,i);
    pt2 = ptEnd(:,i);

    d = sqrt(sum((pt1-pt2).^2));
    n = round(max(d/enableZoneRes,1)); % How many points fit in the line

    % Compute points in between those initial two
    clear p;
    p(1,:) = linspace(pt1(1),pt2(1),n);
    p(2,:) = linspace(pt1(2),pt2(2),n);
    p(3,:) = ones(1,n) * pt1(3);
    p = [p(:,1) p p(:,end)]; %#ok<AGROW> %Add start and finish point twice

    % Figure out which points are in the enable Zone
    isEnabled = enableZone1(p(1,:),p(2,:),p(3,:));
    isEnabled([1 end]) = 0; %Will us later to find boundaries
    df = [0 diff(isEnabled)];

    iStart = find(df==1); %These are start points
    iEnd = find(df==-1); %These are end points

    if (length(iStart) ~= length(iEnd))
        error('Problem here, find me yOCTApplyEnableZone');
    end

    for j=1:length(iStart)
        ptStartO(:,end+1) = p(:,iStart(j)); %#ok<AGROW>
        ptEndO(:,end+1) = p(:,iEnd(j)); %#ok<AGROW>
    end
end

if dim == 2
    % Remove 3rd dimension
    ptStartO(3,:)=[];
    ptEndO(3,:)=[];
end