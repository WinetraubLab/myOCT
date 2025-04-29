function [ptStartO, ptEndO] = yOCTApplyEnableZone(ptStart, ptEnd, enableZone, enableZoneRes)
%This function takes a collection of lines (and returns a collection of
%lines) after trimming the enable zoon, to prevent photobleaching in the disabled zone 
%   ptStart - point(s) to strat line x and y (in mm). Can be 2Xn matrix for
%       drawing multiple lines
%   ptEnd - corresponding end point (x,y), in mm
%   enableZone - a function handle returning 1 if we can photobleach in that coordinate, 0 otherwise.
%   	For example, this function will allow photobleaching only in a circle:
%       @(x,y)(x^2+y^2 < 2^2). enableZoon accuracy.
%   enableZoonRes - resolution / accuracy of enable zoon (mm). Default
%       1/100 mm

%Some play along values:
%ptStart = [-1 -1;-1 1];
%ptEnd = [1 1;1 -1];
%enableZone = @(x,y)(x.^2+y.^2<=0.5^2 | x.^2+y.^2>1^2);
%enableZoneRes = 1e-3;

if ~exist('enableZoonRes','var')
    enableZoneRes = 1/100; %mm
end

%% Preform work

ptStartO = [];
ptEndO = [];
for i=1:size(ptStart,2)
    pt1 = ptStart(:,i);
    pt2 = ptEnd(:,i);

    d = sqrt(sum((pt1-pt2).^2));
    n = max(d/enableZoneRes,1); %How many points fit in the line

    %Compute points in between those initial two
    clear p;
    p(1,:) = linspace(pt1(1),pt2(1),n);
    p(2,:) = linspace(pt1(2),pt2(2),n);
    p = [p(:,1) p p(:,end)]; %#ok<AGROW> %Add start and finish point twice

    %Figure out which points are in the enable Zone
    isEnabled = enableZone(p(1,:),p(2,:));
    isEnabled([1 end]) = 0; %Will us later to find boundaries
    df = [0 diff(isEnabled)];

    iStart = find(df==1); %These are start points
    iEnd = find(df==-1); %These are end points

    if (length(iStart) ~= length(iEnd))
        error('Problem here, find me yOCTApplyEnableZone');
    end

    for j=1:length(iStart)
        ptStartO(:,end+1) = p(:,iStart(j)); 
        ptEndO(:,end+1) = p(:,iEnd(j));
    end
end

%% Plot results
if true
    return;
end

for i=1:size(ptStartO,2)
    plot([ptStartO(1,i) ptEndO(1,i)],[ptStartO(2,i) ptEndO(2,i)]);
    if (i==1)
        hold on;
    end
end
hold off