function [correctedScan, correctedScanValidDataMap] = yOCTOpticalPathCorrection(inputScan, inputScanDimensions, opticalPathCorrectionOptions)
%%This function performs optical path correction on the inputScan
%
% INPUTS:
%   - inputScan - 2D or 3D volume with dimensions (z,x,y). More if there is
%     A/B scan averaging, see yOCTLoadInterfFromFile for more information. 
%     Note: inputScan must only contain real values (not complex). A-scan 
%           and B-scan averaging must be performed before calling
%           yOCTOpticalPathCorrection
%   - inputScanDimensions - The dimension information of the inputScan 
%   - opticalPathCorrectionOptions - This variable must be one of the
%     following options:
%       1. Path to the Volumes folder. This is also where the ScanInfo.json
%          file is stored 
%       2. Struct containing information extracted from ScanInfo.json.
%          This is the output of the awsReadJSON function. 
%       3. The optical path correction polynomial coefficient stores in an
%          array. The length of this array must be 5. The polynomial
%          elements are used as follows: 
%          x*OP_p(1)+y*OP_p(2)+x.^2*OP_p(3)+y.^2*OP_p(4)+x.*y*OP_p(5)
%          where x and y are location coordinates of the scan.
%          The results of the correction polynomial operation are added to the
%          z-coordinates and used for interpolation in order to flatten the
%          parabola shape at the gel-tissue interface in the XZ scans
%
% OUTPUTS:
%   - correctedScan - Scan which has the applied optical path correction.
%                     Any pixel values in the scan which were interpolated 
%                     as nan values, have been replaced with 0's. This
%                     replacement has been made to avoid having nan values
%                     as part of the image
%
%   - correctedScanValidDataMap - This map has the same dimensions as the
%                                 correctedScan output. correctedScanValidDataMap 
%                                 is a mask of correctedScan. The mask is set 
%                                 to 1 at coordinates where data exists in the 
%                                 correctedScan. The mask also assigns 0 to 
%                                 coordinates where valid data does not exist 
%                                 in correctedScan (see comment about nan 
%                                 values under correctedScan)

%% Check if dimensions have valid units
if strcmpi(inputScanDimensions.x.units, 'na') || ...
   strcmpi(inputScanDimensions.y.units, 'na') || ...
   strcmpi(inputScanDimensions.z.units, 'na')
    error(['The units of the dimensions cannot be NA or na. Please refer to', ...
          ' yOCTTileScanGetDimOfOneTile in order to get dimensions with', ...
          ' units for one tile. Pass these dimensions into yOCTLoadInterfFromFile', ...
          ' in order to obtain dimensions with units for a particular scan.']);
end

%% Extract optical path polynomial from opticalPathCorrectionOptions
if isstruct(opticalPathCorrectionOptions)
    OP_p = opticalPathCorrectionOptions.octProbe.OpticalPathCorrectionPolynomial;
    OP_p = OP_p(:)';
elseif isstring(opticalPathCorrectionOptions)
    inputVolumeFolder = awsModifyPathForCompetability([opticalPathCorrectionOptions '/']);
    json = awsReadJSON([inputVolumeFolder 'ScanInfo.json']);
    OP_p = json.octProbe.OpticalPathCorrectionPolynomial;
    OP_p = OP_p(:)';
elseif ismatrix(opticalPathCorrectionOptions)
    if not(isequal(size(opticalPathCorrectionOptions), [1,5])) && not(isequal(size(opticalPathCorrectionOptions), [5,1]))
        error('Optical path correction polynomial must have 5 terms')
    end
    OP_p = opticalPathCorrectionOptions;
else
    error('opticalPathCorrectionOptions must be a file path to the ScanInfo.json file, a struct representing the json, or an array of polynomial terms.');
end

%% Instantiate variable for scan with optical path correction
correctedScan = zeros(size(inputScan));

%% Change dimensions to microns units
inputScanDimensions = yOCTChangeDimensionsStructureUnits(inputScanDimensions,'microns');

%% Iterate through the inputScan volume and apply optical path correction to each individual scan 
for i=1:size(inputScan,3)
    
    % Extract B-scan from volume
    scan = squeeze(inputScan(:,:,i));
    
    %Lens abberation / optical path correction
    correction = @(x,y)(x*OP_p(1)+y*OP_p(2)+x.^2*OP_p(3)+y.^2*OP_p(4)+x.*y*OP_p(5)); %x,y are in microns
    [xx,zz] = meshgrid(inputScanDimensions.x.values,inputScanDimensions.z.values); %um                
    scan_min = min(scan(:));
    scan = interp2(xx,zz,scan,xx,zz+correction(xx,inputScanDimensions.y.values(i)),'nearest');
    scan_nan = isnan(scan);
    scan(scan<scan_min) = scan_min; %Dont let interpolation value go too low
    scan(scan_nan) = 0; %interpolated nan values should not contribute to image
    
    correctedScan(:,:,i) = scan;
    correctedScanValidDataMap = ~scan_nan;
end
