function [out, clim] = yOCTConvertAndReadTif2Png(roboflowDataPath)
%
% This function solves a key compatibility issue between OCT data and Roboflow.
%
% WHY WE NEED THIS:
%   • OCT scanners save data as TIFF with real intensity numbers
%     (can be negative, >255, and contain NaNs).
%   • Roboflow only accepts PNG and sends JPG back, which destroys those
%     true numbers, which surface detection is not compatible.
%
% WHAT THIS FUNCTION DOES:
%   • When we give it a TIFF/TIF: It makes a PNG that Roboflow accepts
%     and saves the original scale (clim cMin,cMax) in the file name.
%   • When we give it a PNG/JPG (like downloaded from Roboflow tester):
%     It reads that scale from the name and rebuilds the real numbers
%     (0  back to  NaN, 1‑255 back to original OCT Scan values).
%
% INPUT:
% roboflowDataPath: is the Path directory to either:
%       • A folder      – converts all TIFFs if present, or reads PNGs/JPGs.
%       • A .tif/.tiff  – converts to PNG with useful name and returns it.
%       • A .png/.jpg   – restores real intensities from filename and returns the slice.
%
% OUTPUTS:
%   • out  – data of a 2‑D image (or cell array of images) with real OCT intensities.
%   • clim – the [min max] scale used for each image
%
% HOW TO USE IT:
%   out = yOCTConvertAndReadTif2Png(path)   % folder or file
%   [slice, clim] = yOCTConvertAndReadTif2Png('scan01.tif')
%
% EXAMPLES:
%   Struct          = yOCTConvertAndReadTif2Png('C:\data\roboflowData');
%   slice           = yOCTConvertAndReadTif2Png('scan01.tif');
%   [slice, clim]   = yOCTConvertAndReadTif2Png('scan01_m-5.2_M2.1.png');
%
% -------------------------------------------------------------------------

%% Initial checks
roboflowDataPath = char(roboflowDataPath); % Ensure input is a character array (path)
if ~(isfolder(roboflowDataPath) || isfile(roboflowDataPath))
    error('Path does not exist: %s', roboflowDataPath);
end

slices = {}; % To store image data
clims = {};  % To store original [min max] intensity range for each image

%% If roboflowDataPath is a FOLDER:
if isfolder(roboflowDataPath)

    fld = roboflowDataPath;
    fprintf('\n Scanning folder: %s\n', fld);
    
    % Look for all .tif, .tiff, .png, and .jpg files in the folder
    tiffs = [dir(fullfile(fld,'*.tif')); dir(fullfile(fld,'*.tiff'))];
    pngs  = [dir(fullfile(fld,'*.png')); dir(fullfile(fld,'*.jpg'))];
    
    % If TIFFs exist, convert to PNGs with scale info and NaN handling
    if ~isempty(tiffs)
        outDir = makeUniqueDir(fld,'png_slices'); % Avoid overwriting: png_slices, png_slices2, etc.
        fprintf(' %d TIFF file(s) found → writing PNGs to "%s"\n', ...
                numel(tiffs), outDir);
        
        % Convert each TIFF to PNG, then read it back
        for k = 1:numel(tiffs)
            tif = fullfile(fld, tiffs(k).name);
            png = convertFromTIFtoPNG(tif, outDir);
            [sl, cm] = readOnePng(png);
            slices{end+1} = sl;   clims{end+1} = cm; %#ok<AGROW>
        end

    % If no TIFFs but PNGs/JPGs are present, just read those
    elseif ~isempty(pngs)
        fprintf('No TIFF files. Reading %d existing PNG(s)…\n', numel(pngs));
        for k = 1:numel(pngs)
            png = fullfile(fld, pngs(k).name);
            [sl, cm] = readOnePng(png);
            slices{end+1} = sl;   clims{end+1} = cm; %#ok<AGROW>
        end
    else
        fprintf('Folder contains NO TIFF or PNG files.\n');
    end

%% If roboflowDataPath is a SINGLE FILE:
else
    [p,~,ext] = fileparts(roboflowDataPath);
    switch lower(ext)
        case {'.tif','.tiff'}
            fprintf('\n Converting single TIFF: %s\n',roboflowDataPath);
            png = convertFromTIFtoPNG(roboflowDataPath, p);
            [slices{1},clims{1}] = readOnePng(png);

        case {'.png','.jpg'}
            fprintf('\n Reading single %s: %s\n',upper(ext(2:end)),roboflowDataPath);
            [slices{1},clims{1}] = readOnePng(roboflowDataPath);

        otherwise
            error('Unsupported file extension: %s', ext);
    end
end

%% Package output based on how many slices we collected

if isempty(slices)
    out  = [];
    clim = [];
elseif numel(slices)==1
    out  = slices{1};
    clim = clims{1};
else
    out  = slices;
    clim = clims;
end

fprintf('Finished. Returned %d slice(s).\n\n', numel(slices));


%% Helper functions:

    function newDir = makeUniqueDir(parent, baseName)
        % Create a unique output folder name (png_slices, png_slices2, …)
        n = 0; newDir = fullfile(parent, baseName);
        while isfolder(newDir)
            n = n + 1;
            newDir = fullfile(parent, sprintf('%s%d', baseName, n));
        end
        mkdir(newDir);
    end

    function pngPath = convertFromTIFtoPNG(tifPath, outDir)
        
        % Load the TIFF (could be single slice or 3‑D volume)
        vol = yOCTFromTif(tifPath);       % returns double with NaNs

        % If multiple slices, let user pick one
        if ndims(vol)==3 && size(vol,3) > 1
            ySel = pickSlice(vol);
            sliceFloat = vol(:,:,ySel);
        else
            sliceFloat = vol;
        end

        % Build 16‑bit integer image with NaN sentinel = 0
        nanMask = isnan(sliceFloat);
        validPix = sliceFloat(~nanMask);

        cMin = min(validPix);
        cMax = max(validPix);
        clim = [cMin cMax];

        bits16 = zeros(size(sliceFloat),'uint16');     % 0 reserved for NaN
        bits16(~nanMask) = uint16( ...
            1 + round(65534 * (validPix - cMin) / (cMax - cMin)) );

        % rescale to 8‑bit for PNG
        bits16Double = double(bits16);                 % avoid int math error
        data  = bits16Double/65535 * (cMax - cMin) + cMin;
        I8    = zeros(size(data),'uint8');
        I8(~nanMask) = uint8(1 + round(254 * (data(~nanMask) - cMin) / (cMax - cMin)));

        % Save PNG with scale & slice No in filename
        [~, base] = fileparts(tifPath);
        if exist('ySel','var') % if user chose a slice, include it
            sliceTag = sprintf('.Slice%d', ySel); % example ".Slice24"
        else
            sliceTag = '';              % single‑slice TIFF → no tag
        end
        pngName = sprintf('%s%s_m%.4f_M%.4f.png', base, sliceTag, cMin, cMax);
        pngPath = fullfile(outDir, pngName);
        imwrite(I8, pngPath);
        fprintf('   ► %s\n', pngName);
    end

    function [slice, clim] = readOnePng(imgPath)
        % Load image (grayscale or RGB)
        img = imread(imgPath);
        if ndims(img)==3, img = rgb2gray(img); end   % JPGs are RGB
        I8  = double(img);

        % Extract cMin and cMax from filename
        [~, fname] = fileparts(imgPath);
        tk = regexp(fname,'_m([-0-9._]+)_M([-0-9._]+)','tokens','once');
        if isempty(tk)
            error('Scale info _m.._M.. not found in filename: %s', imgPath);
        end
        cMinStr = strrep(tk{1}, '_', '.');
        cMaxStr = strrep(tk{2}, '_', '.');
        
        % Remove any trailing dots (for example from extra underscore at the end)
        cMinStr = regexprep(cMinStr, '\.$', '');
        cMaxStr = regexprep(cMaxStr, '\.$', '');
        cMin = str2double(cMinStr);
        cMax = str2double(cMaxStr);
        clim = [cMin cMax];
        
        % Restore original intensity values from 8-bit scale
        slice = NaN(size(I8));              % Default to NaN everywhere
        valid = I8>0;                       % 0 = NaN sentinel
        slice(valid) = (I8(valid)-1)/254 * (cMax-cMin) + cMin;
    end

    function yIndex = pickSlice(volume)
        
        Ny  = size(volume,3);
        cur = round(Ny/2);    % start in the middle
    
        % window option layout
        fig      = figure('Name','Pick slice','NumberTitle','off',...
                          'Toolbar','none','Menubar','none',...
                          'Resize','off','Position',[100 100 600 600]);
    
        instrTxt = uicontrol(fig,'Style','text','String','Pick a slice to save as PNG:',...
                             'FontSize',12,'Units','normalized',...
                             'Position',[0.05 0.93 0.9 0.05],'HorizontalAlignment','left');
    
        ax       = axes('Parent',fig,'Position',[0.05 0.20 0.9 0.7]);
        hIm      = imshow(volume(:,:,cur),[],'Parent',ax);
    
        slider   = uicontrol(fig,'Style','slider','Min',1,'Max',Ny,...
                             'Value',cur,'SliderStep',[1/(Ny-1) , 10/(Ny-1)],...
                             'Units','normalized','Position',[0.05 0.12 0.7 0.05],...
                             'Callback',@sliderFcn);
    
        editBox  = uicontrol(fig,'Style','edit','String',num2str(cur),...
                             'Units','normalized','Position',[0.77 0.12 0.12 0.05],...
                             'Callback',@editFcn);
    
        doneBtn  = uicontrol(fig,'Style','pushbutton','String','Done',...
                             'Units','normalized','Position',[0.90 0.12 0.07 0.05],...
                             'Callback',@(~,~) uiresume(fig));
    
        set(fig,'WindowScrollWheelFcn',@wheelFcn,...
                 'KeyPressFcn',@keyFcn);
    
        updateTitle();
        uiwait(fig);               % wait for user to click Done or press Enter
        yIndex = cur;
        close(fig);                % tidy up

        % nested functions:
        function wheelFcn(~,ev),    adjust(-ev.VerticalScrollCount);     end
        function sliderFcn(src,~),  adjust(round(get(src,'Value'))-cur); end
        function editFcn(src,~)
            v = str2double(get(src,'String'));
            if isnan(v), set(src,'String',num2str(cur)); return; end
            adjust(v-cur);
        end
        function keyFcn(~,ev)
            switch ev.Key
                case {'leftarrow','uparrow'},   adjust(-1);
                case {'rightarrow','downarrow'},adjust( 1);
                case {'return','space'},         uiresume(fig);
            end
        end
    
        function adjust(delta)
            cur = max(1,min(Ny,cur+delta));
            set(slider,'Value',cur);
            set(editBox,'String',num2str(cur));
            set(hIm,'CData',volume(:,:,cur));
            updateTitle();
            drawnow;
        end
        function updateTitle()
            title(ax,sprintf('Y = %d / %d  (wheel, arrows, slider, or type)',cur,Ny));
        end
    end
end
